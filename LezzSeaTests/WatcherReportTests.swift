//
//  WatcherReportTests.swift
//  LezzSeaTests
//
//  The watcher half of adhd's report is a pure function of the `light-update`
//  lines in adhd's JSONL log. These tests pin the aggregation and one scenario
//  verdict per predicate, plus the incremental scan the live row uses.
//

import Foundation
import Testing
@testable import LezzSea

struct WatcherReportTests {

    private func lightUpdate(
        endpoint: String,
        target: String,
        old: String = "",
        new: String,
        via: String = "poll"
    ) -> String {
        let object: [String: Any] = [
            "timestamp": "2026-10-26T22:28:55.820134Z",
            "type": "light-update",
            "endpoint": endpoint,
            "target_id": target,
            "old_status": old,
            "new_status": new,
            "via": via,
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }

    @Test func anEmptyLogHasNoCoverage() {
        let report = WatcherReport(evidence: .init())

        #expect(report.rows.count == 9)
        #expect(report.passCount == 0)
        #expect(report.failCount == 0)
        #expect(report.noCoverageCount == 9)
        #expect(report.summary == "0 pass · 0 fail · 9 no coverage")
        #expect(report.rows.allSatisfy { $0.status == .noCoverage })
    }

    @Test func everyWatcherScenarioPassesOnAFullLog() {
        var evidence = WatcherReport.Evidence()
        WatcherReport.ingest([
            lightUpdate(endpoint: "primary", target: "mcp-1", new: "green"),
            lightUpdate(endpoint: "primary", target: "mcp-1", old: "green", new: "red"),
            lightUpdate(endpoint: "secondary", target: "tool-2", new: "green", via: "sse"),
        ], into: &evidence)

        #expect(evidence.events.count == 3)
        #expect(evidence.endpoints.count == 2)
        #expect(evidence.bySource["poll"] == 2)
        #expect(evidence.bySource["sse"] == 1)
        #expect(evidence.transitions == 1)
        #expect(evidence.seenStatuses == ["green", "red"])

        let report = WatcherReport(evidence: evidence)
        #expect(report.passCount == 9)
        #expect(report.failCount == 0)
        #expect(report.noCoverageCount == 0)
    }

    @Test func aMissingSubscriptionIsNoCoverageNotFailure() {
        var evidence = WatcherReport.Evidence()
        WatcherReport.ingest([
            lightUpdate(endpoint: "primary", target: "mcp-1", old: "green", new: "red"),
            lightUpdate(endpoint: "secondary", target: "tool-2", new: "green"),
        ], into: &evidence)

        let report = WatcherReport(evidence: evidence)
        let sse = report.rows.first { $0.name.contains("SSE") }

        #expect(sse?.status == .noCoverage)
        #expect(sse?.note.contains("use_sse: true") == true)
        #expect(report.failCount == 0)
    }

    @Test func oneEndpointFailsTheMultipleEndpointScenario() {
        var evidence = WatcherReport.Evidence()
        WatcherReport.ingest([
            lightUpdate(endpoint: "primary", target: "mcp-1", old: "green", new: "red"),
            lightUpdate(endpoint: "primary", target: "mcp-1", old: "red", new: "green"),
        ], into: &evidence)

        let report = WatcherReport(evidence: evidence)
        let multiple = report.rows.first { $0.name.contains("Multiple") }

        #expect(multiple?.status == .fail)
        #expect(multiple?.note == "only 1 endpoint(s) seen (need ≥ 2)")
    }

    @Test func otherTrafficLinesAreIgnored() {
        var evidence = WatcherReport.Evidence()
        WatcherReport.ingest([
            #"{"type":"request","method":"adhd.lights.list"}"#,
            #"{"type":"response","method":"adhd.lights.list"}"#,
            "not json at all",
        ], into: &evidence)

        #expect(evidence.isEmpty)
    }

    @Test func theScannerReadsOnlyWhatIsNew() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-report-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("adhd.log")
        let first = lightUpdate(endpoint: "primary", target: "mcp-1", new: "green")
        try Data((first + "\n").utf8).write(to: url)

        var scanner = WatcherReport.Scanner()
        scanner.update(url: url)
        #expect(scanner.evidence.events.count == 1)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        let second = lightUpdate(endpoint: "primary", target: "mcp-1", old: "green", new: "red")
        try handle.write(contentsOf: Data((second + "\n").utf8))
        try handle.close()

        scanner.update(url: url)
        #expect(scanner.evidence.events.count == 2)
        #expect(scanner.evidence.transitions == 1)
    }

    @Test func theTextNamesEveryScenarioAndTheSummary() {
        let report = WatcherReport(evidence: .init())
        let text = report.text

        #expect(text.contains("ADHD watcher report (smoke-alarm-network)"))
        #expect(text.contains("Poll smoke-alarm /status endpoint"))
        #expect(text.contains("Light state convergence"))
        #expect(text.contains("Summary: 0 pass · 0 fail · 9 no coverage"))
    }
}
