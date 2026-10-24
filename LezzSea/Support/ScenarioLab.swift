//
//  ScenarioLab.swift
//  LezzSea
//
//  Runs a scenario through the signed lab helper.
//
//  The sandboxed build can only copy commands: macOS refuses to launch an
//  external process from it, and an SMAppService agent would have to be
//  sandboxed too, which cannot exec `lezz`. The launcher is therefore compiled
//  into the unsandboxed Lab configuration, where it runs `lezz` directly.
//
//  Each launch gets its own derived config (absolute state, remapped ports) and
//  its own instance directory. The alarm writes its pid file there, so the same
//  job channel stops it with `ops stop`.
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ScenarioLab {

    struct Instance: Codable, Identifiable, Hashable, Sendable {
        let scenarioID: String
        let name: String
        let slug: String
        let offset: Int
        let healthPort: Int
        let configPath: String
        let pidPath: String
        let startedAt: Date

        var id: String { "\(slug)-\(offset)" }

        var directory: URL {
            URL(fileURLWithPath: configPath).deletingLastPathComponent()
        }

        var healthURL: URL {
            URL(string: "http://127.0.0.1:\(healthPort)/status")!
        }

        var adhdEndpoint: String {
            "http://127.0.0.1:\(healthPort)"
        }

        var launchCommand: String {
            "lezz run ocd-smoke-alarm serve --config=\(configPath) --mode=headless"
        }
    }

    enum RunState: String, Sendable {
        case starting
        case running
        case unreachable

        var label: String {
            switch self {
            case .starting: "starting"
            case .running: "running"
            case .unreachable: "unreachable"
            }
        }
    }

    private(set) var checkout: URL?
    private(set) var instances: [Instance] = []
    private(set) var states: [String: RunState] = [:]
    private(set) var busy: Set<String> = []
    var lastError: String?

    private let bookmarkKey = "lab.smokeAlarmCheckout"
    private let fileManager = FileManager.default

    init() {
        restoreCheckout()
        loadInstances()
    }

    // MARK: - Checkout

    func chooseCheckout() {
        let panel = NSOpenPanel()
        panel.message = "Choose the smoke-alarm checkout — the folder containing configs/samples."
        panel.prompt = "Use Checkout"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = checkout
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("projects/personal/smoke-alarm", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            _ = url.startAccessingSecurityScopedResource()
            checkout = url
            lastError = nil
        } catch {
            lastError = "Could not keep access to \(url.path): \(error.localizedDescription)"
        }
    }

    var checkoutName: String? {
        checkout?.lastPathComponent
    }

    private func restoreCheckout() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            #if LAB_LAUNCHER
            checkout = defaultCheckout()
            #endif
            return
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            #if LAB_LAUNCHER
            checkout = defaultCheckout()
            #endif
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        checkout = url
    }

    /// The Lab build is unsandboxed and usually runs on the lab machine, so the
    /// conventional checkout is a useful default. The sandboxed build never
    /// reaches this path without a user-selected bookmark.
    private func defaultCheckout() -> URL? {
        let url = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("projects/personal/smoke-alarm", isDirectory: true)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Launch

    func instance(for scenario: ScenarioCatalog.Scenario) -> Instance? {
        instances.first { $0.scenarioID == scenario.file }
    }

    func state(for scenario: ScenarioCatalog.Scenario) -> RunState? {
        instance(for: scenario).flatMap { states[$0.id] }
    }

    func launch(_ scenario: ScenarioCatalog.Scenario) async {
        guard !busy.contains(scenario.id) else { return }

        if checkout == nil {
            chooseCheckout()
        }
        guard let checkout else {
            lastError = "Choose the smoke-alarm checkout before launching."
            return
        }

        let sample = checkout.appendingPathComponent("configs/samples/\(scenario.file)")
        guard fileManager.isReadableFile(atPath: sample.path) else {
            lastError = "\(scenario.file) is not readable in the selected checkout."
            return
        }

        busy.insert(scenario.id)
        defer { busy.remove(scenario.id) }

        var created: Instance?

        do {
            let source = try String(contentsOf: sample, encoding: .utf8)
            let prepared = try prepare(source: source, scenario: scenario)
            try writeMetadata(prepared.instance)

            created = prepared.instance
            instances.append(prepared.instance)
            states[prepared.instance.id] = .starting

            _ = try runLezz([
                "run", "ocd-smoke-alarm", "serve",
                "--config=\(prepared.instance.configPath)",
                "--mode=headless",
            ], wait: false)

            await waitForHealth(prepared.instance)
        } catch {
            if let created, states[created.id] == .starting {
                removeMetadata(created)
            }
            lastError = error.localizedDescription
        }
    }

    private struct Prepared {
        let instance: Instance
    }

    private func prepare(
        source: String,
        scenario: ScenarioCatalog.Scenario
    ) throws -> Prepared {
        // The app is not entitled to bind a probe socket (network.server), so
        // it cannot ask the kernel which ports are free. Instead each live
        // instance owns a slot; a port taken by something else shows up as an
        // unreachable instance, and Stop frees the slot for a retry.
        let used = Set(instances.map(\.offset))
        guard let offset = stride(from: 0, through: 30_000, by: 1_000)
            .first(where: { !used.contains($0) }) else {
            throw LabError.noFreeSlot
        }

        let directory = instancesRoot
            .appendingPathComponent("\(scenario.slug)-\(offset)", isDirectory: true)
        let derived = try ScenarioConfig.derive(
            source: source,
            instanceDirectory: directory,
            offset: offset
        )

        try fileManager.createDirectory(
            at: directory.appendingPathComponent("state", isDirectory: true),
            withIntermediateDirectories: true
        )
        let configURL = directory.appendingPathComponent("config.yaml")
        try derived.text.write(to: configURL, atomically: true, encoding: .utf8)

        let instance = Instance(
            scenarioID: scenario.file,
            name: scenario.name,
            slug: scenario.slug,
            offset: offset,
            healthPort: derived.healthPort,
            configPath: configURL.path,
            pidPath: directory.appendingPathComponent("ocd-smoke-alarm.pid").path,
            startedAt: .now
        )
        return Prepared(instance: instance)
    }

    // MARK: - Stop

    func stop(_ instance: Instance) async {
        guard !busy.contains(instance.id) else { return }

        busy.insert(instance.id)
        defer { busy.remove(instance.id) }

        do {
            let status = try runLezz([
                "run", "ocd-smoke-alarm", "ops", "stop",
                "-pid-file", instance.pidPath,
            ], wait: true)
            guard status == 0 else {
                throw LabError.launcherRejected("ops stop exited \(status)")
            }

            for _ in 0..<10 {
                if await isHealthy(instance) == false { break }
                try? await Task.sleep(for: .milliseconds(300))
            }
            removeMetadata(instance)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reveal(_ instance: Instance) {
        NSWorkspace.shared.activateFileViewerSelecting([instance.directory])
    }

    // MARK: - Health

    func monitor() async {
        while !Task.isCancelled {
            await refreshHealth()
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func refreshHealth() async {
        for instance in instances {
            if await isHealthy(instance) {
                states[instance.id] = .running
            } else if states[instance.id] == .running {
                states[instance.id] = .unreachable
            }
        }
    }

    private func waitForHealth(_ instance: Instance) async {
        for _ in 0..<20 {
            if await isHealthy(instance) {
                states[instance.id] = .running
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        states[instance.id] = .unreachable
        lastError = "\(instance.name) did not answer on 127.0.0.1:\(instance.healthPort)."
    }

    private func isHealthy(_ instance: Instance) async -> Bool {
        var request = URLRequest(url: instance.healthURL)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }

        return object["live"] as? Bool == true
    }

    // MARK: - Storage

    private var instancesRoot: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("LezzSea/Instances", isDirectory: true)
    }

    private func loadInstances() {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: instancesRoot,
            includingPropertiesForKeys: nil
        ) else { return }

        instances = directories.compactMap { directory in
            let url = directory.appendingPathComponent("instance.json")
            guard
                let data = try? Data(contentsOf: url),
                let instance = try? JSONDecoder().decode(Instance.self, from: data)
            else { return nil }
            return instance
        }
        .sorted { $0.startedAt < $1.startedAt }

        for instance in instances {
            states[instance.id] = .starting
        }
    }

    private func writeMetadata(_ instance: Instance) throws {
        let data = try JSONEncoder().encode(instance)
        try data.write(
            to: instance.directory.appendingPathComponent("instance.json"),
            options: .atomic
        )
    }

    private func removeMetadata(_ instance: Instance) {
        try? fileManager.removeItem(at: instance.directory.appendingPathComponent("instance.json"))
        instances.removeAll { $0.id == instance.id }
        states[instance.id] = nil
    }

    // MARK: - lezz

    private func lezzBinary() -> String? {
        let candidates = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".lezz/bin/lezz").path,
            "/opt/homebrew/bin/lezz",
            "/usr/local/bin/lezz",
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    /// Runs `lezz` with a fixed, app-built argument list. The Lab build is
    /// unsandboxed, so the alarm it execs can bind its ports and write state.
    private func runLezz(_ arguments: [String], wait: Bool) throws -> Int32 {
        #if LAB_LAUNCHER
        guard let lezz = lezzBinary() else {
            throw LabError.lezzMissing
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lezz)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // LaunchServices gives a GUI app a minimal PATH; the npx/uvx probes
        // need the Homebrew paths a terminal would have.
        var environment = ProcessInfo.processInfo.environment
        let inherited = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + inherited
        process.environment = environment

        try process.run()

        if wait {
            process.waitUntilExit()
            return process.terminationStatus
        }
        return 0
        #else
        throw LabError.labBuildRequired
        #endif
    }
}

enum LabError: LocalizedError {
    case noFreeSlot
    case labBuildRequired
    case lezzMissing
    case launcherRejected(String)

    var errorDescription: String? {
        switch self {
        case .noFreeSlot:
            "All lab slots are in use. Stop an instance and try again."
        case .labBuildRequired:
            "Launching needs the Lab build of lezz.sea; the App Store build only copies commands."
        case .lezzMissing:
            "lezz is not installed. Install it from the lab, then try again."
        case .launcherRejected(let message):
            "The launcher could not start the alarm: \(message)"
        }
    }
}
