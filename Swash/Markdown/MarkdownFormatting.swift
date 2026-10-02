//
//  MarkdownFormatting.swift
//  Swash
//
//  AST-aware formatting operations for the bubble menu: which inline formats and block
//  types are active for a selection, and the minimal Markdown edits that toggle them.
//  All ranges are UTF-16 offsets into the raw Markdown.
//

import Foundation

enum MarkdownInlineFormat: CaseIterable {
    case strong, emphasis, strikethrough, code

    func matches(_ kind: MarkdownNode.Kind) -> Bool {
        switch (self, kind) {
        case (.strong, .strong), (.emphasis, .emphasis), (.strikethrough, .strikethrough), (.code, .code): return true
        default: return false
        }
    }

    var delimiter: String {
        switch self {
        case .strong: return "**"
        case .emphasis: return "*"
        case .strikethrough: return "~~"
        case .code: return "`"
        }
    }
}

enum MarkdownBlockFormat: Equatable {
    case paragraph
    case heading(Int)
    case quote
    case bulletList
    case numberedList
    case taskList
}

/// Result of a formatting operation: the new document text and the selection to show.
struct MarkdownEdit: Equatable {
    let text: String
    let selection: NSRange
}

struct MarkdownFormatting {
    let text: String
    let document: MarkdownDocument
    private let ns: NSString

    init(text: String, document: MarkdownDocument? = nil) {
        self.text = text
        self.document = document ?? MarkdownDocument.parse(text)
        self.ns = text as NSString
    }

    // MARK: - Node queries

