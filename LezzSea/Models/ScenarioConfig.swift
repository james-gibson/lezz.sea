//
//  ScenarioConfig.swift
//  LezzSea
//
//  Derives a per-instance smoke-alarm config from a sample.
//
//  Two things make a sample unsafe to run twice as written: every instance
//  writes relative state into the checkout, and several instances want the
//  same fixed ports (18088 for health, 8877 for the mock auth server, and so
//  on). macOS will not let an unprivileged process bind 127.0.0.2, so the
//  isolation is a port offset on loopback rather than a second loopback
//  address.
//
//  The rewrite is deliberately narrow: only the listener ports declared by
//  `health`, `auth`, `hosted` and the federation slot range move, plus the
//  self-references to those exact ports. A target pointing at some other
//  localhost service is left alone.
//

import Foundation

enum ScenarioConfig {

    struct Derived: Sendable {
        let text: String
        /// The remapped health port, used for `/status` and the adhd block.
        let healthPort: Int
        /// Every port this instance will bind; the launcher checks them free.
        let ports: [Int]
    }

    enum DeriveError: LocalizedError {
        case noHealthListener
        case missingRuntimeKey(String)
        case portOutOfRange(Int)

        var errorDescription: String? {
            switch self {
            case .noHealthListener:
                "The sample does not declare a health listener."
            case .missingRuntimeKey(let key):
                "The sample does not declare runtime.\(key)."
            case .portOutOfRange(let port):
                "Port \(port) is outside the valid range after remapping."
            }
        }
    }

    // MARK: - Derivation

    static func derive(
        source: String,
        instanceDirectory: URL,
        offset: Int
    ) throws -> Derived {
        let lines = source.components(separatedBy: .newlines)

        // First pass: find the listeners and the federation slot range.
        var section = ""
        var health: Int?
        var basePorts = Set<Int>()
        var federationRange: ClosedRange<Int>?

        for line in lines {
            if let name = topLevelName(line) {
                section = name
            }

            if ["health", "auth", "hosted"].contains(section),
               let address = listenAddress(line),
               let port = address.port,
               port != 0,
               isLocalHost(address.host) {
                basePorts.insert(port)
                if section == "health", health == nil {
                    health = port
                }
            }

            if section == "federation",
               let key = keyName(line),
               (key == "base_port" || key == "max_port"),
               let value = intValue(line) {
                basePorts.insert(value)
                if key == "base_port" {
                    federationRange = value...value
                } else if let range = federationRange {
                    federationRange = min(range.lowerBound, value)...max(range.upperBound, value)
                }
            }
        }

        guard let health else { throw DeriveError.noHealthListener }

        var mapping: [Int: Int] = [:]
        for port in basePorts {
            mapping[port] = port + offset
        }
        if let range = federationRange {
            for port in range {
                mapping[port] = port + offset
            }
        }

        for port in mapping.values where port < 1 || port > 65_535 {
            throw DeriveError.portOutOfRange(port)
        }

        // Second pass: rewrite.
        var output: [String] = []
        output.reserveCapacity(lines.count)
        section = ""
        var seenRuntime = Set<String>()

        for line in lines {
            if let name = topLevelName(line) {
                section = name
            }

            if section == "runtime",
               let key = keyName(line),
               ["state_dir", "lock_file", "baseline_file"].contains(key) {
                seenRuntime.insert(key)
                output.append(runtimeLine(line, key: key, directory: instanceDirectory))
                continue
            }

            if ["health", "auth", "hosted"].contains(section),
               let address = listenAddress(line),
               let port = address.port,
               isLocalHost(address.host) {
                if port == 0 {
                    output.append(line)
                } else if let mapped = mapping[port] {
                    output.append(listenLine(line, port: mapped))
                } else {
                    output.append(line)
                }
                continue
            }

            if section == "federation",
               let key = keyName(line),
               key == "base_port" || key == "max_port",
               let value = intValue(line),
               let mapped = mapping[value] {
                output.append(replacingInt(line, old: value, new: mapped))
                continue
            }

            output.append(rewriteSelfReferences(line, mapping: mapping))
        }

        for key in ["state_dir", "lock_file", "baseline_file"] where !seenRuntime.contains(key) {
            throw DeriveError.missingRuntimeKey(key)
        }

        let ports = Set(mapping.values).sorted()
        return Derived(
            text: output.joined(separator: "\n"),
            healthPort: health + offset,
            ports: ports
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

    private static func intValue(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        var value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if let hash = value.firstIndex(of: "#") {
            value = String(value[..<hash]).trimmingCharacters(in: .whitespaces)
        }
        return Int(value)
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

    private static func listenLine(_ line: String, port: Int) -> String {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let suffix: String
        if let hash = line.firstIndex(of: "#") {
            suffix = " " + String(line[hash...])
        } else {
            suffix = ""
        }
        return "\(indent)listen_addr: \"127.0.0.1:\(port)\"\(suffix)"
    }

    private static func runtimeLine(_ line: String, key: String, directory: URL) -> String {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let value: URL
        switch key {
        case "state_dir":
            value = directory.appendingPathComponent("state", isDirectory: true)
        case "lock_file":
            value = directory.appendingPathComponent("ocd-smoke-alarm.pid")
        default:
            value = directory.appendingPathComponent("state/known-good.json")
        }
        return "\(indent)\(key): \"\(value.path)\""
    }

    private static func rewriteSelfReferences(_ line: String, mapping: [Int: Int]) -> String {
        var result = line
        for (old, new) in mapping {
            for host in ["localhost", "0.0.0.0", "127.0.0.1"] {
                result = result.replacingOccurrences(
                    of: "\(host):\(old)",
                    with: "127.0.0.1:\(new)"
                )
            }
        }
        return result
    }

    private static func replacingInt(_ line: String, old: Int, new: Int) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        let start = line.index(after: colon)
        guard let range = line.range(of: "\(old)", range: start..<line.endIndex) else { return line }
        return line.replacingCharacters(in: range, with: "\(new)")
    }
}
