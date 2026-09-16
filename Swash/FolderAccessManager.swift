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
    private var activeSecurityScopedURLs: [URL: Bool] = [:]
    
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
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                if resolvedURL.startAccessingSecurityScopedResource() {
                    activeSecurityScopedURLs[resolvedURL.standardizedFileURL] = true
                }
                
                if isStale {
                    if let newBookmark = try? resolvedURL.bookmarkData(
                        options: .withSecurityScope,
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
                if let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
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
            if stdURL.startAccessingSecurityScopedResource() {
                self.lock.lock()
                self.activeSecurityScopedURLs[stdURL] = true
                self.lock.unlock()
            }
            
            // Save security-scoped bookmark
            if let bookmarkData = try? stdURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                var dict = (UserDefaults.standard.dictionary(forKey: self.bookmarksDefaultsKey) as? [String: Data]) ?? [:]
                dict[stdURL.path] = bookmarkData
                UserDefaults.standard.set(dict, forKey: self.bookmarksDefaultsKey)
            }
            
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
