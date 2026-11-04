import Foundation
import Testing
@testable import MacAppKitExtras

struct FolderAccessManagerTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "MacAppKitExtrasTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func makeFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func grantingAccessSavesABookmarkUnderTheConfiguredKeyAndAnnouncesIt() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manager = FolderAccessManager(configuration: .init(bookmarksDefaultsKey: "test_bookmarks", defaults: defaults))
        let before = manager.accessGrantedTrigger

        let notification = NotificationCenter.default.notifications(named: FolderAccessManager.accessGrantedNotification, object: manager)
        let granted = await withCheckedContinuation { continuation in
            manager.grantAccess(to: folder) { continuation.resume(returning: $0) }
        }

        #expect(granted)
        let saved = defaults.dictionary(forKey: "test_bookmarks") as? [String: Data]
        #expect(saved?[folder.standardizedFileURL.path] != nil)
        #expect(manager.accessGrantedTrigger != before)
        let posted = await notification.first { _ in true }
        #expect(posted?.userInfo?[FolderAccessManager.grantedURLKey] as? URL == folder.standardizedFileURL)
    }

    @Test func readableFoldersNeedNoBookmark() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manager = FolderAccessManager(configuration: .init(defaults: defaults))

        #expect(manager.hasAccess(to: folder))
        #expect(manager.ensureAccess(for: folder))
        #expect(defaults.dictionary(forKey: manager.configuration.bookmarksDefaultsKey) == nil)
    }

    @Test func defaultPanelMessageNamesTheFolder() {
        let message = FolderAccessManager.Configuration().panelMessage("Notes")
        #expect(message.contains("“Notes”"))
    }
}
