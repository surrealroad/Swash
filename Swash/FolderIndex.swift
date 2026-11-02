//
//  FolderIndex.swift
//  Swash
//
//  The pure logic behind folder windows: scanning a folder into a tree of Markdown files,
//  filtering it by name, searching the files' text, and resolving links between notes.
//  Foundation only, so `Tests/FolderIndex/run_folder_tests.sh` can check it with swiftc.
//

import Foundation

/// A Markdown file or a folder holding some, in a folder window's sidebar.
nonisolated struct FolderNode: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    var children: [FolderNode] = []

    var id: URL { url }
    /// Files are shown without their extension.
    var displayName: String {
        isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }
}

/// A scanned folder: its tree, every Markdown file in it, and whether a limit cut the scan short.
nonisolated struct FolderScan: Equatable {
    var nodes: [FolderNode] = []
    var files: [URL] = []
    var isTruncated = false
}

nonisolated enum FolderScanner {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkdn"]
    /// Folders never worth listing: tool caches, dependencies and build output.
    static let skippedFolderNames: Set<String> = [
        "node_modules", "Pods", "Carthage", "DerivedData", "build", "dist",
        "__pycache__", "venv", "target", "vendor",
    ]
    static let maximumDepth = 8
    static let maximumFiles = 5000
    static let maximumFolders = 2000

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func skipsFolder(named name: String) -> Bool {
        name.hasPrefix(".") || skippedFolderNames.contains(name) || name.hasSuffix(".app") || name.hasSuffix(".xcodeproj")
    }

    /// Lists `root`'s Markdown files and the subfolders that hold some, folders first, each level
    /// sorted as the Finder sorts names. Hidden items and `skippedFolderNames` are skipped, and
    /// the scan stops at `maximumDepth`, `maximumFiles` or `maximumFolders`.
    static func scan(
        _ root: URL,
        maximumDepth: Int = maximumDepth,
        maximumFiles: Int = maximumFiles,
        maximumFolders: Int = maximumFolders,
        isCancelled: () -> Bool = { false }
    ) -> FolderScan {
        var result = FolderScan()
        var folderCount = 0

        func children(of folder: URL, depth: Int) -> [FolderNode] {
            if isCancelled() { result.isTruncated = true; return [] }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { return [] }
            let sorted = contents.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            var folders: [FolderNode] = []
            var files: [FolderNode] = []
            for item in sorted {
                let values = try? item.resourceValues(forKeys: Set(keys))
                let url = item.standardizedFileURL
                // Symbolic links are not followed, so a link to a parent folder can't loop
                if values?.isSymbolicLink == true { continue }
                if values?.isDirectory == true {
                    guard values?.isPackage != true, !skipsFolder(named: url.lastPathComponent) else { continue }
                    guard depth < maximumDepth else { result.isTruncated = true; continue }
                    guard folderCount < maximumFolders else { result.isTruncated = true; continue }
                    folderCount += 1
                    let nested = children(of: url, depth: depth + 1)
                    // Folders without any Markdown files are left out
                    if !nested.isEmpty {
                        folders.append(FolderNode(url: url, isFolder: true, children: nested))
                    }
                } else if values?.isRegularFile == true, isMarkdown(url) {
                    guard result.files.count < maximumFiles else { result.isTruncated = true; continue }
                    result.files.append(url)
                    files.append(FolderNode(url: url, isFolder: false))
                }
            }
            return folders + files
        }

        result.nodes = children(of: root.standardizedFileURL, depth: 0)
        return result
    }

    /// The tree with only the files whose names contain `query` (ignoring case and accents), and
    /// the folders leading to them. A folder whose own name matches keeps all of its contents.
    static func filter(_ nodes: [FolderNode], query: String) -> [FolderNode] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nodes }
        return nodes.compactMap { node in
            if node.isFolder {
                if node.displayName.localizedStandardContains(query) { return node }
                let kept = filter(node.children, query: query)
                return kept.isEmpty ? nil : FolderNode(url: node.url, isFolder: true, children: kept)
            }
            return node.url.lastPathComponent.localizedStandardContains(query) ? node : nil
        }
    }

    /// URLs of every folder in the tree, for expanding all of them.
    static func folderURLs(in nodes: [FolderNode]) -> Set<URL> {
        var urls: Set<URL> = []
        for node in nodes where node.isFolder {
            urls.insert(node.url)
            urls.formUnion(folderURLs(in: node.children))
        }
        return urls
    }

    /// `url`'s path below `root` ("Notes/Ideas.md"), or its name when it is outside `root`.
    static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }

    /// Whether `url` is `root` or inside it.
    static func contains(_ root: URL, _ url: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    /// `url` after `oldURL` was renamed or moved to `newURL`: itself, or a file inside a renamed folder.
    static func relocate(_ url: URL, from oldURL: URL, to newURL: URL) -> URL? {
        let old = oldURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == old { return newURL.standardizedFileURL }
        guard path.hasPrefix(old + "/") else { return nil }
        return newURL.standardizedFileURL.appendingPathComponent(String(path.dropFirst(old.count + 1))).standardizedFileURL
    }

    /// Why `name` can't be used to rename a file or folder, or nil when it can.
    static func renameProblem(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "The name can’t be empty." }
        if trimmed.contains("/") || trimmed.contains(":") { return "The name can’t contain “/” or “:”." }
        if trimmed.hasPrefix(".") { return "Names that begin with a dot are hidden." }
        return nil
    }

    /// The file name for renaming `url` to `name`: a file keeps its Markdown extension when the
    /// new name has none.
    static func renamedFileName(for url: URL, to name: String, isFolder: Bool) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFolder || isMarkdown(URL(fileURLWithPath: trimmed)) { return trimmed }
        let ext = url.pathExtension
        return ext.isEmpty ? trimmed : trimmed + "." + ext
    }
}

