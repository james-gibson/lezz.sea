//
//  ADHDClient.swift
//  LezzSea
//

import Foundation

/// A small JSON-RPC client for adhd's MCP endpoint.
///
/// adhd answers both the standard `tools/call` envelope and its own method
/// names directly (`adhd.status`, `adhd.lights.list`). The direct form keeps
/// the result shape readable, so that is what the dashboard uses.
final class ADHDClient {
    enum ClientError: LocalizedError {
        case http(Int)
        case rpc(String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .http(let code): "The cluster answered HTTP \(code)."
            case .rpc(let message): message
            case .malformed: "The cluster sent a response the app could not read."
            }
        }
    }

    private struct RPCError: Decodable {
        let code: Int
        let message: String
    }

    private struct Envelope<T: Decodable>: Decodable {
        let result: T?
        let error: RPCError?
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = FlexibleDate.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised date: \(text)"
                )
            }
            return date
        }
        self.decoder = decoder
    }

    func status(at endpoint: URL) async throws -> ClusterStatus {
        try await call("adhd.status", at: endpoint, as: ClusterStatus.self)
    }

    func lights(at endpoint: URL) async throws -> [Light] {
        try await call("adhd.lights.list", at: endpoint, as: LightsResponse.self).lights
    }

    func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
        return data
    }

    private func call<T: Decodable>(_ method: String, at endpoint: URL, as: T.Type) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": [:] as [String: String],
        ])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }

        let envelope = try decoder.decode(Envelope<T>.self, from: data)
        if let error = envelope.error {
            throw ClientError.rpc(error.message)
        }
        guard let result = envelope.result else {
            throw ClientError.malformed
        }
        return result
    }
}
