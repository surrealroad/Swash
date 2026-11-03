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

    /// `document`, when given, must be the parse of `text`; callers that already have one pass it
    /// so the check doesn't parse the whole document again.
    private static func isInCode(_ location: Int, text: String, document: MarkdownDocument?) -> Bool {
        let parsed = document.flatMap { $0.source == text ? $0 : nil }
        return MarkdownFormatting(text: text, document: parsed).codeBlock(containing: NSRange(location: location, length: 0)) != nil
    }

    // MARK: - Enter

    static func newline(text: String, selection: NSRange, document: MarkdownDocument? = nil) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let current = line(at: selection.location, in: ns)
        let s = current.structure
        guard current.isListItem || !s.quotePrefix.isEmpty else { return nil }
        let caretInLine = selection.location - current.range.location
        // Caret inside the prefix/marker: default behaviour
        guard caretInLine >= current.contentOffset else { return nil }
        // The only check that parses the document, so it runs last
        guard !isInCode(selection.location, text: text, document: document) else { return nil }

        let contentIsEmpty = s.content.trimmingCharacters(in: .whitespaces).isEmpty
        if contentIsEmpty {
            // Empty item: outdent a nested item, otherwise leave the list (or one quote level)
            if current.isListItem && !s.indent.isEmpty {
                return outdent(text: text, selection: selection, document: document)
            }
            let prefix = current.isListItem ? s.quotePrefix : removingOneQuoteLevel(s.quotePrefix)
            // A line straight after the list (or quote) would be a lazy continuation of it, so the
            // new paragraph needs a blank line before it (one at the outer quote level).
            var replacement = prefix
            if current.range.location > 0 {
                let previous = line(at: current.range.location - 1, in: ns)
                if !previous.text.trimmingCharacters(in: CharacterSet(charactersIn: " \t>")).isEmpty {
                    let blank = prefix.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
                    replacement = blank + "\n" + prefix
                }
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
    static func indent(text: String, selection: NSRange, document: MarkdownDocument? = nil) -> MarkdownEdit? {
        let ns = text as NSString
        let current = line(at: selection.location, in: ns)
        guard current.isListItem, !isInCode(selection.location, text: text, document: document) else { return nil }
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
        // A list item with nothing to nest under keeps the Tab (rather than inserting a tab character)
        guard let previous = sibling else { return MarkdownEdit(text: text, selection: selection) }
        let width = previous.structure.marker.count
        guard width > 0 else { return MarkdownEdit(text: text, selection: selection) }
        let insertAt = current.range.location + current.structure.quotePrefix.utf16.count
        let spaces = String(repeating: " ", count: width)
        let edited = NSMutableString(string: ns.replacingCharacters(in: NSRange(location: insertAt, length: 0), with: spaces))
        var caret = selection.location + width
        if current.structure.format == .numberedList {
            // The item starts (or continues) the nested list, and the outer list closes the gap
            let nestedIndent = level + width
            var number = 1
            var search = current.range.location
            while search > previous.range.location {
                let candidate = line(at: search - 1, in: ns)
                if candidate.range.location <= previous.range.location { break }
                if candidate.structure.quotePrefix == current.structure.quotePrefix,
                   candidate.structure.indent.count == nestedIndent, candidate.structure.format == .numberedList {
                    number = markerNumber(candidate.structure) + 1
                    break
                }
                search = candidate.range.location
            }
            caret += setMarkerNumber(number, onLineAt: current.range.location, in: edited)
            let nested = line(at: current.range.location, in: edited).structure
            let renumbered = renumber(edited, fromLineAt: current.range.location, prefix: nested.quotePrefix + nested.indent)
            let outer = renumber(renumbered, fromLineAt: previous.range.location, prefix: previous.structure.quotePrefix + previous.structure.indent)
            return MarkdownEdit(text: outer as String, selection: NSRange(location: caret, length: selection.length))
        }
        return MarkdownEdit(text: edited as String, selection: NSRange(location: caret, length: selection.length))
    }

    /// The number of an ordered-list marker (`3. ` → 3).
    private static func markerNumber(_ s: MarkdownFormatting.LineStructure) -> Int {
        Int(s.marker.trimmingCharacters(in: .whitespaces).prefix(while: { $0.isNumber })) ?? 1
    }

    /// Renumbers the ordered-list marker of the line at `location`; returns the change in length.
    private static func setMarkerNumber(_ number: Int, onLineAt location: Int, in text: NSMutableString) -> Int {
        let current = line(at: location, in: text)
        let s = current.structure
        guard s.format == .numberedList else { return 0 }
        let trimmed = s.marker.trimmingCharacters(in: .whitespaces)
        let delimiter = trimmed.last.map(String.init) ?? "."
        let spacing = String(s.marker.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
        let newMarker = "\(number)\(delimiter)\(spacing)"
        let markerRange = NSRange(location: current.range.location + (s.quotePrefix + s.indent).utf16.count, length: s.marker.utf16.count)
        text.replaceCharacters(in: markerRange, with: newMarker)
        return (newMarker as NSString).length - markerRange.length
    }
    
    /// Moves a nested list item one level out.
    static func outdent(text: String, selection: NSRange, document: MarkdownDocument? = nil) -> MarkdownEdit? {
        let ns = text as NSString
        let current = line(at: selection.location, in: ns)
        guard current.isListItem, !current.structure.indent.isEmpty, !isInCode(selection.location, text: text, document: document) else { return nil }
        // Remove the indentation down to the parent item's column
        var parentIndent = 0
        var parent: Line? = nil
        var search = current.range.location
        while search > 0 {
            let candidate = line(at: search - 1, in: ns)
            if candidate.isListItem && candidate.structure.indent.count < current.structure.indent.count {
                parentIndent = candidate.structure.indent.count
                parent = candidate
                break
            }
            if candidate.range.location == 0 { break }
            search = candidate.range.location
        }
        let remove = current.structure.indent.count - parentIndent
        guard remove > 0 else { return nil }
        let start = current.range.location + current.structure.quotePrefix.utf16.count + parentIndent
        let edited = NSMutableString(string: ns.replacingCharacters(in: NSRange(location: start, length: remove), with: ""))
        var caret = max(current.range.location, selection.location - remove)
        if current.structure.format == .numberedList {
            // The item now follows its old parent in the outer list
            let number = parent.map { $0.structure.format == .numberedList ? markerNumber($0.structure) + 1 : 1 } ?? 1
            let delta = setMarkerNumber(number, onLineAt: current.range.location, in: edited)
            if selection.location - remove > current.range.location { caret += delta }
            let outer = line(at: current.range.location, in: edited).structure
            let renumbered = renumber(edited, fromLineAt: current.range.location, prefix: outer.quotePrefix + outer.indent)
            return MarkdownEdit(text: renumbered as String, selection: NSRange(location: caret, length: selection.length))
        }
        return MarkdownEdit(text: edited as String, selection: NSRange(location: caret, length: selection.length))
    }

    // MARK: - Backspace

    /// At the start of a block's content, removes its marker (heading, list, task) or one quote level.
    /// `markersHidden`: in the WYSIWYG editor the prefix is invisible, so a caret anywhere before the
    /// content (even at the very start of the line) counts as being at the start of the block.
    static func backspace(text: String, selection: NSRange, markersHidden: Bool = false, document: MarkdownDocument? = nil) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let current = line(at: selection.location, in: ns)
        let s = current.structure
        var caretInLine = selection.location - current.range.location
        let prefixLength = (s.quotePrefix + s.indent).utf16.count
        guard caretInLine <= current.contentOffset, current.contentOffset > 0 else { return nil }
        if markersHidden { caretInLine = current.contentOffset }
        guard caretInLine > 0 else { return nil }
        // The only check that parses the document, so it runs after the per-line ones
        guard !isInCode(selection.location, text: text, document: document) else { return nil }
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
    
    // MARK: - "/" block menu
    
    enum BlockInsert: CaseIterable {
        case text, heading1, heading2, heading3, bulletList, numberedList, todoList, quote, callout, codeBlock, divider, table, footnote
        
        var title: String {
            switch self {
            case .text: return "Text"
            case .heading1: return "Heading 1"
            case .heading2: return "Heading 2"
            case .heading3: return "Heading 3"
            case .bulletList: return "Bulleted List"
            case .numberedList: return "Numbered List"
            case .todoList: return "To-do List"
            case .quote: return "Quote"
            case .callout: return "Callout"
            case .codeBlock: return "Code Block"
            case .divider: return "Divider"
            case .table: return "Table"
            case .footnote: return "Footnote"
            }
        }
        
        var symbolName: String {
            switch self {
            case .text: return "text.alignleft"
            case .heading1: return "textformat.size.larger"
            case .heading2: return "textformat.size"
            case .heading3: return "textformat.size.smaller"
            case .bulletList: return "list.bullet"
            case .numberedList: return "list.number"
            case .todoList: return "checklist"
            case .quote: return "text.quote"
            case .callout: return "info.circle"
            case .codeBlock: return "curlybraces"
            case .divider: return "minus"
            case .table: return "tablecells"
            case .footnote: return "textformat.superscript"
            }
        }
    }
    
    /// Whether typing "/" at `location` should open the block menu: the caret is at the start of an
    /// otherwise empty block (an empty line, quote line or list item), outside code.
    static func isBlockMenuTrigger(text: String, location: Int) -> Bool {
        let ns = text as NSString
        guard location <= ns.length else { return false }
        let current = line(at: location, in: ns)
        guard location - current.range.location >= current.contentOffset else { return false }
        guard current.structure.content.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if case .heading = current.structure.format { return false }
        return !isInCode(location, text: text, document: nil)
    }
    
    /// Replaces the line holding the "/" at `slashLocation` with the chosen block.
    static func insertBlock(_ kind: BlockInsert, text: String, slashLocation: Int) -> MarkdownEdit? {
        let ns = text as NSString
        guard slashLocation < ns.length, ns.character(at: slashLocation) == 0x2F else { return nil }
        if kind == .footnote {
            // A reference where the "/" was, and its definition at the end of the document
            let withoutSlash = ns.replacingCharacters(in: NSRange(location: slashLocation, length: 1), with: "")
            return MarkdownFormatting(text: withoutSlash).insertFootnote(selection: NSRange(location: slashLocation, length: 0))
        }
        let current = line(at: slashLocation, in: ns)
        let s = current.structure
        // Keep the quote prefix and indentation; replace any list marker
        let prefix = s.quotePrefix + s.indent
        let continuation = s.quotePrefix.isEmpty ? "" : s.quotePrefix.trimmingCharacters(in: .whitespaces).isEmpty ? "" : s.quotePrefix
        let lineText: String
        var caretOffset: Int? = nil
        switch kind {
        case .text: lineText = prefix
        case .heading1: lineText = prefix + "# "
        case .heading2: lineText = prefix + "## "
        case .heading3: lineText = prefix + "### "
        case .bulletList: lineText = prefix + "- "
        case .numberedList: lineText = prefix + "1. "
        case .todoList: lineText = prefix + "- [ ] "
        case .quote: lineText = prefix + "> "
        case .callout: lineText = prefix + "> [!NOTE]\n" + continuation + s.indent + "> "
        case .codeBlock:
            let open = prefix + "```\n" + continuation + s.indent
            lineText = open + "\n" + continuation + s.indent + "```"
            caretOffset = (open as NSString).length
        case .divider: lineText = prefix + "---\n" + continuation + s.indent
        case .table:
            let header = prefix + "| Column 1 | Column 2 |"
            lineText = header + "\n" + prefix + "| --- | --- |\n" + prefix + "|  |  |\n\n" + continuation + s.indent
        case .footnote:
            return nil
        }
        let edited = ns.replacingCharacters(in: current.range, with: lineText)
        let caret = current.range.location + (caretOffset ?? (lineText as NSString).length)
        return MarkdownEdit(text: edited, selection: NSRange(location: caret, length: 0))
    }
    
    // MARK: - Code block language
    
    static let commonLanguages = ["swift", "python", "javascript", "typescript", "json", "html", "css", "bash",
                                  "ruby", "go", "rust", "java", "kotlin", "c", "cpp", "sql", "yaml", "markdown", "mermaid"]
    
    /// Sets (or clears, with nil) the info string of the fenced code block containing `location`.
    static func setCodeLanguage(_ language: String?, text: String, location: Int) -> MarkdownEdit? {
        let ns = text as NSString
        let formatting = MarkdownFormatting(text: text)
        guard let block = formatting.codeBlock(containing: NSRange(location: location, length: 0)),
              case .codeBlock(true, _) = block.kind, let fence = block.markers.first else { return nil }
        let fenceLine = ns.substring(with: fence)
        let fenceChars = fenceLine.prefix(while: { $0 == "`" || $0 == "~" })
        let replacement = String(fenceChars) + (language ?? "")
        let edited = ns.replacingCharacters(in: fence, with: replacement)
        let delta = (replacement as NSString).length - fence.length
        return MarkdownEdit(text: edited, selection: NSRange(location: location > fence.location ? location + delta : location, length: 0))
    }
}
