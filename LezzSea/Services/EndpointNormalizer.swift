//
//  EndpointNormalizer.swift
//  LezzSea
//

import Foundation

/// Turns whatever the operator types, drops, or pastes into an adhd MCP URL.
enum EndpointNormalizer {
    /// `127.0.0.1:9090` → `http://127.0.0.1:9090/mcp`
    static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix(":") {
            text = "127.0.0.1\(text)"
        }
        if !text.contains("://") {
            text = "http://\(text)"
        }
        guard
            var components = URLComponents(string: text),
            let host = components.host,
            !host.isEmpty
        else { return nil }

        components.scheme = (components.scheme ?? "http").lowercased()
        components.fragment = nil
        components.query = nil
        if components.path.isEmpty || components.path == "/" {
            components.path = "/mcp"
        }
        return components.url
    }

    /// Finds adhd endpoints in a config file: an `mcp_server.addr` value, or
    /// any explicit URL whose path names an MCP surface. Alarm endpoints are
    /// deliberately not candidates — they are not adhd.
    static func endpoints(in text: String) -> [URL] {
        var candidates: [String] = []

        for match in matches(#"addr\s*:\s*"?([^"\s,}]+)"#, in: text) {
            candidates.append(match)
        }
        for match in matches(#"https?://[^\s"'<>\\]+"#, in: text)
        where match.lowercased().contains("/mcp") {
            candidates.append(match.trimmingCharacters(in: CharacterSet(charactersIn: ".,;)]}")))
        }

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard let url = normalize(candidate) else { return nil }
            return seen.insert(url.absoluteString).inserted ? url : nil
        }
    }

    static func dedupe(_ clusters: [Cluster]) -> [Cluster] {
        var seen = Set<String>()
        return clusters.filter { seen.insert($0.id).inserted }
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            guard result.numberOfRanges > 1, let range = Range(result.range(at: 1), in: text) else {
                return nil
            }
            return String(text[range])
        }
    }
}
