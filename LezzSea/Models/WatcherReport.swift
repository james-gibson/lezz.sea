//
//  WatcherReport.swift
//  LezzSea
//
//  The watcher half of adhd's scenario report.
//
//  adhd's `internal/report` cross-references a JSONL traffic log against
//  Gherkin scenarios. Half of that report is about adhd's own MCP calls; the
//  half that applies to a smoke-alarm scenario is the watcher evidence: the
//  `light-update` lines adhd writes as it polls the alarm the launcher started.
//  A paired adhd produces exactly those lines and no MCP traffic of its own, so
//  that is the half this app can score.
//
//  The predicates are copied from adhd's `internal/report/matcher.go`
//  (`watcherSpecs`) and `scanner.go` (`WatcherEvidence`). They are deliberately
//  few and stable; when adhd adds a watcher scenario, add it here too.
//

import Foundation

struct WatcherReport: Sendable {

    enum Status: String, Sendable {
        case pass
        case fail
        case noCoverage

        var label: String {
            switch self {
            case .pass: "PASS"
            case .fail: "FAIL"
            case .noCoverage: "NO COVERAGE"
            }
        }

        var symbol: String {
            switch self {
            case .pass: "✓"
            case .fail: "✗"
            case .noCoverage: "○"
            }
        }
    }

    struct Row: Identifiable, Hashable, Sendable {
        /// The Gherkin scenario name in adhd's `smoke-alarm-network.feature`.
        let name: String
        let status: Status
        let note: String

        var id: String { name }
    }

    /// The aggregation `scanner.go` builds from `light-update` entries.
    struct Evidence: Sendable {
        struct Event: Sendable {
            let endpoint: String
            let target: String
            let oldStatus: String
            let newStatus: String
            let via: String
        }

        var events: [Event] = []
        var endpoints: [String: Int] = [:]
        var bySource: [String: Int] = [:]
        var seenStatuses: Set<String> = []
        var transitions = 0

        var isEmpty: Bool {
            events.isEmpty && endpoints.isEmpty
        }
    }

    let rows: [Row]

    var passCount: Int { rows.filter { $0.status == .pass }.count }
    var failCount: Int { rows.filter { $0.status == .fail }.count }
    var noCoverageCount: Int { rows.filter { $0.status == .noCoverage }.count }

    var summary: String {
        "\(passCount) pass · \(failCount) fail · \(noCoverageCount) no coverage"
    }

    /// The report as text, for the row's copy action. Shaped after
    /// `report.Format`, reduced to the lines this half can produce.
    var text: String {
        var lines = [
            "ADHD watcher report (smoke-alarm-network)",
            String(repeating: "─", count: 52),
        ]
        for row in rows {
            lines.append("  \(row.status.symbol)  \(row.status.label.padding(toLength: 12, withPad: " ", startingAt: 0))  \(row.name)")
            lines.append("          \(row.note)")
        }
        lines.append(String(repeating: "─", count: 52))
        lines.append("Summary: \(summary)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Scanning

    /// Reads the new complete lines from a growing log. The offset and the
    /// partial line live with the scan, so a refresh parses only what adhd has
    /// written since the last one.
    struct Scanner {
        private(set) var evidence = Evidence()
        private var offset: UInt64 = 0
        private var buffer: [UInt8] = []

        mutating func update(url: URL) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? handle.close() }

            let size = (try? handle.seekToEnd()) ?? 0
            if size < offset {
                // The log was rotated or truncated; the report starts over
                // rather than mixing two runs.
                self = Scanner()
            }
            guard size > offset else { return }

            try? handle.seek(toOffset: offset)
            guard let data = try? handle.read(upToCount: Int(size - offset)), !data.isEmpty else {
                return
            }
            offset = size
            buffer.append(contentsOf: data)

            var lines: [String] = []
            var start = 0
            for index in buffer.indices where buffer[index] == 0x0A {
                if index > start, let line = String(bytes: buffer[start..<index], encoding: .utf8) {
                    lines.append(line)
                }
                start = index + 1
            }
            if start > 0 {
                buffer.removeFirst(start)
            }
            WatcherReport.ingest(lines, into: &evidence)
        }
    }

    /// Adds the `light-update` entries in `lines` to `evidence`. Every other
    /// line (requests, responses, adhd's own log noise) is ignored: this half
    /// of the report is watcher evidence only.
    static func ingest(_ lines: [String], into evidence: inout Evidence) {
        for line in lines {
            guard
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["type"] as? String == "light-update"
            else { continue }

            let event = Evidence.Event(
                endpoint: object["endpoint"] as? String ?? "",
                target: object["target_id"] as? String ?? "",
                oldStatus: object["old_status"] as? String ?? "",
                newStatus: object["new_status"] as? String ?? "",
                via: object["via"] as? String ?? ""
            )
            evidence.events.append(event)

            if !event.endpoint.isEmpty {
                evidence.endpoints[event.endpoint, default: 0] += 1
            }
            if !event.via.isEmpty {
                evidence.bySource[event.via, default: 0] += 1
            }
            for status in [event.oldStatus, event.newStatus] where !status.isEmpty {
                evidence.seenStatuses.insert(status)
            }
            if !event.oldStatus.isEmpty,
               !event.newStatus.isEmpty,
               event.oldStatus != event.newStatus {
                evidence.transitions += 1
            }
        }
    }

