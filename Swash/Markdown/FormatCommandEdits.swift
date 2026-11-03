//
//  FormatCommandEdits.swift
//  Swash
//
//  Turns a FormatCommand into a Markdown edit with the AST formatting engine. The Format menu
//  and keyboard shortcuts use it (through ContentView), and so does the shared conformance
//  corpus (`scripts/run_conformance_tests.sh`). Ranges are raw-Markdown UTF-16 offsets.
//

import Foundation

enum FormatCommandEdits {
    /// The edit for `command`, or nil when it does not apply (or a manifest `enabledWhen`
    /// condition fails). `.link` needs a URL, so callers use `link(_:text:selection:)`; table,
    /// callout, footnote and table-of-contents edits live in the macOS editor.
    static func edit(for command: FormatCommand, text: String, selection: NSRange) -> MarkdownEdit? {
        edit(for: command, formatting: MarkdownFormatting(text: text), selection: selection)
    }

    /// The same, reusing a parse of the text (the editor caches one).
    static func edit(for command: FormatCommand, formatting: MarkdownFormatting, selection: NSRange) -> MarkdownEdit? {
        let text = formatting.text
        guard formatting.isEnabled(command, selection: selection) else { return nil }
        switch command {
        case .bold: return formatting.toggle(.strong, selection: selection)
        case .italic: return formatting.toggle(.emphasis, selection: selection)
        case .strikethrough: return formatting.toggle(.strikethrough, selection: selection)
        case .code:
            // In a code block, the code toggle removes the fences; across lines it makes a block
            if formatting.codeBlock(containing: selection) != nil || formatting.segments(in: selection).count > 1 {
                return toggleCodeBlock(text: text, selection: selection, formatting: formatting)
            }
            return formatting.toggle(.code, selection: selection)
        case .heading(let level): return formatting.toggleBlock(.heading(level), selection: selection)
        case .paragraph: return formatting.toggleBlock(.paragraph, selection: selection)
        case .bulletList: return formatting.toggleBlock(.bulletList, selection: selection)
        case .numberedList: return formatting.toggleBlock(.numberedList, selection: selection)
        case .taskList: return formatting.toggleBlock(.taskList, selection: selection)
        case .quote: return formatting.toggleBlock(.quote, selection: selection)
        case .codeBlock: return toggleCodeBlock(text: text, selection: selection, formatting: formatting)
        case .link, .table, .callout, .footnote, .tableOfContents: return nil
        }
    }

    /// Sets the link URL on the selection, or removes the link when `url` is nil or empty.
    static func link(_ url: String?, text: String, selection: NSRange) -> MarkdownEdit? {
        let formatting = MarkdownFormatting(text: text)
        guard formatting.isEnabled(.link, selection: selection) else { return nil }
        guard let url = url, !url.isEmpty else { return formatting.removeLink(selection: selection) }
        return formatting.setLink(url, selection: selection)
    }

    /// Makes the selection a fenced code block with `language` (nil for no info string). Inside
    /// a fenced block, only the info string changes.
    static func codeBlock(language: String?, text: String, selection: NSRange) -> MarkdownEdit? {
        let formatting = MarkdownFormatting(text: text)
        guard formatting.isEnabled(.codeBlock, selection: selection) else { return nil }
        if let block = formatting.codeBlock(containing: selection), case .codeBlock(true, _) = block.kind {
            guard let edit = MarkdownEditingCommands.setCodeLanguage(language, text: text, location: selection.location) else { return nil }
            // setCodeLanguage reports a caret; keep a range selection's length
            return MarkdownEdit(text: edit.text, selection: NSRange(location: edit.selection.location, length: selection.length))
        }
        return wrapInCodeBlock(text: text, selection: selection, language: language)
    }

    /// Removes the fences of the code block around the selection, or wraps the selected lines in one.
    private static func toggleCodeBlock(text: String, selection: NSRange, formatting: MarkdownFormatting) -> MarkdownEdit? {
        let ns = text as NSString
        guard let block = formatting.codeBlock(containing: selection) else {
            return wrapInCodeBlock(text: text, selection: selection, language: nil)
        }
        let blockText = ns.substring(with: block.range)
        var lines = blockText.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard lines.count >= 1,
              let first = lines.first?.trimmingCharacters(in: .whitespaces),
              first.hasPrefix("```") || first.hasPrefix("~~~") else { return nil }
        let last = lines.last!.trimmingCharacters(in: .whitespaces)
        let hasClosingFence = lines.count > 1 && (last.hasPrefix("```") || last.hasPrefix("~~~"))
        let bodyLines = lines.dropFirst().dropLast(hasClosingFence ? 1 : 0)
        let body = bodyLines.joined(separator: "\n")
        let trailing = blockText.hasSuffix("\n") ? "\n" : ""
        let newText = ns.replacingCharacters(in: block.range, with: body + trailing)
        // Keep the selection where it was in the body, clamped to the body
        let bodyStart = block.range.location + (lines[0] as NSString).length + 1
        let bodyLength = (body as NSString).length
        func map(_ position: Int) -> Int {
            block.range.location + min(max(position - bodyStart, 0), bodyLength)
        }
        let start = map(selection.location)
        let end = map(NSMaxRange(selection))
        return MarkdownEdit(text: newText, selection: NSRange(location: start, length: end - start))
    }

    /// Wraps the lines the selection touches in a fenced code block, keeping the selection on the same text.
    private static func wrapInCodeBlock(text: String, selection: NSRange, language: String?) -> MarkdownEdit? {
        let ns = text as NSString
        guard selection.location != NSNotFound, NSMaxRange(selection) <= ns.length else { return nil }
        let lineRange = ns.lineRange(for: selection)
        var body = ns.substring(with: lineRange)
        let endsWithNewline = body.hasSuffix("\n")
        if endsWithNewline { body.removeLast() }
        let opening = "```" + (language ?? "") + "\n"
        let replacement = opening + body + "\n```" + (endsWithNewline ? "\n" : "")
        let newText = ns.replacingCharacters(in: lineRange, with: replacement)
        let shift = (opening as NSString).length
        return MarkdownEdit(text: newText, selection: NSRange(location: selection.location + shift, length: selection.length))
    }
}
