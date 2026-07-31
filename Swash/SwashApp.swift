//
//  SwashApp.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            DefaultAppManager.shared.checkAndPromptIfNecessary()
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            let url = URL(fileURLWithPath: filename)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        return true
    }
}

@main
struct SwashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var sparkleUpdater = SparkleUpdater.shared
    
    var body: some Scene {
        DocumentGroup(newDocument: SwashDocument()) { file in
            ContentView(document: file.$document)
        }
        .windowToolbarStyle(.expanded)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    sparkleUpdater.checkForUpdates()
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}
