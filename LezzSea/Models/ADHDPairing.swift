//
//  ADHDPairing.swift
//  LezzSea
//
//  The config that makes adhd watch a lab cluster.
//
//  Pairing is a derived artifact, like the alarms' configs: the endpoints are
//  the ports the members actually bound, not the ports their samples asked for.
//  The shape is the one scripts/lab-cluster.sh --pair-adhd writes, so a cluster
//  the app launched and one the script launched are paired identically.
//
//  Nothing here is a claim about a member. A `smoke_alarm` entry points at a
//  `127.0.0.1:<port>` that answered `/status` with that member's isotope name;
//  a port the app could not resolve is omitted rather than guessed.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

enum ADHDPairing {

    /// The ports the paired adhd's MCP server is allocated from. Kept off the
    /// alarms' ports and away from adhd's 9090 default, so a paired instance
    /// cannot collide with the idle agent's adhd on the same machine. The range
    /// matches scripts/lab-cluster.sh.
    static let portRange = 9_190...9_289

    /// The smallest adhd config that watches every member of a cluster.
    ///
    /// `gherkinDirectory` is the checkout's `features/` directory. When it
    /// exists the config also points adhd's `features.binaries` at its
    /// `.feature` files, so the paired instance loads the same Gherkin the
    /// report reads instead of an empty feature set.
    static func config(
        slug: String,
        healthPorts: [Int],
        mcpPort: Int,
        gherkinDirectory: URL?
    ) -> String {
        var lines = [
            "mcp_server:",
            "  enabled: true",
            "  addr: \"127.0.0.1:\(mcpPort)\"",
            "smoke_alarm:",
        ]

        for (offset, port) in healthPorts.enumerated() {
            let name = healthPorts.count == 1 ? slug : "\(slug)-\(offset + 1)"
            lines.append(contentsOf: [
                "  - name: \"\(name)\"",
                "    endpoint: \"http://127.0.0.1:\(port)\"",
                "    interval: 10s",
            ])
        }

        if let gherkinDirectory, let firstPort = healthPorts.first {
            lines.append(contentsOf: [
                "features:",
                "  binaries:",
                "    - name: ocd-smoke-alarm",
                "      endpoint: \"http://127.0.0.1:\(firstPort)/status\"",
                "      gherkin_files:",
                "        - \"\(gherkinDirectory.path)/*.feature\"",
            ])
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Port

    /// The first port in `range` that can be bound on loopback.
    ///
    /// adhd takes the port as an address rather than negotiating one, so the
    /// app has to hand it a port nobody holds. The probe binds and closes
    /// immediately; adhd binds it a moment later. The race is the same one
    /// scripts/lab-cluster.sh runs, and a lost race surfaces as adhd not
    /// answering, never as a cluster paired with somebody else's process.
    static func freePort(in range: ClosedRange<Int> = portRange) -> Int? {
        #if canImport(Darwin)
        for port in range {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            defer { _ = close(descriptor) }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(UInt16(port).bigEndian)
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bound == 0 { return port }
        }
        return nil
        #else
        return nil
        #endif
    }
}