// MARK: - Full-text search

/// One occurrence of a search in a folder's files.
nonisolated struct FolderSearchMatch: Identifiable, Hashable {
    let file: URL
    /// One-based line number.
    let line: Int
    /// The match in the file's text (UTF-16 offsets, as the editor's selection uses).
    let range: NSRange
    /// The line around the match, shortened if it is long.
    let snippet: String
    /// The match within `snippet`.
    let snippetRange: NSRange

    var id: String { "\(file.path)#\(range.location)" }
}

nonisolated enum FolderSearch {
    static let maximumResults = 500
    static let maximumResultsPerFile = 50
    /// Larger files are not searched.
    static let maximumFileSize = 5 * 1024 * 1024
    private static let snippetLength = 120

    /// Occurrences of `query` in `text`, ignoring case and accents.
    static func matches(of query: String, in text: String, file: URL, limit: Int = maximumResultsPerFile) -> [FolderSearchMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        let string = text as NSString
        var results: [FolderSearchMatch] = []
        var searchStart = 0
        var line = 1
        var lineCountedTo = 0
        while searchStart < string.length, results.count < limit {
            let found = string.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: NSRange(location: searchStart, length: string.length - searchStart)
            )
            guard found.location != NSNotFound, found.length > 0 else { break }
            line += newlineCount(in: string, from: lineCountedTo, to: found.location)
            lineCountedTo = found.location
            let lineRange = string.lineRange(for: NSRange(location: found.location, length: 0))
            let (snippet, snippetRange) = makeSnippet(string, line: lineRange, match: found)
            results.append(FolderSearchMatch(file: file, line: line, range: found, snippet: snippet, snippetRange: snippetRange))
            searchStart = NSMaxRange(found)
        }
        return results
    }

    /// Searches `files`, using `texts` for files with unsaved edits and reading the rest from disk.
    static func search(
        _ query: String,
        in files: [URL],
        texts: [URL: String] = [:],
        limit: Int = maximumResults,
        isCancelled: () -> Bool = { false }
    ) -> [FolderSearchMatch] {
        var results: [FolderSearchMatch] = []
        for file in files {
            if isCancelled() || results.count >= limit { break }
            guard let text = texts[file] ?? read(file) else { continue }
            results += matches(of: query, in: text, file: file, limit: min(maximumResultsPerFile, limit - results.count))
        }
        return results
    }

    private static func read(_ url: URL) -> String? {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileSize { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func newlineCount(in string: NSString, from start: Int, to end: Int) -> Int {
        var count = 0
        var index = start
        while index < end {
            if string.character(at: index) == 0x0A { count += 1 }
            index += 1
        }
        return count
    }

    private static func makeSnippet(_ string: NSString, line: NSRange, match: NSRange) -> (String, NSRange) {
        // Without the line break, and without leading indentation
        var start = line.location
        var end = NSMaxRange(line)
        while end > start, [0x0A, 0x0D].contains(string.character(at: end - 1)) { end -= 1 }
        while start < match.location, [0x20, 0x09].contains(string.character(at: start)) { start += 1 }
        var prefix = ""
        var suffix = ""
        if end - start > snippetLength {
            let lead = 40
            if match.location - start > lead {
                start = match.location - lead
                prefix = "…"
            }
            if end - start > snippetLength {
                end = max(NSMaxRange(match), start + snippetLength)
                suffix = "…"
            }
        }
        // Don't split a surrogate pair at either end
        let range = string.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: max(0, end - start)))
        let text = prefix + string.substring(with: range) + suffix
        let offset = (prefix as NSString).length + match.location - range.location
        return (text, NSRange(location: offset, length: match.length))
    }
}

