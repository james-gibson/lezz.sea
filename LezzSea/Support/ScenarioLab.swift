//
//  ScenarioLab.swift
//  LezzSea
//
//  Runs a scenario through the signed lab helper, and reads the clusters that
//  are already running.
//
//  The sandboxed build can only copy commands: macOS refuses to launch an
//  external process from it, and an SMAppService agent would have to be
//  sandboxed too, which cannot exec `lezz`. The launcher is therefore compiled
//  into the unsandboxed Lab configuration, where it runs `lezz` directly.
//
//  Ports are not moved to tell instances apart. The alarm already negotiates
//  its own: the health server scans upward when its port is taken, and the
//  federation claims the first free slot in its range. The launcher therefore
//  rotates the isotope name, turns mDNS on, and finds the bound port by
//  scanning loopback upward and accepting a port only when `/status` names that
//  isotope. The advertisement is the designed channel and is used when it
//  answers, but a 127.0.0.1 port must not depend on the local-network
//  permission mDNS needs. The federation root is where peers announce each
//  other, so it is also where the app asks whether a cluster is whole.
//
//  `cluster.json` is the contract. A test script can write one and the app
//  treats that cluster exactly like one it started, which is how the launcher
//  was verified before it was allowed to launch multi-process scenarios.
//

import AppKit
import Foundation
import Observation

#if canImport(Darwin)
import Darwin
#endif

@MainActor
@Observable
final class ScenarioLab {

    enum RunState: String, Sendable {
        case starting
        case running
        /// Some members of the cluster answered, but not all of them.
        case partial
        case unreachable

        var label: String {
            switch self {
            case .starting: "starting"
            case .running: "running"
            case .partial: "partial"
            case .unreachable: "unreachable"
            }
        }
    }

    private(set) var checkout: URL?
    private(set) var clusters: [LabCluster] = []
    private(set) var states: [String: RunState] = [:]
    /// Members seen per cluster, for the `3/3` in the row badge.
    private(set) var membersUp: [String: Int] = [:]
    /// The port each member actually bound, keyed by isotope name. Filled from
    /// mDNS, or from a `/status` answer that names the isotope.
    private(set) var resolvedPorts: [String: Int] = [:]
    private(set) var busy: Set<String> = []
    /// The clusters whose paired adhd answered the last probe.
    private(set) var adhdAnswering: Set<String> = []
    /// How many lights the paired adhd reports, when it answered.
    private(set) var adhdLights: [String: Int] = [:]
    /// Why a pairing did not happen, keyed by cluster. Shown on the row so a
    /// missing adhd is visible without failing the launch that succeeded.
    private(set) var pairingNotes: [String: String] = [:]
    /// The watcher report for a paired cluster, rebuilt from its adhd.log.
    private(set) var reports: [String: WatcherReport] = [:]
    var lastError: String?

    private let bookmarkKey = "lab.smokeAlarmCheckout"
    private let fileManager = FileManager.default
    private let watcher = ServicePortWatcher(serviceType: ScenarioConfig.discoveryType)
    private let adhdClient = ADHDClient()
    @ObservationIgnored private var reportScans: [String: WatcherReport.Scanner] = [:]
    @ObservationIgnored private var advertisedPorts: [String: Int] = [:]
    @ObservationIgnored private var watching = false

    init() {
        restoreCheckout()
        loadClusters()
        watcher.onChange = { [weak self] ports in
            Task { @MainActor in
                self?.advertisedPorts = ports
                self?.applyAdvertisedPorts()
            }
        }
        startWatchingIfNeeded()
    }

