//
//  MarkdownParser.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import Foundation
import AppKit

enum TableAlignment: String, Codable, Equatable, CaseIterable {
    case left
    case center
    case right
    case defaultAlignment
}

struct MarkdownTableData: Equatable {
    var headers: [String]
    var alignments: [TableAlignment]
    var rows: [[String]]
}

enum AlertType: String, Codable, Equatable, CaseIterable {
    case note
    case tip
    case important
    case warning
    case caution
    
    var title: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }
}

enum BlockType: Equatable {
    case heading(level: Int)
    case blockquote
    case alertCallout(type: AlertType, text: String)
    case codeBlock(code: String, language: String?)
    case list(isOrdered: Bool, indentLevel: Int, itemNumber: Int = 1)
    case taskList(isChecked: Bool, indentLevel: Int)
    case table(headers: [String], alignments: [TableAlignment], rows: [[String]])
    case horizontalRule
    case footnoteDefinition(label: String, text: String)
    case linkReference(label: String, url: String)
    case paragraph
}

struct MarkdownBlock: Identifiable, Equatable {
    let id = UUID()
    let type: BlockType
    let text: String
    
    static func == (lhs: MarkdownBlock, rhs: MarkdownBlock) -> Bool {
        return lhs.type == rhs.type && lhs.text == rhs.text
    }
}

