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
        
        for line in lines {
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
                continue
            }
            
            if line.hasPrefix("```") {
                flushParagraph()
                inCodeBlock = true
                let lang = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                currentCodeLanguage = lang.isEmpty ? nil : lang
                continue
            }
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Horizontal Rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .horizontalRule, text: ""))
                continue
            }
            
            // Headings
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 1), text: String(trimmed.dropFirst(2))))
                continue
            } else if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 2), text: String(trimmed.dropFirst(3))))
                continue
            } else if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 3), text: String(trimmed.dropFirst(4))))
                continue
            } else if trimmed.hasPrefix("#### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 4), text: String(trimmed.dropFirst(5))))
                continue
            } else if trimmed.hasPrefix("##### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 5), text: String(trimmed.dropFirst(6))))
                continue
            } else if trimmed.hasPrefix("###### ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .heading(level: 6), text: String(trimmed.dropFirst(7))))
                continue
            }
            
            // Blockquotes
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .blockquote, text: String(trimmed.dropFirst(2))))
                continue
            } else if trimmed == ">" {
                flushParagraph()
                blocks.append(MarkdownBlock(type: .blockquote, text: ""))
                continue
            }
            
            // List items
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " }).count / 2
                blocks.append(MarkdownBlock(type: .list(isOrdered: false, indentLevel: indent), text: String(trimmed.dropFirst(2))))
                continue
            }
            
            // Numbered list items (e.g. 1. )
            let pattern = "^[0-9]+\\.\\s+"
            if let range = trimmed.range(of: pattern, options: .regularExpression) {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " }).count / 2
                let content = trimmed.replacingCharacters(in: range, with: "")
                blocks.append(MarkdownBlock(type: .list(isOrdered: true, indentLevel: indent), text: content))
                continue
            }
            
            if trimmed.isEmpty {
                flushParagraph()
            } else {
                currentParagraphLines.append(line)
            }
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
        
        // 3. Bold: *text* -> **text**
        if let boldRegex = try? NSRegularExpression(pattern: "(?<=^|[\\s\\p{P}])\\*([^*\\n]+?)\\*(?=$|[\\s\\p{P}])", options: []) {
            result = boldRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "**$1**"
            )
        }
        
        // Note: _italic_ is standard markdown italic too, so we let standard AttributedString handle it.
        
        // 4. Strikethrough: ~text~ -> ~~text~~
        if let strikeRegex = try? NSRegularExpression(pattern: "(?<=^|[\\s\\p{P}])~([^~\\n]+?)~(?=$|[\\s\\p{P}])", options: []) {
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
