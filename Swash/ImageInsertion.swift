//
//  ImageInsertion.swift
//  Swash
//
//  Adds images to a document by drag and drop or paste. Image files and pasted image data
//  (screenshots) are copied into an assets folder beside the document (Settings › Images) and
//  linked with a relative `![](assets/…)`. Images already in the document's folder are linked
//  where they are.
//

import AppKit
import UniformTypeIdentifiers

enum ImageInsertion {
    static let folderDefaultsKey = "imageAssetsFolder"
    static let defaultFolderName = "assets"

    /// The folder, relative to the document, that new images are copied into ("" for the document's own folder).
    static var assetsFolderName: String {
        let name = UserDefaults.standard.string(forKey: folderDefaultsKey) ?? defaultFolderName
        return name.trimmingCharacters(in: CharacterSet(charactersIn: "/ ").union(.whitespacesAndNewlines))
    }

    enum Item: Equatable {
        /// An image file on disk.
        case file(URL)
        /// Image data with no file of its own (a screenshot, an image copied from a web page).
        case data(Data, UTType)
    }

    enum InsertionError: LocalizedError {
        case untitledDocument
        case noFolderAccess(URL)

        var errorDescription: String? {
            switch self {
            case .untitledDocument:
                return "Save the document first, so the image can be stored beside it."
            case .noFolderAccess(let folder):
                return "Swash doesn’t have permission to add files to “\(folder.lastPathComponent)”."
            }
        }
    }

    // MARK: Reading the pasteboard

    /// The images on `pasteboard`, or nil when it holds anything else (text with images is pasted as text).
    static func items(on pasteboard: NSPasteboard) -> [Item]? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !urls.isEmpty {
            let images = urls.filter(isImageFile)
            return images.count == urls.count ? images.map(Item.file) : nil
        }
        // Copied web text carries HTML and a string; only bare image data is an image paste
        guard pasteboard.string(forType: .string) == nil else { return nil }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) {
                return [type == .png ? .data(data, .png) : .data(data, .tiff)]
            }
        }
        return nil
    }

    nonisolated static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    // MARK: Storing

    /// Copies the images beside the document where needed and returns the Markdown that links them.
    /// Without a document file only existing files can be linked (by file URL).
    static func markdown(for items: [Item], documentURL: URL?, date: Date = Date()) throws -> String {
        var links: [String] = []
        for item in items {
            let url: URL
            switch item {
            case .file(let file):
                guard let documentURL else {
                    links.append(link(alt: file.deletingPathExtension().lastPathComponent, source: file.absoluteString))
                    continue
                }
                url = isInside(file, folder: documentURL.deletingLastPathComponent()) ? file : try copy(file, besides: documentURL)
            case .data(let data, let type):
                guard let documentURL else { throw InsertionError.untitledDocument }
                url = try write(data, type: type, besides: documentURL, date: date)
            }
            links.append(link(alt: url.deletingPathExtension().lastPathComponent, source: MarkdownImageSource.source(for: url, relativeTo: documentURL)))
        }
        return links.joined(separator: "\n")
    }

    /// The folder the images go into, created if needed.
    static func assetsFolder(besides documentURL: URL) throws -> URL {
        let folder = documentURL.deletingLastPathComponent()
        let name = assetsFolderName
        guard !name.isEmpty else { return folder }
        let assets = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        return assets
    }

    private static func copy(_ file: URL, besides documentURL: URL) throws -> URL {
        let destination = uniqueURL(in: try assetsFolder(besides: documentURL), name: file.deletingPathExtension().lastPathComponent, extension: file.pathExtension)
        try FileManager.default.copyItem(at: file, to: destination)
        return destination
    }

    /// Writes pasted image data as a PNG named like a macOS screenshot.
    private static func write(_ data: Data, type: UTType, besides documentURL: URL, date: Date) throws -> URL {
        var png = data
        if type != .png {
            guard let rep = NSBitmapImageRep(data: data), let converted = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            png = converted
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let destination = uniqueURL(in: try assetsFolder(besides: documentURL), name: "Pasted Image \(formatter.string(from: date))", extension: "png")
        try png.write(to: destination, options: .withoutOverwriting)
        return destination
    }

    static func uniqueURL(in folder: URL, name: String, extension ext: String) -> URL {
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    private static func isInside(_ file: URL, folder: URL) -> Bool {
        let folderPath = folder.standardizedFileURL.path
        return file.standardizedFileURL.path.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/")
    }

    private static func link(alt: String, source: String) -> String {
        let escaped = alt.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "![\(escaped)](\(source))"
    }

    // MARK: Inserting

    /// Stores the images and inserts their Markdown at the text view's selection, asking for access to
    /// the document's folder first when the sandbox doesn't allow writing there.
    @MainActor
    static func insert(_ items: [Item], documentURL: URL?, in textView: NSTextView, insertMarkdown: @escaping (String) -> Void) {
        let needsFolder = documentURL != nil && items.contains { item in
            if case .file(let url) = item { return !isInside(url, folder: documentURL!.deletingLastPathComponent()) }
            return true
        }
        let finish = {
            do {
                insertMarkdown(try markdown(for: items, documentURL: documentURL))
            } catch {
                present(error, in: textView.window)
            }
        }
        guard needsFolder, let folder = documentURL?.deletingLastPathComponent() else {
            finish()
            return
        }
        FolderAccessManager.shared.ensureAccess(for: folder)
        if FileManager.default.isWritableFile(atPath: folder.path) {
            finish()
            return
        }
        // Keep the drop point while the access panel is up
        let selection = textView.selectedRange()
        FolderAccessManager.shared.promptForAccess(to: folder, window: textView.window) { granted in
            guard granted, FileManager.default.isWritableFile(atPath: folder.path) else {
                present(InsertionError.noFolderAccess(folder), in: textView.window)
                return
            }
            textView.setSelectedRange(selection)
            finish()
        }
    }

    @MainActor
    private static func present(_ error: Error, in window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "The image couldn’t be added."
        alert.informativeText = error.localizedDescription
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
