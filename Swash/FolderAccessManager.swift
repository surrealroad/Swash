//
//  FolderAccessManager.swift
//  Swash
//
//  Created by Jack James on 16/09/2026.
//

import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

final class FolderAccessManager: ObservableObject {
    static let shared = FolderAccessManager()
    
    private let bookmarksDefaultsKey = "swash_security_scoped_folder_bookmarks"
    private let lock = NSLock()
    /// Saved bookmarks by folder path, read from UserDefaults once.
    private var cachedBookmarks: [String: Data]? = nil
    /// Folders whose security-scoped access was started this session. Access is started once per
    /// folder and kept for the app's lifetime, so repeated lookups don't stack up access counts.
    private var activeFolders: Set<String> = []
    /// Folders whose bookmark couldn't be resolved this session; not retried on every render.
    private var failedFolders: Set<String> = []
    
    @Published var accessGrantedTrigger: UUID = UUID()
    
    /// Bookmarks are resolved lazily, the first time a folder is needed, rather than all at launch.
    private init() {}
    
    private var bookmarks: [String: Data] {
        if let cached = cachedBookmarks { return cached }
        let saved = (UserDefaults.standard.dictionary(forKey: bookmarksDefaultsKey) as? [String: Data]) ?? [:]
        cachedBookmarks = saved
        return saved
    }
    
    /// Ensures that security-scoped access is active for the given directory or any of its parent directories.
    @discardableResult
    func ensureAccess(for folderURL: URL) -> Bool {
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
                if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale),
                   resolved.startAccessingSecurityScopedResource() {
                    activeFolders.insert(path)
                    if isStale, let refreshed = try? resolved.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                        var updated = bookmarks
                        updated[path] = refreshed
                        cachedBookmarks = updated
                        UserDefaults.standard.set(updated, forKey: bookmarksDefaultsKey)
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
    func hasAccess(to folderURL: URL) -> Bool {
        ensureAccess(for: folderURL)
    }
    
    /// Prompts the user with an NSOpenPanel to grant access to the specified directory.
    @MainActor
    func promptForAccess(to folderURL: URL, window: NSWindow? = nil, completion: @escaping (Bool) -> Void) {
        #if canImport(AppKit)
        // Guard against extension process
        guard Bundle.main.bundleURL.pathExtension != "appex" else {
            completion(false)
            return
        }
        
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
            
            let stdURL = selectedURL.standardizedFileURL
            self.lock.lock()
            if !self.activeFolders.contains(stdURL.path), stdURL.startAccessingSecurityScopedResource() {
                self.activeFolders.insert(stdURL.path)
            }
            self.failedFolders.remove(stdURL.path)
            
            // Save security-scoped bookmark
            if let bookmarkData = try? stdURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                var dict = self.bookmarks
                dict[stdURL.path] = bookmarkData
                self.cachedBookmarks = dict
                UserDefaults.standard.set(dict, forKey: self.bookmarksDefaultsKey)
            }
            self.lock.unlock()
            ImageCache.shared.removeAll()
            
            DispatchQueue.main.async {
                self.accessGrantedTrigger = UUID()
                NotificationCenter.default.post(name: NSNotification.Name("SwashFolderAccessGranted"), object: nil, userInfo: ["url": stdURL])
                completion(true)
            }
        }
        
        if let window = window {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            let response = panel.runModal()
            handleResponse(response)
        }
        #else
        completion(false)
        #endif
    }
}
