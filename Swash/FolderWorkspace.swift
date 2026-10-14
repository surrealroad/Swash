//
//  FolderWorkspace.swift
//  Swash
//
//  A folder of Markdown files opened together. It lists the folder's Markdown files, loads the
//  selected one into a `SwashDocument` and saves edits back to disk shortly after they are made.
//

import Foundation
import Combine

final class FolderWorkspace: ObservableObject {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkdn"]

    let folderURL: URL

    /// Markdown files directly inside the folder, sorted as the Finder sorts them.
    @Published private(set) var files: [URL] = []
    @Published private(set) var selectedFile: URL?
    @Published var document = SwashDocument() {
        didSet {
            if document.text != savedText { scheduleSave() }
        }
    }
    /// The last read or write that failed, for the window to show.
    @Published var errorMessage: String?

    /// The selected file's text as it is on disk.
    private var savedText = ""
    private var pendingSave: DispatchWorkItem?
    private var watcher: DispatchSourceFileSystemObject?

    init(folderURL: URL) {
        self.folderURL = folderURL.standardizedFileURL
    }

    var hasUnsavedChanges: Bool {
        selectedFile != nil && document.text != savedText
    }

    /// Lists the folder, opens its first Markdown file and starts watching for changes.
    func open() {
        reloadFiles()
        if selectedFile == nil, let first = files.first {
            select(first)
        }
        startWatching()
    }

    /// Saves any pending edit and stops watching the folder.
    func close() {
        save()
        watcher?.cancel()
        watcher = nil
    }

    func select(_ url: URL) {
        guard url != selectedFile else { return }
        save()
        do {
            let text = try Self.read(url)
            savedText = text
            selectedFile = url
            document = SwashDocument(text: text)
        } catch {
            errorMessage = "“\(url.lastPathComponent)” couldn’t be opened. \(error.localizedDescription)"
        }
    }

    /// Creates an empty Markdown file in the folder and selects it.
    @discardableResult
    func createFile() -> URL? {
        var url = folderURL.appendingPathComponent("Untitled.md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folderURL.appendingPathComponent("Untitled \(counter).md")
            counter += 1
        }
        do {
            try Data().write(to: url, options: .withoutOverwriting)
        } catch {
            errorMessage = "A new file couldn’t be created. \(error.localizedDescription)"
            return nil
        }
        reloadFiles()
        select(url)
        return url
    }

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

    func reloadFiles() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let markdown = contents
            .filter { Self.markdownExtensions.contains($0.pathExtension.lowercased()) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map(\.standardizedFileURL)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if markdown != files {
            files = markdown
        }

        guard let selected = selectedFile else { return }
        if !files.contains(selected) {
            // The open file was renamed or deleted elsewhere
            pendingSave?.cancel()
            pendingSave = nil
            selectedFile = nil
            savedText = ""
            document = SwashDocument()
            if let first = files.first { select(first) }
        } else if !hasUnsavedChanges, let text = try? Self.read(selected), text != savedText {
            // Changed by another app, with no edits here to lose
            savedText = text
            document = SwashDocument(text: text)
        }
    }

    /// Reloads when files are added, removed, renamed or saved by apps that replace the file.
    private func startWatching() {
        guard watcher == nil else { return }
        let descriptor = Darwin.open(folderURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reloadFiles() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        watcher = source
    }

    private static func read(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }
}