    /// Scores every scenario in adhd's `smoke-alarm-network.feature` against
    /// the evidence. A predicate that cannot be confirmed because the watcher
    /// has not run is NO COVERAGE, not FAIL — the same distinction
    /// `matcher.go` makes.
    init(evidence: Evidence) {
        rows = Self.specs.map { spec in
            if evidence.isEmpty {
                return Row(name: spec.scenario, status: .noCoverage, note: spec.fallback)
            }

            let (passed, note) = spec.predicate(evidence)
            if passed {
                return Row(name: spec.scenario, status: .pass, note: note)
            }
            // Without light-update evidence there is nothing to fail: the same
            // rule `matcher.go` applies (`len(events) == 0 || optional`).
            let status: Status = (evidence.events.isEmpty || spec.optional) ? .noCoverage : .fail
            return Row(name: spec.scenario, status: status, note: note)
        }
    }

    // MARK: - Specs

    private struct Spec {
        let scenario: String
        var optional = false
        let fallback: String
        let predicate: @Sendable (Evidence) -> (Bool, String)
    }

    private static let specs: [Spec] = [
        Spec(
            scenario: "Poll smoke-alarm /status endpoint",
            fallback: "no watcher events — configure smoke-alarm endpoints and run with watcher",
            predicate: { evidence in
                let count = evidence.bySource["poll"] ?? 0
                guard count > 0 else { return (false, "no poll events observed") }
                return (true, "\(count) poll events across \(evidence.endpoints.count) endpoint(s)")
            }
        ),
        Spec(
            scenario: "Light naming from smoke-alarm",
            fallback: "no watcher events",
            predicate: { evidence in
                guard let event = evidence.events.first(where: {
                    !$0.endpoint.isEmpty && !$0.target.isEmpty
                }) else {
                    return (false, evidence.events.isEmpty
                        ? "no light-update events"
                        : "events seen but no endpoint+targetID pairing")
                }
                return (true, "light named smoke:\(event.endpoint)/\(event.target) observed")
            }
        ),
        Spec(
            scenario: "Light status mapped from HealthState",
            fallback: "no watcher events — need alarms returning healthy + degraded/outage",
            predicate: { evidence in
                guard evidence.seenStatuses.count >= 2 else {
                    return (false, "only \(evidence.seenStatuses.count) distinct status value(s) seen (need ≥ 2)")
                }
                return (true, "status values observed: \(evidence.seenStatuses.sorted().joined(separator: ", "))")
            }
        ),
        Spec(
            scenario: "SSE subscription for real-time updates",
            optional: true,
            fallback: "no watcher events",
            predicate: { evidence in
                let count = evidence.bySource["sse"] ?? 0
                guard count > 0 else {
                    return (false, "no SSE events observed (configure use_sse: true on an endpoint)")
                }
                return (true, "\(count) SSE events observed")
            }
        ),
        Spec(
            scenario: "Light update on status change",
            fallback: "no watcher events — need an alarm whose targets change state",
            predicate: { evidence in
                guard evidence.transitions > 0 else {
                    return (false, "no status transitions observed")
                }
                return (true, "\(evidence.transitions) status transitions observed")
            }
        ),
        Spec(
            scenario: "Multiple smoke-alarm endpoints",
            fallback: "no watcher events — configure multiple smoke-alarm endpoints",
            predicate: { evidence in
                guard evidence.endpoints.count >= 2 else {
                    return (false, "only \(evidence.endpoints.count) endpoint(s) seen (need ≥ 2)")
                }
                return (true, "\(evidence.endpoints.count) distinct endpoints observed")
            }
        ),
        Spec(
            scenario: "Graceful handling of smoke-alarm unavailability",
            fallback: "no watcher events — start watcher with at least one reachable + one unreachable endpoint",
            predicate: { evidence in
                // If the watcher ran at all, it survived whatever was
                // unreachable; the log is the only evidence available here.
                (true, "watcher continued operating (unreachable endpoints did not crash it)")
            }
        ),
        Spec(
            scenario: "Network visibility without direct connection",
            fallback: "no watcher events",
            predicate: { evidence in
                guard !evidence.events.isEmpty else {
                    return (false, "no light-update events")
                }
                return (true, "\(evidence.endpoints.count) light(s) visible via smoke-alarm proxy")
            }
        ),
        Spec(
            scenario: "Light state convergence",
            fallback: "no watcher events",
            predicate: { evidence in
                guard !evidence.events.isEmpty else {
                    return (false, "no watcher events")
                }
                let unique = Set(evidence.events.map {
                    "\($0.endpoint)/\($0.target)/\($0.newStatus)"
                })
                return (true, "\(evidence.events.count) events, \(unique.count) unique target-state combinations")
            }
        ),
    ]
}
