//
//  DefaultAppManager.swift
//  MacAppKitExtras
//
//  Checks and sets this app as the default handler for a set of content types, and offers to do so
//  on launch with a "Yes / No / Ask me later" alert.
//

#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import Combine
import os

@MainActor
public final class DefaultAppManager: ObservableObject {
    /// The launch alert's text.
    public struct Prompt {
        public var messageText: String
        public var informativeText: String
        public var yesTitle: String
        public var noTitle: String
        public var laterTitle: String

        public init(messageText: String, informativeText: String, yesTitle: String = "Yes", noTitle: String = "No", laterTitle: String = "Ask me later") {
            self.messageText = messageText
            self.informativeText = informativeText
            self.yesTitle = yesTitle
            self.noTitle = noTitle
            self.laterTitle = laterTitle
        }
    }

    @Published public private(set) var isDefaultApp: Bool = false

    public let contentTypes: [UTType]
    public let prompt: Prompt
    private let suppressKey: String
    private let defaults: UserDefaults
    private var hasCheckedThisSession = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacAppKitExtras", category: "DefaultAppManager")

    /// - Parameters:
    ///   - contentTypes: The types this app should open by default.
    ///   - prompt: The text of the alert `checkAndPromptIfNecessary()` shows.
    ///   - suppressPromptDefaultsKey: Set to true when the user answers "No", so they aren't asked again.
    public init(contentTypes: [UTType], prompt: Prompt, suppressPromptDefaultsKey: String = "suppressDefaultAppPrompt", defaults: UserDefaults = .standard) {
        self.contentTypes = contentTypes
        self.prompt = prompt
        self.suppressKey = suppressPromptDefaultsKey
        self.defaults = defaults
        refreshDefaultStatus()
    }

    /// Refresh the cached default app status.
    public func refreshDefaultStatus() {
        isDefaultApp = isDefaultHandler()
    }

    /// Checks if this app is the default application for any of the content types.
    public func isDefaultHandler() -> Bool {
        guard let currentBundleID = Bundle.main.bundleIdentifier else { return false }
        let currentAppURL = Bundle.main.bundleURL.standardized

        for uti in contentTypes {
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

    /// Makes this app the default for every content type.
    public func makeDefaultApp() {
        let appURL = Bundle.main.bundleURL

        for uti in contentTypes {
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: uti) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        self?.logger.error("Error setting default application for \(uti.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    } else {
                        self?.logger.info("Set as default application for \(uti.identifier, privacy: .public)")
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

    /// Prompts the user once per launch if this app is not the default, unless they declined before.
    public func checkAndPromptIfNecessary() {
        guard !hasCheckedThisSession else { return }
        hasCheckedThisSession = true

        // Do not prompt if user explicitly chose "No" previously
        if defaults.bool(forKey: suppressKey) {
            return
        }

        // Do not prompt if this app is already the default
        if isDefaultHandler() {
            return
        }

        presentDefaultAppAlert()
    }

    private func presentDefaultAppAlert() {
        let alert = NSAlert()
        alert.messageText = prompt.messageText
        alert.informativeText = prompt.informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: prompt.yesTitle)
        alert.addButton(withTitle: prompt.noTitle)
        alert.addButton(withTitle: prompt.laterTitle)

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Yes
            makeDefaultApp()
        case .alertSecondButtonReturn: // No
            defaults.set(true, forKey: suppressKey)
        case .alertThirdButtonReturn: // Ask me later
            // Do not suppress prompt; keep false so user will be asked on next launch
            break
        default:
            break
        }
    }
}
#endif
