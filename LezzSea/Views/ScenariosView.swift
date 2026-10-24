//
//  ScenariosView.swift
//  LezzSea
//
//  The scenario catalog: smoke-alarm's ready-to-run configs, grouped by the
//  theme each one exercises. A row carries the lab command, the adhd pairing
//  block, and — when a checkout is selected — a launch through the signed
//  Lezz.app with a derived, port-isolated config.
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
                                let instance = lab.instance(for: scenario)
                                ScenarioRow(
                                    scenario: scenario,
                                    instance: instance,
                                    state: instance.flatMap { lab.states[$0.id] },
                                    busy: lab.busy.contains(scenario.id)
                                        || (instance.map { lab.busy.contains($0.id) } ?? false),
                                    copied: copied == scenario.id,
                                    onCopy: { copy(scenario, instance: instance) },
                                    onCopyADHD: { copyADHD(scenario, instance: instance) },
                                    onLaunch: { Task { await lab.launch(scenario) } },
                                    onStop: {
                                        if let instance {
                                            Task { await lab.stop(instance) }
                                        }
                                    },
                                    onReveal: {
                                        if let instance { lab.reveal(instance) }
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
            Text("smoke-alarm’s ready-to-run configs, grouped by the theme each one exercises. Launching derives a config with absolute state and remapped ports, then runs the alarm headless; the YAML is the source of truth.")
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
            Text("Launching runs the alarm headless on 127.0.0.1 with remapped ports; macOS will not bind 127.0.0.N without an alias.")
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

    private func copy(_ scenario: ScenarioCatalog.Scenario, instance: ScenarioLab.Instance?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(instance?.launchCommand ?? scenario.command, forType: .string)

        copied = scenario.id
        AccessibilityAnnouncer.announce("lezz command for \(scenario.name) copied.")

        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == scenario.id {
                copied = nil
            }
        }
    }

    private func copyADHD(_ scenario: ScenarioCatalog.Scenario, instance: ScenarioLab.Instance?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            scenario.adhdSmokeAlarmBlock(healthPort: instance?.healthPort),
            forType: .string
        )

        AccessibilityAnnouncer.announce("adhd smoke_alarm block for \(scenario.name) copied.")
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
    let instance: ScenarioLab.Instance?
    let state: ScenarioLab.RunState?
    let busy: Bool
    let copied: Bool
    let onCopy: () -> Void
    let onCopyADHD: () -> Void
    let onLaunch: () -> Void
    let onStop: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void

    private var command: String {
        instance?.launchCommand ?? scenario.command
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scenario.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                #if LAB_LAUNCHER
                if busy {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Working on \(scenario.name)")
                } else if let state {
                    StateBadge(state: state, instance: instance)
                }

                if instance == nil {
                    Button(action: onLaunch) {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Launch this scenario via lezz")
                    .accessibilityLabel("Launch \(scenario.name) via lezz")
                    .disabled(busy)
                } else {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Stop this instance")
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
                    if instance != nil {
                        Button("Reveal config") { onReveal() }
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
    let instance: ScenarioLab.Instance?

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
    }

    private var symbol: String {
        switch state {
        case .starting: "clock"
        case .running: "play.circle.fill"
        case .unreachable: "exclamationmark.triangle.fill"
        }
    }

    private var label: String {
        if state == .running, let port = instance?.healthPort {
            return ":\(port)"
        }
        return state.label
    }

    private var tint: Color {
        switch state {
        case .starting: .secondary
        case .running: .green
        case .unreachable: .orange
        }
    }

    private var spoken: String {
        switch state {
        case .starting:
            "Starting"
        case .running:
            "Running on port \(instance?.healthPort ?? 0)"
        case .unreachable:
            "Unreachable"
        }
    }
}
