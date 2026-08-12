//
//  SwashApp.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let servicesProvider = ServicesProvider()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = servicesProvider
        DispatchQueue.main.async {
            DefaultAppManager.shared.checkAndPromptIfNecessary()
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "swash" {
                handleSwashURL(url)
            } else {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
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
    
    private func handleSwashURL(_ url: URL) {
        guard url.scheme == "swash" else { return }
        
        if url.host == "new" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let text = components?.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            let title = components?.queryItems?.first(where: { $0.name == "title" })?.value ?? "Untitled"
            
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "\(title).md".replacingOccurrences(of: "/", with: "-")
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            do {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
                NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }
            } catch {
                print("Failed to handle swash://new: \(error)")
            }
        } else if url.host == "open" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let path = components?.queryItems?.first(where: { $0.name == "path" })?.value {
                let fileURL = URL(fileURLWithPath: path)
                NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }
            }
        }
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
        .defaultSize(width: 800, height: 750)
        .handlesExternalEvents(matching: ["*"])
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