    /// Browsing triggers the local-network prompt, and the sandboxed build can
    /// never have a launcher cluster to resolve. Only browse once a cluster
    /// exists to browse for.
    private func startWatchingIfNeeded() {
        guard !watching, !clusters.isEmpty else { return }
        watching = true
        watcher.start()
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

    // MARK: - Queries

    func cluster(for scenario: ScenarioCatalog.Scenario) -> LabCluster? {
        clusters.first { $0.scenarioID == scenario.file }
            ?? clusters.first { $0.slug == scenario.slug }
    }

    func state(for scenario: ScenarioCatalog.Scenario) -> RunState? {
        cluster(for: scenario).flatMap { states[$0.id] }
    }

    func membersUp(for scenario: ScenarioCatalog.Scenario) -> Int? {
        cluster(for: scenario).flatMap { membersUp[$0.id] }
    }

    /// The ports to hand adhd, in member order. A member whose port has not
    /// been discovered yet is skipped rather than guessed: pairing adhd with a
    /// port that answers for somebody else is worse than pairing it later.
    func healthPorts(for scenario: ScenarioCatalog.Scenario) -> [Int] {
        guard let cluster = cluster(for: scenario) else { return [] }
        return cluster.members.compactMap { resolvedPorts[$0.isotope] }
    }

    func port(for member: LabMember) -> Int? {
        resolvedPorts[member.isotope]
    }

    /// The pairing line for a row: the endpoint adhd answers on and how many
    /// lights it reports, or why it is not there. nil before a launch, when
    /// there is nothing to pair yet.
    func adhdSummary(for cluster: LabCluster) -> String? {
        if let note = pairingNotes[cluster.id] {
            return "adhd: \(note)"
        }
        guard let adhd = cluster.adhd else { return nil }
        guard adhdAnswering.contains(cluster.id) else {
            return "adhd: :\(adhd.port) not answering"
        }
        let lights = adhdLights[cluster.id].map { " · \($0) lights" } ?? ""
        return "adhd: :\(adhd.port)\(lights)"
    }

    /// The watcher report for a paired cluster. nil before a pairing exists,
    /// and after the cluster is stopped.
    func report(for cluster: LabCluster) -> WatcherReport? {
        reports[cluster.id]
    }

    // MARK: - Launch

    func launch(_ scenario: ScenarioCatalog.Scenario) async {
        guard !busy.contains(scenario.id) else { return }

        guard scenario.processes == 1 else {
            lastError = "\(scenario.name) is a \(scenario.processes)-process cluster. "
                + "Launch it with scripts/lab-cluster.sh until the launcher's discovery is verified."
            return
        }

        if cluster(for: scenario) != nil { return }

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

        var created: LabCluster?

        do {
            let source = try String(contentsOf: sample, encoding: .utf8)
            let cluster = try prepare(source: source, scenario: scenario)
            try writeMetadata(cluster)

            created = cluster
            clusters.append(cluster)
            states[cluster.id] = .starting

            for member in cluster.members {
                _ = try runLezz([
                    "run", "ocd-smoke-alarm", "serve",
                    "--config=\(member.configPath)",
                    "--mode=headless",
                ], log: member.logPath, wait: false)
            }

            await waitForHealth(cluster)

            if states[cluster.id] == .running {
                await pair(cluster)
            }
        } catch {
            if let created, states[created.id] == .starting {
                removeMetadata(created)
            }
            lastError = error.localizedDescription
        }
    }

    private func prepare(
        source: String,
        scenario: ScenarioCatalog.Scenario
    ) throws -> LabCluster {
        let clusterDirectory = clustersRoot
            .appendingPathComponent(scenario.slug, isDirectory: true)

        var members: [LabMember] = []
        var clusterID: String?
        var rootPort: Int?

        for index in 1...scenario.processes {
            let memberDirectory = clusterDirectory
                .appendingPathComponent("member-\(index)", isDirectory: true)
            let derived = try ScenarioConfig.derive(
                source: source,
                instanceDirectory: memberDirectory,
                slug: scenario.slug,
                index: index
            )

            try fileManager.createDirectory(
                at: memberDirectory.appendingPathComponent("state", isDirectory: true),
                withIntermediateDirectories: true
            )
            let configURL = memberDirectory.appendingPathComponent("config.yaml")
            try derived.text.write(to: configURL, atomically: true, encoding: .utf8)

            clusterID = derived.clusterID
            rootPort = derived.rootPort

            members.append(LabMember(
                index: index,
                isotope: derived.isotope,
                preferredHealthPort: derived.preferredHealthPort,
                configPath: configURL.path,
                pidPath: memberDirectory.appendingPathComponent("ocd-smoke-alarm.pid").path,
                logPath: memberDirectory.appendingPathComponent("alarm.log").path,
                stateDir: memberDirectory.appendingPathComponent("state", isDirectory: true).path
            ))
        }

        return LabCluster(
            scenarioID: scenario.file,
            name: scenario.name,
            slug: scenario.slug,
            clusterID: clusterID,
            rootPort: rootPort,
            startedAt: .now,
            members: members
        )
    }

    /// A launch is not finished when `lezz` exits; it is finished when the
    /// cluster answers. Give self-negotiation a few seconds, then say what to
    /// read if it never does.
    private func waitForHealth(_ cluster: LabCluster) async {
        for _ in 0..<30 {
            await refresh(cluster)
            if states[cluster.id] == .running { return }
            try? await Task.sleep(for: .milliseconds(400))
        }
        states[cluster.id] = .unreachable
        lastError = "\(cluster.name) did not answer on the federation root or its health ports. "
            + "Reveal the cluster directory to read member-1/alarm.log."
    }

    // MARK: - Pairing

    /// Starts a headless adhd that watches the cluster, and records its
    /// endpoint in `cluster.json` under the same `adhd` key the verification
    /// script writes.
    ///
    /// Pairing is best effort and after the fact: the alarm is already running,
    /// so a machine without adhd gets a note on the row rather than a failed
    /// launch. Every endpoint is a port whose `/status` named its member; a
    /// member that never resolved is not guessed at.
    private func pair(_ cluster: LabCluster) async {
        guard cluster.adhd == nil else { return }

        guard let adhdBinary = adhdBinary() else {
            pairingNotes[cluster.id] = "not installed — the alarm is running, but nothing is watching it"
            return
        }

        let ports = cluster.members.compactMap { resolvedPorts[$0.isotope] }
        guard ports.count == cluster.members.count else {
            pairingNotes[cluster.id] = "waits for every member's bound port"
            return
        }

        guard let mcpPort = ADHDPairing.freePort() else {
            pairingNotes[cluster.id] = "no free port in "
                + "\(ADHDPairing.portRange.lowerBound)–\(ADHDPairing.portRange.upperBound)"
            return
        }

        let directory = clusterDirectory(cluster)
        let features = checkout?.appendingPathComponent("features", isDirectory: true)
        let gherkinDirectory = features.flatMap {
            fileManager.fileExists(atPath: $0.path) ? $0 : nil
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let configURL = directory.appendingPathComponent("adhd.yaml")
            try ADHDPairing.config(
                slug: cluster.slug,
                healthPorts: ports,
                mcpPort: mcpPort,
                gherkinDirectory: gherkinDirectory
            )
            .write(to: configURL, atomically: true, encoding: .utf8)

            let logPath = directory.appendingPathComponent("adhd.log").path
            let pidPath = directory.appendingPathComponent("adhd.pid").path

            // An interrupted run can leave an adhd behind even though its
            // cluster.json is gone. Stop the orphan before writing over its pid
            // file, or two watchers would answer for this alarm and only one
            // would ever be stopped.
            stopProcess(atPIDFile: pidPath)
            reports[cluster.id] = nil
            reportScans[cluster.id] = nil

            let process = try start(adhdBinary, ["--headless", "--config", configURL.path], log: logPath)
            try "\(process.processIdentifier)\n".write(
                toFile: pidPath,
                atomically: true,
                encoding: .utf8
            )

            let record = LabADHD(
                endpoint: "http://127.0.0.1:\(mcpPort)/mcp",
                port: mcpPort,
                configPath: configURL.path,
                pidPath: pidPath
            )
            try store(record, on: cluster)
            pairingNotes[cluster.id] = nil

            await waitForADHD(cluster)
        } catch {
            pairingNotes[cluster.id] = error.localizedDescription
        }
    }

    /// Writes the pairing into the contract and the in-memory copy, so the row
    /// and `cluster.json` agree immediately.
    private func store(_ adhd: LabADHD, on cluster: LabCluster) throws {
        guard let index = clusters.firstIndex(where: { $0.id == cluster.id }) else { return }
        clusters[index].adhd = adhd
        try writeMetadata(clusters[index])
    }

    /// adhd opens its MCP port a moment after `Process.run` returns. A probe is
    /// the readiness check: an answer also gives the row its light count.
    private func waitForADHD(_ cluster: LabCluster) async {
        guard
            let index = clusters.firstIndex(where: { $0.id == cluster.id }),
            let adhd = clusters[index].adhd,
            let endpoint = adhd.mcpURL
        else { return }

        for _ in 0..<15 {
            if let lights = try? await adhdClient.lights(at: endpoint) {
                adhdAnswering.insert(cluster.id)
                adhdLights[cluster.id] = lights.count
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        pairingNotes[cluster.id] = "did not answer on :\(adhd.port) — see adhd.log"
    }

    /// Keeps the pairing line live after launch: an adhd that was stopped
    /// outside the app stops being reported as answering.
    private func refreshADHD(_ cluster: LabCluster) async {
        guard let adhd = cluster.adhd, let endpoint = adhd.mcpURL else { return }

        if let lights = try? await adhdClient.lights(at: endpoint) {
            adhdAnswering.insert(cluster.id)
            adhdLights[cluster.id] = lights.count
            pairingNotes[cluster.id] = nil
        } else {
            adhdAnswering.remove(cluster.id)
        }
    }

    /// Stops adhd before its alarms, so it is not woken by the shutdown it is
    /// watching. The pid file is checked against the executable name: a pid
    /// that has been reused is not adhd, and is left alone.
    private func stopADHD(_ cluster: LabCluster) {
        guard let adhd = cluster.adhd else { return }

        stopProcess(atPIDFile: adhd.pidPath)

        adhdAnswering.remove(cluster.id)
        adhdLights[cluster.id] = nil
        pairingNotes[cluster.id] = nil
    }

    /// Stops the adhd named by a pid file. The executable name is checked
    /// first: a pid that has been reused is not adhd, and is left alone.
    private func stopProcess(atPIDFile path: String) {
        defer { try? fileManager.removeItem(atPath: path) }

        guard
            let text = try? String(contentsOfFile: path, encoding: .utf8),
            let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
            pid > 0,
            processName(of: pid) == "adhd"
        else { return }

        kill(pid, SIGTERM)
        for _ in 0..<20 {
            if processName(of: pid) != "adhd" { return }
            usleep(100_000)
        }
        if processName(of: pid) == "adhd" {
            kill(pid, SIGKILL)
        }
    }

    /// The executable's last path component, or nil when the pid is gone.
    private func processName(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * 1024)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer).split(separator: "/").last.map(String.init)
    }

    private func adhdBinary() -> String? {
        let candidates = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".lezz/bin/adhd").path,
            "/opt/homebrew/bin/adhd",
            "/usr/local/bin/adhd",
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    // MARK: - Stop

    func stop(_ cluster: LabCluster) async {
        guard !busy.contains(cluster.id) else { return }

        busy.insert(cluster.id)
        defer { busy.remove(cluster.id) }

        stopADHD(cluster)

        for member in cluster.members {
            _ = try? runLezz([
                "run", "ocd-smoke-alarm", "ops", "stop",
                "-pid-file", member.pidPath,
            ], log: nil, wait: true)
        }

        var stopped = false
        for _ in 0..<10 {
            await refresh(cluster)
            if await membersAnswering(cluster) == 0 {
                stopped = true
                break
            }
            try? await Task.sleep(for: .milliseconds(300))
        }

        if stopped {
            removeMetadata(cluster)
        } else {
            // Keep the contract so the operator can try again: a member that
            // ignored `ops stop` is still stoppable, and hiding it would make
            // the port look free when it is not.
            states[cluster.id] = .unreachable
            lastError = "\(cluster.name) did not stop. Its log is in the cluster directory."
        }
    }

    func reveal(_ cluster: LabCluster) {
        guard let directory = cluster.members.first?.directory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory.deletingLastPathComponent()])
    }

    func revealADHD(_ cluster: LabCluster) {
        guard let adhd = cluster.adhd else { return }
        if fileManager.fileExists(atPath: adhd.logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([adhd.logURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([adhd.directory])
        }
    }

    // MARK: - Health

    func monitor() async {
        while !Task.isCancelled {
            loadClusters()
            for cluster in clusters {
                await refresh(cluster)
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    func refreshHealth() async {
        loadClusters()
        for cluster in clusters {
            await refresh(cluster)
        }
    }

    private func refresh(_ cluster: LabCluster) async {
        let (state, up) = await health(cluster)
        states[cluster.id] = state
        membersUp[cluster.id] = up

        // The badge needs membership only; the adhd block needs the port each
        // member bound. Resolve those here so both are available before the
        // operator copies anything.
        await resolvePorts(for: cluster)
        await refreshADHD(cluster)
        refreshReport(cluster)
    }

    /// Parses only the log lines that arrived since the last tick. The report
    /// is derived from the same file the Events panel reads; a cluster without
    /// a paired adhd has no log to score.
    private func refreshReport(_ cluster: LabCluster) {
        guard let adhd = cluster.adhd else {
            reports[cluster.id] = nil
            reportScans[cluster.id] = nil
            return
        }

        var scan = reportScans[cluster.id] ?? WatcherReport.Scanner()
        scan.update(url: adhd.logURL)
        reportScans[cluster.id] = scan
        reports[cluster.id] = WatcherReport(evidence: scan.evidence)
    }

    /// A federation cluster is whole when its root answers and every member's
    /// isotope is in the membership view under one agreement. A single-process
    /// sample has no root, so it is whole when its own `/status` answers and
    /// names the isotope.
    private func health(_ cluster: LabCluster) async -> (RunState, Int) {
        if let url = cluster.membershipURL {
            guard let membership = try? await fetchMembership(url) else {
                return (.unreachable, 0)
            }
            return Self.evaluate(cluster: cluster, membership: membership)
        }

        let up = await membersAnswering(cluster)
        switch up {
        case 0: return (.unreachable, 0)
        case cluster.members.count: return (.running, up)
        default: return (.partial, up)
        }
    }

    /// The decision the badge shows, separated from the network so it can be
    /// tested: a root that names every member under this cluster's agreement is
    /// whole, a root that names some of them is partial, and a root whose
    /// agreement differs is somebody else's cluster on our port.
    nonisolated static func evaluate(
        cluster: LabCluster,
        membership: FederationMembership
    ) -> (RunState, Int) {
        let expected = Set(cluster.members.map(\.isotope))
        let up = expected.intersection(membership.serviceNames).count

        if let agreement = cluster.clusterID,
           membership.clusterIDs != [agreement] {
            return (.unreachable, up)
        }
        return up == expected.count ? (.running, up) : (.partial, up)
    }

    private func membersAnswering(_ cluster: LabCluster) async -> Int {
        var up = 0
        for member in cluster.members {
            if await isLive(member) { up += 1 }
        }
        return up
    }

    private func isLive(_ member: LabMember) async -> Bool {
        if let port = await resolvePort(member) {
            return await statusNames(member, port: port, timeout: 1.5)
        }
        return false
    }

    /// Finds the port a member actually bound.
    ///
    /// Loopback does not need the local-network permission mDNS does, so the
    /// app never makes a 127.0.0.1 port depend on it: the preferred port is
    /// scanned upward, exactly as the health server scans for a free one, and a
    /// candidate is accepted only when `/status` names this member's isotope. A
    /// port that answers for another process is not this member — the rotated
    /// isotope is what makes that check possible.
    private func resolvePort(_ member: LabMember) async -> Int? {
        if let cached = resolvedPorts[member.isotope] {
            if await statusNames(member, port: cached, timeout: 1.5) {
                return cached
            }
            resolvedPorts[member.isotope] = nil
        }

        // When the advertisement did arrive it is authoritative and saves the
        // scan; it is an optimisation, not the mechanism.
        if let advertised = advertisedPorts[member.isotope],
           await statusNames(member, port: advertised, timeout: 1.5) {
            resolvedPorts[member.isotope] = advertised
            return advertised
        }

        for offset in 0...scanWindow {
            let port = member.preferredHealthPort + offset
            if await statusNames(member, port: port, timeout: 0.4) {
                resolvedPorts[member.isotope] = port
                return port
            }
        }
        return nil
    }

    /// The health server retries ten ports upward; the window is wider than
    /// that so several members starting at the same preferred port all fit.
    private let scanWindow = 40

    private func resolvePorts(for cluster: LabCluster) async {
        for member in cluster.members {
            _ = await resolvePort(member)
        }
    }

    private func statusNames(_ member: LabMember, port: Int, timeout: TimeInterval) async -> Bool {
        guard let status = try? await fetchStatus(member.healthURL(port: port), timeout: timeout) else {
            return false
        }
        return status.live == true && status.service == member.isotope
    }

    private func applyAdvertisedPorts() {
        for member in clusters.flatMap(\.members) {
            if let port = advertisedPorts[member.isotope] {
                resolvedPorts[member.isotope] = port
            }
        }
    }

    private func fetchMembership(_ url: URL) async throws -> FederationMembership {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LabError.launcherRejected("membership exited \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return try JSONDecoder().decode(FederationMembership.self, from: data)
    }

    private func fetchStatus(_ url: URL, timeout: TimeInterval = 2) async throws -> AlarmStatus {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LabError.launcherRejected("status exited \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return try JSONDecoder().decode(AlarmStatus.self, from: data)
    }

    // MARK: - Storage

    /// One directory per scenario. `cluster.json` names the members; the app
    /// does not care who wrote it.
    private var clustersRoot: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("LezzSea/Clusters", isDirectory: true)
    }

    private func loadClusters() {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: clustersRoot,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let found = directories.compactMap { directory -> LabCluster? in
            let url = directory.appendingPathComponent("cluster.json")
            guard
                let data = try? Data(contentsOf: url),
                let cluster = try? decoder.decode(LabCluster.self, from: data)
            else { return nil }
            return cluster
        }
        .sorted { $0.startedAt < $1.startedAt }

        // Keep the state of clusters that are still listed so the badge does
        // not flicker back to `starting` on every monitor tick.
        clusters = found
        let listed = Set(found.map(\.id))
        for id in Array(states.keys) where !listed.contains(id) {
            states[id] = nil
            membersUp[id] = nil
            adhdAnswering.remove(id)
            adhdLights[id] = nil
            pairingNotes[id] = nil
            reports[id] = nil
            reportScans[id] = nil
        }
        for cluster in found where states[cluster.id] == nil {
            states[cluster.id] = .starting
        }
        startWatchingIfNeeded()
    }

    private func writeMetadata(_ cluster: LabCluster) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cluster)
        try data.write(
            to: clusterDirectory(cluster).appendingPathComponent("cluster.json"),
            options: .atomic
        )
    }

    private func removeMetadata(_ cluster: LabCluster) {
        try? fileManager.removeItem(at: clusterDirectory(cluster).appendingPathComponent("cluster.json"))
        clusters.removeAll { $0.id == cluster.id }
        states[cluster.id] = nil
        membersUp[cluster.id] = nil
        adhdAnswering.remove(cluster.id)
        adhdLights[cluster.id] = nil
        pairingNotes[cluster.id] = nil
        reports[cluster.id] = nil
        reportScans[cluster.id] = nil
        for member in cluster.members {
            resolvedPorts[member.isotope] = nil
        }
    }

    private func clusterDirectory(_ cluster: LabCluster) -> URL {
        clustersRoot.appendingPathComponent(cluster.slug, isDirectory: true)
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
    /// A launched alarm's output goes to the member's own log: the bound port
    /// and the elected role are lines in it, and a failed launch is otherwise
    /// a mystery.
    @discardableResult
    private func runLezz(_ arguments: [String], log: String?, wait: Bool) throws -> Int32 {
        #if LAB_LAUNCHER
        guard let lezz = lezzBinary() else {
            throw LabError.lezzMissing
        }
        let process = try start(lezz, arguments, log: log)
        if wait {
            process.waitUntilExit()
            return process.terminationStatus
        }
        return 0
        #else
        throw LabError.labBuildRequired
        #endif
    }

    /// Starts a child with an app-built argument list and its output appended
    /// to `log`. The paired adhd needs the same PATH and the same log handling
    /// as `lezz`, and its pid so the row can stop it later.
    private func start(_ executable: String, _ arguments: [String], log: String?) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if let log {
            if !fileManager.fileExists(atPath: log) {
                fileManager.createFile(atPath: log, contents: nil)
            }
            if let handle = FileHandle(forWritingAtPath: log) {
                _ = try? handle.seekToEnd()
                process.standardOutput = handle
                process.standardError = handle
            } else {
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
            }
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        // LaunchServices gives a GUI app a minimal PATH; the npx/uvx probes
        // need the Homebrew paths a terminal would have.
        var environment = ProcessInfo.processInfo.environment
        let inherited = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + inherited
        process.environment = environment

        try process.run()
        return process
    }
}

enum LabError: LocalizedError {
    case labBuildRequired
    case lezzMissing
    case launcherRejected(String)

    var errorDescription: String? {
        switch self {
        case .labBuildRequired:
            "Launching needs the Lab build of lezz.sea; the App Store build only copies commands."
        case .lezzMissing:
            "lezz is not installed. Install it from the lab, then try again."
        case .launcherRejected(let message):
            "The launcher could not start the alarm: \(message)"
        }
    }
}
