//
//  BonjourBrowser.swift
//  LezzSea
//

import Foundation
import Network

/// Watches one Bonjour service type with Network.framework and reports the host
/// and port each instance name resolved to.
///
/// `NetServiceBrowser` / `NetService` did this while both still shipped; Apple
/// deprecated them in 10.15 and they were the last legacy API in the app.
/// `NWBrowser` finds the instances. Turning an `NWEndpoint.service` into an
/// address has no verb in the framework, so the resolver does it in two steps:
/// a UDP connection resolves the advertisement to a host and port without
/// putting a packet on the wire, and a TCP connection to a candidate address
/// confirms it before the URL is published. An address nothing accepts is not
/// an address the app should be told to use.
///
/// Loopback is handled explicitly because it is the case the app is built for.
/// adhd binds `127.0.0.1` by policy and still advertises the machine's LAN
/// address; probing the advertised address is then refused — and
/// `NWConnection` does not fall back to the SRV target's other addresses, it
/// waits — while the service is alive and perfectly reachable. When the
/// resolved address belongs to this machine, loopback is tried first and the
/// advertised address second.
final class BonjourBrowser {
    struct Endpoint: Equatable {
        let host: String
        let port: Int

        var isLoopback: Bool {
            host == "::1" || host.hasPrefix("127.")
        }
    }

    /// Called with every instance currently resolved, keyed by instance name.
    /// Fires on a private queue; both callers hop to the main actor.
    var onChange: (([String: Endpoint]) -> Void)?

    private let serviceType: String
    private let queue = DispatchQueue(label: "co.jamesgibson.LezzSea.bonjour")
    /// `resolved` is read from the main actor through `port(for:)`, so it sits
    /// behind a lock; the browse bookkeeping is confined to `queue`.
    private let lock = NSLock()
    private var browser: NWBrowser?
    private var browsing: Set<String> = []
    private var probes: [String: NWConnection] = [:]
    private var resolved: [String: Endpoint] = [:]

    /// One candidate address gets this long to accept, and a resolve this long
    /// in total — the budget `NetService.resolve(withTimeout: 4)` used.
    private static let candidateTimeout: DispatchTimeInterval = .seconds(2)
    private static let resolveTimeout: DispatchTimeInterval = .seconds(4)

    init(serviceType: String) {
        // NWBrowser takes the type without the trailing dot the old API wanted.
        var type = serviceType
        while type.hasSuffix(".") {
            type.removeLast()
        }
        self.serviceType = type
    }

    func start() {
        queue.async { [weak self] in self?.startOnQueue() }
    }

    func stop() {
        queue.async { [weak self] in self?.stopOnQueue() }
    }

    /// The port an instance name currently resolves to, if it is advertised.
    func port(for name: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return resolved[name]?.port
    }

    // MARK: - Browsing

