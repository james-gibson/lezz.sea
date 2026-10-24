//
//  LezzSeaApp.swift
//  LezzSea
//

import SwiftUI

@main
struct LezzSeaApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("lezz.sea", id: "main") {
            ContentView()
                .environment(model)
                .task { await model.start() }
        }
        .defaultSize(
            width: LayoutMetrics.preferredWindowWidth,
            height: LayoutMetrics.preferredWindowHeight
        )
        // AppKit enforces ContentView's minimum frame. Without this the window
        // can be dragged small enough that the sidebar and detail pane fight
        // for the same pixels.
        .windowResizability(.contentMinSize)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
        .windowResizability(.contentMinSize)
    }
}
