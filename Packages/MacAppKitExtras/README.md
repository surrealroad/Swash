# MacAppKitExtras

Small AppKit (and UIKit) helpers extracted from Swash for reuse in other apps. macOS 14+, iOS 17+.

| Type | Platforms | What it does |
| --- | --- | --- |
| `FolderAccessManager` | macOS, iOS | Asks the user for a folder (open panel or document picker), saves a security-scoped bookmark and reactivates it on later launches, so a sandboxed app can read files beside a document it opened. |
| `DefaultAppManager` | macOS | Checks and sets the app as default handler for content types, with an optional "Yes / No / Ask me later" launch prompt. |
| `ScrollSync` | macOS, iOS | Keeps several scroll views at the same vertical offset without going through SwiftUI state. |
| `NestedScrollRouter` | macOS | Sends vertical scroll gestures that start over a nested horizontal scroll view to the outer scroll view. |

```swift
import MacAppKitExtras

extension FolderAccessManager {
    static let shared = FolderAccessManager(configuration: .init(bookmarksDefaultsKey: "my_app_folder_bookmarks"))
}

FolderAccessManager.shared.ensureAccess(for: documentURL.deletingLastPathComponent())
```

Sandboxed apps need the `com.apple.security.files.user-selected.read-write` and `com.apple.security.files.bookmarks.app-scope` entitlements for `FolderAccessManager`.

Run the tests with `swift test`.
