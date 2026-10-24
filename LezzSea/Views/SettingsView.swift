//
//  SettingsView.swift
//  LezzSea
//

import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }

            StreamSettings(model: model)
                .tabItem { Label("Stream", systemImage: "waveform.path.ecg") }
        }
        // A floor, not a fixed size: the window may grow with the text and the
        // user's chosen size, and never collapses to where the form clips.
        .frame(minWidth: 520, minHeight: 380)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Discovery") {
                Toggle("Discover clusters automatically", isOn: $model.autoDiscover)

                TextField("Registry", text: $model.registryText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Cluster registry URL")

                TextField("Default endpoint", text: $model.defaultEndpointText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Default adhd endpoint")
            }

            Section("Refresh") {
                LabeledContent("Interval") {
                    HStack {
                        Slider(value: $model.refreshInterval, in: 1...30, step: 1)
                            .accessibilityLabel("Refresh interval")
                            .accessibilityValue("\(Int(model.refreshInterval)) seconds")

                        Text("\(Int(model.refreshInterval)) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                }

                Stepper(value: $model.maxEvents, in: 100...10_000, step: 100) {
                    Text("Keep \(model.maxEvents) events")
                        .monospacedDigit()
                }
                .accessibilityLabel("Events retained")
                .accessibilityValue("\(model.maxEvents)")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Stream

private struct StreamSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Traffic log") {
                LabeledContent("File") {
                    Text(URL(fileURLWithPath: model.logPath).lastPathComponent)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                Text(model.logPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel("Log path")

                HStack {
                    Button("Choose Log…") { model.chooseLog() }
                        .accessibilityIdentifier("settings.chooseLog")

                    Button("Use Default") { model.openDefaultLog() }
                        .accessibilityIdentifier("settings.useDefaultLog")
                }
            }

            Section {
                Text("The app follows the file incrementally, exactly as adhd writes it. A log that does not exist yet is picked up when it appears. macOS remembers your choice across launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Add cluster

struct AddClusterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var endpoint = ""
    @State private var error: String?
    @FocusState private var focused: Field?

    private enum Field {
        case name
        case endpoint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a Cluster")
                .font(.headline)

            Form {
                TextField("Name", text: $name, prompt: Text("Optional"))
                    .focused($focused, equals: .name)
                    .accessibilityLabel("Cluster name")

                TextField(
                    "MCP Endpoint",
                    text: $endpoint,
                    prompt: Text("http://127.0.0.1:9090/mcp")
                )
                .focused($focused, equals: .endpoint)
                .accessibilityLabel("MCP endpoint")
                .accessibilityHint("A host and port is enough. lezz.sea adds http:// and /mcp.")
                .onSubmit(add)
            }
            .textFieldStyle(.roundedBorder)

            Text("A host and port is enough — lezz.sea adds http:// and /mcp.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(error)")
            }

            HStack {
                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("sheet.add")
            }
        }
        .padding(20)
        // A minimum, not a fixed width, so the sheet does not force the text
        // fields to truncate at large text sizes.
        .frame(minWidth: 420, alignment: .leading)
        .onAppear { focused = .name }
        .accessibilityIdentifier("sheet.addCluster")
    }

    private func add() {
        if let message = model.addCluster(name: name, urlString: endpoint) {
            error = message
            AccessibilityAnnouncer.announce(message, priority: .high)
        } else {
            dismiss()
        }
    }
}
