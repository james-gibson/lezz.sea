//
//  BonjourDiscoveryTests.swift
//  LezzSeaTests
//

import Foundation
import Network
import Testing
@testable import LezzSea

/// Discovery itself needs a live advertisement, but the two steps that decide
/// what `AppModel` sees — turning a satisfied path into an address, and an
/// address into an MCP URL — are pure and covered here.
struct BonjourAddressTests {
    @Test func interfaceZoneIsDroppedFromAnIPv4Address() {
        let remote = NWEndpoint.hostPort(host: "192.168.1.12%en1", port: 9101)
        let endpoint = BonjourBrowser.endpoint(from: remote)
        #expect(endpoint == BonjourBrowser.Endpoint(host: "192.168.1.12", port: 9101))
    }

    @Test func interfaceZoneIsDroppedFromAnIPv6Address() {
        // Network.framework canonicalises the address on the way in, so the
        // expectation spells it the way the host will.
        let remote = NWEndpoint.hostPort(host: "fe80::1013%en0", port: 9101)
        let endpoint = BonjourBrowser.endpoint(from: remote)
        #expect(endpoint == BonjourBrowser.Endpoint(host: "fe80::1013", port: 9101))
    }

    @Test func anUnresolvedServiceEndpointHasNoAddress() {
        let remote = NWEndpoint.service(
            name: "primary",
            type: "_adhd-isotope._tcp",
            domain: "local.",
            interface: nil
        )
        #expect(BonjourBrowser.endpoint(from: remote) == nil)
        #expect(BonjourBrowser.endpoint(from: nil) == nil)
    }

    @Test func aZeroPortIsNotAnAddress() {
        let remote = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        #expect(BonjourBrowser.endpoint(from: remote) == nil)
    }

    @Test func anAddressElsewhereIsTheOnlyCandidate() {
        let address = BonjourBrowser.Endpoint(host: "203.0.113.9", port: 18088)
        #expect(BonjourBrowser.candidates(for: address) == [address])
    }

    @Test func loopbackIsItsOwnCandidate() {
        let address = BonjourBrowser.Endpoint(host: "127.0.0.1", port: 9090)
        #expect(BonjourBrowser.candidates(for: address) == [address])
    }
}

struct BonjourURLTests {
    @Test func anIPv4AdvertisementBecomesAnMCPURL() {
        let endpoint = BonjourBrowser.Endpoint(host: "192.168.1.12", port: 18088)
        #expect(BonjourDiscovery.url(for: endpoint)?.absoluteString == "http://192.168.1.12:18088/mcp")
    }

    @Test func anIPv6AdvertisementIsBracketed() {
        let endpoint = BonjourBrowser.Endpoint(host: "::1", port: 9090)
        #expect(BonjourDiscovery.url(for: endpoint)?.absoluteString == "http://[::1]:9090/mcp")
    }
}
