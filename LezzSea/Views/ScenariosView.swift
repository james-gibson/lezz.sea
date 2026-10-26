//
//  ScenariosView.swift
//  LezzSea
//
//  The scenario catalog: smoke-alarm's ready-to-run configs, grouped by the
//  theme each one exercises. A row carries the lab command, the adhd pairing
//  block, and — when a checkout is selected — a launch through the signed
//  Lezz.app with a derived, port-isolated config, a paired headless adhd, and
//  the watcher half of its Gherkin report.
//

import AppKit
import SwiftUI

struct ScenariosView: View {
    @State private var query = ""
    @State private var copied: String?
    @State private var lab = ScenarioLab()

    private var groups: [ScenarioCatalog.Group] {
        ScenarioCatalog.filtered(query)
    }

    private var total: Int { ScenarioCatalog.all.count }

    private var shown: Int {
        groups.reduce(0) { $0 + $1.scenarios.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let error = lab.lastError {
                errorBanner(error)
            }

            Divider()

            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No matching scenarios", systemImage: "magnifyingglass")
                } description: {
                    Text("Nothing in the catalog matches “\(query)”.")
                } actions: {
                    Button("Clear Filter") { query = "" }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.scenarios) { scenario in
                                let cluster = lab.cluster(for: scenario)
                                ScenarioRow(
                                    scenario: scenario,
                                    cluster: cluster,
                                    state: lab.state(for: scenario),
                                    membersUp: lab.membersUp(for: scenario),
                                    port: cluster?.members.first.flatMap { lab.port(for: $0) },
                                    adhdSummary: cluster.flatMap { lab.adhdSummary(for: $0) },
                                    report: cluster.flatMap { lab.report(for: $0) },
                                    busy: lab.busy.contains(scenario.id)
                                        || (cluster.map { lab.busy.contains($0.id) } ?? false),
                                    copied: copied == scenario.id,
                                    onCopy: { copy(scenario, cluster: cluster) },
                                    onCopyScript: { copyScript(scenario) },
                                    onCopyADHD: { copyADHD(scenario, cluster: cluster) },
                                    onCopyReport: {
                                        if let cluster, let report = lab.report(for: cluster) {
                                            copyReport(scenario, report: report)
                                        }
                                    },
                                    onLaunch: { Task { await lab.launch(scenario) } },
                                    onStop: {
                                        if let cluster {
                                            Task { await lab.stop(cluster) }
                                        }
                                    },
                                    onReveal: {
                                        if let cluster { lab.reveal(cluster) }
                                    },
                                    onRevealADHD: {
                                        if let cluster { lab.revealADHD(cluster) }
                                    },
                                    onOpen: { NSWorkspace.shared.open(scenario.url) }
                                )
                            }
                        } header: {
                            ThemeHeader(theme: group.theme, count: group.scenarios.count)
                        }
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("scenarios.list")
            }

            Divider()
            footer
                // The List will happily take the footer's space and clip the
                // provenance paragraph at the window floor. The footer is
                // fixed content; give it its ideal height first.
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scenarios: smoke-alarm’s ready-to-run configs")
        .accessibilityIdentifier("scenarios.root")
        .task {
            await lab.monitor()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Scenarios")
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 8)

                Text(countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            #if LAB_LAUNCHER
            Text("smoke-alarm’s ready-to-run configs, grouped by the theme each one exercises. Launching derives a config with absolute state, rotates the isotope for mDNS and runs the alarm headless; ports are left to self-negotiate. The YAML is the source of truth.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #else
            Text("smoke-alarm’s ready-to-run configs, grouped by the theme each one exercises. Copy the lezz command and the adhd pairing; launching is available in the Lab build.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif

            TextField("Filter scenarios", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter scenarios")
                .accessibilityIdentifier("scenarios.search")

            #if LAB_LAUNCHER
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .accessibilityHidden(true)

                Text(checkoutText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                Button(lab.checkout == nil ? "Choose…" : "Change…") {
                    lab.chooseCheckout()
                }
                .buttonStyle(.link)
                .help("Choose the smoke-alarm checkout that contains configs/samples")
                .accessibilityIdentifier("scenarios.checkout")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var checkoutText: String {
        if let name = lab.checkoutName {
            return "Checkout: \(name)"
        }
        return "No smoke-alarm checkout selected"
    }

    private var countText: String {
        query.isEmpty ? "\(total) configs" : "\(shown) of \(total)"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)

            Text(message)
                .lineLimit(3)

            Spacer(minLength: 8)

            Button("Dismiss") {
                lab.lastError = nil
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.14))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Launch problem: \(message)")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Transcribed from smoke-alarm configs/samples at \(ScenarioCatalog.sourceCommit) (\(ScenarioCatalog.sourceDate)). Generated configs and the dev/QA harness are omitted.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            #if LAB_LAUNCHER
            Text("Launching runs the alarm headless on 127.0.0.1. Members keep the sample’s ports: the first process takes the federation slot and the health port, the rest self-negotiate, and the isotope name is what mDNS uses to tell them apart.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            #else
            Text("The Sandbox build copies the command and the adhd pairing. Launching needs the Lab build, which runs outside the App Sandbox.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8 + LayoutMetrics.statusBarHeight)
    }

    // MARK: - Actions

    private func copy(_ scenario: ScenarioCatalog.Scenario, cluster: LabCluster?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            cluster?.launchCommand ?? scenario.command,
            forType: .string
        )

        copied = scenario.id
        AccessibilityAnnouncer.announce("lezz command for \(scenario.name) copied.")

        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == scenario.id {
                copied = nil
            }
        }
    }

    private func copyScript(_ scenario: ScenarioCatalog.Scenario) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            "scripts/lab-cluster.sh configs/samples/\(scenario.file)",
            forType: .string
        )
        AccessibilityAnnouncer.announce("Lab cluster command for \(scenario.name) copied.")
    }

    private func copyADHD(_ scenario: ScenarioCatalog.Scenario, cluster: LabCluster?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let ports = cluster == nil ? [] : lab.healthPorts(for: scenario)
        pasteboard.setString(
            scenario.adhdSmokeAlarmBlock(healthPorts: ports),
            forType: .string
        )

        AccessibilityAnnouncer.announce("adhd smoke_alarm block for \(scenario.name) copied.")
    }

    private func copyReport(_ scenario: ScenarioCatalog.Scenario, report: WatcherReport) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report.text, forType: .string)

        AccessibilityAnnouncer.announce("Gherkin report for \(scenario.name) copied.")
    }
}

