//
//  LightsView.swift
//  LezzSea
//

import AppKit
import SwiftUI

struct LightsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()

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
                Table(model.lights, selection: $selection) {
                    TableColumn("") { light in
                        Circle()
                            .fill(light.statusColor)
                            .frame(width: 10, height: 10)
                            .help(light.status)
                    }
                    .width(20)

                    TableColumn("Name", value: \.name)

                    TableColumn("Type") { light in
                        Text(light.type ?? "—")
                            .foregroundStyle(.secondary)
                    }

                    TableColumn("Source") { light in
                        Text(light.source ?? "—")
                            .foregroundStyle(.secondary)
                    }

                    TableColumn("Details") { light in
                        Text(light.details.flatMap { $0.isEmpty ? nil : $0 } ?? "—")
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    TableColumn("Updated") { light in
                        if let updated = light.lastUpdated {
                            Text(updated, format: .relative(presentation: .named))
                        } else {
                            Text("—")
                        }
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
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
}
