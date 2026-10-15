//
//  DocumentOpening.swift
//  Swash
//
//  Opening, reopening and importing documents: open requests from Finder and URLs are coalesced
//  and checked first so failures get a specific explanation; closed documents can be reopened;
//  Word, RTF and HTML files are imported as new Markdown documents.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Opening

enum DocumentOpenFailure: Equatable {
    case missing, folder, unreadable, tooLarge(Int64), notText

    var explanation: String {
        switch self {
        case .missing: return "The file no longer exists."
        case .folder: return "It is a folder, not a document."
        case .unreadable: return "Swash doesn't have permission to read it."
        case .tooLarge(let bytes):
            return "It is too large to edit (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))."
        case .notText: return "It isn't a text file."
        }
    }
}

@MainActor
final class DocumentOpener {
    static let shared = DocumentOpener()

    /// Opening more documents than this at once asks first.
    static let confirmationThreshold = 10
    nonisolated static let maximumFileSize: Int64 = 50 * 1024 * 1024

    private var pending: [URL] = []
    private var flushScheduled = false

    /// Queues `urls` for opening. Requests arriving within a moment of each other (a Finder
    /// multi-selection is delivered as several events) are handled together.
    func open(_ urls: [URL]) {
        for url in urls where !pending.contains(url) { pending.append(url) }
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in self?.flush() }
    }

    private func flush() {
        flushScheduled = false
        let urls = pending
        pending = []
        guard !urls.isEmpty else { return }

        if urls.count > Self.confirmationThreshold {
            let alert = NSAlert()
            alert.messageText = "Open \(urls.count) documents?"
            alert.informativeText = "Each document opens in its own window."
            alert.addButton(withTitle: "Open All")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        var failures: [(URL, DocumentOpenFailure)] = []
        for url in urls {
            if let failure = Self.check(url) {
                failures.append((url, failure))
                continue
            }
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                guard let error = error else { return }
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return }
                NSApp.presentError(error)
            }
        }
        if !failures.isEmpty { Self.report(failures) }
    }

    /// Why `url` can't be opened as a document, or nil when it looks fine.
    nonisolated static func check(_ url: URL) -> DocumentOpenFailure? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .missing }
        if isDirectory.boolValue { return .folder }
        guard manager.isReadableFile(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else { return .unreadable }
        defer { try? handle.close() }
        if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int64, size > maximumFileSize {
            return .tooLarge(size)
        }
        let head = (try? handle.read(upToCount: 8192)) ?? Data()
        return looksLikeText(head) ? nil : .notText
    }

    /// Text has no NUL bytes, unless it is UTF-16 (which starts with a byte-order mark).
    nonisolated static func looksLikeText(_ head: Data) -> Bool {
        if head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) { return true }
        return !head.contains(0)
    }

    private static func report(_ failures: [(URL, DocumentOpenFailure)]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if failures.count == 1, let (url, failure) = failures.first {
            alert.messageText = "“\(url.lastPathComponent)” can't be opened."
            alert.informativeText = failure.explanation
        } else {
            alert.messageText = "\(failures.count) files can't be opened."
            alert.informativeText = failures.map { "\($0.0.lastPathComponent): \($0.1.explanation)" }.joined(separator: "\n")
        }
        alert.runModal()
    }
}

// MARK: - New documents with content

/// Text for the next untitled documents to start with (quick capture, import). `ContentView`
/// takes one when an empty, unsaved document appears.
@MainActor
enum NewDocumentSeed {
    private static var queue: [String] = []

    static func createDocument(with text: String) {
        queue.append(text)
        NSDocumentController.shared.newDocument(nil)
    }

    static func take() -> String? {
        queue.isEmpty ? nil : queue.removeFirst()
    }
}

// MARK: - Reopening

/// Recently closed document files, most recent last, for File ▸ Reopen Closed Document.
@MainActor
final class RecentlyClosedDocuments: ObservableObject {
    static let shared = RecentlyClosedDocuments()
    @Published private(set) var urls: [URL] = []
    private let limit = 20

    func push(_ url: URL) {
        urls.removeAll { $0 == url }
        urls.append(url)
        if urls.count > limit { urls.removeFirst(urls.count - limit) }
    }

    /// Reopens the most recently closed document that isn't open again already and still exists.
    func reopenLast() {
        let open = Set(NSDocumentController.shared.documents.compactMap { $0.fileURL?.standardizedFileURL })
        while let url = urls.popLast() {
            if open.contains(url.standardizedFileURL) { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            DocumentOpener.shared.open([url])
            return
        }
        NSSound.beep()
    }
}

// MARK: - Importing

enum DocumentImporter {
    static let importableTypes: [UTType] = [
        .rtf, .rtfd, .flatRTFD, .html, .webArchive,
        UTType("org.openxmlformats.wordprocessingml.document"),
        UTType("com.microsoft.word.doc"),
        UTType("org.oasis-open.opendocument.text"),
    ].compactMap { $0 }

    /// Asks for Word, RTF, HTML or OpenDocument files and opens each as a new Markdown document.
    @MainActor
    static func runImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import"
        panel.message = "Choose Word, RTF, HTML or OpenDocument files to convert to Markdown."
        panel.prompt = "Import"
        panel.allowedContentTypes = importableTypes
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var failed: [String] = []
        for url in panel.urls {
            if let markdown = markdown(from: url) {
                NewDocumentSeed.createDocument(with: markdown)
            } else {
                failed.append(url.lastPathComponent)
            }
        }
        if !failed.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = failed.count == 1 ? "“\(failed[0])” couldn't be imported." : "\(failed.count) files couldn't be imported."
            alert.informativeText = "Swash couldn't read any text from \(failed.count == 1 ? "it" : failed.joined(separator: ", "))."
            alert.runModal()
        }
    }

    /// Converts a rich-text document to Markdown through HTML, the same path as pasting rich text.
    static func markdown(from url: URL) -> String? {
        let html: String
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .html),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            html = source
        } else {
            guard let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil),
                  attributed.length > 0,
                  let data = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                                  documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
                  let converted = String(data: data, encoding: .utf8) else { return nil }
            html = converted
        }
        guard let markdown = HTMLToMarkdown.convert(html)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !markdown.isEmpty else { return nil }
        return markdown + "\n"
    }
}

// MARK: - Menu commands

struct FileMenuCommands: Commands {
    @ObservedObject private var recentlyClosed = RecentlyClosedDocuments.shared

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Reopen Closed Document") { recentlyClosed.reopenLast() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(recentlyClosed.urls.isEmpty)
        }
        CommandGroup(after: .importExport) {
            Button("Import…") { DocumentImporter.runImportPanel() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }
    }
}