// MARK: - Links between notes

nonisolated enum NoteLinkResolver {
    /// The Markdown file in `root` that a link destination written in `file` points to, for a
    /// relative link ("Other.md", "../Ideas/Plan.md#goals", "Some%20Note.md"), a path from the
    /// folder's top ("/Notes/Plan.md") or a `file:` URL inside `root`. Destinations without an
    /// extension also try ".md". Web links, in-page anchors, other file types and files outside
    /// `root` give nil, as do files `exists` says are missing.
    static func resolve(
        _ destination: String,
        from file: URL,
        root: URL,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        var link = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.hasPrefix("<"), link.hasSuffix(">") { link = String(link.dropFirst().dropLast()) }
        guard !link.isEmpty, !link.hasPrefix("#") else { return nil }

        let path: String
        if let scheme = scheme(of: link) {
            guard scheme == "file", let url = URL(string: link) else { return nil }
            path = url.path
        } else {
            if let cut = link.firstIndex(where: { $0 == "#" || $0 == "?" }) { link = String(link[..<cut]) }
            let decoded = link.removingPercentEncoding ?? link
            guard !decoded.isEmpty else { return nil }
            if decoded.hasPrefix("/") {
                path = root.standardizedFileURL.path + decoded
            } else {
                path = file.deletingLastPathComponent().standardizedFileURL.path + "/" + decoded
            }
        }

        let target = URL(fileURLWithPath: path).standardizedFileURL
        guard FolderScanner.contains(root, target), target.path != root.standardizedFileURL.path else { return nil }
        if FolderScanner.isMarkdown(target) {
            return exists(target) ? target : nil
        }
        if target.pathExtension.isEmpty {
            let withExtension = target.appendingPathExtension("md")
            if exists(withExtension) { return withExtension }
        }
        return nil
    }

    /// The URL scheme of `link` ("https" in "https://…"), or nil for a path.
    private static func scheme(of link: String) -> String? {
        guard let colon = link.firstIndex(of: ":") else { return nil }
        let scheme = link[..<colon]
        guard let first = scheme.first, first.isLetter,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else { return nil }
        return scheme.lowercased()
    }

    // MARK: Wiki links

    /// `[[Note]]`, `[[Folder/Note|label]]` and `[[Note#Heading]]` links in `text`, with the note
    /// name each one names.
    static func wikiLinks(in text: String) -> [(range: NSRange, target: String)] {
        let string = text as NSString
        return wikiLinkPattern.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap { match in
            let inner = string.substring(with: match.range(at: 1))
            let target = wikiTarget(inner)
            return target.isEmpty ? nil : (match.range, target)
        }
    }

    /// The note name in a wiki link's contents, without its label or heading.
    static func wikiTarget(_ inner: String) -> String {
        var target = inner
        if let bar = target.firstIndex(of: "|") { target = String(target[..<bar]) }
        if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
        return target.trimmingCharacters(in: .whitespaces)
    }

    private static let wikiLinkPattern = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+?)\]\]"#)

    /// The file a wiki link names: a file with that name (ignoring case, extension optional), or
    /// with that path below `root` when the name includes folders. A file beside `file` wins,
    /// then the one with the shortest path.
    static func resolveWiki(_ name: String, from file: URL, root: URL, files: [URL]) -> URL? {
        var name = wikiTarget(name)
        guard !name.isEmpty else { return nil }
        if FolderScanner.isMarkdown(URL(fileURLWithPath: name)) {
            name = (name as NSString).deletingPathExtension
        }
        let wanted = name.lowercased()
        let candidates = files.filter { url in
            let relative = (FolderScanner.relativePath(of: url, in: root) as NSString).deletingPathExtension.lowercased()
            if wanted.contains("/") {
                return relative == wanted.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    || relative.hasSuffix("/" + wanted)
            }
            return url.deletingPathExtension().lastPathComponent.lowercased() == wanted
        }
        let folder = file.deletingLastPathComponent().standardizedFileURL
        if let sibling = candidates.first(where: { $0.deletingLastPathComponent().standardizedFileURL == folder }) {
            return sibling
        }
        return candidates.min { lhs, rhs in
            let l = FolderScanner.relativePath(of: lhs, in: root), r = FolderScanner.relativePath(of: rhs, in: root)
            return l.count != r.count ? l.count < r.count : l < r
        }
    }
}
