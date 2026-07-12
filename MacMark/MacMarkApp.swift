//
//  MacMarkApp.swift
//  MacMark
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI

@main
struct MacMarkApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MacMarkDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
