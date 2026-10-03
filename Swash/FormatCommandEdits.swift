//
//  FormatCommandEdits.swift
//  Swash
//
//  Turns a FormatCommand into a Markdown edit with the AST formatting engine. The iOS editor
//  uses it for the keyboard bar, the edit menu and the iPadOS Format menu. (The macOS
//  ContentView keeps its own handler, which also drives the bubble menu.)
//

import Foundation

enum FormatCommandEdits {
    /// The edit for `command`, or nil when it does not apply. `.link` needs a URL, so callers
    /// use `link(_:text:selection:)` instead.
    static func edit(for command: FormatCommand, text: String, selection: NSRange) -> MarkdownEdit? {
        let formatting = MarkdownFormatting(text: text)
        switch command {
        case .bold: return formatting.toggle(.strong, selection: selection)
        case .italic: return formatting.toggle(.emphasis, selection: selection)
        case .strikethrough: return formatting.toggle(.strikethrough, selection: selection)
        case .code:
            if formatting.segments(in: selection).count > 1 {
                return codeBlock(text: text, selection: selection, formatting: formatting)
            }
            return formatting.toggle(.code, selection: selection)
        case .heading(let level): return formatting.toggleBlock(.heading(level), selection: selection)
        case .paragraph: return formatting.toggleBlock(.paragraph, selection: selection)
        case .bulletList: return formatting.toggleBlock(.bulletList, selection: selection)
        case .numberedList: return formatting.toggleBlock(.numberedList, selection: selection)
        case .taskList: return formatting.toggleBlock(.taskList, selection: selection)
        case .quote: return formatting.toggleBlock(.quote, selection: selection)
        case .codeBlock: return codeBlock(text: text, selection: selection, formatting: formatting)
        case .link: return nil
        }
    }

    /// The link under the selection, as (URL, link node range), for pre-filling a link prompt.
    static func activeLink(text: String, selection: NSRange) -> String? {
        let formatting = MarkdownFormatting(text: text)
        guard let node = formatting.link(at: selection), case .link(let destination, _, _) = node.kind else { return nil }
        return destination
    }

    /// Sets the link URL on the selection, or removes the link when `url` is nil.
    static func link(_ url: String?, text: String, selection: NSRange) -> MarkdownEdit? {
        let formatting = MarkdownFormatting(text: text)
        guard let url = url else { return formatting.removeLink(selection: selection) }
        return formatting.setLink(url, selection: selection)
    }

    /// Wraps the selected lines in a fenced code block, or removes the fences of the block
    /// around the selection.
    private static func codeBlock(text: String, selection: NSRange, formatting: MarkdownFormatting) -> MarkdownEdit? {
        let ns = text as NSString
        if let block = formatting.codeBlock(containing: selection) {
            let blockText = ns.substring(with: block.range)
            var lines = blockText.components(separatedBy: "\n")
            if lines.last?.isEmpty == true { lines.removeLast() }
            guard lines.count >= 2,
                  let first = lines.first?.trimmingCharacters(in: .whitespaces),
                  first.hasPrefix("```") || first.hasPrefix("~~~") else { return nil }
            let last = lines.last!.trimmingCharacters(in: .whitespaces)
            let hasClosingFence = lines.count > 1 && (last.hasPrefix("```") || last.hasPrefix("~~~"))
            let body = lines.dropFirst().dropLast(hasClosingFence ? 1 : 0).joined(separator: "\n")
            let trailing = blockText.hasSuffix("\n") ? "\n" : ""
            let replacement = body + trailing
            let newText = ns.replacingCharacters(in: block.range, with: replacement)
            return MarkdownEdit(text: newText, selection: NSRange(location: block.range.location, length: (body as NSString).length))
        }
        let lineRange = ns.lineRange(for: selection)
        var body = ns.substring(with: lineRange)
        let endsWithNewline = body.hasSuffix("\n")
        if endsWithNewline { body.removeLast() }
        let replacement = "```\n" + body + "\n```" + (endsWithNewline ? "\n" : "")
        let newText = ns.replacingCharacters(in: lineRange, with: replacement)
        return MarkdownEdit(text: newText, selection: NSRange(location: lineRange.location + 4, length: (body as NSString).length))
    }
}
