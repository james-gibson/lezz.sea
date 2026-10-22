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
        .defaultSize(width: 1_120, height: 720)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
    }
}
