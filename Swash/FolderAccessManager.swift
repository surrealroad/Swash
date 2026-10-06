//
//  FolderAccessManager.swift
//  Swash
//
//  Created by Jack James on 16/09/2026.
//

import Foundation
import Combine
#if os(macOS)
import AppKit
typealias PlatformWindow = NSWindow
#else
import UIKit
import UniformTypeIdentifiers
typealias PlatformWindow = UIWindow
#endif

final class FolderAccessManager: ObservableObject {
    static let shared = FolderAccessManager()
    
    private let bookmarksDefaultsKey = "swash_security_scoped_folder_bookmarks"
    private let lock = NSLock()
    private var activeSecurityScopedURLs: [URL: Bool] = [:]
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
    
    @Published var accessGrantedTrigger: UUID = UUID()
    
    private init() {
        restoreAllSavedBookmarks()
    }
    
    /// Restores any previously granted security-scoped bookmarks from UserDefaults.
    func restoreAllSavedBookmarks() {
        guard let savedDict = UserDefaults.standard.dictionary(forKey: bookmarksDefaultsKey) as? [String: Data] else {
            return
        }
        
        var updatedDict = savedDict
        var didUpdateStale = false
        
        lock.lock()
        defer {
            lock.unlock()
            if didUpdateStale {
                UserDefaults.standard.set(updatedDict, forKey: bookmarksDefaultsKey)
            }
        }
        
        for (path, bookmarkData) in savedDict {
            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: Self.bookmarkResolutionOptions,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if resolvedURL.startAccessingSecurityScopedResource() {
                    activeSecurityScopedURLs[resolvedURL.standardizedFileURL] = true
                }
                
                if isStale {
                    if let newBookmark = try? resolvedURL.bookmarkData(
                        options: Self.bookmarkCreationOptions,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    ) {
                        updatedDict[path] = newBookmark
                        didUpdateStale = true
                    }
                }
            } catch {
                // If resolving fails, keep existing dictionary intact
            }
        }
    }
    
    /// Ensures that security-scoped access is active for the given directory or any of its parent directories.
    @discardableResult
    func ensureAccess(for folderURL: URL) -> Bool {
        let stdFolder = folderURL.standardizedFileURL
        
        // Check if directly readable
        if FileManager.default.isReadableFile(atPath: stdFolder.path) {
            return true
        }
        
        // Search saved bookmarks for this folder or ancestor folders
        guard let savedDict = UserDefaults.standard.dictionary(forKey: bookmarksDefaultsKey) as? [String: Data] else {
            return false
        }
        
        var current: URL? = stdFolder
        while let candidate = current, candidate.path != "/" && candidate.path.count > 1 {
            if let data = savedDict[candidate.path] {
                var isStale = false
                if let resolved = try? URL(resolvingBookmarkData: data, options: Self.bookmarkResolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    if resolved.startAccessingSecurityScopedResource() {
                        lock.lock()
                        activeSecurityScopedURLs[resolved.standardizedFileURL] = true
                        lock.unlock()
                        if FileManager.default.isReadableFile(atPath: stdFolder.path) {
                            return true
                        }
                    }
                }
            }
            current = candidate.deletingLastPathComponent()
        }
        
        return FileManager.default.isReadableFile(atPath: stdFolder.path)
    }
    
    /// Checks whether the app currently has read access to the specified folder or path.
    func hasAccess(to folderURL: URL) -> Bool {
        return FileManager.default.isReadableFile(atPath: folderURL.standardizedFileURL.path)
    }
    
    /// Asks the user to pick the specified directory (an open panel on macOS, the document picker on
    /// iOS) and keeps a bookmark so access survives relaunches.
    @MainActor
    func promptForAccess(to folderURL: URL, window: PlatformWindow? = nil, completion: @escaping (Bool) -> Void) {
        // Guard against extension process
        guard Bundle.main.bundleURL.pathExtension != "appex" else {
            completion(false)
            return
        }
        
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Grant Folder Access"
        let folderName = folderURL.lastPathComponent
        panel.message = "Swash needs permission to access images and linked files in “\(folderName)”. Please select this folder and click “Grant Access”."
        panel.prompt = "Grant Access"
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
    private func grantAccess(to selectedURL: URL, completion: @escaping (Bool) -> Void) {
        let stdURL = selectedURL.standardizedFileURL
        if stdURL.startAccessingSecurityScopedResource() {
            lock.lock()
            activeSecurityScopedURLs[stdURL] = true
            lock.unlock()
        }
        
        // Save security-scoped bookmark
        if let bookmarkData = try? stdURL.bookmarkData(
            options: Self.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            var dict = (UserDefaults.standard.dictionary(forKey: bookmarksDefaultsKey) as? [String: Data]) ?? [:]
            dict[stdURL.path] = bookmarkData
            UserDefaults.standard.set(dict, forKey: bookmarksDefaultsKey)
        }
        
        DispatchQueue.main.async {
            self.accessGrantedTrigger = UUID()
            NotificationCenter.default.post(name: NSNotification.Name("SwashFolderAccessGranted"), object: nil, userInfo: ["url": stdURL])
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
