//
//  SwashApp.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI

@main
struct SwashApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: SwashDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
