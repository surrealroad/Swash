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
        if let linkWithPipeRegex = try? NSRegularExpression(pattern: "<([^>|\\n]+)\\|([^>|\\n]+)>", options: []) {
            result = linkWithPipeRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "[$2]($1)"
            )
        }
        if let linkRegex = try? NSRegularExpression(pattern: "<([^>|\\n]+)>", options: []) {
            result = linkRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "[$1]($1)"
            )
        }
        if let boldRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", options: []) {
            result = boldRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "**$1**"
            )
        }
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
        
        // 2. Bold: **text** -> *text*
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*([^\\*\\n]+?)\\*\\*", options: []) {
            result = boldRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "*$1*"
            )
        }
        
        // 3. Strikethrough: ~~text~~ -> ~text~
        if let strikeRegex = try? NSRegularExpression(pattern: "~~([^~\\n]+?)~~", options: []) {
            result = strikeRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "~$1~"
            )
        }
        
        // 4. Single asterisk italic *text* -> _text_ (because * in Slack is bold)
        if let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", options: []) {
            result = italicRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "_$1_"
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
    
    /// Converts bare URLs outside code blocks/inline code/existing links to autolinks `<url>`
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
        
        // Find bare URLs
        guard let bareUrlRegex = try? NSRegularExpression(pattern: "https?://[^\\s<>\"'\\)]+", options: []) else { return text }
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
            
            // Wrap bare URL in angle brackets <...> for standard autolink
            result += "<\(str)>"
            lastIndex = matchRange.location + matchRange.length
        }
        
        if lastIndex < length {
            result += nsText.substring(with: NSRange(location: lastIndex, length: length - lastIndex))
        }
        
        return result
    }
}

