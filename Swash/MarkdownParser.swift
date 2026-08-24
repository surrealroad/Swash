//
//  MarkdownParser.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import Foundation

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
        
        for char in trimmed {
            if isEscaped {
                currentCell.append(char)
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "|" {
                cells.append(currentCell.trimmingCharacters(in: .whitespaces))
                currentCell = ""
            } else {
                currentCell.append(char)
            }
        }
        cells.append(currentCell.trimmingCharacters(in: .whitespaces))
        return cells
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
        
        var inCodeBlock = false
        var currentCodeFence = "```"
        var currentCodeLines: [String] = []
        var currentCodeLanguage: String? = nil
        
        var currentParagraphLines: [String] = []
        
        func flushParagraph() {
            if !currentParagraphLines.isEmpty {
                let paragraphText = currentParagraphLines.joined(separator: "\n")
                blocks.append(MarkdownBlock(type: .paragraph, text: paragraphText))
                currentParagraphLines.removeAll()
            }
        }
        
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if inCodeBlock {
                if trimmed.hasPrefix(currentCodeFence) {
                    inCodeBlock = false
                    let code = currentCodeLines.joined(separator: "\n")
                    blocks.append(MarkdownBlock(type: .codeBlock(code: code, language: currentCodeLanguage), text: ""))
                    currentCodeLines.removeAll()
                    currentCodeLanguage = nil
                } else {
                    currentCodeLines.append(line)
                }
                lineIndex += 1
                continue
            }
            
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                inCodeBlock = true
                currentCodeFence = trimmed.hasPrefix("~~~") ? "~~~" : "```"
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                currentCodeLanguage = lang.isEmpty ? nil : lang
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
                if trimmed.range(of: "^=+$", options: .regularExpression) != nil {
                    let headingText = currentParagraphLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    currentParagraphLines.removeAll()
                    blocks.append(MarkdownBlock(type: .heading(level: 1), text: headingText))
                    lineIndex += 1
                    continue
                } else if trimmed.range(of: "^-+$", options: .regularExpression) != nil {
                    let headingText = currentParagraphLines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    currentParagraphLines.removeAll()
                    blocks.append(MarkdownBlock(type: .heading(level: 2), text: headingText))
                    lineIndex += 1
                    continue
                }
            }
            
            // Footnote Definition [^label]: text
            let footnoteDefPattern = "^\\[\\^([^\\]]+)\\]:\\s*(.*)$"
            if let regex = try? NSRegularExpression(pattern: footnoteDefPattern),
               let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) {
                flushParagraph()
                let nsTrimmed = trimmed as NSString
                let label = nsTrimmed.substring(with: match.range(at: 1))
                let content = nsTrimmed.substring(with: match.range(at: 2))
                blocks.append(MarkdownBlock(type: .footnoteDefinition(label: label, text: content), text: ""))
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
                        
                        blocks.append(MarkdownBlock(type: .table(headers: headers, alignments: alignments, rows: rows), text: ""))
                        continue
                    }
                }
            }
            
            // Horizontal Rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .horizontalRule, text: ""))
                lineIndex += 1
                continue
            }
            
            // Headings
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 1), text: String(trimmed.dropFirst(2))))
                lineIndex += 1
                continue
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 2), text: String(trimmed.dropFirst(3))))
                lineIndex += 1
                continue
            } else if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 3), text: String(trimmed.dropFirst(4))))
                lineIndex += 1
                continue
            } else if trimmed.hasPrefix("#### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 4), text: String(trimmed.dropFirst(5))))
                lineIndex += 1
                continue
            } else if trimmed.hasPrefix("##### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 5), text: String(trimmed.dropFirst(6))))
                lineIndex += 1
                continue
            } else if trimmed.hasPrefix("###### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 6), text: String(trimmed.dropFirst(7))))
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
                        blocks.append(MarkdownBlock(type: .alertCallout(type: alertType, text: combinedText), text: ""))
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
                
                blocks.append(MarkdownBlock(type: .blockquote, text: quoteLines.joined(separator: "\n")))
                continue
            }
            
            // Task List Items (- [ ] or - [x])
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("* [ ] ") {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                blocks.append(MarkdownBlock(type: .taskList(isChecked: false, indentLevel: indent), text: String(trimmed.dropFirst(6))))
                lineIndex += 1
                continue
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") || trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                blocks.append(MarkdownBlock(type: .taskList(isChecked: true, indentLevel: indent), text: String(trimmed.dropFirst(6))))
                lineIndex += 1
                continue
            }
            
            // List items
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                blocks.append(MarkdownBlock(type: .list(isOrdered: false, indentLevel: indent, itemNumber: 1), text: String(trimmed.dropFirst(2))))
                lineIndex += 1
                continue
            }
            
            // Numbered list items (e.g. 1. )
            let pattern = "^[0-9]+\\.\\s+"
            if let range = trimmed.range(of: pattern, options: .regularExpression) {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                let prefixString = String(trimmed[range])
                let numberString = prefixString.prefix(while: { $0.isNumber })
                let itemNumber = Int(numberString) ?? 1
                let content = trimmed.replacingCharacters(in: range, with: "")
                blocks.append(MarkdownBlock(type: .list(isOrdered: true, indentLevel: indent, itemNumber: itemNumber), text: content))
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

