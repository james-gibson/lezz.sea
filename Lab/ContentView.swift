//
//  ContentView.swift
//  Lab
//
//  Created by dev on 10/21/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: LabDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(LabDocument()))
}
