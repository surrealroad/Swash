//
//  FolderWorkspace.swift
//  Swash
//
//  A folder of Markdown files opened together. It lists the folder's Markdown files (subfolders
//  included), loads the selected one into a `SwashDocument`, saves edits back to disk shortly after
//  they are made, searches the files and follows links between them. The pure logic lives in
//  `FolderIndex.swift`.
//
//  All file access relies on the folder's security-scoped bookmark, started by
//  `FolderAccessManager` when the window opens: everything here stays inside `folderURL`.
//

#if os(macOS)
import Foundation
import Combine
#if canImport(CoreServices)
import CoreServices
#endif

final class FolderWorkspace: ObservableObject {
    static var markdownExtensions: Set<String> { FolderScanner.markdownExtensions }

    let folderURL: URL

    /// The folder's subfolders and Markdown files, folders first.
    @Published private(set) var tree: [FolderNode] = []
    /// Every Markdown file in `tree`.
    @Published private(set) var files: [URL] = []
    /// The folder is too large or deep to list completely.
    @Published private(set) var isTruncated = false
    /// The first scan hasn't finished.
    @Published private(set) var isLoading = true
    @Published private(set) var selectedFile: URL?
    @Published var document = SwashDocument() {
        didSet {
            if document.text != savedText { scheduleSave() }
        }
    }
    /// A selection to show once the selected file is in the editor (a search result).
    @Published private(set) var revealRequest: TextRevealRequest?
    /// The last read or write that failed, for the window to show.
    @Published var errorMessage: String?

    /// Full-text search results for `searchQuery`.
    @Published private(set) var searchResults: [FolderSearchMatch] = []
    @Published private(set) var isSearching = false
    private(set) var searchQuery = ""

    /// The selected file's text as it is on disk.
    private var savedText = ""
    private var pendingSave: DispatchWorkItem?
    private var eventStream: FSEventStreamRef?
    private var scanTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var pendingReload: DispatchWorkItem?

    init(folderURL: URL) {
        self.folderURL = folderURL.standardizedFileURL
    }

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    var hasUnsavedChanges: Bool {
        selectedFile != nil && document.text != savedText
    }

    /// `url`'s path below the folder, for subtitles and search results.
    func relativePath(of url: URL) -> String {
        FolderScanner.relativePath(of: url, in: folderURL)
    }

    /// Lists the folder, opens its first Markdown file and starts watching for changes.
    func open() {
        reloadFiles { [weak self] in
            guard let self, self.selectedFile == nil else { return }
            // A file at the top of the folder rather than the first one in a subfolder
            let topLevel = self.tree.first { !$0.isFolder }?.url
            if let first = topLevel ?? self.files.first { self.select(first) }
        }
        startWatching()
    }

    /// Saves any pending edit and stops watching the folder.
    func close() {
        save()
        scanTask?.cancel()
        searchTask?.cancel()
        stopWatching()
    }

    /// Opens `url` in the editor, optionally selecting `range` (raw-Markdown offsets) once it is shown.
    func select(_ url: URL, revealing range: NSRange? = nil) {
        let url = url.standardizedFileURL
        if url == selectedFile {
            if let range { revealRequest = TextRevealRequest(fileURL: url, range: range) }
            return
        }
        save()
        do {
            let text = try Self.read(url)
            savedText = text
            revealRequest = range.map { TextRevealRequest(fileURL: url, range: $0) }
            selectedFile = url
            document = SwashDocument(text: text)
        } catch {
            errorMessage = "“\(url.lastPathComponent)” couldn’t be opened. \(error.localizedDescription)"
        }
    }

    // MARK: File operations

    /// Creates an empty Markdown file in `folder` (the workspace folder by default) and selects it.
    @discardableResult
    func createFile(in folder: URL? = nil) -> URL? {
        let folder = folder ?? folderURL
        guard FolderScanner.contains(folderURL, folder) else { return nil }
        var url = folder.appendingPathComponent("Untitled.md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("Untitled \(counter).md")
            counter += 1
        }
        do {
            try Data().write(to: url, options: .withoutOverwriting)
        } catch {
            errorMessage = "A new file couldn’t be created. \(error.localizedDescription)"
            return nil
        }
        select(url)
        reloadFiles()
        return url
    }

