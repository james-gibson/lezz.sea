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
///
/// The browse is `NWBrowser` (`BonjourBrowser`); this type only keeps the port
/// half of each resolved instance.
final class ServicePortWatcher {
    var onChange: (([String: Int]) -> Void)?

    private let browser: BonjourBrowser
    private var published: [String: Int] = [:]

    init(serviceType: String) {
        browser = BonjourBrowser(serviceType: serviceType)
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

    func port(for name: String) -> Int? {
        browser.port(for: name)
    }

    private func merge(_ endpoints: [String: BonjourBrowser.Endpoint]) {
        let next = endpoints.mapValues { $0.port }
        guard next != published else { return }
        published = next
        onChange?(next)
    }
}
