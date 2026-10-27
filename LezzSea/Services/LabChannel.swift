//
//  LabChannel.swift
//  LezzSea
//
//  The private channel to `lezz sea run`.
//
//  When lezz.go starts the app it sets LEZZ_CHANNEL=1 and gives it a pipe on
//  stdin/stdout. The app can then *ask* for an isotope — a running member with
//  its own identity — instead of exec'ing anything itself. That is what lets
//  the sandboxed App Store build launch a lab: the request is data, and lezz.go
//  (outside the sandbox) is the process that runs the alarm.
//
//  One JSON object per line. A normal Finder launch has no channel and prints
//  nothing; the same build stays a viewer and offers the copy actions.
//

import Darwin
import Foundation

@MainActor
final class LabChannel {

    static let shared = LabChannel()

    struct Request: Encodable {
        var v = 1
        var type = "request"
        var id = ""
        var want: String
        var cluster: String?
        var members: [Member]?
        var slug: String?
        var healthPorts: [Int]?
        var gherkinDirectory: String?
    }

    /// The derived YAML travels in the request. The app's sandbox container is
    /// TCC-protected from lezz.go, so a path into it would be unreadable.
    struct Member: Encodable {
        var name: String
        var config: String
    }

    struct Reply: Decodable {
        var v: Int?
        var type: String?
        var id: String?
        var ok: Bool?
        var error: String?
        var adhd: ADHDPayload?
    }

    struct ADHDPayload: Decodable {
        var endpoint: String
        var port: Int
        var configPath: String
        var pidPath: String
    }

    enum ChannelError: LocalizedError {
        case inactive
        case timeout
        case lost
        case refused(String)

        var errorDescription: String? {
            switch self {
            case .inactive:
                "This build was not started by `lezz sea run`, so it has no isotope channel."
            case .timeout:
                "lezz did not answer the isotope request."
            case .lost:
                "The lezz channel closed; relaunch the app with `lezz sea run`."
            case .refused(let message):
                message
            }
        }
    }

    let isActive: Bool
    /// The directory lezz.go owns for configs, logs and pid files. Set only
    /// when lezz.go started the app; it is outside this app's sandbox.
    let labRoot: URL?
    private(set) var isConnected = false
    private var started = false
    private var nextID = 0
    private var buffer: [UInt8] = []
    private var pending: [String: CheckedContinuation<Reply, Error>] = [:]

    private init() {
        isActive = ProcessInfo.processInfo.environment["LEZZ_CHANNEL"] == "1"
        labRoot = ProcessInfo.processInfo.environment["LEZZ_SEA_LAB_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Starts the channel and announces the directory the app writes its
    /// cluster configs into. lezz.go confines every requested path to it.
    func start(clustersRoot: URL) {
        guard isActive, !started else { return }
        started = true

        // A parent that exits closes the pipe; a write must not kill the app.
        signal(SIGPIPE, SIG_IGN)

        let hello: [String: Any] = [
            "v": 1,
            "type": "hello",
            "clustersRoot": clustersRoot.path,
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        ]
        _ = write(hello)

        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                self?.ingest(data)
            }
        }
        isConnected = true
    }

    // MARK: - Requests

    func startIsotope(_ cluster: LabCluster, configs: [String]) async throws -> Reply {
        let members = cluster.members.enumerated().map { index, member in
            Member(
                name: member.directory.lastPathComponent,
                config: index < configs.count ? configs[index] : ""
            )
        }
        var request = Request(want: "start", cluster: cluster.slug)
        request.members = members
        return try await send(request)
    }

    func pairADHD(slug: String, healthPorts: [Int], gherkin: URL?) async throws -> Reply {
        var request = Request(want: "adhd", cluster: slug)
        request.slug = slug
        request.healthPorts = healthPorts
        request.gherkinDirectory = gherkin?.path
        return try await send(request)
    }

    func stopIsotopes(_ cluster: LabCluster) async throws -> Reply {
        try await send(Request(want: "stop", cluster: cluster.slug))
    }

    func reveal(_ cluster: LabCluster) async throws -> Reply {
        try await send(Request(want: "reveal", cluster: cluster.slug))
    }

    private func send(_ request: Request) async throws -> Reply {
        guard isActive else { throw ChannelError.inactive }
        guard isConnected else { throw ChannelError.lost }

        nextID += 1
        let id = "\(nextID)"
        var request = request
        request.id = id

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            guard write(request) else {
                pending.removeValue(forKey: id)?.resume(throwing: ChannelError.lost)
                return
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard let self, let waiting = self.pending.removeValue(forKey: id) else { return }
                waiting.resume(throwing: ChannelError.timeout)
            }
        }
    }

    // MARK: - Wire

    private func write(_ request: Request) -> Bool {
        guard let data = try? JSONEncoder().encode(request) else { return false }
        return write(data)
    }

    private func write(_ object: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        return write(data)
    }

    private func write(_ data: Data) -> Bool {
        var line = data
        line.append(0x0A)
        do {
            try FileHandle.standardOutput.write(contentsOf: line)
            return true
        } catch {
            isConnected = false
            return false
        }
    }

    private func ingest(_ data: Data) {
        guard !data.isEmpty else {
            isConnected = false
            FileHandle.standardInput.readabilityHandler = nil
            for (_, waiting) in pending {
                waiting.resume(throwing: ChannelError.lost)
            }
            pending.removeAll()
            return
        }

        buffer.append(contentsOf: data)
        var start = 0
        for index in buffer.indices where buffer[index] == 0x0A {
            if index > start {
                let line = Data(buffer[start..<index])
                handle(line)
            }
            start = index + 1
        }
        if start > 0 {
            buffer.removeFirst(start)
        }
    }

    private func handle(_ line: Data) {
        guard
            let reply = try? JSONDecoder().decode(Reply.self, from: line),
            let id = reply.id,
            let waiting = pending.removeValue(forKey: id)
        else { return }

        if reply.ok == true {
            waiting.resume(returning: reply)
        } else {
            waiting.resume(throwing: ChannelError.refused(reply.error ?? "lezz refused the request."))
        }
    }
}