    /// Renames a file or folder in place. Returns the new URL, or nil (with `errorMessage` set).
    @discardableResult
    func rename(_ url: URL, to name: String) -> URL? {
        let url = url.standardizedFileURL
        guard FolderScanner.contains(folderURL, url), url != folderURL else { return nil }
        if let problem = FolderScanner.renameProblem(name) {
            errorMessage = problem
            return nil
        }
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let newName = FolderScanner.renamedFileName(for: url, to: name, isFolder: isFolder)
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName).standardizedFileURL
        guard destination != url else { return url }
        // A case-only rename ("notes" → "Notes") is the same item on a case-insensitive volume
        let caseOnly = destination.path.lowercased() == url.path.lowercased()
        if !caseOnly, FileManager.default.fileExists(atPath: destination.path) {
            errorMessage = "“\(newName)” already exists."
            return nil
        }
        save()
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            errorMessage = "“\(url.lastPathComponent)” couldn’t be renamed. \(error.localizedDescription)"
            return nil
        }
        if let selected = selectedFile, let moved = FolderScanner.relocate(selected, from: url, to: destination) {
            selectedFile = moved
        }
        reloadFiles()
        return destination
    }

    /// Moves a file or folder to the Trash (never deletes it). The caller confirms first.
    func moveToTrash(_ url: URL) {
        let url = url.standardizedFileURL
        guard FolderScanner.contains(folderURL, url), url != folderURL else { return }
        let containsSelection = selectedFile.map { FolderScanner.relocate($0, from: url, to: url) != nil } ?? false
        // Unsaved edits go to the Trash with the file
        save()
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            errorMessage = "“\(url.lastPathComponent)” couldn’t be moved to the Trash. \(error.localizedDescription)"
            return
        }
        if containsSelection { clearSelection() }
        reloadFiles { [weak self] in
            guard let self, self.selectedFile == nil, let first = self.files.first else { return }
            self.select(first)
        }
    }

    // MARK: Saving

    /// Writes the selected file if its text has changed.
    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let url = selectedFile, document.text != savedText else { return }
        let text = document.text
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedText = text
        } catch {
            errorMessage = "“\(url.lastPathComponent)” couldn’t be saved. \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func clearSelection() {
        pendingSave?.cancel()
        pendingSave = nil
        selectedFile = nil
        savedText = ""
        revealRequest = nil
        document = SwashDocument()
    }

    // MARK: Listing

    /// Rescans the folder off the main thread, then calls `completion` with the new listing in place.
    func reloadFiles(completion: (() -> Void)? = nil) {
        scanTask?.cancel()
        let root = folderURL
        scanTask = Task { [weak self] in
            let scan = await Task.detached(priority: .userInitiated) {
                FolderScanner.scan(root, isCancelled: { Task.isCancelled })
            }.value
            guard !Task.isCancelled, let self else { return }
            self.apply(scan)
            completion?()
        }
    }

    private func apply(_ scan: FolderScan) {
        if scan.nodes != tree { tree = scan.nodes }
        if scan.files != files { files = scan.files }
        if scan.isTruncated != isTruncated { isTruncated = scan.isTruncated }
        if isLoading { isLoading = false }

        guard let selected = selectedFile else { return }
        if !FileManager.default.fileExists(atPath: selected.path) {
            // The open file was renamed or deleted elsewhere
            clearSelection()
            if let first = files.first { select(first) }
        } else if !hasUnsavedChanges, let text = try? Self.read(selected), text != savedText {
            // Changed by another app, with no edits here to lose
            savedText = text
            document = SwashDocument(text: text)
        }
    }

    /// Reloads when anything in the folder or its subfolders is added, removed, renamed or saved.
    private func startWatching() {
        guard eventStream == nil else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let workspace = Unmanaged<FolderWorkspace>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { workspace.scheduleReload() }
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [folderURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func stopWatching() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    /// Coalesces bursts of file-system events (an app saving several files) into one rescan.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadFiles()
            // Results may point at text that has changed
            if let self, !self.searchQuery.isEmpty { self.search(self.searchQuery, debounce: false) }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    // MARK: Search

    /// Searches every Markdown file's text for `query`, off the main thread, after a short pause
    /// in typing. The open file is searched as edited, not as saved.
    func search(_ query: String, debounce: Bool = true) {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchQuery = query
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        let files = self.files
        var texts: [URL: String] = [:]
        if let selected = selectedFile { texts[selected] = document.text }
        searchTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            let results = await Task.detached(priority: .userInitiated) {
                FolderSearch.search(query, in: files, texts: texts, isCancelled: { Task.isCancelled })
            }.value
            guard !Task.isCancelled, let self else { return }
            self.searchResults = results
            self.isSearching = false
        }
    }

    // MARK: Links

    /// Opens the note a clicked link points to, if it is a Markdown file in this folder: a relative
    /// link or a `[[wiki link]]`. Returns false for anything else, which opens as usual.
    func openLink(_ url: URL) -> Bool {
        guard let current = selectedFile else { return false }
        let target: URL?
        if url.scheme == wikiLinkScheme {
            let name = (url.absoluteString.dropFirst(wikiLinkScheme.count + 1)).removingPercentEncoding ?? ""
            target = NoteLinkResolver.resolveWiki(name, from: current, root: folderURL, files: files)
            if target == nil {
                errorMessage = "There’s no note named “\(name)” in “\(folderURL.lastPathComponent)”."
                return true
            }
        } else {
            // Relative links have no scheme; their text is the destination as written
            let destination = url.scheme == nil ? url.relativeString : url.absoluteString
            target = NoteLinkResolver.resolve(destination, from: current, root: folderURL)
        }
        guard let target else { return false }
        select(target)
        return true
    }

    private static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }
}
#endif
