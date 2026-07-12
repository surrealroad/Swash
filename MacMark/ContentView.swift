//
//  ContentView.swift
//  MacMark
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MacMarkDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(MacMarkDocument()))
}
