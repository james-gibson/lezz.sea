//
//  AppModel.swift
//  LezzSea
//

import AppKit
import Foundation
import Observation

/// Everything the window shows: which adhd cluster is selected, its lights,
/// and the live tail of its MCP traffic log.
@MainActor
@Observable
final class AppModel {
    enum Connection: Equatable {
        case idle
        case connecting
        case online
        case offline(String)

        var isOnline: Bool {
            if case .online = self { return true }
            return false
        }

        var label: String {
            switch self {
            case .idle: "Not connected"
            case .connecting: "Connecting…"
            case .online: "Connected"
            case .offline(let message): message
            }
        }
    }

    enum LogState: Equatable {
        case missing
        case waiting
        case streaming
    }

    enum Tab: String, CaseIterable, Identifiable {
        case lights
        case events
        case isotopes
        case boundaries
        case scenarios

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lights: "Lights"
            case .events: "Events"
            case .isotopes: "Isotopes"
            case .boundaries: "Boundaries"
            case .scenarios: "Scenarios"
            }
        }

        var symbol: String {
            switch self {
            case .lights: "circle.grid.2x2"
            case .events: "waveform.path.ecg"
            case .isotopes: "atom"
            case .boundaries: "checkmark.shield"
            case .scenarios: "list.bullet.rectangle"
            }
        }

        /// Lights and events describe a cluster. The isotope chart, the
        /// boundary list and the scenario catalog are static and must stay
        /// reachable with no cluster running.
        var needsCluster: Bool {
            self == .lights || self == .events
        }
    }

    // MARK: - Observable state

    private(set) var manualClusters: [Cluster] = []
    private(set) var discoveredClusters: [Cluster] = []
    private(set) var lights: [Light] = []
    private(set) var status: ClusterStatus?
    private(set) var connection: Connection = .idle
    private(set) var lastRefresh: Date?
    private(set) var events: [TrafficEvent] = []
    private(set) var eventsPaused = false
    private(set) var backlog: [TrafficEvent] = []
    private(set) var logState: LogState = .missing
    private(set) var logPath: String = ""
    private(set) var isDiscovering = false
    var selectedClusterID: String?
    var tab: Tab = .lights
    var toast: String?
    var isAddingCluster = false

    // MARK: - Settings (persisted)

    var refreshInterval: Double = 3 {
        didSet { defaults.set(refreshInterval, forKey: Key.refresh) }
    }

    var maxEvents: Int = 2_000 {
        didSet {
            defaults.set(maxEvents, forKey: Key.maxEvents)
            trimEvents()
        }
    }

    var autoDiscover: Bool = true {
        didSet { defaults.set(autoDiscover, forKey: Key.autoDiscover) }
    }

    var registryText: String = "http://127.0.0.1:19100/cluster" {
        didSet { defaults.set(registryText, forKey: Key.registry) }
    }

    var defaultEndpointText: String = "http://127.0.0.1:9090/mcp" {
        didSet { defaults.set(defaultEndpointText, forKey: Key.endpoint) }
    }

    // MARK: - Derived

    var clusters: [Cluster] {
        EndpointNormalizer.dedupe(manualClusters + discoveredClusters)
    }

    var selectedCluster: Cluster? {
        guard let selectedClusterID else { return nil }
        return clusters.first { $0.id == selectedClusterID }
    }

    var summary: LightSummary {
        if let lights = status?.lights { return lights }
        return LightSummary(
            total: lights.count,
            green: lights.filter { $0.status == "green" }.count,
            red: lights.filter { $0.status == "red" }.count,
            yellow: lights.filter { $0.status == "yellow" }.count,
            dark: lights.filter { $0.status == "dark" }.count
        )
    }

    // MARK: - Plumbing

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let client = ADHDClient()
    @ObservationIgnored private let tail = EventTail()
    @ObservationIgnored private let bonjour = BonjourDiscovery()
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    /// The URL whose security scope this process currently holds. The app is
    /// sandboxed, so a log outside the container is only readable after the
    /// user picks it; the scope is what keeps that permission alive for the
    /// current run, and the bookmark is what survives the next launch.
    @ObservationIgnored private var scopedURL: URL?

    private enum Key {
        static let refresh = "refreshInterval"
        static let maxEvents = "maxEvents"
        static let autoDiscover = "autoDiscover"
        static let registry = "registryURL"
        static let endpoint = "defaultEndpoint"
        static let manual = "manualClusters"
        static let selected = "selectedCluster"
        static let logPath = "logPath"
        static let logBookmark = "logBookmark"
    }

    static var defaultLogPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/kb-adhd.jsonl")
            .path
    }

    init() {
        let defaults = UserDefaults.standard

        refreshInterval = defaults.object(forKey: Key.refresh) as? Double ?? 3
        maxEvents = defaults.object(forKey: Key.maxEvents) as? Int ?? 2_000
        autoDiscover = defaults.object(forKey: Key.autoDiscover) as? Bool ?? true
        registryText = defaults.string(forKey: Key.registry) ?? "http://127.0.0.1:19100/cluster"
        defaultEndpointText = defaults.string(forKey: Key.endpoint) ?? "http://127.0.0.1:9090/mcp"
        logPath = defaults.string(forKey: Key.logPath) ?? Self.defaultLogPath
        selectedClusterID = defaults.string(forKey: Key.selected)

        if let data = defaults.data(forKey: Key.manual),
           let saved = try? JSONDecoder().decode([Cluster].self, from: data) {
            manualClusters = saved
        }

        tail.onLines = { [weak self] lines in self?.ingest(lines) }
        tail.onOpen = { [weak self] in self?.logState = .streaming }
        tail.onMissing = { [weak self] in self?.logState = .missing }

        bonjour.onChange = { [weak self] urls in
            Task { @MainActor in self?.mergeBonjour(urls) }
        }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true

        resolveStoredLog()
        startTail()
        bonjour.start()

        await discover()
        startMonitor()
    }

    private func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = max(1, self.refreshInterval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    // MARK: - Selection

    func select(_ id: String?) {
        guard selectedClusterID != id else { return }
        selectedClusterID = id
        defaults.set(id, forKey: Key.selected)
        lights = []
        status = nil
        lastRefresh = nil
        connection = .idle
        Task { await refresh() }
    }

    func removeCluster(_ cluster: Cluster) {
        manualClusters.removeAll { $0.id == cluster.id }
        persistManual()
        if selectedClusterID == cluster.id {
            select(clusters.first?.id)
        }
    }

    @discardableResult
    func addCluster(name: String, urlString: String) -> String? {
        guard let endpoint = EndpointNormalizer.normalize(urlString) else {
            return "That is not a host or URL the app can reach."
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cluster = Cluster(
            name: trimmed.isEmpty ? (endpoint.host ?? "adhd") : trimmed,
            endpoint: endpoint,
            source: .manual
        )
        if !manualClusters.contains(where: { $0.endpoint == endpoint }) {
            manualClusters.append(cluster)
            persistManual()
        }
        discoveredClusters.removeAll { $0.endpoint == endpoint }
        select(cluster.id)
        return nil
    }

    private func persistManual() {
        guard let data = try? JSONEncoder().encode(manualClusters) else { return }
        defaults.set(data, forKey: Key.manual)
    }

    // MARK: - Discovery

    func discover() async {
        isDiscovering = true
        defer { isDiscovering = false }

        var found: [Cluster] = []

        if autoDiscover {
            if let url = URL(string: registryText) {
                found += await registryClusters(from: url)
            }
            if let endpoint = EndpointNormalizer.normalize(defaultEndpointText) {
                if let instance = await probe(endpoint) {
                    found.append(Cluster(
                        name: instance.isEmpty ? "local adhd" : instance,
                        endpoint: endpoint,
                        source: .local
                    ))
                }
            }
            if let local = EndpointNormalizer.normalize("127.0.0.1:9090"),
               !found.contains(where: { $0.endpoint == local }),
               let instance = await probe(local) {
                found.append(Cluster(
                    name: instance.isEmpty ? "local adhd" : instance,
                    endpoint: local,
                    source: .local
                ))
            }
        }

        let bonjourClusters = discoveredClusters.filter { $0.source == .bonjour }
        discoveredClusters = EndpointNormalizer.dedupe(found + bonjourClusters)
        ensureSelection()
    }

    private func registryClusters(from url: URL) async -> [Cluster] {
        guard
            let data = try? await client.fetch(url),
            let entries = try? JSONDecoder().decode([String: RegistryEntry].self, from: data)
        else { return [] }

        var clusters: [Cluster] = []
        for (name, entry) in entries {
            guard
                let raw = entry.adhdMcp,
                let endpoint = EndpointNormalizer.normalize(raw),
                await probe(endpoint) != nil
            else { continue }
            clusters.append(Cluster(name: name, endpoint: endpoint, source: .registry))
        }
        return clusters
    }

    private func probe(_ endpoint: URL) async -> String? {
        guard let status = try? await client.status(at: endpoint) else { return nil }
        return status.instance ?? "adhd"
    }

    private func mergeBonjour(_ urls: [URL]) {
        var merged = discoveredClusters.filter { $0.source != .bonjour }
        merged += urls.map { Cluster(name: $0.host ?? "adhd", endpoint: $0, source: .bonjour) }
        discoveredClusters = EndpointNormalizer.dedupe(merged)
        ensureSelection()
    }

    private func ensureSelection() {
        let all = clusters
        if let selectedClusterID, all.contains(where: { $0.id == selectedClusterID }) {
            return
        }
        let preferred = all.first { $0.source == .registry }
            ?? all.first { $0.source == .local }
            ?? all.first
        selectedClusterID = preferred?.id
        defaults.set(preferred?.id, forKey: Key.selected)
        if preferred != nil {
            Task { await refresh() }
        }
    }

    // MARK: - Polling

    func refresh() async {
        guard let cluster = selectedCluster else {
            connection = .idle
            return
        }
        if !connection.isOnline {
            connection = .connecting
        }

        do {
            async let statusRequest = client.status(at: cluster.endpoint)
            async let lightsRequest = client.lights(at: cluster.endpoint)
            let (newStatus, newLights) = try await (statusRequest, lightsRequest)

            guard cluster.id == selectedCluster?.id else { return }
            status = newStatus
            lights = newLights
            connection = .online
            lastRefresh = .now
        } catch {
            guard cluster.id == selectedCluster?.id else { return }
            connection = .offline(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        if error is DecodingError {
            return "The cluster sent a response the app could not read."
        }
        return error.localizedDescription
    }

    // MARK: - Event log

    func startTail() {
        events.removeAll()
        backlog.removeAll()
        logState = FileManager.default.fileExists(atPath: logPath) ? .waiting : .missing
        tail.start(url: URL(fileURLWithPath: logPath))
    }

    func chooseLog() {
        let panel = NSOpenPanel()
        panel.title = "Choose adhd MCP traffic log"
        panel.message = "adhd writes one JSON object per line to its stdout log."
        panel.prompt = "Stream"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json, .plainText, .data]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)

        if panel.runModal() == .OK, let url = panel.url {
            setLogURL(url)
        }
    }

    func setLogURL(_ url: URL) {
        adoptSecurityScope(for: url)
        logPath = url.path
        defaults.set(logPath, forKey: Key.logPath)

        // Persist a security-scoped bookmark so a sandboxed relaunch can read
        // the same file without asking again. Outside the sandbox the call
        // throws and the stored path is used instead.
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: Key.logBookmark)
        } else {
            defaults.removeObject(forKey: Key.logBookmark)
        }

        startTail()
        toast = "Streaming \(url.lastPathComponent)"
    }

    func openDefaultLog() {
        let url = URL(fileURLWithPath: Self.defaultLogPath)

        // In the sandbox the default log is outside the container and is not
        // readable until the user grants it. Sending them to the picker is the
        // honest move; a silent "missing" state would look like a broken app.
        if FileManager.default.isReadableFile(atPath: url.path) {
            setLogURL(url)
        } else {
            chooseLog()
        }
    }

    // MARK: - Log bookmarks

    private func resolveStoredLog() {
        if let data = defaults.data(forKey: Key.logBookmark) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                adoptSecurityScope(for: url)
                logPath = url.path

                if stale, let refreshed = try? url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    defaults.set(refreshed, forKey: Key.logBookmark)
                }
                return
            }
            defaults.removeObject(forKey: Key.logBookmark)
        }

        if !FileManager.default.fileExists(atPath: logPath) {
            logPath = Self.defaultLogPath
        }
    }

    private func adoptSecurityScope(for url: URL) {
        releaseSecurityScope()
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }
    }

    private func releaseSecurityScope() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    func clearEvents() {
        events.removeAll()
        backlog.removeAll()
    }

    func togglePause() {
        if eventsPaused {
            eventsPaused = false
            if !backlog.isEmpty {
                append(backlog)
                backlog.removeAll()
            }
        } else {
            eventsPaused = true
        }
    }

    private func ingest(_ lines: [String]) {
        let incoming = lines.compactMap(TrafficEvent.init(line:))
        guard !incoming.isEmpty else { return }

        if eventsPaused {
            backlog.append(contentsOf: incoming)
            if backlog.count > maxEvents {
                backlog.removeFirst(backlog.count - maxEvents)
            }
        } else {
            append(incoming)
        }
    }

    private func append(_ incoming: [TrafficEvent]) {
        events.append(contentsOf: incoming)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    private func trimEvents() {
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    // MARK: - Drag and drop

    func acceptDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        var addedClusters = 0
        var firstAdded: URL?
        var openedLog = false
        var unsupported: [String] = []

        for url in urls {
            switch url.pathExtension.lowercased() {
            case "jsonl", "ndjson", "log", "txt":
                setLogURL(url)
                openedLog = true

            case "yaml", "yml", "json":
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    unsupported.append(url.lastPathComponent)
                    continue
                }
                let endpoints = EndpointNormalizer.endpoints(in: text)
                for endpoint in endpoints where addClusterSilently(endpoint) {
                    addedClusters += 1
                    if firstAdded == nil { firstAdded = endpoint }
                }

            default:
                unsupported.append(url.lastPathComponent)
            }
        }

        if let firstAdded, let cluster = clusters.first(where: { $0.endpoint == firstAdded }) {
            select(cluster.id)
        }

        if addedClusters > 0 {
            toast = "Added \(addedClusters) cluster\(addedClusters == 1 ? "" : "s")"
        } else if !openedLog {
            if let name = unsupported.first {
                toast = "Can't use \(name). Drop a .jsonl log or a cluster config."
            }
        }
    }

    private func addClusterSilently(_ endpoint: URL) -> Bool {
        guard !clusters.contains(where: { $0.endpoint == endpoint }) else { return false }
        let cluster = Cluster(
            name: endpoint.host ?? "adhd",
            endpoint: endpoint,
            source: .manual
        )
        manualClusters.append(cluster)
        persistManual()
        if selectedClusterID == nil {
            select(cluster.id)
        }
        return true
    }
}

private struct RegistryEntry: Decodable {
    let adhdMcp: String?

    private enum CodingKeys: String, CodingKey {
        case adhdMcp = "adhd_mcp"
    }
}