    private func startOnQueue() {
        guard browser == nil else { return }

        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: "local."),
            using: .tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.apply(results)
        }
        browser.stateUpdateHandler = { [weak self] state in
            // A denied local-network prompt or a cancelled browser takes the
            // whole browse down. Keep what resolved and wait for a restart.
            if case .failed = state {
                self?.stopOnQueue()
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func stopOnQueue() {
        browser?.cancel()
        browser = nil
        for probe in probes.values {
            probe.cancel()
        }
        probes.removeAll()
        browsing.removeAll()

        lock.lock()
        let hadAny = !resolved.isEmpty
        resolved.removeAll()
        lock.unlock()

        if hadAny {
            publish()
        }
    }

    /// Reconciles the browse result with what is being probed and what is
    /// resolved. A name that leaves the result set is forgotten, so if the
    /// same advertisement comes back it is resolved again.
    private func apply(_ results: Set<NWBrowser.Result>) {
        var found: [String: NWEndpoint] = [:]
        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            found[name] = result.endpoint
        }

        var changed = false
        for name in browsing.subtracting(found.keys) {
            probes.removeValue(forKey: name)?.cancel()
            changed = remove(name) || changed
        }

        let appeared = Set(found.keys).subtracting(browsing)
        browsing.formUnion(appeared)
        for name in appeared {
            if let endpoint = found[name] {
                resolve(name, endpoint)
            }
        }

        if changed {
            publish()
        }
    }

    // MARK: - Resolving

    /// Learns the advertised host and port, then confirms an address for them.
    private func resolve(_ name: String, _ endpoint: NWEndpoint) {
        // UDP carries no handshake, so this reads the SRV target without
        // knocking on the door.
        let lookup = NWConnection(to: endpoint, using: .udp)
        probes[name] = lookup

        lookup.stateUpdateHandler = { [weak self] state in
            guard let self, self.probes[name] === lookup else { return }
            switch state {
            case .ready:
                let address = Self.endpoint(from: lookup.currentPath?.remoteEndpoint)
                lookup.cancel()
                guard let address else {
                    self.abandon(name)
                    return
                }
                self.confirm(name, Self.candidates(for: address), at: 0)
            case .failed:
                self.abandon(name)
            default:
                break
            }
        }
        lookup.start(queue: queue)
        expire(name, after: Self.resolveTimeout, while: lookup)
    }

    /// Tries the candidate addresses in order and settles on the first that
    /// accepts a connection.
    private func confirm(_ name: String, _ candidates: [Endpoint], at index: Int) {
        guard index < candidates.count else {
            abandon(name)
            return
        }

        let candidate = candidates[index]
        guard let port = NWEndpoint.Port(rawValue: UInt16(candidate.port)) else {
            abandon(name)
            return
        }
        let probe = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(candidate.host), port: port),
            using: .tcp
        )
        probes[name] = probe

        probe.stateUpdateHandler = { [weak self] state in
            guard let self, self.probes[name] === probe else { return }
            switch state {
            case .ready:
                probe.cancel()
                self.finish(name, at: candidate)
            case .waiting, .failed:
                // Refused, or no route: this address will not answer now.
                probe.cancel()
                self.confirm(name, candidates, at: index + 1)
            default:
                break
            }
        }
        probe.start(queue: queue)
        expire(name, after: Self.candidateTimeout, while: probe)
    }

    private func expire(_ name: String, after delay: DispatchTimeInterval, while probe: NWConnection) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.probes[name] === probe else { return }
            self.abandon(name)
        }
    }

    private func finish(_ name: String, at endpoint: Endpoint) {
        probes.removeValue(forKey: name)

        lock.lock()
        let unchanged = resolved[name] == endpoint
        resolved[name] = endpoint
        lock.unlock()

        if !unchanged {
            publish()
        }
    }

    private func abandon(_ name: String) {
        probes.removeValue(forKey: name)?.cancel()
        if remove(name) {
            publish()
        }
    }

    // MARK: - Bookkeeping

    /// Drops a name from the resolved set. Returns whether anything went.
    private func remove(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return resolved.removeValue(forKey: name) != nil
    }

    private func publish() {
        lock.lock()
        let snapshot = resolved
        lock.unlock()
        onChange?(snapshot)
    }

    // MARK: - Address

    /// The host and port behind a satisfied path.
    ///
    /// A resolve scopes the address to the interface that answered
    /// (`192.168.1.12%en1`, `fe80::1013%en0`); the zone means something to the
    /// socket layer and nothing to a URL, so it is dropped here.
    static func endpoint(from remote: NWEndpoint?) -> Endpoint? {
        guard case let .hostPort(host, port)? = remote else { return nil }

        var name = "\(host)"
        if let zone = name.firstIndex(of: "%") {
            name = String(name[..<zone])
        }
        guard !name.isEmpty, port.rawValue > 0 else { return nil }

        return Endpoint(host: name, port: Int(port.rawValue))
    }

    /// Where to look for the advertised service. A service on this machine
    /// answers on loopback whatever interface it bound; a service elsewhere
    /// has the one address to try.
    static func candidates(for address: Endpoint) -> [Endpoint] {
        guard !address.isLoopback, LocalAddresses.contains(address.host) else {
            return [address]
        }
        return [Endpoint(host: "127.0.0.1", port: address.port), address]
    }
}

/// The addresses this machine currently holds, so a resolved advertisement can
/// be recognised as local.
private enum LocalAddresses {
    static func contains(_ host: String) -> Bool {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(head) }

        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = interface.pointee.ifa_addr else { continue }

            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            let status = getnameinfo(
                address, length, &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST
            )
            if status == 0, host == String(cString: name) {
                return true
            }
        }
        return false
    }
}
