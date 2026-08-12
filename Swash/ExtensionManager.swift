//
//  ExtensionManager.swift
//  Swash
//

import AppKit
import Foundation
import Combine

@MainActor
final class ExtensionManager: ObservableObject {
    static let shared = ExtensionManager()
    
    private let hasLaunchedBeforeKey = "hasLaunchedBefore"
    private let suppressQuickLookKey = "suppressQuickLookPrompt"
    private let suppressShareExtensionKey = "suppressShareExtensionPrompt"
    private let suppressWidgetKey = "suppressWidgetPrompt"
    
    private var hasRunPipelineThisSession = false
    
    private let quickLookBundleIDs = [
        "com.surrealroad.Swash.SwashQuickLookExtension",
        "com.surrealroad.Swash.SwashThumbnailExtension"
    ]
    private let shareExtensionBundleID = "com.surrealroad.Swash.SwashShareExtension"
    private let widgetExtensionBundleID = "com.surrealroad.Swash.SwashWidgetExtension"
    
    private init() {}
    
    /// Runs the startup check pipeline sequentially. Prompts at most ONE item per launch session.
    func runLaunchCheckPipeline() {
        guard !hasRunPipelineThisSession else { return }
        hasRunPipelineThisSession = true
        
        // 1. Skip all checks on the very first launch ever
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey)
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
            return
        }
        
        // 2. Step 1: Default App Check
        if DefaultAppManager.shared.checkAndPromptIfNecessary() {
            return
        }
        
        // 3. Step 2: Quick Look Extension Check
        if checkAndPromptQuickLookIfNecessary() {
            return
        }
        
        // 4. Step 3: Share Extension Check
        if checkAndPromptShareExtensionIfNecessary() {
            return
        }
        
        // 5. Step 4: Widget Extension Check
        if checkAndPromptWidgetIfNecessary() {
            return
        }
    }
    
    // MARK: - Quick Look Checks & Prompts
    
    private func checkAndPromptQuickLookIfNecessary() -> Bool {
        if UserDefaults.standard.bool(forKey: suppressQuickLookKey) {
            return false
        }
        
        if isExtensionEnabled(bundleID: quickLookBundleIDs[0]) {
            return false
        }
        
        return presentExtensionAlert(
            title: "Enable Swash Quick Look Extensions?",
            informativeText: "Swash includes Quick Look and Thumbnail extensions to render Markdown file previews and icons directly in Finder. Would you like to enable them in System Settings?",
            suppressKey: suppressQuickLookKey,
            settingsURLString: "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        )
    }
    
    // MARK: - Share Extension Checks & Prompts
    
    private func checkAndPromptShareExtensionIfNecessary() -> Bool {
        if UserDefaults.standard.bool(forKey: suppressShareExtensionKey) {
            return false
        }
        
        if isExtensionEnabled(bundleID: shareExtensionBundleID) {
            return false
        }
        
        return presentExtensionAlert(
            title: "Enable Swash Share Extension?",
            informativeText: "Swash includes a Share extension so you can quickly convert or open text in Swash from other applications. Would you like to enable it in System Settings?",
            suppressKey: suppressShareExtensionKey,
            settingsURLString: "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        )
    }
    
    // MARK: - Widget Extension Checks & Prompts
    
    private func checkAndPromptWidgetIfNecessary() -> Bool {
        if UserDefaults.standard.bool(forKey: suppressWidgetKey) {
            return false
        }
        
        if isExtensionEnabled(bundleID: widgetExtensionBundleID) {
            return false
        }
        
        return presentExtensionAlert(
            title: "Enable Swash Widgets?",
            informativeText: "Swash includes widgets for your Notification Center and Desktop. Would you like to view extension settings?",
            suppressKey: suppressWidgetKey,
            settingsURLString: "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        )
    }
    
    // MARK: - Helper Methods
    
    /// Checks whether an extension is enabled using pluginkit.
    private func isExtensionEnabled(bundleID: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        task.arguments = ["-m", "-i", bundleID]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                return output.contains("+") || (!output.contains("disabled") && !output.contains("not found"))
            }
        } catch {
            print("Swash: Error checking extension status for \(bundleID): \(error)")
        }
        return false
    }
    
    /// Presents an alert asking the user to enable an extension. Returns `true` if presented.
    private func presentExtensionAlert(
        title: String,
        informativeText: String,
        suppressKey: String,
        settingsURLString: String
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        
        // Button 1: Open System Settings
        alert.addButton(withTitle: "Open System Settings")
        // Button 2: No
        alert.addButton(withTitle: "No")
        // Button 3: Ask me later
        alert.addButton(withTitle: "Ask me later")
        
        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Open System Settings
            if let url = URL(string: settingsURLString) {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn: // No
            UserDefaults.standard.set(true, forKey: suppressKey)
        case .alertThirdButtonReturn: // Ask me later
            break
        default:
            break
        }
        
        return true
    }
}