    private func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        NSIntersectionRange(a, b).length > 0
    }

    /// Leaf blocks that hold inline content (paragraphs, headings, table cells) intersecting `range`.
    func inlineContainers(intersecting range: NSRange) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        document.root.walk { node in
            switch node.kind {
            case .paragraph, .heading, .tableCell:
                let r = node.range
                let hit = range.length == 0
                    ? (range.location >= r.location && range.location <= NSMaxRange(r))
                    : intersects(r, range)
                if hit { result.append(node) }
            default:
                break
            }
        }
        return result
    }

    /// All nodes (pre-order) satisfying `predicate` whose range intersects (or, for a caret, touches) `range`.
    private func nodes(intersecting range: NSRange, where predicate: (MarkdownNode) -> Bool) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        document.root.walk { node in
            guard predicate(node) else { return }
            let r = node.range
            let hit = range.length == 0
                ? (range.location > r.location && range.location < NSMaxRange(r))
                : intersects(r, range)
            if hit { result.append(node) }
        }
        return result
    }

    /// The code block (fenced or indented) containing `range`, if any.
    func codeBlock(containing range: NSRange) -> MarkdownNode? {
        var found: MarkdownNode? = nil
        document.root.walk { node in
            if found == nil, case .codeBlock = node.kind, contains(node.range, range) || (range.length == 0 && range.location == NSMaxRange(node.range)) {
                found = node
            }
        }
        return found
    }

    /// The code span containing (or exactly covering) `range`, if any.
    func codeSpan(containing range: NSRange) -> MarkdownNode? {
        nodes(intersecting: range) { if case .code = $0.kind { return true }; return false }
            .first { contains($0.range, range) }
    }

    func isInTable(_ range: NSRange) -> Bool {
        !nodes(intersecting: range) { if case .table = $0.kind { return true }; return false }.isEmpty
    }

    /// Innermost link (not image) at the selection; a caret anywhere inside the link counts.
    func link(at range: NSRange) -> MarkdownNode? {
        var found: MarkdownNode? = nil
        document.root.walk { node in
            guard case .link = node.kind else { return }
            let r = node.range
            let hit = range.length == 0
                ? (range.location >= r.location && range.location <= NSMaxRange(r))
                : intersects(r, range)
            if hit { found = node }
        }
        return found
    }

    /// Source range of a link's visible text (between its brackets), or the whole node for autolinks.
    func linkTextRange(_ link: MarkdownNode) -> NSRange {
        guard link.markers.count == 2, ns.length >= NSMaxRange(link.markers[1]) else { return link.range }
        let start = NSMaxRange(link.markers[0])
        return NSRange(location: start, length: max(0, link.markers[1].location - start))
    }

    // MARK: - Segments

    /// The parts of the selection that inline formats apply to: per inline container and per line,
    /// excluding container prefixes (quote markers, list indentation) and surrounding whitespace.
    func segments(in selection: NSRange) -> [NSRange] {
        guard selection.length > 0 else { return [] }
        var result: [NSRange] = []
        for block in inlineContainers(intersecting: selection) {
            let blockRange = NSIntersectionRange(block.range, selection)
            guard blockRange.length > 0 else { continue }
            let prefixMarkers = block.ancestors.flatMap { ancestor -> [NSRange] in
                switch ancestor.kind {
                case .blockQuote, .alert: return ancestor.markers
                default: return []
                }
            }
            var lineStart = blockRange.location
            let end = NSMaxRange(blockRange)
            while lineStart < end {
                let lineRange = ns.lineRange(for: NSRange(location: lineStart, length: 0))
                var a = max(lineStart, lineRange.location)
                var b = min(end, NSMaxRange(lineRange))
                // Skip quote markers and indentation at the start of continuation lines
                if a == lineRange.location {
                    while a < b {
                        let c = ns.character(at: a)
                        if c == 0x20 || c == 0x09 || prefixMarkers.contains(where: { $0.location <= a && a < NSMaxRange($0) }) {
                            a += 1
                        } else {
                            break
                        }
                    }
                }
                while a < b, isWhitespace(ns.character(at: a)) { a += 1 }
                while b > a, isWhitespace(ns.character(at: b - 1)) { b -= 1 }
                if b > a { result.append(NSRange(location: a, length: b - a)) }
                if NSMaxRange(lineRange) <= lineStart { break }
                lineStart = NSMaxRange(lineRange)
            }
        }
        return result
    }

    private func isWhitespace(_ c: unichar) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }

    // MARK: - Inline formats

    func isActive(_ format: MarkdownInlineFormat, selection: NSRange) -> Bool {
        let formatted = nodes(intersecting: NSRange(location: 0, length: ns.length)) { format.matches($0.kind) }
        if selection.length == 0 {
            return formatted.contains { $0.range.location < selection.location && selection.location < NSMaxRange($0.range) }
        }
        let segs = segments(in: selection)
        guard !segs.isEmpty else { return false }
        return segs.allSatisfy { seg in formatted.contains { contains($0.range, seg) } }
    }

    private func isValid(_ selection: NSRange) -> Bool {
        selection.location != NSNotFound && selection.location >= 0 && NSMaxRange(selection) <= ns.length
    }
    
    func toggle(_ format: MarkdownInlineFormat, selection: NSRange) -> MarkdownEdit? {
        guard isValid(selection) else { return nil }
        if isActive(format, selection: selection) {
            return remove(format, selection: selection)
        }
        return apply(format, selection: selection)
    }

    /// Removes the delimiters of every `format` node covering the selection.
    private func remove(_ format: MarkdownInlineFormat, selection: NSRange) -> MarkdownEdit? {
        let targets: [MarkdownNode]
        if selection.length == 0 {
            targets = nodes(intersecting: selection) { format.matches($0.kind) }.suffix(1)
        } else {
            let formatted = nodes(intersecting: selection) { format.matches($0.kind) }
            // The innermost covering node for each segment
            var picked: [MarkdownNode] = []
            for seg in segments(in: selection) {
                if let node = formatted.last(where: { contains($0.range, seg) }), !picked.contains(where: { $0 === node }) {
                    picked.append(node)
                }
            }
            targets = picked
        }
        guard !targets.isEmpty else { return nil }
        let edits = targets.flatMap { node in node.markers.map { (range: $0, replacement: "") } }
        return applying(edits, selection: selection)
    }

    /// Wraps each segment in the format's delimiters, merging with overlapping nodes of the same format.
    private func apply(_ format: MarkdownInlineFormat, selection: NSRange) -> MarkdownEdit? {
        let segs = segments(in: selection)
        guard !segs.isEmpty else {
            // Caret: insert an empty pair and place the caret between the delimiters
            let pair = format.delimiter + format.delimiter
            let edited = ns.replacingCharacters(in: selection, with: pair)
            return MarkdownEdit(text: edited, selection: NSRange(location: selection.location + format.delimiter.utf16.count, length: 0))
        }
        var edits: [(range: NSRange, replacement: String)] = []
        var resultSelection: NSRange? = nil
        for seg in segs {
            guard let container = inlineContainers(intersecting: seg).first(where: { contains($0.range, seg) }) else { continue }
            var union = seg
            var merged: [MarkdownNode] = []
            // Grow the span until it no longer cuts through another inline node
            var changed = true
            while changed {
                changed = false
                container.walk { node in
                    // Text can be split anywhere; other inline nodes must not be cut through
                    guard node !== container, !node.kind.isBlock else { return }
                    switch node.kind {
                    case .text, .softBreak, .hardBreak: return
                    default: break
                    }
                    let r = node.range
                    guard intersects(r, union), !contains(r, union) else { return }
                    if format.matches(node.kind) {
                        if !merged.contains(where: { $0 === node }) { merged.append(node) }
                        if !contains(union, r) { union = NSUnionRange(union, r); changed = true }
                    } else if !contains(union, r) {
                        union = NSUnionRange(union, r)
                        changed = true
                    }
                }
            }
            // Inner content: the span minus the delimiters of merged nodes of the same format
            var inner = ns.substring(with: union)
            let removals = merged.flatMap { $0.markers }.filter { contains(union, $0) }.sorted { $0.location > $1.location }
            for marker in removals {
                let local = NSRange(location: marker.location - union.location, length: marker.length)
                inner = (inner as NSString).replacingCharacters(in: local, with: "")
            }
            let delimiter: String
            var padding = ""
            if format == .code {
                let longestRun = inner.components(separatedBy: CharacterSet(charactersIn: "`").inverted).map { $0.count }.max() ?? 0
                delimiter = String(repeating: "`", count: longestRun + 1)
                if longestRun > 0 { padding = " " }
            } else {
                delimiter = format.delimiter
            }
            let replacement = delimiter + padding + inner + padding + delimiter
            edits.append((union, replacement))
            if segs.count == 1 {
                resultSelection = NSRange(location: union.location + (delimiter + padding).utf16.count, length: (inner as NSString).length)
            }
        }
        guard var edit = applying(edits, selection: selection) else { return nil }
        if let explicit = resultSelection {
            edit = MarkdownEdit(text: edit.text, selection: explicit)
        }
        return edit
    }

    // MARK: - Links

    func setLink(_ url: String, selection: NSRange) -> MarkdownEdit? {
        guard isValid(selection) else { return nil }
        if let link = link(at: selection) {
            let content = ns.substring(with: linkTextRange(link))
            let replacement = "[\(content)](\(url))"
            let edited = ns.replacingCharacters(in: link.range, with: replacement)
            return MarkdownEdit(text: edited, selection: NSRange(location: link.range.location, length: (replacement as NSString).length))
        }
        guard let seg = segments(in: selection).first else {
            let replacement = "[\(url)](\(url))"
            let edited = ns.replacingCharacters(in: selection, with: replacement)
            return MarkdownEdit(text: edited, selection: NSRange(location: selection.location, length: (replacement as NSString).length))
        }
        let replacement = "[\(ns.substring(with: seg))](\(url))"
        let edited = ns.replacingCharacters(in: seg, with: replacement)
        return MarkdownEdit(text: edited, selection: NSRange(location: seg.location, length: (replacement as NSString).length))
    }

    func removeLink(selection: NSRange) -> MarkdownEdit? {
        guard isValid(selection), let link = link(at: selection) else { return nil }
        let content = ns.substring(with: linkTextRange(link))
        let edited = ns.replacingCharacters(in: link.range, with: content)
        return MarkdownEdit(text: edited, selection: NSRange(location: link.range.location, length: (content as NSString).length))
    }

    // MARK: - Blocks

    /// Line structure: container quote markers, indentation, the block marker, and the content.
    struct LineStructure {
        let quotePrefix: String
        let indent: String
        let marker: String
        let format: MarkdownBlockFormat
        let content: String
    }

    private static let lineRegex = try! NSRegularExpression(pattern: "^((?:[ \\t]{0,3}>[ \\t]?)*)([ \\t]*)((?:#{1,6}(?:[ \\t]+|$))|(?:[-*+][ \\t]+\\[[ xX]\\](?:[ \\t]+|$))|(?:[-*+](?:[ \\t]+|$))|(?:[0-9]{1,9}[.)](?:[ \\t]+|$)))?")

    static func structure(of line: String) -> LineStructure {
        let nsLine = line as NSString
        guard let m = lineRegex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)) else {
            return LineStructure(quotePrefix: "", indent: "", marker: "", format: .paragraph, content: line)
        }
        func group(_ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : nsLine.substring(with: r)
        }
        let quote = group(1)
        let indent = group(2)
        let marker = group(3)
        let content = nsLine.substring(from: m.range.location + m.range.length)
        let trimmed = marker.trimmingCharacters(in: .whitespaces)
        var format: MarkdownBlockFormat = quote.isEmpty ? .paragraph : .quote
        if trimmed.hasPrefix("#") {
            format = .heading(trimmed.count)
        } else if trimmed.contains("[") {
            format = .taskList
        } else if let first = trimmed.first, "-*+".contains(first) {
            format = .bulletList
        } else if let first = trimmed.first, first.isNumber {
            format = .numberedList
        }
        return LineStructure(quotePrefix: quote, indent: indent, marker: marker, format: format, content: content)
    }

    /// Line ranges (without terminators) touched by the selection.
    private func selectedLines(_ selection: NSRange) -> [NSRange] {
        let whole = ns.lineRange(for: NSRange(location: min(selection.location, ns.length), length: min(selection.length, max(0, ns.length - selection.location))))
        var lines: [NSRange] = []
        var start = whole.location
        while start < NSMaxRange(whole) {
            var end = 0, contentsEnd = 0
            ns.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))
            lines.append(NSRange(location: start, length: contentsEnd - start))
            if end <= start { break }
            start = end
        }
        if lines.isEmpty { lines.append(NSRange(location: whole.location, length: 0)) }
        return lines
    }

    /// Lines inside fenced or indented code are never rewritten by block formats.
    private func isCodeLine(_ line: NSRange) -> Bool {
        var inside = false
        document.root.walk { node in
            if !inside, case .codeBlock = node.kind, contains(node.range, line) {
                inside = true
            }
        }
        return inside
    }

    /// The block format shared by every non-blank selected line, if any.
    func activeBlockFormat(selection: NSRange) -> MarkdownBlockFormat? {
        let lines = selectedLines(selection).filter { !ns.substring(with: $0).trimmingCharacters(in: .whitespaces).isEmpty && !isCodeLine($0) }
        guard !lines.isEmpty else { return nil }
        let formats = lines.map { Self.structure(of: ns.substring(with: $0)).format }
        if formats.allSatisfy({ $0 == formats[0] }) { return formats[0] }
        return nil
    }

    /// True when every non-blank selected line is inside a blockquote.
    func isQuoted(selection: NSRange) -> Bool {
        let lines = selectedLines(selection).filter { !ns.substring(with: $0).trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { !Self.structure(of: ns.substring(with: $0)).quotePrefix.isEmpty }
    }

    /// Turns the selected lines into `format` (or back to paragraphs when it is already active).
    /// Enclosing quote markers are kept; code lines are never touched.
    func toggleBlock(_ format: MarkdownBlockFormat, selection: NSRange) -> MarkdownEdit? {
        guard isValid(selection) else { return nil }
        let lines = selectedLines(selection)
        var edits: [(range: NSRange, replacement: String)] = []

        if format == .quote {
            let quoted = isQuoted(selection: selection)
            for line in lines {
                let s = Self.structure(of: ns.substring(with: line))
                if quoted {
                    // Remove one level of quoting
                    var prefix = s.quotePrefix
                    if let gt = prefix.firstIndex(of: ">") {
                        var end = prefix.index(after: gt)
                        if end < prefix.endIndex && (prefix[end] == " " || prefix[end] == "\t") { end = prefix.index(after: end) }
                        prefix.removeSubrange(prefix.startIndex..<end)
                    }
                    edits.append((NSRange(location: line.location, length: (s.quotePrefix as NSString).length), prefix))
                } else {
                    let isBlank = ns.substring(with: line).trimmingCharacters(in: .whitespaces).isEmpty
                    edits.append((NSRange(location: line.location, length: 0), isBlank ? ">" : "> "))
                }
            }
            return applying(edits, selection: selection)
        }

        let active = activeBlockFormat(selection: selection)
        let turningOff = active == format
        var number = 1
        for line in lines {
            let lineText = ns.substring(with: line)
            if lineText.trimmingCharacters(in: .whitespaces).isEmpty || isCodeLine(line) { continue }
            let s = Self.structure(of: lineText)
            let newMarker: String
            if turningOff {
                newMarker = ""
            } else {
                switch format {
                case .paragraph: newMarker = ""
                case .heading(let level): newMarker = String(repeating: "#", count: level) + " "
                case .bulletList: newMarker = "- "
                case .numberedList: newMarker = "\(number). "; number += 1
                case .taskList: newMarker = "- [ ] "
                case .quote: newMarker = ""
                }
            }
            let markerStart = line.location + ((s.quotePrefix + s.indent) as NSString).length
            edits.append((NSRange(location: markerStart, length: (s.marker as NSString).length), newMarker))
        }
        return applying(edits, selection: selection)
    }

    // MARK: - Edit application

    /// Applies non-overlapping edits and maps the selection through them.
    private func applying(_ edits: [(range: NSRange, replacement: String)], selection: NSRange) -> MarkdownEdit? {
        guard !edits.isEmpty else { return nil }
        let sorted = edits.sorted { $0.range.location > $1.range.location }
        let result = NSMutableString(string: text)
        for edit in sorted {
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        func map(_ position: Int, isEnd: Bool) -> Int {
            var delta = 0
            for edit in edits {
                let r = edit.range
                let replacementLength = (edit.replacement as NSString).length
                if NSMaxRange(r) <= position {
                    delta += replacementLength - r.length
                } else if r.location < position && position < NSMaxRange(r) {
                    delta += (isEnd ? replacementLength : 0) - (position - r.location)
                }
            }
            return position + delta
        }
        let start = map(selection.location, isEnd: false)
        let end = map(NSMaxRange(selection), isEnd: true)
        return MarkdownEdit(text: result as String, selection: NSRange(location: start, length: max(0, end - start)))
    }
}
