//
//  FolderAccessManager.swift
//  Swash
//
//  Created by Jack James on 16/09/2026.
//
//  Swash's shared folder-access manager. The manager itself lives in MacAppKitExtras.
//

import Foundation
import MacAppKitExtras

extension FolderAccessManager {
    /// The bookmarks key predates MacAppKitExtras; keep it so folders granted earlier stay granted.
    static let shared = FolderAccessManager(configuration: .init(
        bookmarksDefaultsKey: "swash_security_scoped_folder_bookmarks",
        panelMessage: { folderName in
            "Swash needs permission to access images and linked files in “\(folderName)”. Please select this folder and click “Grant Access”."
        },
        // Images that failed to load before the grant are cached as failures
        onAccessGranted: { _ in ImageCache.shared.removeAll() }
    ))
}
