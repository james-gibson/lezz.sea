//
//  LabApp.swift
//  Lab
//
//  Created by dev on 10/21/26.
//

import SwiftUI

@main
struct LabApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: LabDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
