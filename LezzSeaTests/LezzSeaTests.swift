//
//  LezzSeaTests.swift
//  LezzSeaTests
//

import CoreGraphics
import Foundation
import Testing
@testable import LezzSea

struct EndpointTests {
    @Test func hostAndPortBecomeMCPURL() {
        #expect(EndpointNormalizer.normalize("127.0.0.1:9090")?.absoluteString == "http://127.0.0.1:9090/mcp")
    }

    @Test func explicitMCPPathIsKept() {
        #expect(EndpointNormalizer.normalize("http://dev.local:9090/mcp")?.absoluteString == "http://dev.local:9090/mcp")
    }

    @Test func wildcardBindBecomesLoopback() {
        #expect(EndpointNormalizer.normalize(":9090")?.absoluteString == "http://127.0.0.1:9090/mcp")
    }

    @Test func configYieldsMCPEndpointsOnly() {
        let yaml = """
        mcp_server:
          enabled: true
          addr: "127.0.0.1:9090"
        smoke_alarm:
          - name: primary
            endpoint: "http://localhost:8088"
        """
        let endpoints = EndpointNormalizer.endpoints(in: yaml)
        #expect(endpoints.map(\.absoluteString) == ["http://127.0.0.1:9090/mcp"])
    }
}

struct DecodingTests {
    @Test func decodesLightsList() throws {
        let json = #"""
        {"jsonrpc":"2.0","id":1,"result":{"lights":[
          {"name":"primary","type":"smoke-alarm","source":"smoke-alarm","status":"green",
           "details":"","lastUpdated":"2026-10-15T23:26:40.687273Z"}
        ]}}
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return FlexibleDate.parse(text)!
        }
        struct Envelope: Decodable { let result: LightsResponse }
        let response = try decoder.decode(Envelope.self, from: Data(json.utf8))
        #expect(response.result.lights.first?.name == "primary")
        #expect(response.result.lights.first?.status == "green")
        #expect(response.result.lights.first?.lastUpdated != nil)
    }

    @Test func parsesNanosecondTimestamps() {
        #expect(FlexibleDate.parse("2026-10-15T23:26:40.687273Z") != nil)
        #expect(FlexibleDate.parse("2026-10-15T23:26:40.687Z") != nil)
        #expect(FlexibleDate.parse("2026-10-15T23:26:40Z") != nil)
    }
}

struct TrafficEventTests {
    @Test func readsLightUpdate() throws {
        let line = #"{"timestamp":"2026-10-15T23:26:41.999706Z","type":"light-update","target_id":"target-1","endpoint":"primary","old_status":"dark","new_status":"green","via":"poll"}"#
        let event = try #require(TrafficEvent(line: line))
        #expect(event.kind == .lightUpdate)
        #expect(event.summary == "primary")
        #expect(event.detail == "dark → green · poll")
    }

    @Test func ignoresNonJSON() {
        #expect(TrafficEvent(line: "not json") == nil)
    }
}

// MARK: - Presentation and layout

struct LightStatusStyleTests {
    /// Status must survive greyscale: every state needs its own shape, not just
    /// its own colour.
    @Test func everyStatusHasADistinctSymbol() {
        let statuses = ["green", "red", "yellow", "dark"]
        for status in statuses {
            #expect(!LightStatusStyle.symbol(for: status).isEmpty)
        }
        let symbols = Set(statuses.map { LightStatusStyle.symbol(for: $0) })
        #expect(symbols.count == statuses.count)
    }

    @Test func statusLabelsAreSpokenWords() {
        #expect(LightStatusStyle.label(for: "green") == "Green")
        #expect(LightStatusStyle.label(for: "RED") == "Red")
        #expect(LightStatusStyle.label(for: "yellow") == "Yellow")
        #expect(LightStatusStyle.label(for: "dark") == "Dark")
    }

    @Test func unknownStatusStillHasAName() {
        #expect(LightStatusStyle.label(for: "") == "Unknown")
        #expect(LightStatusStyle.label(for: "   ") == "Unknown")
        #expect(LightStatusStyle.label(for: "blue") == "Blue")
        #expect(LightStatusStyle.symbol(for: "blue") == "questionmark.circle")
    }
}

struct CountTextTests {
    @Test func countsPluralise() {
        #expect(CountText.lights(0) == "0 lights")
        #expect(CountText.lights(1) == "1 light")
        #expect(CountText.lights(6) == "6 lights")
        #expect(CountText.count(1, "green") == "1 green light")
        #expect(CountText.count(3, "green") == "3 green lights")
    }
}

struct LayoutMetricsTests {
    /// The floor must leave the detail pane enough room for the sidebar and the
    /// lights table's minimum column widths. Anything less is the overlap bug
    /// in a different disguise.
    @Test func windowFloorLeavesRoomForTheTable() {
        #expect(LayoutMetrics.minimumWindowWidth >= LayoutMetrics.sidebarMinimumWidth + 480)
        #expect(LayoutMetrics.minimumWindowHeight >= 500)
        #expect(LayoutMetrics.preferredWindowWidth > LayoutMetrics.minimumWindowWidth)
        #expect(LayoutMetrics.preferredWindowHeight > LayoutMetrics.minimumWindowHeight)
    }
}
