//
//  MarkdownParser.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import Foundation

enum BlockType: Equatable {
    case heading(level: Int)
    case blockquote
    case codeBlock(code: String, language: String?)
    case list(isOrdered: Bool, indentLevel: Int)
    case taskList(isChecked: Bool, indentLevel: Int)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
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
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        
        var inCodeBlock = false
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
            
            if inCodeBlock {
                if line.hasPrefix("```") {
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
            
            if line.hasPrefix("```") {
                flushParagraph()
                inCodeBlock = true
                let lang = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                currentCodeLanguage = lang.isEmpty ? nil : lang
                lineIndex += 1
                continue
            }
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Table Detection
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && lineIndex + 1 < lines.count {
                let nextTrimmed = lines[lineIndex + 1].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.hasPrefix("|") && nextTrimmed.contains("-") {
                    flushParagraph()
                    
                    let headers = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    var rows: [[String]] = []
                    
                    // Skip header and separator line
                    lineIndex += 2
                    
                    while lineIndex < lines.count {
                        let rowLine = lines[lineIndex].trimmingCharacters(in: .whitespaces)
                        if rowLine.hasPrefix("|") && rowLine.hasSuffix("|") {
                            let cells = rowLine.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                            rows.append(cells)
                            lineIndex += 1
                        } else {
                            break
                        }
                    }
                    
                    blocks.append(MarkdownBlock(type: .table(headers: headers, rows: rows), text: ""))
                    continue
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
            
            // Blockquotes
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .blockquote, text: String(trimmed.dropFirst(2))))
                lineIndex += 1
                continue
            } else if trimmed == ">" {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .blockquote, text: ""))
                lineIndex += 1
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
                blocks.append(MarkdownBlock(type: .list(isOrdered: false, indentLevel: indent), text: String(trimmed.dropFirst(2))))
                lineIndex += 1
                continue
            }
            
            // Numbered list items (e.g. 1. )
            let pattern = "^[0-9]+\\.\\s+"
            if let range = trimmed.range(of: pattern, options: .regularExpression) {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                let content = trimmed.replacingCharacters(in: range, with: "")
                blocks.append(MarkdownBlock(type: .list(isOrdered: true, indentLevel: indent), text: content))
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
        
        // 2. Links: <url> -> [url](url)
        if let linkRegex = try? NSRegularExpression(pattern: "<([^>|\\n]+)>", options: []) {
            result = linkRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "[$1]($1)"
            )
        }
        
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
}
