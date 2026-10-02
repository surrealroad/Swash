//
//  MarkdownEditingCommands.swift
//  Swash
//
//  Notion-style structural editing: Enter continues lists, task lists and quotes (and exits
//  them on an empty item), Tab / Shift-Tab nest list items, and Backspace at the start of a
//  block removes its formatting. Each command maps (raw Markdown, selection) to an edit, or
//  nil when the key should keep its default behaviour.
//

import Foundation

enum MarkdownEditingCommands {
    private struct Line {
        let range: NSRange          // Without the line terminator
        let text: String
        let structure: MarkdownFormatting.LineStructure
        /// Offset of the content within the line (after quote prefix, indentation and marker)
        var contentOffset: Int { (structure.quotePrefix + structure.indent + structure.marker).utf16.count }
        var isListItem: Bool {
            switch structure.format {
            case .bulletList, .numberedList, .taskList: return true
            default: return false
            }
        }
    }

    private static func line(at location: Int, in ns: NSString) -> Line {
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(location, ns.length), length: 0))
        let range = NSRange(location: start, length: contentsEnd - start)
        let text = ns.substring(with: range)
        return Line(range: range, text: text, structure: MarkdownFormatting.structure(of: text))
    }

    private static func isInCode(_ location: Int, text: String) -> Bool {
        MarkdownFormatting(text: text).codeBlock(containing: NSRange(location: location, length: 0)) != nil
    }

    // MARK: - Enter

    static func newline(text: String, selection: NSRange) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let current = line(at: selection.location, in: ns)
        let s = current.structure
        guard current.isListItem || !s.quotePrefix.isEmpty else { return nil }
        guard !isInCode(selection.location, text: text) else { return nil }
        let caretInLine = selection.location - current.range.location
        // Caret inside the prefix/marker: default behaviour
        guard caretInLine >= current.contentOffset else { return nil }

        let contentIsEmpty = s.content.trimmingCharacters(in: .whitespaces).isEmpty
        if contentIsEmpty {
            // Empty item: outdent a nested item, otherwise leave the list (or one quote level)
            if current.isListItem && !s.indent.isEmpty {
                return outdent(text: text, selection: selection)
            }
            let replacement: String
            if current.isListItem {
                replacement = s.quotePrefix
            } else {
                replacement = removingOneQuoteLevel(s.quotePrefix)
            }
            let edited = ns.replacingCharacters(in: current.range, with: replacement)
            return MarkdownEdit(text: edited, selection: NSRange(location: current.range.location + (replacement as NSString).length, length: 0))
        }

        // Split the line at the caret and continue the structure on the new line
        let continuation = s.quotePrefix + s.indent + nextMarker(after: s)
        let insertion = "\n" + continuation
        var edited = ns.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: insertion) as NSString
        let caret = selection.location + (insertion as NSString).length
        if s.format == .numberedList {
            edited = renumber(edited, fromLineAt: caret, prefix: s.quotePrefix + s.indent)
        }
        return MarkdownEdit(text: edited as String, selection: NSRange(location: caret, length: 0))
    }

    private static func nextMarker(after s: MarkdownFormatting.LineStructure) -> String {
        let marker = s.marker
        let spacing = String(marker.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
        let pad = spacing.isEmpty ? " " : spacing
        switch s.format {
        case .bulletList:
            return String(marker.trimmingCharacters(in: .whitespaces).prefix(1)) + pad
        case .taskList:
            return String(marker.trimmingCharacters(in: .whitespaces).prefix(1)) + " [ ]" + pad
        case .numberedList:
            let trimmed = marker.trimmingCharacters(in: .whitespaces)
            let number = Int(trimmed.prefix(while: { $0.isNumber })) ?? 0
            let delimiter = trimmed.last.map(String.init) ?? "."
            return "\(number + 1)\(delimiter)" + pad
        default:
            return ""
        }
    }

    /// Renumbers the ordered items that follow the line at `location` at the same nesting level.
    private static func renumber(_ text: NSString, fromLineAt location: Int, prefix: String) -> NSString {
        let result = NSMutableString(string: text)
        var current = line(at: location, in: result)
        guard current.structure.format == .numberedList else { return result }
        var expected = (Int(current.structure.marker.trimmingCharacters(in: .whitespaces).prefix(while: { $0.isNumber })) ?? 0) + 1
        var position = NSMaxRange(current.range) + 1
        while position < result.length {
            current = line(at: position, in: result)
            let s = current.structure
            let samePrefix = s.quotePrefix + s.indent == prefix
            if samePrefix && s.format == .numberedList {
                let trimmed = s.marker.trimmingCharacters(in: .whitespaces)
                let delimiter = trimmed.last.map(String.init) ?? "."
                let spacing = String(s.marker.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
                let newMarker = "\(expected)\(delimiter)\(spacing)"
                let markerRange = NSRange(location: current.range.location + (s.quotePrefix + s.indent).utf16.count, length: s.marker.utf16.count)
                result.replaceCharacters(in: markerRange, with: newMarker)
                expected += 1
            } else if (s.quotePrefix + s.indent).count > prefix.count && !current.text.trimmingCharacters(in: .whitespaces).isEmpty {
                // Nested content of the previous item: keep going
            } else {
                break
            }
            current = line(at: position, in: result)
            position = NSMaxRange(current.range) + 1
        }
        return result
    }

    private static func removingOneQuoteLevel(_ prefix: String) -> String {
        var p = prefix
        guard let gt = p.lastIndex(of: ">") else { return prefix }
        var end = p.index(after: gt)
        if end < p.endIndex && (p[end] == " " || p[end] == "\t") { end = p.index(after: end) }
        p.removeSubrange(gt..<end)
        return p.trimmingCharacters(in: .whitespaces).isEmpty ? "" : p
    }

    // MARK: - Tab / Shift-Tab

    /// Nests a list item under its previous sibling (indentation = that sibling's content column).
    static func indent(text: String, selection: NSRange) -> MarkdownEdit? {
        let ns = text as NSString
        let current = line(at: selection.location, in: ns)
        guard current.isListItem, !isInCode(selection.location, text: text) else { return nil }
        let level = current.structure.indent.count
        // Walk up past deeper (nested) lines and blank lines to the previous sibling item
        var sibling: Line? = nil
        var search = current.range.location
        while search > 0 {
            let candidate = line(at: search - 1, in: ns)
            let blank = candidate.text.trimmingCharacters(in: .whitespaces).isEmpty
            if !blank {
                guard candidate.structure.quotePrefix == current.structure.quotePrefix else { break }
                let candidateLevel = candidate.structure.indent.count
                if candidate.isListItem && candidateLevel == level { sibling = candidate; break }
                if candidateLevel <= level { break }
            }
            if candidate.range.location == 0 { break }
            search = candidate.range.location
        }
        guard let previous = sibling else { return nil }
        let width = previous.structure.marker.count
        guard width > 0 else { return nil }
        let insertAt = current.range.location + current.structure.quotePrefix.utf16.count
        let spaces = String(repeating: " ", count: width)
        let edited = ns.replacingCharacters(in: NSRange(location: insertAt, length: 0), with: spaces)
        return MarkdownEdit(text: edited, selection: NSRange(location: selection.location + width, length: selection.length))
    }
    
    /// Moves a nested list item one level out.
    static func outdent(text: String, selection: NSRange) -> MarkdownEdit? {
        let ns = text as NSString
        let current = line(at: selection.location, in: ns)
        guard current.isListItem, !current.structure.indent.isEmpty, !isInCode(selection.location, text: text) else { return nil }
        // Remove the indentation down to the parent item's column
        var parentIndent = 0
        var search = current.range.location
        while search > 0 {
            let candidate = line(at: search - 1, in: ns)
            if candidate.isListItem && candidate.structure.indent.count < current.structure.indent.count {
                parentIndent = candidate.structure.indent.count
                break
            }
            if candidate.range.location == 0 { break }
            search = candidate.range.location
        }
        let remove = current.structure.indent.count - parentIndent
        guard remove > 0 else { return nil }
        let start = current.range.location + current.structure.quotePrefix.utf16.count + parentIndent
        let edited = ns.replacingCharacters(in: NSRange(location: start, length: remove), with: "")
        return MarkdownEdit(text: edited, selection: NSRange(location: max(current.range.location, selection.location - remove), length: selection.length))
    }

    // MARK: - Backspace

    /// At the start of a block's content, removes its marker (heading, list, task) or one quote level.
    /// `markersHidden`: in the WYSIWYG editor the prefix is invisible, so a caret anywhere before the
    /// content (even at the very start of the line) counts as being at the start of the block.
    static func backspace(text: String, selection: NSRange, markersHidden: Bool = false) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let current = line(at: selection.location, in: ns)
        let s = current.structure
        guard !isInCode(selection.location, text: text) else { return nil }
        var caretInLine = selection.location - current.range.location
        let prefixLength = (s.quotePrefix + s.indent).utf16.count
        guard caretInLine <= current.contentOffset, current.contentOffset > 0 else { return nil }
        if markersHidden { caretInLine = current.contentOffset }
        guard caretInLine > 0 else { return nil }
        if !s.marker.isEmpty, caretInLine > prefixLength {
            // Caret at (or within) the marker: remove it, keeping quote prefix and indentation
            let markerRange = NSRange(location: current.range.location + prefixLength, length: s.marker.utf16.count)
            let edited = ns.replacingCharacters(in: markerRange, with: "")
            return MarkdownEdit(text: edited, selection: NSRange(location: markerRange.location, length: 0))
        }
        if s.marker.isEmpty, !s.quotePrefix.isEmpty, caretInLine <= s.quotePrefix.utf16.count + s.indent.utf16.count {
            let reduced = removingOneQuoteLevel(s.quotePrefix)
            let prefixRange = NSRange(location: current.range.location, length: s.quotePrefix.utf16.count)
            let edited = ns.replacingCharacters(in: prefixRange, with: reduced)
            return MarkdownEdit(text: edited, selection: NSRange(location: current.range.location + (reduced as NSString).length, length: 0))
        }
        return nil
    }
}
