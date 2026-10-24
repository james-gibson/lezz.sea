//
//  LightsView.swift
//  LezzSea
//

import AppKit
import SwiftUI

struct LightsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()

    /// Width below which the six-column table is replaced by a four-column
    /// one. `Table` lays its columns out at their ideal widths and clips (it
    /// does not squeeze them), so a six-column table can never fit the detail
    /// pane at the window's minimum size. Dropping Type and Source there is
    /// better than hiding the Updated column off the right edge.
    private let fullTableWidth: CGFloat = 740

    var body: some View {
        Group {
            if model.lights.isEmpty {
                ContentUnavailableView {
                    Label("No Lights", systemImage: "lightbulb")
                } description: {
                    if model.connection.isOnline {
                        Text("This cluster has no lights yet. Join a smoke-alarm instance or refresh.")
                    } else {
                        Text("Connect to the cluster to read its lights.")
                    }
                } actions: {
                    Button("Refresh") {
                        Task { await model.refresh() }
                    }
                }
            } else {
                GeometryReader { proxy in
                    if proxy.size.width >= fullTableWidth {
                        chrome(fullTable)
                    } else {
                        chrome(compactTable)
                    }
                }
            }
        }
    }

    // MARK: - Tables

    private var fullTable: some View {
        Table(model.lights, selection: $selection) {
            // The status column carries a shape as well as a colour: a check
            // for green, a stop sign for red, a warning triangle for yellow, a
            // dotted ring for dark. VoiceOver reads the status word, so neither
            // colour-blind nor screen-reader users depend on hue.
            TableColumn("Status") { light in
                LightStatusCell(light: light)
            }
            .width(min: 52, ideal: 64, max: 84)

            TableColumn("Name", value: \.name)
                .width(min: 76, ideal: 120, max: 240)

            TableColumn("Type") { light in
                Text(light.type ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 56, ideal: 80, max: 130)

            TableColumn("Source") { light in
                Text(light.source ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 56, ideal: 90, max: 150)

            TableColumn("Details") { light in
                Text(light.details.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .width(min: 80, ideal: 140, max: 380)

            TableColumn("Updated") { light in
                if let updated = light.lastUpdated {
                    Text(updated, format: .relative(presentation: .named))
                        .lineLimit(1)
                } else {
                    Text("—")
                }
            }
            .width(min: 64, ideal: 80, max: 120)
        }
    }

    private var compactTable: some View {
        Table(model.lights, selection: $selection) {
            TableColumn("Status") { light in
                LightStatusCell(light: light)
            }
            .width(min: 52, ideal: 64, max: 84)

            TableColumn("Name", value: \.name)
                .width(min: 76, ideal: 120, max: 240)

            TableColumn("Details") { light in
                Text(light.details.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .width(min: 80, ideal: 140, max: 380)

            TableColumn("Updated") { light in
                if let updated = light.lastUpdated {
                    Text(updated, format: .relative(presentation: .named))
                        .lineLimit(1)
                } else {
                    Text("—")
                }
            }
            .width(min: 64, ideal: 80, max: 120)
        }
    }

    // MARK: - Shared chrome

    private func chrome(_ table: some View) -> some View {
        table
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .accessibilityLabel("Lights")
            .accessibilityIdentifier("lights.table")
            .contextMenu(forSelectionType: String.self) { names in
                if let name = names.first {
                    Button("Copy Name") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(name, forType: .string)
                    }
                }
            } primaryAction: { names in
                guard
                    let name = names.first,
                    let light = model.lights.first(where: { $0.name == name })
                else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(light.details ?? light.name, forType: .string)
            }
    }
}

// MARK: - Status cell

private struct LightStatusCell: View {
    let light: Light

    var body: some View {
        Image(systemName: LightStatusStyle.symbol(for: light.status))
            .foregroundStyle(light.statusColor)
            .imageScale(.medium)
            .help("Status: \(LightStatusStyle.label(for: light.status))")
            .accessibilityLabel(LightStatusStyle.label(for: light.status))
    }
}

// MARK: - Status colours

extension Light {
    var statusColor: Color {
        switch status.lowercased() {
        case "green": .green
        case "red": .red
        case "yellow": .yellow
        case "dark": Color(nsColor: .tertiaryLabelColor)
        default: .secondary
        }
    }

    /// The status word, for VoiceOver and for the status cell's tooltip.
    var statusLabel: String {
        LightStatusStyle.label(for: status)
    }
}
