//
//  FolderAccessManager.swift
//  MacAppKitExtras
//
//  Persistent folder access for sandboxed apps. A sandbox grants access only to the exact file the
//  user opened, so files beside it (images, linked documents) stay unreadable until the user picks
//  their folder. This asks for that folder, keeps a security-scoped bookmark in UserDefaults and
//  reactivates it on later launches.
//

import Foundation
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

public final class FolderAccessManager: ObservableObject {
    /// Where bookmarks are kept and how the folder picker asks for access.
    public struct Configuration {
        /// The UserDefaults key holding a `[path: bookmark data]` dictionary.
        public var bookmarksDefaultsKey: String
        public var defaults: UserDefaults
        /// The open panel's title (macOS only).
        public var panelTitle: String
        /// The open panel's confirm button (macOS only).
        public var panelPrompt: String
        /// The open panel's message for a folder name (macOS only).
        public var panelMessage: (_ folderName: String) -> String
        /// Called when the user grants a folder, after its bookmark is saved and before observers are
        /// told; for clearing caches of files that were unreadable.
        public var onAccessGranted: ((URL) -> Void)?

        public init(
            bookmarksDefaultsKey: String = "security_scoped_folder_bookmarks",
            defaults: UserDefaults = .standard,
            panelTitle: String = "Grant Folder Access",
            panelPrompt: String = "Grant Access",
            panelMessage: @escaping (_ folderName: String) -> String = { folderName in
                let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "This app"
                return "\(appName) needs permission to access files in “\(folderName)”. Please select this folder and click “Grant Access”."
            },
            onAccessGranted: ((URL) -> Void)? = nil
        ) {
            self.bookmarksDefaultsKey = bookmarksDefaultsKey
            self.defaults = defaults
            self.panelTitle = panelTitle
            self.panelPrompt = panelPrompt
            self.panelMessage = panelMessage
            self.onAccessGranted = onAccessGranted
        }
    }

    /// Posted on the main queue after the user grants access to a folder. The folder's URL is in
    /// `userInfo[FolderAccessManager.grantedURLKey]`.
    public static let accessGrantedNotification = Notification.Name("MacAppKitExtras.FolderAccessGranted")
    public static let grantedURLKey = "url"

    #if os(macOS)
    public typealias Window = NSWindow
    #else
    public typealias Window = UIWindow
    #endif

    public let configuration: Configuration
    private let lock = NSLock()
    /// Saved bookmarks by folder path, read from UserDefaults once.
    private var cachedBookmarks: [String: Data]? = nil
    /// Folders whose security-scoped access was started this session. Access is started once per
    /// folder and kept for the app's lifetime, so repeated lookups don't stack up access counts.
    private var activeFolders: Set<String> = []
    /// Folders whose bookmark couldn't be resolved this session; not retried on every render.
    private var failedFolders: Set<String> = []
    #if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = .withSecurityScope
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
    // iOS bookmarks made from a security-scoped URL carry the scope implicitly
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
    /// Keeps the document picker's delegate alive while the picker is on screen.
    private var pickerDelegate: FolderPickerDelegate?
    #endif

    /// Changes whenever access is granted, so SwiftUI views can reload (for example with `.id(_:)`).
    @Published public private(set) var accessGrantedTrigger: UUID = UUID()

    /// Creates a manager. Saved bookmarks are resolved lazily, the first time a folder is needed,
    /// rather than all at launch.
    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Call with `lock` held.
    private var bookmarks: [String: Data] {
        if let cached = cachedBookmarks { return cached }
        let saved = (configuration.defaults.dictionary(forKey: configuration.bookmarksDefaultsKey) as? [String: Data]) ?? [:]
        cachedBookmarks = saved
        return saved
    }

