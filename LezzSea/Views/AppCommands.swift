//
//  AppCommands.swift
//  LezzSea
//

import SwiftUI

struct AppCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Cluster…") {
                model.isAddingCluster = true
            }
            .keyboardShortcut("n")

            Button("Open adhd Log…") {
                model.chooseLog()
            }
            .keyboardShortcut("o")
        }

        CommandGroup(after: .toolbar) {
            Button("Lights") {
                model.tab = .lights
            }
            .keyboardShortcut("1")

            Button("Events") {
                model.tab = .events
            }
            .keyboardShortcut("2")

            Button("Isotopes") {
                model.tab = .isotopes
            }
            .keyboardShortcut("3")

            Button("Boundaries") {
                model.tab = .boundaries
            }
            .keyboardShortcut("4")

            Button("Scenarios") {
                model.tab = .scenarios
            }
            .keyboardShortcut("5")

            Divider()

            Toggle("Pause Events", isOn: pauseBinding)
                .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Clear Events") {
                model.clearEvents()
            }
            .keyboardShortcut("k")

            Divider()

            Button("Refresh") {
                Task { await model.refresh() }
            }
            .keyboardShortcut("r")

            Button("Discover Clusters") {
                Task { await model.discover() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .help) {
            Link(
                "lezz.sea on GitHub",
                destination: URL(string: "https://github.com/james-gibson/lezz.sea")!
            )
        }
    }

    private var pauseBinding: Binding<Bool> {
        Binding(get: { model.eventsPaused }, set: { _ in model.togglePause() })
    }
}
