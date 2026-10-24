//
//  ScenarioConfig.swift
//  LezzSea
//
//  Derives a per-instance smoke-alarm config from a sample.
//
//  A scenario's instances are not told apart by moving their ports. They are
//  told apart by identity, and by what the alarm already does when a port is
//  taken:
//
//  - `health` binds its preferred port and scans upwards on EADDRINUSE, then
//    advertises the port it actually bound over mDNS;
//  - `federation` claims the first free slot in its range, so the first
//    process becomes the introducer and the rest become followers announcing
//    at the root (`http://localhost:<base_port>`).
//
//  So the rewrite leaves every port alone and rotates the isotope instead: the
//  service name is what mDNS prints, and it has to be unique per instance or
//  three instances share one advertisement.
//
//  The launcher does not invent a federation agreement. `cluster_id` is a
//  sample's statement that its members may trust each other by construction
//  (mesh declares one; pool, chain, star and dependency deliberately do not,
//  because a pool of identical workers must not trust itself). The launcher
//  keeps a declared id and never fills an empty one — the mesh sample's own
//  comment says an empty value disables self-trust.
//
//  What it does change is state: every instance writes its own absolute
//  runtime paths, so two instances never share a lock file or a baseline.
//

import Foundation

enum ScenarioConfig {

    struct Derived: Sendable {
        let text: String
        /// The isotope name this instance advertises. Also the mDNS instance
        /// name, and the key the launcher uses to find the bound port.
        let isotope: String
        /// The health port the instance asks for. It may bind the next free
        /// one instead, which is why the advertised port is authoritative.
        let preferredHealthPort: Int
        /// The federation slot range's first port — the root a follower
        /// announces at, and the leader's slot when this instance is first.
        let rootPort: Int?
        /// The cluster identity the instance announces, when the sample
        /// declares one. Same value for every member of one launch; nil means
        /// the sample does not opt into self-trust.
        let clusterID: String?
    }

    enum DeriveError: LocalizedError {
        case noHealthListener
        case noServiceName
        case missingRuntimeKey(String)

        var errorDescription: String? {
            switch self {
            case .noHealthListener:
                "The sample does not declare a health listener."
            case .noServiceName:
                "The sample does not declare service.name."
            case .missingRuntimeKey(let key):
                "The sample does not declare runtime.\(key)."
            }
        }
    }

    /// The service type the alarm advertises. A constant: it is the discovery
    /// channel the app and adhd both browse.
    static let discoveryType = "_smoke-alarm._tcp"

    /// The isotope name an instance advertises. The base is the sample's own
    /// service name, so a lab cluster still reads as the product it is; the
    /// suffix makes it unique on the wire.
    static func isotopeName(base: String, slug: String, index: Int) -> String {
        "\(base)-\(slug)-\(index)"
    }

    // MARK: - Derivation

