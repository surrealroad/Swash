//
//  MarkdownParser.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MarkdownTableData: Equatable {
    var headers: [String]
    var alignments: [TableAlignment]
    var rows: [[String]]
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
    
    static func resolveImage(urlString: String, baseURL: URL? = nil, windowURL: URL? = nil) -> PlatformImage? {
        let (cleanedURL, _) = cleanImageURLAndTitle(urlString)
        guard !cleanedURL.isEmpty else { return nil }
        
        // 1. Direct path check
        if cleanedURL.hasPrefix("file://") {
            if let fileURL = URL(string: cleanedURL), fileURL.isFileURL {
                if let direct = PlatformImage(contentsOf: fileURL) {
                    return direct
                }
            }
            let directPath = cleanedURL.replacingOccurrences(of: "file://", with: "")
            if let direct = PlatformImage(contentsOfFile: directPath) {
                return direct
            }
        } else if cleanedURL.hasPrefix("/") {
            if let direct = PlatformImage(contentsOfFile: cleanedURL) {
                return direct
            }
            if let decoded = cleanedURL.removingPercentEncoding,
               let direct = PlatformImage(contentsOfFile: decoded) {
                return direct
            }
        }
        
        // 2. Identify candidate document base URL
        var documentURL: URL? = baseURL
        if documentURL == nil {
            documentURL = windowURL
        }
        #if os(macOS)
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
        #endif
        
        // 3. Resolve strictly relative to document folder
        if let docURL = documentURL {
            let folderURL = docURL.hasDirectoryPath ? docURL : docURL.deletingLastPathComponent()
            _ = FolderAccessManager.shared.ensureAccess(for: folderURL)
            let targetURL = folderURL.appendingPathComponent(cleanedURL)
            if let img = PlatformImage(contentsOfFile: targetURL.path) ?? PlatformImage(contentsOf: targetURL) {
                return img
            }
            if let decoded = cleanedURL.removingPercentEncoding {
                let decodedTarget = folderURL.appendingPathComponent(decoded)
                if let img = PlatformImage(contentsOfFile: decodedTarget.path) ?? PlatformImage(contentsOf: decodedTarget) {
                    return img
                }
            }
        }
        
        // 4. Fallback relative to current working directory
        let currentDir = FileManager.default.currentDirectoryPath
        let cwdURL = URL(fileURLWithPath: currentDir).appendingPathComponent(cleanedURL)
        if let img = PlatformImage(contentsOfFile: cwdURL.path) {
            return img
        }
        if let decoded = cleanedURL.removingPercentEncoding {
            let decodedCwd = URL(fileURLWithPath: currentDir).appendingPathComponent(decoded)
            if let img = PlatformImage(contentsOfFile: decodedCwd.path) {
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
    
    #if os(macOS)
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
    #else
    static func scaleImageForEditor(_ image: UIImage, maxWidth: CGFloat = 550) -> UIImage {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0, originalSize.width > maxWidth else { return image }
        let targetSize = CGSize(width: maxWidth, height: ceil(originalSize.height * maxWidth / originalSize.width))
        return UIGraphicsImageRenderer(size: targetSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    static func placeholderImage(alt: String) -> UIImage {
        let displayText = alt.isEmpty ? "Image" : alt
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let textSize = (displayText as NSString).size(withAttributes: attrs)
        let size = CGSize(width: min(max(textSize.width + 44, 80), 550), height: 28)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.secondaryLabel.withAlphaComponent(0.12).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            UIImage(systemName: "photo", withConfiguration: configuration)?
                .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 8, y: (size.height - 12) / 2, width: 14, height: 12))
            (displayText as NSString).draw(at: CGPoint(x: 28, y: (size.height - textSize.height) / 2), withAttributes: attrs)
        }
    }
    #endif
    
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
    
    // MARK: - Code Range Detection

    /// A fenced code block located in raw markdown (UTF-16 offsets).
    struct FencedCodeBlock {
        let fullRange: NSRange      // Opening fence line through closing fence line (no trailing newline)
        let contentRange: NSRange   // Lines between the fences (no trailing newline)
        let language: String?
        let isClosed: Bool
    }

    /// Code regions of a document, computed in a single O(n) pass.
    struct CodeRanges {
        var fencedBlocks: [FencedCodeBlock] = []
        var indentedBlocks: [NSRange] = []
        /// Code spans including their backtick delimiters, with the inner content range.
        var spans: [(full: NSRange, content: NSRange, fenceLength: Int)] = []

        /// Sorted block-level code ranges (fenced + indented) and span ranges, finalised once per scan.
        private(set) var blockRanges: [NSRange] = []
        private(set) var spanRanges: [NSRange] = []

        mutating func finalize() {
            blockRanges = (fencedBlocks.map { $0.fullRange } + indentedBlocks).sorted { $0.location < $1.location }
            spanRanges = spans.map { $0.full }
        }

        func blockIntersects(_ range: NSRange) -> Bool {
            CodeRanges.anyIntersects(blockRanges, range)
        }

        func spanContains(_ location: Int) -> Bool {
            CodeRanges.anyContains(spanRanges, location)
        }

        /// True when a match should be excluded from markdown interpretation: it overlaps a code block,
        /// or one of its delimiters (first/last character) sits inside a code span.
        func excludes(_ range: NSRange) -> Bool {
            if blockIntersects(range) { return true }
            guard range.length > 0 else { return spanContains(range.location) }
            return spanContains(range.location) || spanContains(range.location + range.length - 1)
        }

        /// Binary search over sorted, non-overlapping ranges.
        static func anyContains(_ sorted: [NSRange], _ location: Int) -> Bool {
            var lo = 0, hi = sorted.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                let r = sorted[mid]
                if location < r.location { hi = mid - 1 }
                else if location >= r.location + r.length { lo = mid + 1 }
                else { return true }
            }
            return false
        }

        static func anyIntersects(_ sorted: [NSRange], _ range: NSRange) -> Bool {
            // First range whose end is after range.location
            var lo = 0, hi = sorted.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if sorted[mid].location + sorted[mid].length <= range.location { lo = mid + 1 } else { hi = mid }
            }
            guard lo < sorted.count else { return false }
            let candidate = sorted[lo]
            if range.length == 0 {
                return range.location >= candidate.location && range.location < candidate.location + candidate.length
            }
            return candidate.location < range.location + range.length
        }
    }

    private static let listMarkerRegex = try? NSRegularExpression(pattern: "^\\s*(?:[-*+]|[0-9]+[.)])\\s+")

    static func isListItemLine(_ line: String) -> Bool {
        guard let regex = listMarkerRegex else { return false }
        return regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// Locates fenced code blocks, indented code blocks and code spans in a single pass.
    static func codeRanges(in text: String) -> CodeRanges {
        var result = CodeRanges()
        let nsText = text as NSString
        let lines = text.components(separatedBy: "\n")

        var offset = 0
        var openFence: CodeFenceInfo? = nil
        var openStart = 0
        var openContentStart = 0
        var previousLineBlank = true
        var inListContext = false
        var indentedStart: Int? = nil
        var indentedEnd = 0
        var proseRanges: [NSRange] = []   // Regions where code spans may occur
        var proseStart: Int? = nil

        func closeIndented() {
            if let start = indentedStart {
                result.indentedBlocks.append(NSRange(location: start, length: indentedEnd - start))
                indentedStart = nil
            }
        }
        func closeProse(at end: Int) {
            if let start = proseStart, end > start {
                proseRanges.append(NSRange(location: start, length: end - start))
            }
            proseStart = nil
        }

        for line in lines {
            let length = (line as NSString).length
            let lineEnd = offset + length

            if let fence = openFence {
                if isClosingCodeFence(line, matching: fence) {
                    let contentLength = max(0, offset - 1 - openContentStart)
                    result.fencedBlocks.append(FencedCodeBlock(
                        fullRange: NSRange(location: openStart, length: lineEnd - openStart),
                        contentRange: NSRange(location: openContentStart, length: offset > openContentStart ? contentLength : 0),
                        language: fence.language,
                        isClosed: true))
                    openFence = nil
                    previousLineBlank = false
                }
                offset = lineEnd + 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isBlank = trimmed.isEmpty
            let isIndented = line.hasPrefix("    ") || line.hasPrefix("\t")

            if indentedStart != nil {
                if isIndented || isBlank {
                    if !isBlank { indentedEnd = lineEnd }
                    offset = lineEnd + 1
                    previousLineBlank = isBlank
                    continue
                }
                closeIndented()
            }

            if let fence = parseOpeningCodeFence(line) {
                closeProse(at: offset)
                openFence = fence
                openStart = offset
                openContentStart = lineEnd + 1
                inListContext = false
            } else if isIndented && !isBlank && previousLineBlank && !inListContext && !isListItemLine(line) {
                closeProse(at: offset)
                indentedStart = offset
                indentedEnd = lineEnd
            } else {
                if isBlank {
                    // Code spans cannot cross a blank line
                    closeProse(at: offset)
                } else {
                    if proseStart == nil { proseStart = offset }
                    if isListItemLine(line) {
                        inListContext = true
                    } else if !line.hasPrefix(" ") && !line.hasPrefix("\t") && previousLineBlank {
                        inListContext = false
                    }
                }
            }

            previousLineBlank = isBlank
            offset = lineEnd + 1
        }

        if let fence = openFence {
            let end = nsText.length
            result.fencedBlocks.append(FencedCodeBlock(
                fullRange: NSRange(location: openStart, length: end - openStart),
                contentRange: NSRange(location: min(openContentStart, end), length: max(0, end - openContentStart)),
                language: fence.language,
                isClosed: false))
        }
        closeIndented()
        closeProse(at: nsText.length)

        for prose in proseRanges {
            result.spans.append(contentsOf: codeSpans(in: nsText, range: prose))
        }
        result.finalize()
        return result
    }

    /// CommonMark code spans: a backtick run closed by the next run of exactly the same length.
    private static func codeSpans(in text: NSString, range: NSRange) -> [(full: NSRange, content: NSRange, fenceLength: Int)] {
        let backtick: unichar = 0x60
        let backslash: unichar = 0x5C
        let end = range.location + range.length
        var spans: [(full: NSRange, content: NSRange, fenceLength: Int)] = []
        var i = range.location

        func runLength(at index: Int) -> Int {
            var j = index
            while j < end && text.character(at: j) == backtick { j += 1 }
            return j - index
        }

        while i < end {
            let c = text.character(at: i)
            if c == backslash && i + 1 < end && text.character(at: i + 1) == backtick {
                i += 2
                continue
            }
            guard c == backtick else { i += 1; continue }
            let openLength = runLength(at: i)
            var j = i + openLength
            var closeStart: Int? = nil
            while j < end {
                if text.character(at: j) == backtick {
                    let closeLength = runLength(at: j)
                    if closeLength == openLength { closeStart = j; break }
                    j += closeLength
                } else {
                    j += 1
                }
            }
            guard let close = closeStart else {
                i += openLength
                continue
            }
            var contentStart = i + openLength
            var contentEnd = close
            // Strip one leading and trailing space when both are present and content is not all spaces
            if contentEnd - contentStart >= 2,
               text.character(at: contentStart) == 0x20, text.character(at: contentEnd - 1) == 0x20,
               text.substring(with: NSRange(location: contentStart, length: contentEnd - contentStart)).contains(where: { $0 != " " }) {
                contentStart += 1
                contentEnd -= 1
            }
            spans.append((full: NSRange(location: i, length: close + openLength - i),
                          content: NSRange(location: contentStart, length: contentEnd - contentStart),
                          fenceLength: openLength))
            i = close + openLength
        }
        return spans
    }

    /// Returns the fenced code block (``` or ~~~) containing the given raw-markdown range, if any.
    static func fencedCodeBlock(containing range: NSRange, in text: String) -> FencedCodeBlock? {
        codeRanges(in: text).fencedBlocks.first { block in
            range.location >= block.fullRange.location &&
            range.location + range.length <= block.fullRange.location + block.fullRange.length
        }
    }
}
