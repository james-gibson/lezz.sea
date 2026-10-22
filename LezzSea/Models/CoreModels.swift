//
//  CoreModels.swift
//  LezzSea
//
//  The shapes adhd's MCP surface returns, and the events its JSONL traffic
//  log records.
//

import Foundation

// MARK: - Lights

/// One indicator from `adhd.lights.list`.
struct Light: Identifiable, Decodable, Hashable {
    let name: String
    let type: String?
    let source: String?
    let status: String
    let details: String?
    let lastUpdated: Date?

    var id: String { name }
}

/// The count-by-status block from `adhd.status`.
struct LightSummary: Decodable, Hashable {
    let total: Int
    let green: Int
    let red: Int
    let yellow: Int
    let dark: Int
}

/// The result of `adhd.status`.
struct ClusterStatus: Decodable, Hashable {
    let lights: LightSummary?
    let instance: String?
    let isotope: String?
    let trustRung: Int?
    let clusterPeers: [String]?
    let paths: Int?
    let dynamicTools: Int?
    let tick: String?
}

struct LightsResponse: Decodable {
    let lights: [Light]
}

// MARK: - Clusters

/// An adhd instance the app can talk to.
struct Cluster: Identifiable, Codable, Hashable {
    enum Source: String, Codable {
        case manual
        case registry
        case bonjour
        case local
    }

    var name: String
    var endpoint: URL
    var source: Source

    var id: String { endpoint.absoluteString }
}

// MARK: - Traffic events

/// One line of adhd's JSONL MCP traffic log.
///
/// Lines are heterogeneous — requests carry params, responses carry latency,
/// light updates carry a transition — so this decodes into a summary with the
/// original line kept intact for copying.
struct TrafficEvent: Identifiable, Hashable {
    enum Kind: Hashable {
        case request
        case response
        case lightUpdate
        case error
        case other

        var symbol: String {
            switch self {
            case .request: "arrow.up.circle.fill"
            case .response: "arrow.down.circle.fill"
            case .lightUpdate: "lightbulb.fill"
            case .error: "exclamationmark.triangle.fill"
            case .other: "circle.fill"
            }
        }

        var label: String {
            switch self {
            case .request: "Request"
            case .response: "Response"
            case .lightUpdate: "Light"
            case .error: "Error"
            case .other: "Event"
            }
        }
    }

    let id = UUID()
    let time: Date?
    let type: String
    let method: String?
    let summary: String
    let detail: String?
    let latency: Double?
    let raw: String
    let hasError: Bool

    var kind: Kind {
        if hasError { return .error }
        switch type {
        case "request": return .request
        case "response": return .response
        case "light-update": return .lightUpdate
        default: return .other
        }
    }

    init?(line: String) {
        guard
            let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        type = object["type"] as? String ?? "event"
        method = object["method"] as? String
        time = (object["timestamp"] as? String).flatMap(FlexibleDate.parse)
        latency = object["latency_ms"] as? Double ?? (object["latency_ms"] as? Int).map(Double.init)
        raw = line
        hasError = object["error"] != nil

        let errorMessage = ((object["error"] as? [String: Any])?["message"] as? String)
        let oldStatus = object["old_status"] as? String
        let newStatus = object["new_status"] as? String
        let endpoint = object["endpoint"] as? String
        let target = object["target_id"] as? String

        switch type {
        case "request":
            summary = method ?? "request"
            detail = TrafficEvent.compactJSON(object["params"])

        case "response":
            summary = method ?? "response"
            detail = errorMessage

        case "light-update":
            summary = endpoint ?? target ?? "light"
            var transition = [oldStatus, newStatus]
                .compactMap { $0 }
                .joined(separator: " → ")
            if let via = object["via"] as? String, !via.isEmpty {
                transition += " · \(via)"
            }
            detail = transition.isEmpty ? nil : transition

        default:
            summary = method ?? type
            detail = errorMessage ?? TrafficEvent.compactJSON(object["result"])
        }
    }

    private static func compactJSON(_ value: Any?) -> String? {
        guard
            let value,
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8),
            text != "{}"
        else { return nil }
        return text
    }
}

// MARK: - Dates

/// adhd writes RFC 3339 with nanoseconds, which ISO8601DateFormatter only
/// partly accepts. Parse the common forms and fall back to dropping the
/// fractional part.
enum FlexibleDate {
    private static let iso = ISO8601DateFormatter()

    private static let plain: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        if let date = iso.date(from: string) { return date }

        var stripped = string
        if let dot = stripped.firstIndex(of: ".") {
            var end = stripped.index(after: dot)
            while end < stripped.endIndex, stripped[end].isNumber {
                end = stripped.index(after: end)
            }
            stripped.removeSubrange(dot..<end)
        }
        if let date = iso.date(from: stripped) { return date }
        return plain.date(from: stripped)
    }
}
