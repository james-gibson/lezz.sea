//
//  ScenariosView.swift
//  LezzSea
//
//  The scenario catalog: smoke-alarm's ready-to-run configs, grouped by the
//  theme each one exercises. Selecting a scenario is a decision about the lab
//  the user wants, so the row carries the command that would start it and the
//  file it comes from — but it does not start anything. Launching is the next
//  step (ADR 0017), and it has to be done by something that can own the
//  identity, the key and the port.
//

import AppKit
import SwiftUI

struct ScenariosView: View {
    @State private var query = ""
    @State private var copied: String?

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
                                ScenarioRow(
                                    scenario: scenario,
                                    copied: copied == scenario.id,
                                    onCopy: { copy(scenario) },
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scenarios")
                .font(.title3.weight(.semibold))

            Text("smoke-alarm’s ready-to-run configs, grouped by the theme each one exercises. Copy the command and run it from a smoke-alarm checkout; the YAML is the source of truth.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("Filter scenarios", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Filter scenarios")
                    .accessibilityIdentifier("scenarios.search")

                Text(query.isEmpty ? "\(total) configs" : "\(shown) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minWidth: 72, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Transcribed from smoke-alarm configs/samples at \(ScenarioCatalog.sourceCommit) (\(ScenarioCatalog.sourceDate)). Generated configs and the dev/QA harness are omitted.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Launching a lab cluster from a scenario is the next step: the identity, key and port belong to the launcher (ADR 0017).")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8 + LayoutMetrics.statusBarHeight)
    }

    // MARK: - Actions

    private func copy(_ scenario: ScenarioCatalog.Scenario) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(scenario.command, forType: .string)

        copied = scenario.id
        AccessibilityAnnouncer.announce("Command for \(scenario.name) copied.")

        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == scenario.id {
                copied = nil
            }
        }
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
    let copied: Bool
    let onCopy: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scenario.name)
                    .font(.callout.weight(.medium))

                Spacer(minLength: 8)

                Button(action: onCopy) {
                    Label(
                        copied ? "Copied" : "Copy",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Copy the serve command")
                .accessibilityLabel("Copy the command for \(scenario.name)")

                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Open \(scenario.file) on GitHub")
                .accessibilityLabel("Open \(scenario.file) on GitHub in the browser")
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
                Label(note, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // The command gets the full row width and two lines. Squeezed
            // beside the buttons, middle truncation removed exactly the
            // --config path the user needs to recognise the scenario.
            Text(scenario.command)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(scenario.command)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("scenario.\(scenario.file)")
    }
}