struct MarkdownParser {
    static func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") && !trimmed.hasSuffix("\\|") {
            trimmed.removeLast()
        }
        
        var cells: [String] = []
        var currentCell = ""
        var isEscaped = false
        var inBacktickSpan = false
        
        for char in trimmed {
            if isEscaped {
                currentCell.append(char)
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "`" {
                currentCell.append(char)
                inBacktickSpan = !inBacktickSpan
            } else if char == "|" && !inBacktickSpan {
                cells.append(currentCell.trimmingCharacters(in: .whitespaces))
                currentCell = ""
            } else {
                currentCell.append(char)
            }
        }
        cells.append(currentCell.trimmingCharacters(in: .whitespaces))
        return cells
    }
    
    // MARK: - GFM Block Parsing Helpers
    
    struct CodeFenceInfo {
        let char: Character
        let count: Int
        let language: String?
    }
    
    static func parseOpeningCodeFence(_ line: String) -> CodeFenceInfo? {
        let trimmedLeading = line.drop(while: { $0 == " " })
        let leadingSpaces = line.count - trimmedLeading.count
        guard leadingSpaces <= 3 else { return nil }
        
        guard let firstChar = trimmedLeading.first, firstChar == "`" || firstChar == "~" else { return nil }
        let fenceCount = trimmedLeading.prefix(while: { $0 == firstChar }).count
        guard fenceCount >= 3 else { return nil }
        
        let remaining = trimmedLeading.dropFirst(fenceCount).trimmingCharacters(in: .whitespaces)
        if firstChar == "`" && remaining.contains("`") {
            return nil
        }
        let language = remaining.components(separatedBy: .whitespaces).first?.trimmingCharacters(in: .whitespaces)
        let cleanLang = (language?.isEmpty ?? true) ? nil : language
        return CodeFenceInfo(char: firstChar, count: fenceCount, language: cleanLang)
    }
    
    static func isClosingCodeFence(_ line: String, matching openFence: CodeFenceInfo) -> Bool {
        let trimmedLeading = line.drop(while: { $0 == " " })
        let leadingSpaces = line.count - trimmedLeading.count
        guard leadingSpaces <= 3 else { return false }
        
        guard let firstChar = trimmedLeading.first, firstChar == openFence.char else { return false }
        let fenceCount = trimmedLeading.prefix(while: { $0 == firstChar }).count
        guard fenceCount >= openFence.count else { return false }
        
        let remaining = trimmedLeading.dropFirst(fenceCount).trimmingCharacters(in: .whitespaces)
        return remaining.isEmpty
    }
    
    private static let thematicBreakRegex = try? NSRegularExpression(
        pattern: "^(?: {0,3})(?:(?:\\*[ \\t]*){3,}|(?:-[ \\t]*){3,}|(?:_[ \\t]*){3,})$"
    )
    
    static func isThematicBreak(_ line: String) -> Bool {
        guard let regex = thematicBreakRegex else { return false }
        let nsLine = line as NSString
        return regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) != nil
    }
    
    static func parseATXHeading(_ line: String) -> (level: Int, text: String)? {
        let trimmedLeading = line.drop(while: { $0 == " " })
        let leadingSpaces = line.count - trimmedLeading.count
        guard leadingSpaces <= 3 else { return nil }
        
        var level = 0
        var remaining = trimmedLeading
        while remaining.first == "#" && level < 6 {
            level += 1
            remaining.removeFirst()
        }
        guard level >= 1 && level <= 6 else { return nil }
        
        if !remaining.isEmpty && remaining.first != " " && remaining.first != "\t" {
            return nil
        }
        
        var headingText = remaining.trimmingCharacters(in: .whitespaces)
        if let closingMatch = headingText.range(of: "(?:[ \\t]+#+[ \\t]*)$", options: .regularExpression) {
            headingText = String(headingText[..<closingMatch.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return (level, headingText)
    }
    
    static func extractLinkReferenceDefinition(_ line: String) -> (label: String, url: String)? {
        let pattern = "^ {0,3}\\[([^^][^\\]]*)\\]:\\s*<?([^>\\s]+)>?(?:\\s+[\"'(](.*?)[\"')])?\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) else { return nil }
        let label = nsLine.substring(with: match.range(at: 1)).lowercased()
        let url = nsLine.substring(with: match.range(at: 2))
        return (label, url)
    }
    
    static func resolveReferenceLinks(_ text: String, references: [String: String]) -> String {
        guard !references.isEmpty else { return text }
        var result = text
        
        // 1. Full reference links: [text][label]
        let fullRefPattern = "\\[([^\\]]+)\\]\\[([^\\]]+)\\]"
        if let regex = try? NSRegularExpression(pattern: fullRefPattern) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let textStr = nsText.substring(with: match.range(at: 1))
                let labelStr = nsText.substring(with: match.range(at: 2)).lowercased()
                if let url = references[labelStr] {
                    let replacement = "[\(textStr)](\(url))"
                    result = (result as NSString).replacingCharacters(in: match.range(at: 0), with: replacement)
                }
            }
        }
        
        // 2. Collapsed reference links: [label][]
        let collapsedPattern = "\\[([^\\]]+)\\]\\[\\]"
        if let regex = try? NSRegularExpression(pattern: collapsedPattern) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let labelStr = nsText.substring(with: match.range(at: 1))
                if let url = references[labelStr.lowercased()] {
                    let replacement = "[\(labelStr)](\(url))"
                    result = (result as NSString).replacingCharacters(in: match.range(at: 0), with: replacement)
                }
            }
        }
        
        // 3. Shortcut reference links: [label]
        let shortcutPattern = "\\[([^\\]\\^]+)\\](?![\\(\\[:])"
        if let regex = try? NSRegularExpression(pattern: shortcutPattern) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let labelStr = nsText.substring(with: match.range(at: 1))
                if let url = references[labelStr.lowercased()] {
                    let replacement = "[\(labelStr)](\(url))"
                    result = (result as NSString).replacingCharacters(in: match.range(at: 0), with: replacement)
                }
            }
        }
        
        return result
    }
    
    static func cleanImageURLAndTitle(_ rawDestination: String) -> (url: String, title: String?) {
        var trimmed = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        var title: String? = nil
        
        // Match optional trailing title: "title", 'title', or (title)
        let titlePattern = "(?:\\s+[\"'(](.*?)[\"')])\\s*$"
        if let regex = try? NSRegularExpression(pattern: titlePattern),
           let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
            if match.numberOfRanges > 1 {
                title = (trimmed as NSString).substring(with: match.range(at: 1))
            }
            let nsTrimmed = trimmed as NSString
            trimmed = nsTrimmed.substring(with: NSRange(location: 0, length: match.range(at: 0).location)).trimmingCharacters(in: .whitespaces)
        }
        
        // Strip angle brackets <...>
        if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") && trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        
        return (trimmed, title)
    }
    
    static func resolveImage(urlString: String, baseURL: URL? = nil, windowURL: URL? = nil) -> NSImage? {
        let (cleanedURL, _) = cleanImageURLAndTitle(urlString)
        guard !cleanedURL.isEmpty else { return nil }
        
        // 1. Direct path check
        if cleanedURL.hasPrefix("file://") {
            if let fileURL = URL(string: cleanedURL), fileURL.isFileURL {
                if let direct = NSImage(contentsOf: fileURL) {
                    return direct
                }
            }
            let directPath = cleanedURL.replacingOccurrences(of: "file://", with: "")
            if let direct = NSImage(contentsOfFile: directPath) {
                return direct
            }
        } else if cleanedURL.hasPrefix("/") {
            if let direct = NSImage(contentsOfFile: cleanedURL) {
                return direct
            }
            if let decoded = cleanedURL.removingPercentEncoding,
               let direct = NSImage(contentsOfFile: decoded) {
                return direct
            }
        }
        
        // 2. Identify candidate document base URL
        var documentURL: URL? = baseURL
        if documentURL == nil {
            documentURL = windowURL
        }
        if documentURL == nil, let keyWin = NSApp.keyWindow {
            documentURL = keyWin.representedURL ?? NSDocumentController.shared.document(for: keyWin)?.fileURL
        }
        if documentURL == nil, let mainWin = NSApp.mainWindow {
            documentURL = mainWin.representedURL ?? NSDocumentController.shared.document(for: mainWin)?.fileURL
        }
        if documentURL == nil {
            for doc in NSDocumentController.shared.documents {
                if let docURL = doc.fileURL {
                    documentURL = docURL
                    break
                }
            }
        }
        
        // 3. Resolve strictly relative to document folder
        if let docURL = documentURL {
            let folderURL = docURL.hasDirectoryPath ? docURL : docURL.deletingLastPathComponent()
            _ = FolderAccessManager.shared.ensureAccess(for: folderURL)
            let targetURL = folderURL.appendingPathComponent(cleanedURL)
            if let img = NSImage(contentsOfFile: targetURL.path) ?? NSImage(contentsOf: targetURL) {
                return img
            }
            if let decoded = cleanedURL.removingPercentEncoding {
                let decodedTarget = folderURL.appendingPathComponent(decoded)
                if let img = NSImage(contentsOfFile: decodedTarget.path) ?? NSImage(contentsOf: decodedTarget) {
                    return img
                }
            }
        }
        
        // 4. Fallback relative to current working directory
        let currentDir = FileManager.default.currentDirectoryPath
        let cwdURL = URL(fileURLWithPath: currentDir).appendingPathComponent(cleanedURL)
        if let img = NSImage(contentsOfFile: cwdURL.path) {
            return img
        }
        if let decoded = cleanedURL.removingPercentEncoding {
            let decodedCwd = URL(fileURLWithPath: currentDir).appendingPathComponent(decoded)
            if let img = NSImage(contentsOfFile: decodedCwd.path) {
                return img
            }
        }
        
        return nil
    }
    
    static func unreadableRelativeFolder(in markdown: String, baseURL: URL?) -> URL? {
        guard let baseURL = baseURL else { return nil }
        let folderURL = baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent()
        if FolderAccessManager.shared.hasAccess(to: folderURL) {
            return nil
        }
        
        let pattern = #"!\[([^\]]*)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            if match.numberOfRanges >= 3 {
                let destWithTitle = nsString.substring(with: match.range(at: 2))
                let (cleanedURL, _) = cleanImageURLAndTitle(destWithTitle)
                if !cleanedURL.isEmpty && !cleanedURL.contains("://") && !cleanedURL.hasPrefix("/") {
                    let target = folderURL.appendingPathComponent(cleanedURL)
                    if !FileManager.default.isReadableFile(atPath: target.path) {
                        return folderURL
                    }
                }
            }
        }
        return nil
    }
    
    static func scaleImageForEditor(_ image: NSImage, maxWidth: CGFloat = 550) -> NSImage {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return image }
        if originalSize.width <= maxWidth {
            return image
        }
        let scale = maxWidth / originalSize.width
        let targetSize = NSSize(width: maxWidth, height: ceil(originalSize.height * scale))
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: originalSize),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    static func placeholderImage(alt: String) -> NSImage {
        let displayText = alt.isEmpty ? "Image" : alt
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let textSize = (displayText as NSString).size(withAttributes: attrs)
        let badgeWidth = min(max(textSize.width + 44, 80), 550)
        let badgeHeight: CGFloat = 28
        let img = NSImage(size: NSSize(width: badgeWidth, height: badgeHeight))
        img.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: badgeWidth, height: badgeHeight)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
        path.fill()
        if let icon = NSImage(systemSymbolName: "photo", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            if let configured = icon.withSymbolConfiguration(config) {
                configured.draw(in: NSRect(x: 8, y: (badgeHeight - 12) / 2, width: 14, height: 12))
            }
        }
        (displayText as NSString).draw(at: NSPoint(x: 28, y: (badgeHeight - textSize.height) / 2), withAttributes: attrs)
        img.unlockFocus()
        return img
    }
    
    static func parseAlignments(_ line: String) -> [TableAlignment] {
        let cells = parseTableCells(line)
        return cells.map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let hasLeftColon = trimmed.hasPrefix(":")
            let hasRightColon = trimmed.hasSuffix(":")
            if hasLeftColon && hasRightColon {
                return .center
            } else if hasRightColon {
                return .right
            } else if hasLeftColon {
                return .left
            } else {
                return .defaultAlignment
            }
        }
    }
    
    static func tableToMarkdown(headers: [String], alignments: [TableAlignment], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "" }
        
        let columnCount = headers.count
        var colWidths = [Int](repeating: 3, count: columnCount)
        
        for (i, header) in headers.enumerated() {
            colWidths[i] = max(colWidths[i], header.utf16.count)
        }
        
        for row in rows {
            for i in 0..<columnCount {
                let cellText = i < row.count ? row[i] : ""
                colWidths[i] = max(colWidths[i], cellText.utf16.count)
            }
        }
        
        // Format Header
        var headerCells: [String] = []
        for i in 0..<columnCount {
            let cellText = headers[i]
            let width = colWidths[i]
            let padded = cellText.padding(toLength: width, withPad: " ", startingAt: 0)
            headerCells.append(padded)
        }
        let headerLine = "| " + headerCells.joined(separator: " | ") + " |"
        
        // Format Delimiter
        var delimiterCells: [String] = []
        for i in 0..<columnCount {
            let align = i < alignments.count ? alignments[i] : .defaultAlignment
            let width = colWidths[i]
            let dashes = String(repeating: "-", count: max(3, width))
            switch align {
            case .left:
                delimiterCells.append(":" + String(dashes.dropFirst()))
            case .center:
                delimiterCells.append(":" + String(dashes.dropFirst().dropLast()) + ":")
            case .right:
                delimiterCells.append(String(dashes.dropLast()) + ":")
            case .defaultAlignment:
                delimiterCells.append(dashes)
            }
        }
        let delimiterLine = "| " + delimiterCells.joined(separator: " | ") + " |"
        
        // Format Rows
        var rowLines: [String] = []
        for row in rows {
            var rowCells: [String] = []
            for i in 0..<columnCount {
                let cellText = i < row.count ? row[i] : ""
                let width = colWidths[i]
                let padded = cellText.padding(toLength: width, withPad: " ", startingAt: 0)
                rowCells.append(padded)
            }
            rowLines.append("| " + rowCells.joined(separator: " | ") + " |")
        }
        
        var lines = [headerLine, delimiterLine]
        lines.append(contentsOf: rowLines)
        return lines.joined(separator: "\n")
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        
        // Pre-scan link reference definitions: [label]: url "optional title"
        var linkReferences: [String: String] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let (label, url) = extractLinkReferenceDefinition(trimmed) {
                linkReferences[label] = url
            }
        }
        
        var inCodeBlock = false
        var currentOpenCodeFence: CodeFenceInfo? = nil
        var currentCodeLines: [String] = []
        var currentCodeLanguage: String? = nil
        
        var currentParagraphLines: [String] = []
        
        func flushParagraph() {
            if !currentParagraphLines.isEmpty {
                let paragraphText = currentParagraphLines.joined(separator: "\n")
                let resolved = resolveReferenceLinks(paragraphText, references: linkReferences)
                blocks.append(MarkdownBlock(type: .paragraph, text: resolved))
                currentParagraphLines.removeAll()
            }
        }
        
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if inCodeBlock {
                if let fence = currentOpenCodeFence, isClosingCodeFence(line, matching: fence) {
                    inCodeBlock = false
                    let code = currentCodeLines.joined(separator: "\n")
                    blocks.append(MarkdownBlock(type: .codeBlock(code: code, language: currentCodeLanguage), text: ""))
                    currentCodeLines.removeAll()
                    currentCodeLanguage = nil
                    currentOpenCodeFence = nil
                } else {
                    currentCodeLines.append(line)
                }
                lineIndex += 1
                continue
            }
            
            if let openFence = parseOpeningCodeFence(line) {
                flushParagraph()
                inCodeBlock = true
                currentOpenCodeFence = openFence
                currentCodeLanguage = openFence.language
                lineIndex += 1
                continue
            }
            
            // Indented Code Block (4 spaces or 1 tab when not in paragraph)
            if currentParagraphLines.isEmpty && (line.hasPrefix("    ") || line.hasPrefix("\t")) && !trimmed.isEmpty {
                var codeLines: [String] = []
                while lineIndex < lines.count {
                    let indentedLine = lines[lineIndex]
                    let indentedTrimmed = indentedLine.trimmingCharacters(in: .whitespaces)
                    if indentedLine.hasPrefix("    ") {
                        codeLines.append(String(indentedLine.dropFirst(4)))
                        lineIndex += 1
                    } else if indentedLine.hasPrefix("\t") {
                        codeLines.append(String(indentedLine.dropFirst(1)))
                        lineIndex += 1
                    } else if indentedTrimmed.isEmpty {
                        codeLines.append("")
                        lineIndex += 1
                    } else {
                        break
                    }
                }
                // Trim trailing blank lines
                while codeLines.last?.isEmpty == true {
                    codeLines.removeLast()
                }
                let code = codeLines.joined(separator: "\n")
                blocks.append(MarkdownBlock(type: .codeBlock(code: code, language: nil), text: ""))
                continue
            }
            
            // Setext Headings (=== for H1, --- for H2)
            if !currentParagraphLines.isEmpty {
                if trimmed.range(of: "^ {0,3}=+[ \\t]*$", options: .regularExpression) != nil {
                    let headingText = currentParagraphLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    currentParagraphLines.removeAll()
                    blocks.append(MarkdownBlock(type: .heading(level: 1), text: headingText))
                    lineIndex += 1
                    continue
                } else if trimmed.range(of: "^ {0,3}-+[ \\t]*$", options: .regularExpression) != nil {
                    let headingText = currentParagraphLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    currentParagraphLines.removeAll()
                    blocks.append(MarkdownBlock(type: .heading(level: 2), text: headingText))
                    lineIndex += 1
                    continue
                }
            }
            
            // Footnote Definition [^label]: text (supports multi-line indented continuation)
            let footnoteDefPattern = "^\\[\\^([^\\]]+)\\]:\\s*(.*)$"
            if let regex = try? NSRegularExpression(pattern: footnoteDefPattern),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                flushParagraph()
                let nsTrimmed = trimmed as NSString
                let label = nsTrimmed.substring(with: match.range(at: 1))
                let firstLineContent = nsTrimmed.substring(with: match.range(at: 2))
                var fnLines: [String] = []
                if !firstLineContent.isEmpty {
                    fnLines.append(firstLineContent)
                }
                lineIndex += 1
                while lineIndex < lines.count {
                    let nextLine = lines[lineIndex]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.isEmpty {
                        // Check if followed by an indented continuation line
                        if lineIndex + 1 < lines.count && (lines[lineIndex + 1].hasPrefix("    ") || lines[lineIndex + 1].hasPrefix("\t") || lines[lineIndex + 1].hasPrefix("  ")) {
                            fnLines.append("")
                            lineIndex += 1
                            continue
                        } else {
                            break
                        }
                    }
                    if nextLine.hasPrefix("    ") || nextLine.hasPrefix("\t") || nextLine.hasPrefix("  ") {
                        fnLines.append(nextTrimmed)
                        lineIndex += 1
                    } else {
                        break
                    }
                }
                let combinedText = fnLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                let resolved = resolveReferenceLinks(combinedText, references: linkReferences)
                blocks.append(MarkdownBlock(type: .footnoteDefinition(label: label, text: resolved), text: ""))
                continue
            }
            
            // Link Reference Definition [label]: url
            if let (label, url) = extractLinkReferenceDefinition(trimmed) {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .linkReference(label: label, url: url), text: ""))
                lineIndex += 1
                continue
            }
            
            // Table Detection
            let isTableStart = trimmed.contains("|") && lineIndex + 1 < lines.count
            if isTableStart {
                let nextTrimmed = lines[lineIndex + 1].trimmingCharacters(in: .whitespaces)
                let isDelimiterLine = nextTrimmed.contains("|") && nextTrimmed.contains("-")
                if isDelimiterLine {
                    let headers = parseTableCells(trimmed)
                    let alignments = parseAlignments(nextTrimmed)
                    
                    if !headers.isEmpty {
                        flushParagraph()
                        var rows: [[String]] = []
                        
                        // Skip header and separator line
                        lineIndex += 2
                        
                        while lineIndex < lines.count {
                            let rowLine = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                            if rowLine.contains("|") && !rowLine.isEmpty {
                                let cells = parseTableCells(rowLine)
                                rows.append(cells)
                                lineIndex += 1
                            } else {
                                break
                            }
                        }
                        
                        let resolvedHeaders = headers.map { resolveReferenceLinks($0, references: linkReferences) }
                        let resolvedRows = rows.map { $0.map { resolveReferenceLinks($0, references: linkReferences) } }
                        blocks.append(MarkdownBlock(type: .table(headers: resolvedHeaders, alignments: alignments, rows: resolvedRows), text: ""))
                        continue
                    }
                }
            }
            
            // Thematic Break (Horizontal Rule)
            if isThematicBreak(line) {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .horizontalRule, text: ""))
                lineIndex += 1
                continue
            }
            
            // ATX Headings
            if let heading = parseATXHeading(line) {
                flushParagraph()
                let resolved = resolveReferenceLinks(heading.text, references: linkReferences)
                blocks.append(MarkdownBlock(type: .heading(level: heading.level), text: resolved))
                lineIndex += 1
                continue
            }
            
            // GitHub Alerts & Blockquotes
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                let firstQuoteText = trimmed.hasPrefix("> ") ? String(trimmed.dropFirst(2)) : ""
                
                // Check GitHub Alert pattern: > [!NOTE], > [!TIP], > [!IMPORTANT], > [!WARNING], > [!CAUTION]
                let alertPattern = "^\\[\\!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]\\s*(.*)$"
                if let alertRegex = try? NSRegularExpression(pattern: alertPattern, options: [.caseInsensitive]),
                   let match = alertRegex.firstMatch(in: firstQuoteText, options: [], range: NSRange(location: 0, length: (firstQuoteText as NSString).length)) {
                    let nsQuote = firstQuoteText as NSString
                    let typeStr = nsQuote.substring(with: match.range(at: 1)).lowercased()
                    let firstLineContent = nsQuote.substring(with: match.range(at: 2))
                    if let alertType = AlertType(rawValue: typeStr) {
                        var alertLines: [String] = []
                        if !firstLineContent.trimmingCharacters(in: .whitespaces).isEmpty {
                            alertLines.append(firstLineContent)
                        }
                        lineIndex += 1
                        
                        while lineIndex < lines.count {
                            let lTrimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                            if lTrimmed.hasPrefix("> ") {
                                alertLines.append(String(lTrimmed.dropFirst(2)))
                                lineIndex += 1
                            } else if lTrimmed == ">" {
                                alertLines.append("")
                                lineIndex += 1
                            } else if lTrimmed.hasPrefix(">") {
                                alertLines.append(String(lTrimmed.dropFirst(1)))
                                lineIndex += 1
                            } else {
                                break
                            }
                        }
                        
                        let combinedText = alertLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        let resolved = resolveReferenceLinks(combinedText, references: linkReferences)
                        blocks.append(MarkdownBlock(type: .alertCallout(type: alertType, text: resolved), text: ""))
                        continue
                    }
                }
                
                // Normal Blockquote
                var quoteLines: [String] = []
                while lineIndex < lines.count {
                    let lTrimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                    if lTrimmed.hasPrefix("> ") {
                        quoteLines.append(String(lTrimmed.dropFirst(2)))
                        lineIndex += 1
                    } else if lTrimmed == ">" {
                        quoteLines.append("")
                        lineIndex += 1
                    } else if lTrimmed.hasPrefix(">") {
                        quoteLines.append(String(lTrimmed.dropFirst(1)))
                        lineIndex += 1
                    } else {
                        break
                    }
                }
                
                let resolvedQuote = resolveReferenceLinks(quoteLines.joined(separator: "\n"), references: linkReferences)
                blocks.append(MarkdownBlock(type: .blockquote, text: resolvedQuote))
                continue
            }
            
            // Task List Items ([-*+] [ ] or [-*+] [xX])
            let taskPattern = "^[-*+]\\s+\\[([ xX])\\](?:\\s+(.*)|$)"
            if let regex = try? NSRegularExpression(pattern: taskPattern),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                let checkChar = (trimmed as NSString).substring(with: match.range(at: 1))
                let isChecked = checkChar.lowercased() == "x"
                var content = ""
                if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                    content = (trimmed as NSString).substring(with: match.range(at: 2))
                }
                let resolved = resolveReferenceLinks(content, references: linkReferences)
                blocks.append(MarkdownBlock(type: .taskList(isChecked: isChecked, indentLevel: indent), text: resolved))
                lineIndex += 1
                continue
            }
            
            // List items
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                let content = String(trimmed.dropFirst(2))
                let resolved = resolveReferenceLinks(content, references: linkReferences)
                blocks.append(MarkdownBlock(type: .list(isOrdered: false, indentLevel: indent, itemNumber: 1), text: resolved))
                lineIndex += 1
                continue
            }
            
            // Numbered list items (e.g. 1. or 1) )
            let pattern = "^[0-9]+[.)]\\s+"
            if let range = trimmed.range(of: pattern, options: .regularExpression) {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                let prefixString = String(trimmed[range])
                let numberString = prefixString.prefix(while: { $0.isNumber })
                let itemNumber = Int(numberString) ?? 1
                let rawContent = trimmed.replacingCharacters(in: range, with: "")
                let resolved = resolveReferenceLinks(rawContent, references: linkReferences)
                blocks.append(MarkdownBlock(type: .list(isOrdered: true, indentLevel: indent, itemNumber: itemNumber), text: resolved))
                lineIndex += 1
                continue
            }
            
            if trimmed.isEmpty {
                flushParagraph()
            } else {
                currentParagraphLines.append(line)
            }
            
            lineIndex += 1
        }
        
        flushParagraph()
        
        if inCodeBlock && !currentCodeLines.isEmpty {
            let code = currentCodeLines.joined(separator: "\n")
            blocks.append(MarkdownBlock(type: .codeBlock(code: code, language: currentCodeLanguage), text: ""))
        }
        
        return blocks
    }
    
    /// Automatically detects the Markdown flavor based on syntax signatures.
    static func detectFlavor(_ text: String) -> MarkdownFlavor {
        let nsText = text as NSString
        if nsText.length == 0 { return .github }
        
        var slackScore = 0
        var gfmScore = 0
        var originalScore = 0
        var mdLinkCount = 0
        
        // Slack heuristics: <url|text>, ~strikethrough~, *bold*
        if let linkPipe = try? NSRegularExpression(pattern: "<https?://[^>|\\n]+\\|[^>|\\n]+>", options: []) {
            slackScore += linkPipe.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) * 4
        }
        if let slackAngleLink = try? NSRegularExpression(pattern: "<https?://[^>|\\n]+>", options: []) {
            slackScore += slackAngleLink.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) * 2
        }
        if let slackStrike = try? NSRegularExpression(pattern: "(?<!~)~([^~\\n]+?)~(?!~)", options: []) {
            slackScore += slackStrike.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) * 3
        }
        if let slackBold = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", options: []) {
            slackScore += slackBold.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) * 2
        }
        
        // GFM heuristics: ~~strikethrough~~, task lists, tables
        if let gfmStrike = try? NSRegularExpression(pattern: "~~([^~\\n]+?)~~", options: []) {
            gfmScore += gfmStrike.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) * 4
        }
        if let taskList = try? NSRegularExpression(pattern: "^\\s*[-*]\\s+\\[[ xX]\\]\\s+", options: [.anchorsMatchLines]) {
            gfmScore += taskList.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) * 4
        }
        if let table = try? NSRegularExpression(pattern: "^\\|.*\\|\\s*$", options: [.anchorsMatchLines]) {
            gfmScore += table.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) * 2
        }
        
        // Standard Markdown links [text](url)
        if let mdLink = try? NSRegularExpression(pattern: "\\[[^\\]\\n]+\\]\\([^\\)\\n]+\\)", options: []) {
            mdLinkCount = mdLink.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        }
        
        // Original Markdown heuristic: 4-space indented code block without fenced ``` code block
        let hasFencedCode = text.contains("```")
        let hasFourSpaceIndent = (try? NSRegularExpression(pattern: "^ {4}\\S", options: [.anchorsMatchLines]))?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) != nil
        if hasFourSpaceIndent && !hasFencedCode {
            originalScore += 4
        }
        
        if slackScore > gfmScore && slackScore > originalScore {
            return .slack
        } else if originalScore > gfmScore && originalScore > slackScore {
            return .original
        } else if gfmScore > 0 {
            return .github
        } else if mdLinkCount > 0 || hasFencedCode {
            return .commonMark
        }
        
        return .github
    }
    
    /// Converts text in-place from source flavor to target flavor.
    static func convert(_ text: String, from source: MarkdownFlavor, to target: MarkdownFlavor) -> String {
        if source == target { return text }
        
        let (maskedText, placeholders) = maskCodeBlocks(text)
        var result = maskedText
        
        let gfmText = convertToGFM(result, from: source)
        result = convertFromGFM(gfmText, to: target)
        
        return unmaskCodeBlocks(result, placeholders: placeholders)
    }
    
    // Helper to mask code blocks so transformations don't modify source code contents
    private static func maskCodeBlocks(_ text: String) -> (maskedText: String, placeholders: [String: String]) {
        var placeholders: [String: String] = [:]
        var result = text
        var counter = 0
        
        // 1. Mask fenced code blocks ```...```
        if let fencedRegex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: []) {
            let nsString = result as NSString
            let matches = fencedRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length)).reversed()
            for match in matches {
                let blockText = nsString.substring(with: match.range)
                let key = "___SWASH_CODE_BLOCK_\(counter)___"
                placeholders[key] = blockText
                result = (result as NSString).replacingCharacters(in: match.range, with: key)
                counter += 1
            }
        }
        
        // 2. Mask inline code `...`
        if let inlineRegex = try? NSRegularExpression(pattern: "`[^`\\n]+`", options: []) {
            let nsString = result as NSString
            let matches = inlineRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length)).reversed()
            for match in matches {
                let codeText = nsString.substring(with: match.range)
                let key = "___SWASH_INLINE_CODE_\(counter)___"
                placeholders[key] = codeText
                result = (result as NSString).replacingCharacters(in: match.range, with: key)
                counter += 1
            }
        }
        
        return (result, placeholders)
    }
    
    private static func unmaskCodeBlocks(_ text: String, placeholders: [String: String]) -> String {
        var result = text
        for (key, val) in placeholders {
            result = result.replacingOccurrences(of: key, with: val)
        }
        return result
    }
    
    /// Converts Slack mrkdwn string to standard GitHub Flavored Markdown
    static func convertSlackToGithub(_ text: String) -> String {
        var result = text
        
        // 1. Links: <url|text> -> [text](url)
        if let linkWithPipeRegex = try? NSRegularExpression(pattern: "<([^>|\\n]+)\\|([^>|\\n]+)>", options: []) {
            result = linkWithPipeRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "[$2]($1)"
            )
        }
        
        // 2. Links: <url> -> <url>
        
        // 3. Bold: *text* -> **text** (only single asterisk not adjacent to another asterisk)
        if let boldRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", options: []) {
            result = boldRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "**$1**"
            )
        }
        
        // 4. Strikethrough: ~text~ -> ~~text~~
        if let strikeRegex = try? NSRegularExpression(pattern: "(?<!~)~([^~\\n]+?)~(?!~)", options: []) {
            result = strikeRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "~~$1~~"
            )
        }
        
        return result
    }
    
    private static func convertToGFM(_ text: String, from flavor: MarkdownFlavor) -> String {
        switch flavor {
        case .github, .commonMark:
            return text
        case .slack:
            return convertSlackToGithub(text)
        case .original:
            // Convert 4-space indented code blocks to GFM fenced code blocks
            return convertIndentedToFencedCode(text)
        }
    }
    
    private static func convertFromGFM(_ text: String, to flavor: MarkdownFlavor) -> String {
        switch flavor {
        case .github, .commonMark:
            return text
        case .slack:
            return convertGithubToSlack(text)
        case .original:
            // Convert fenced code blocks to 4-space indented code blocks & strip GFM-only strikethroughs
            var res = convertFencedToIndentedCode(text)
            if let strikeRegex = try? NSRegularExpression(pattern: "~~([^~\\n]+?)~~", options: []) {
                res = strikeRegex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: res.utf16.count), withTemplate: "$1")
            }
            return res
        }
    }
    
    private static func convertGithubToSlack(_ text: String) -> String {
        var result = text
        
        // 1. Links: [text](url) -> <url|text>
        if let linkRegex = try? NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\((https?://[^\\)\\n]+|[^\\)\\n]+)\\)", options: []) {
            let nsText = result as NSString
            let matches = linkRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                if match.numberOfRanges >= 3 {
                    let linkText = nsText.substring(with: match.range(at: 1))
                    let url = nsText.substring(with: match.range(at: 2))
                    let replacement = linkText == url ? "<\(url)>" : "<\(url)|\(linkText)>"
                    result = (result as NSString).replacingCharacters(in: match.range(at: 0), with: replacement)
                }
            }
        }
        
        // 2. Convert GFM single asterisk italic *text* -> _text_ BEFORE converting double asterisk bold!
        if let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", options: []) {
            result = italicRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "_$1_"
            )
        }
        
        // 3. Convert GFM double asterisk bold **text** -> *text* (Slack bold)
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*([^\\*\\n]+?)\\*\\*", options: []) {
            result = boldRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "*$1*"
            )
        }
        
        // 4. Convert GFM strikethrough ~~text~~ -> ~text~ (Slack strikethrough)
        if let strikeRegex = try? NSRegularExpression(pattern: "~~([^~\\n]+?)~~", options: []) {
            result = strikeRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "~$1~"
            )
        }
        
        return result
    }
    
    private static func convertIndentedToFencedCode(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var resultLines: [String] = []
        var currentIndentedCodeLines: [String] = []
        
        for line in lines {
            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                let codeLine = String(line.dropFirst(line.hasPrefix("    ") ? 4 : 1))
                currentIndentedCodeLines.append(codeLine)
            } else {
                if !currentIndentedCodeLines.isEmpty {
                    resultLines.append("```")
                    resultLines.append(contentsOf: currentIndentedCodeLines)
                    resultLines.append("```")
                    currentIndentedCodeLines.removeAll()
                }
                resultLines.append(line)
            }
        }
        if !currentIndentedCodeLines.isEmpty {
            resultLines.append("```")
            resultLines.append(contentsOf: currentIndentedCodeLines)
            resultLines.append("```")
        }
        return resultLines.joined(separator: "\n")
    }
    
    private static func convertFencedToIndentedCode(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var resultLines: [String] = []
        var inCode = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode = !inCode
                continue
            }
            if inCode {
                resultLines.append("    \(line)")
            } else {
                resultLines.append(line)
            }
        }
        return resultLines.joined(separator: "\n")
    }
    
    /// Converts bare URLs, www. domains, and email addresses outside code blocks/inline code/existing links to autolinks `<url>`
    static func autolinkBareURLs(_ text: String) -> String {
        let nsText = text as NSString
        let length = nsText.length
        if length == 0 { return text }
        
        // Find protected ranges (inline code, explicit markdown links `[...]` or `<...>`, and code blocks)
        var protectedRanges: [NSRange] = []
        
        // 1. Inline code: `...`
        if let inlineCodeRegex = try? NSRegularExpression(pattern: "`[^`\\n]+`", options: []) {
            let matches = inlineCodeRegex.matches(in: text, options: [], range: NSRange(location: 0, length: length))
            protectedRanges.append(contentsOf: matches.map { $0.range })
        }
        
        // 2. Existing markdown links: [text](url)
        if let markdownLinkRegex = try? NSRegularExpression(pattern: "\\[[^\\]\\n]*\\]\\([^\\)\\n]*\\)", options: []) {
            let matches = markdownLinkRegex.matches(in: text, options: [], range: NSRange(location: 0, length: length))
            protectedRanges.append(contentsOf: matches.map { $0.range })
        }
        
        // 3. Existing autolinks or slack links: <...>
        if let angleLinkRegex = try? NSRegularExpression(pattern: "<[^>\\n]+>", options: []) {
            let matches = angleLinkRegex.matches(in: text, options: [], range: NSRange(location: 0, length: length))
            protectedRanges.append(contentsOf: matches.map { $0.range })
        }
        
        // Match http(s)://, www., and email pattern
        let urlPattern = "(?:https?://|www\\.)[^\\s<>\"'\\)]+|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
        guard let bareUrlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) else { return text }
        let matches = bareUrlRegex.matches(in: text, options: [], range: NSRange(location: 0, length: length))
        
        if matches.isEmpty { return text }
        
        var result = ""
        var lastIndex = 0
        
        for m in matches {
            var matchRange = m.range(at: 0)
            
            // Trim trailing punctuation if any (. , ; : ! ? ) ])
            var str = nsText.substring(with: matchRange)
            while let last = str.last, [".", ",", ";", ":", "!", "?", ")", "]", "\"", "'"].contains(last) {
                str.removeLast()
                matchRange.length -= 1
            }
            if matchRange.length == 0 { continue }
            
            // Check if matchRange intersects any protected range
            let isProtected = protectedRanges.contains { NSIntersectionRange($0, matchRange).length > 0 }
            if isProtected { continue }
            
            // Append preceding un-modified text
            if matchRange.location > lastIndex {
                result += nsText.substring(with: NSRange(location: lastIndex, length: matchRange.location - lastIndex))
            }
            
            // Format link target
            let linkTarget: String
            if str.hasPrefix("www.") {
                linkTarget = "https://\(str)"
            } else if str.contains("@") && !str.hasPrefix("http") {
                linkTarget = "mailto:\(str)"
            } else {
                linkTarget = str
            }
            
            // Wrap in angle brackets <...> for standard autolink
            result += "<\(linkTarget)>"
            lastIndex = matchRange.location + matchRange.length
        }
        
        if lastIndex < length {
            result += nsText.substring(with: NSRange(location: lastIndex, length: length - lastIndex))
        }
        
        return result
    }
    
    /// Pre-processes inline footnote references [^label] into markdown links [[label]](#fn-label)
    static func formatFootnoteReferences(_ text: String) -> String {
        let pattern = "\\[\\^([^\\]]+)\\](?!:)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "[[$1]](#fn-$1)")
    }
}