// MARK: - Section header

private struct ThemeHeader: View {
    let theme: ScenarioCatalog.Theme
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Label(theme.title, systemImage: theme.symbol)
                    .font(.caption.weight(.semibold))

                Spacer(minLength: 8)

                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(theme.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(theme.title), \(count) scenarios. \(theme.summary)")
    }
}

// MARK: - Row

private struct ScenarioRow: View {
    let scenario: ScenarioCatalog.Scenario
    let cluster: LabCluster?
    let state: ScenarioLab.RunState?
    let membersUp: Int?
    let port: Int?
    let adhdSummary: String?
    let report: WatcherReport?
    let busy: Bool
    let copied: Bool
    let onCopy: () -> Void
    let onCopyScript: () -> Void
    let onCopyADHD: () -> Void
    let onCopyReport: () -> Void
    let onLaunch: () -> Void
    let onStop: () -> Void
    let onReveal: () -> Void
    let onRevealADHD: () -> Void
    let onOpen: () -> Void

    private var command: String {
        cluster?.members.first?.launchCommand ?? scenario.command
    }

    private func tint(for status: WatcherReport.Status) -> Color {
        switch status {
        case .pass: .green
        case .fail: .red
        case .noCoverage: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scenario.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if busy {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Working on \(scenario.name)")
                } else if let state, let cluster {
                    StateBadge(state: state, cluster: cluster, membersUp: membersUp, port: port)
                }

                #if LAB_LAUNCHER
                if cluster == nil {
                    if scenario.isLaunchable {
                        Button(action: onLaunch) {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Launch this scenario via lezz")
                        .accessibilityLabel("Launch \(scenario.name) via lezz")
                        .disabled(busy)
                    } else {
                        // A multi-process cluster is launched by the script
                        // until the launcher's discovery is verified against
                        // one, so the row offers the command, not a button
                        // that would start an incomplete cluster.
                        Button(action: onCopyScript) {
                            Image(systemName: "terminal")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Copy the lab script command for this cluster")
                        .accessibilityLabel("Copy the lab cluster command for \(scenario.name)")
                        .disabled(busy)
                    }
                } else {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Stop this cluster")
                    .accessibilityLabel("Stop \(scenario.name)")
                    .disabled(busy)
                }
                #endif

                Button(action: onCopy) {
                    Label(
                        copied ? "Copied" : "Copy",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy the lezz command")
                .accessibilityLabel("Copy the lezz command for \(scenario.name)")

                Menu {
                    #if LAB_LAUNCHER
                    if cluster != nil {
                        Button("Reveal cluster directory") { onReveal() }
                        if cluster?.adhd != nil {
                            Button("Reveal adhd log") { onRevealADHD() }
                        }
                        if report != nil {
                            Button("Copy Gherkin report") { onCopyReport() }
                        }
                        Divider()
                    }
                    if !scenario.isLaunchable {
                        Button("Copy lab cluster command") { onCopyScript() }
                        Divider()
                    }
                    #endif

                    Button("Copy adhd smoke_alarm block") { onCopyADHD() }
                    Divider()
                    Button("Open \(scenario.file) on GitHub") { onOpen() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More actions for \(scenario.name)")
                .accessibilityLabel("More actions for \(scenario.name)")
            }

            Text(scenario.file)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(scenario.useCase)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let note = scenario.note {
                // No leading icon: it indented the note out of the text column
                // the name, use case and command all share.
                Text("Note: \(note)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // The pairing is a fact about the running cluster, not the sample:
            // it names the adhd endpoint that is watching these members.
            if let adhdSummary {
                Text(adhdSummary)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel(adhdSummary)
                    .accessibilityIdentifier("scenario.adhd.\(scenario.file)")
            }

            // The Gherkin report is the watcher half of adhd's scanner: the
            // scenarios its `light-update` lines can confirm. Collapsed by
            // default so a running row stays the height of a catalog row.
            if let report {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(report.rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(row.status.symbol)
                                    .accessibilityHidden(true)
                                Text(row.name)
                                Spacer(minLength: 8)
                                Text(row.status.label)
                            }
                            .font(.caption2)
                            .foregroundStyle(tint(for: row.status))
                            .help(row.note)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(row.name): \(row.status.label). \(row.note)")
                            .accessibilityIdentifier("scenario.report.row.\(scenario.file).\(row.id)")
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Gherkin report · \(report.summary)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Gherkin report: \(report.summary)")
                .accessibilityIdentifier("scenario.report.\(scenario.file)")
            }

            // The command gets the full row width and two lines. Squeezed
            // beside the buttons, middle truncation removed exactly the
            // --config path the user needs to recognise the scenario.
            Text(command)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(command)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("scenario.\(scenario.file)")
    }
}

// MARK: - State badge

private struct StateBadge: View {
    let state: ScenarioLab.RunState
    let cluster: LabCluster
    let membersUp: Int?
    let port: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(label)
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("cluster.state.\(cluster.slug)")
    }

    private var symbol: String {
        switch state {
        case .starting: "clock"
        case .running: "play.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .unreachable: "exclamationmark.triangle.fill"
        }
    }

    private var label: String {
        switch state {
        case .starting, .unreachable:
            return state.label
        case .running, .partial:
            let counts = "\(membersUp ?? cluster.members.count)/\(cluster.members.count)"
            if let root = cluster.rootLabel {
                return "\(root) · \(counts)"
            }
            return "(portText)"
        }
    }

    /// A single-process sample has no root, so the badge names the port the
    /// alarm actually bound.
    private var portText: String {
        port.map { ":\($0)" } ?? state.label
    }

    private var tint: Color {
        switch state {
        case .starting: .secondary
        case .running: .green
        case .partial: .orange
        case .unreachable: .orange
        }
    }

    private var spoken: String {
        switch state {
        case .starting:
            "Starting"
        case .running where cluster.rootPort != nil:
            "Running, \(membersUp ?? cluster.members.count) of \(cluster.members.count) members, root port \(cluster.rootPort ?? 0)"
        case .partial where cluster.rootPort != nil:
            "Partial, \(membersUp ?? 0) of \(cluster.members.count) members, root port \(cluster.rootPort ?? 0)"
        case .running:
            "Running on port \(port ?? 0)"
        case .partial:
            "Partial: some members are unreachable"
        case .unreachable:
            "Unreachable"
        }
    }
}