    static func derive(
        source: String,
        instanceDirectory: URL,
        slug: String,
        index: Int
    ) throws -> Derived {
        let lines = source.components(separatedBy: .newlines)

        // First pass: identity, ports, and which sections exist.
        var section = ""
        var baseServiceName: String?
        var health: Int?
        var rootPort: Int?
        var declaredClusterID: String?
        var hasTuner = false
        var hasFederation = false

        for line in lines {
            if let name = topLevelName(line) {
                section = name
                if name == "tuner" { hasTuner = true }
                if name == "federation" { hasFederation = true }
                continue
            }

            switch section {
            case "service":
                if keyName(line) == "name", let value = stringValue(line) {
                    baseServiceName = value
                }
            case "health":
                if keyName(line) == "listen_addr",
                   let address = listenAddress(line),
                   let port = address.port,
                   port != 0,
                   isLocalHost(address.host),
                   health == nil {
                    health = port
                }
            case "federation":
                if keyName(line) == "base_port", let value = intValue(line) {
                    rootPort = value
                }
                if keyName(line) == "cluster_id" {
                    // An empty value is a deliberate "no self-trust"; an absent
                    // key means the sample never opted in. Neither is filled.
                    declaredClusterID = stringValue(line)
                }
            default:
                break
            }
        }

        guard let health else { throw DeriveError.noHealthListener }
        guard let baseServiceName else { throw DeriveError.noServiceName }

        let isotope = isotopeName(base: baseServiceName, slug: slug, index: index)

        // Second pass: rewrite state, rotate the isotope, turn discovery on and
        // make sure every member announces the same agreement.
        var output: [String] = []
        output.reserveCapacity(lines.count + 10)
        section = ""
        var seenRuntime = Set<String>()
        var tunerAdvertiseWritten = false
        var tunerTypeWritten = false

        func flushTunerDefaults() {
            if !tunerAdvertiseWritten {
                output.append("  advertise: true")
                tunerAdvertiseWritten = true
            }
            if !tunerTypeWritten {
                output.append("  service_type: \"\(discoveryType)\"")
                tunerTypeWritten = true
            }
        }

        for line in lines {
            if let name = topLevelName(line) {
                // Leaving the tuner section: fill in anything it did not say.
                if section == "tuner", name != "tuner" {
                    flushTunerDefaults()
                }
                section = name
                output.append(line)
                continue
            }

            switch section {
            case "service":
                if keyName(line) == "name" {
                    output.append(replacingStringValue(line, with: isotope))
                    continue
                }
            case "runtime":
                if let key = keyName(line),
                   ["state_dir", "lock_file", "baseline_file"].contains(key) {
                    seenRuntime.insert(key)
                    output.append(runtimeLine(line, key: key, directory: instanceDirectory))
                    continue
                }
            case "tuner":
                if keyName(line) == "advertise" {
                    tunerAdvertiseWritten = true
                    output.append(replacingScalar(line, with: "true"))
                    continue
                }
                if keyName(line) == "service_type" {
                    tunerTypeWritten = true
                    output.append(replacingStringValue(line, with: discoveryType))
                    continue
                }
            default:
                break
            }

            output.append(line)
        }

        // The last section never closes, so flush its defaults here.
        if section == "tuner" {
            flushTunerDefaults()
        }

        for key in ["state_dir", "lock_file", "baseline_file"] where !seenRuntime.contains(key) {
            throw DeriveError.missingRuntimeKey(key)
        }

        if !hasTuner {
            output.append(contentsOf: [
                "",
                "# Added by lezz.sea: every instance advertises its own isotope name",
                "# so mDNS can tell the members of a lab cluster apart.",
                "tuner:",
                "  enabled: true",
                "  advertise: true",
                "  service_type: \"\(discoveryType)\"",
            ])
        }

        return Derived(
            text: output.joined(separator: "\n"),
            isotope: isotope,
            preferredHealthPort: health,
            rootPort: hasFederation ? rootPort : nil,
            clusterID: hasFederation ? declaredClusterID : nil
        )
    }

    // MARK: - Line helpers

    /// A top-level key is unindented and ends with a colon.
    private static func topLevelName(_ line: String) -> String? {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("#") else { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let name = String(line[..<colon])
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0 == "_" }) else { return nil }
        return name
    }

    /// The key of an indented `key: value` line.
    private static func keyName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let colon = trimmed.firstIndex(of: ":") else { return nil }
        let key = String(trimmed[..<colon])
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0 == "_" }) else { return nil }
        return key
    }

    private static func scalarValue(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        var value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
        }
        guard !value.isEmpty else { return nil }
        return value
    }

    private static func stringValue(_ line: String) -> String? {
        guard var value = scalarValue(line) else { return nil }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }

    private static func intValue(_ line: String) -> Int? {
        scalarValue(line).flatMap(Int.init)
    }

    /// Keeps the indentation, the key and any trailing comment.
    private static func replacingScalar(_ line: String, with value: String) -> String {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let body = line.dropFirst(indent.count)
        guard let colon = body.firstIndex(of: ":") else { return line }

        // A comment starts at the first '#' that follows the colon. Key text
        // never contains one, so splitting on the line's first '#' is safe for
        // the scalar lines this rewrite touches.
        let suffix: String
        if let hash = body.firstIndex(of: "#") {
            suffix = " " + String(body[hash...])
        } else {
            suffix = ""
        }
        let key = body[..<colon]
        return "\(indent)\(key): \(value)\(suffix)"
    }

    private static func replacingStringValue(_ line: String, with value: String) -> String {
        replacingScalar(line, with: "\"\(value)\"")
    }

    private struct Address {
        let host: String
        let port: Int?
    }

    private static func listenAddress(_ line: String) -> Address? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("listen_addr:") else { return nil }
        var value = trimmed.dropFirst("listen_addr:".count).trimmingCharacters(in: .whitespaces)
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
        }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        guard let colon = value.lastIndex(of: ":") else {
            return Address(host: value, port: nil)
        }
        let host = String(value[..<colon])
        let port = Int(value[value.index(after: colon)...])
        return Address(host: host, port: port)
    }

    private static func isLocalHost(_ host: String) -> Bool {
        host.isEmpty || host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0"
    }

    private static func runtimeLine(_ line: String, key: String, directory: URL) -> String {
        let value: URL
        switch key {
        case "state_dir":
            value = directory.appendingPathComponent("state", isDirectory: true)
        case "lock_file":
            value = directory.appendingPathComponent("ocd-smoke-alarm.pid")
        default:
            value = directory.appendingPathComponent("state/known-good.json")
        }
        return replacingStringValue(line, with: value.path)
    }
}
