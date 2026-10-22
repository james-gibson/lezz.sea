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
final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var onChange: (([URL]) -> Void)?

    private let browser = NetServiceBrowser()
    private var resolved: [String: URL] = [:]

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        browser.searchForServices(ofType: "_adhd-isotope._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        resolved.removeValue(forKey: service.name)
        publish()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender.port > 0 else { return }
        var host = sender.hostName ?? "127.0.0.1"
        if host.hasSuffix(".") {
            host.removeLast()
        }
        guard let url = EndpointNormalizer.normalize("http://\(host):\(sender.port)/mcp") else { return }
        resolved[sender.name] = url
        publish()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolved.removeValue(forKey: sender.name)
        publish()
    }

    private func publish() {
        onChange?(Array(resolved.values))
    }
}
