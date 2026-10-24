//
//  ServicePortWatcher.swift
//  LezzSea
//

import Foundation

/// Watches one Bonjour service type and reports the port each instance name
/// resolved to.
///
/// The lab needs this because a smoke-alarm instance self-negotiates its health
/// port: the config asks for `18088`, and the second instance on the machine
/// binds `18089` instead. The advertisement carries the port it actually
/// bound, so the instance name is the only stable key.
final class ServicePortWatcher: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var onChange: (([String: Int]) -> Void)?

    private let serviceType: String
    private let browser = NetServiceBrowser()
    private var resolved: [String: Int] = [:]

    init(serviceType: String) {
        // NetServiceBrowser wants the trailing dot; the config spells the type
        // without one.
        self.serviceType = serviceType.hasSuffix(".")
            ? serviceType
            : "\(serviceType)."
        super.init()
        browser.delegate = self
    }

    func start() {
        browser.searchForServices(ofType: serviceType, inDomain: "local.")
    }

    func stop() {
        browser.stop()
    }

    func port(for name: String) -> Int? {
        resolved[name]
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        guard resolved.removeValue(forKey: service.name) != nil else { return }
        publish()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard sender.port > 0 else { return }
        resolved[sender.name] = sender.port
        publish()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard resolved.removeValue(forKey: sender.name) != nil else { return }
        publish()
    }

    private func publish() {
        onChange?(resolved)
    }
}
