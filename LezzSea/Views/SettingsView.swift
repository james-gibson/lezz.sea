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
        .frame(width: 520, height: 380)
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

                TextField("Default endpoint", text: $model.defaultEndpointText)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Refresh") {
                LabeledContent("Interval") {
                    HStack {
                        Slider(value: $model.refreshInterval, in: 1...30, step: 1)
                        Text("\(Int(model.refreshInterval)) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                Stepper(value: $model.maxEvents, in: 100...10_000, step: 100) {
                    Text("Keep \(model.maxEvents) events")
                        .monospacedDigit()
                }
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

                HStack {
                    Button("Choose Log…") { model.chooseLog() }
                    Button("Use Default") { model.openDefaultLog() }
                }
            }

            Section {
                Text("The app follows the file incrementally, exactly as adhd writes it. A log that does not exist yet is picked up when it appears.")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a Cluster")
                .font(.headline)

            Form {
                TextField("Name", text: $name, prompt: Text("Optional"))
                TextField("MCP Endpoint", text: $endpoint, prompt: Text("http://127.0.0.1:9090/mcp"))
            }
            .textFieldStyle(.roundedBorder)

            Text("A host and port is enough — lezz.sea adds http:// and /mcp.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Add") {
                    if let message = model.addCluster(name: name, urlString: endpoint) {
                        error = message
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