    /// Ensures that security-scoped access is active for the given directory or any of its parent directories.
    @discardableResult
    public func ensureAccess(for folderURL: URL) -> Bool {
        let stdFolder = folderURL.standardizedFileURL
        if FileManager.default.isReadableFile(atPath: stdFolder.path) {
            return true
        }

        lock.lock()
        var current: URL? = stdFolder
        while let candidate = current, candidate.path != "/" && candidate.path.count > 1 {
            let path = candidate.path
            if activeFolders.contains(path) || failedFolders.contains(path) {
                // Already started (or known to fail): nothing more to do for this ancestor
            } else if let data = bookmarks[path] {
                var isStale = false
                if let resolved = try? URL(resolvingBookmarkData: data, options: Self.bookmarkResolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale),
                   resolved.startAccessingSecurityScopedResource() {
                    activeFolders.insert(path)
                    if isStale, let refreshed = try? resolved.bookmarkData(options: Self.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        var updated = bookmarks
                        updated[path] = refreshed
                        cachedBookmarks = updated
                        configuration.defaults.set(updated, forKey: configuration.bookmarksDefaultsKey)
                    }
                    if FileManager.default.isReadableFile(atPath: stdFolder.path) {
                        lock.unlock()
                        return true
                    }
                } else {
                    failedFolders.insert(path)
                }
            }
            current = candidate.deletingLastPathComponent()
        }
        lock.unlock()
        return FileManager.default.isReadableFile(atPath: stdFolder.path)
    }

    /// Whether the app can read the specified folder, activating a saved bookmark for it if needed.
    public func hasAccess(to folderURL: URL) -> Bool {
        ensureAccess(for: folderURL)
    }

    /// Asks the user to pick the specified directory (an open panel on macOS, the document picker on
    /// iOS) and keeps a bookmark so access survives relaunches. Always fails inside an app extension.
    @MainActor
    public func promptForAccess(to folderURL: URL, window: Window? = nil, completion: @escaping (Bool) -> Void) {
        // Guard against extension process
        guard Bundle.main.bundleURL.pathExtension != "appex" else {
            completion(false)
            return
        }

        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = configuration.panelTitle
        panel.message = configuration.panelMessage(folderURL.lastPathComponent)
        panel.prompt = configuration.panelPrompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folderURL

        let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let selectedURL = panel.url else {
                completion(false)
                return
            }
            self.grantAccess(to: selectedURL, completion: completion)
        }

        if let window = window {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            let response = panel.runModal()
            handleResponse(response)
        }
        #else
        guard let presenter = Self.topViewController(in: window) else {
            completion(false)
            return
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.directoryURL = folderURL
        picker.allowsMultipleSelection = false
        let delegate = FolderPickerDelegate { [weak self] url in
            self?.pickerDelegate = nil
            guard let self = self, let url = url else {
                completion(false)
                return
            }
            self.grantAccess(to: url, completion: completion)
        }
        pickerDelegate = delegate
        picker.delegate = delegate
        presenter.present(picker, animated: true)
        #endif
    }

    /// Starts accessing a folder the user picked, saves its bookmark and announces the grant.
    public func grantAccess(to selectedURL: URL, completion: @escaping (Bool) -> Void) {
        let stdURL = selectedURL.standardizedFileURL
        lock.lock()
        if !activeFolders.contains(stdURL.path), stdURL.startAccessingSecurityScopedResource() {
            activeFolders.insert(stdURL.path)
        }
        failedFolders.remove(stdURL.path)

        // Save security-scoped bookmark
        if let bookmarkData = try? stdURL.bookmarkData(
            options: Self.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            var dict = bookmarks
            dict[stdURL.path] = bookmarkData
            cachedBookmarks = dict
            configuration.defaults.set(dict, forKey: configuration.bookmarksDefaultsKey)
        }
        lock.unlock()
        configuration.onAccessGranted?(stdURL)

        DispatchQueue.main.async {
            self.accessGrantedTrigger = UUID()
            NotificationCenter.default.post(name: Self.accessGrantedNotification, object: self, userInfo: [Self.grantedURLKey: stdURL])
            completion(true)
        }
    }

    #if os(iOS)
    @MainActor
    private static func topViewController(in window: UIWindow?) -> UIViewController? {
        let keyWindow = window ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
    #endif
}

#if os(iOS)
private final class FolderPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
}
#endif
