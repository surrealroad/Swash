//
//  DefaultAppManager.swift
//  Swash
//

import AppKit
import UniformTypeIdentifiers
import Combine

@MainActor
final class DefaultAppManager: ObservableObject {
    static let shared = DefaultAppManager()
    
    @Published private(set) var isDefaultAppStatus: Bool = false
    
    private let suppressKey = "suppressDefaultAppPrompt"
    private var hasCheckedThisSession = false
    
    private let markdownUTIs: [UTType] = [
        UTType(filenameExtension: "md"),
        UTType("net.daringfireball.markdown")
    ].compactMap { $0 }

    private init() {
        refreshDefaultStatus()
    }

    /// Refresh the cached default app status.
    func refreshDefaultStatus() {
        isDefaultAppStatus = isSwashDefaultApp()
    }

    /// Checks if Swash is set as the default application for .md files.
    func isSwashDefaultApp() -> Bool {
        guard let currentBundleID = Bundle.main.bundleIdentifier else { return false }
        let currentAppURL = Bundle.main.bundleURL.standardized
        
        for uti in markdownUTIs {
            if let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: uti) {
                let defaultAppURLStandardized = defaultAppURL.standardized
                if defaultAppURLStandardized == currentAppURL {
                    return true
                }
                if let bundle = Bundle(url: defaultAppURLStandardized),
                   bundle.bundleIdentifier == currentBundleID {
                    return true
                }
            }
        }
        return false
    }

    /// Makes Swash the default app for markdown content types.
    func makeSwashDefaultApp() {
        let appURL = Bundle.main.bundleURL
        
        for uti in markdownUTIs {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: uti) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("Swash: Error setting default application for \(uti.identifier): \(error.localizedDescription)")
                    } else {
                        print("Swash: Successfully set as default application for \(uti.identifier)")
                    }
                    self?.refreshDefaultStatus()
                }
            }
            
            if let bundleID = Bundle.main.bundleIdentifier {
                LSSetDefaultRoleHandlerForContentType(uti.identifier as CFString, .all, bundleID as CFString)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshDefaultStatus()
        }
    }

    /// Prompts the user on launch if Swash is not the default app for .md files.
    func checkAndPromptIfNecessary() {
        guard !hasCheckedThisSession else { return }
        hasCheckedThisSession = true

        // Do not prompt if user explicitly chose "No" previously
        if UserDefaults.standard.bool(forKey: suppressKey) {
            return
        }

        // Do not prompt if Swash is already the default app
        if isSwashDefaultApp() {
            return
        }

        presentDefaultAppAlert()
    }

    private func presentDefaultAppAlert() {
        let alert = NSAlert()
        alert.messageText = "Make Swash your default Markdown app?"
        alert.informativeText = "Swash is not currently the default app for .md files. Would you like to make it the default app?"
        alert.alertStyle = .informational
        
        // Button 1: Yes
        alert.addButton(withTitle: "Yes")
        // Button 2: No
        alert.addButton(withTitle: "No")
        // Button 3: Ask me later
        alert.addButton(withTitle: "Ask me later")

        NSApp.activate(ignoringOtherApps: true)
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Yes
            makeSwashDefaultApp()
        case .alertSecondButtonReturn: // No
            UserDefaults.standard.set(true, forKey: suppressKey)
        case .alertThirdButtonReturn: // Ask me later
            // Do not suppress prompt; keep false so user will be asked on next launch
            break
        default:
            break
        }
    }
}
