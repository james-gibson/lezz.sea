//
//  BonjourDiscovery.swift
//  LezzSea
//

import Foundation

/// Watches for adhd's `_adhd-isotope._tcp` advertisement on the local network.
///
/// The registry at `:19100/cluster` covers a running lezz demo cluster; mDNS
/// covers an adhd that registered with smoke-alarm on its own. Registration is
/// loopback-only by policy, so this mostly finds instances published on the
/// machine or on the lab LAN.
///
/// The browse is `NWBrowser` (`BonjourBrowser`); this type only turns the
/// resolved instances into the MCP URLs `AppModel` merges, so the callback
/// shape the rest of the app sees is unchanged.
final class BonjourDiscovery {
    var onChange: (([URL]) -> Void)?

    private let browser = BonjourBrowser(serviceType: "_adhd-isotope._tcp")
    private var resolved: [String: URL] = [:]

    init() {
        browser.onChange = { [weak self] endpoints in
            self?.merge(endpoints)
        }
    }

    func start() {
        browser.start()
    }

    func stop() {
        browser.stop()
    }

    private func merge(_ endpoints: [String: BonjourBrowser.Endpoint]) {
        var next: [String: URL] = [:]
        for (name, endpoint) in endpoints {
            guard let url = Self.url(for: endpoint) else { continue }
            next[name] = url
        }

        guard next != resolved else { return }
        resolved = next
        // Sorted by instance name rather than dictionary order, so the sidebar
        // does not reorder when an unrelated instance resolves.
        onChange?(next.keys.sorted().compactMap { next[$0] })
    }

    /// The MCP URL for one resolved advertisement. An IPv6 address needs its
    /// brackets; everything else goes through the same normaliser as a typed
    /// or dropped endpoint.
    static func url(for endpoint: BonjourBrowser.Endpoint) -> URL? {
        let host = endpoint.host.contains(":") ? "[\(endpoint.host)]" : endpoint.host
        return EndpointNormalizer.normalize("http://\(host):\(endpoint.port)/mcp")
    }
}
