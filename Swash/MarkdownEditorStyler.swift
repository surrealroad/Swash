//
//  MarkdownEditorStyler.swift
//  Swash
//
//  Styles the Edit Text (WYSIWYG) text storage from the shared Markdown AST: block layout,
//  inline formatting that composes (bold inside a heading keeps the heading size), hidden
//  syntax markers taken from exact node ranges, list markers by nesting depth, and
//  attachment requests for tables and images.
//

import AppKit

/// An NSTextBlock whose background starts at its left margin, so blocks nested in list items are
/// indented instead of painting their background under the list indentation. NSTextBlock fills its
/// margin with `backgroundColor`, so indented blocks leave that nil and set `fillColor`, which
/// SwashLayoutManager paints from the margin edge. (Overriding drawBackground is avoided: its
/// `controlView` parameter changed optionality between SDKs.)
final class IndentedTextBlock: NSTextBlock {
    var fillColor: NSColor?
    
    /// Uses the standard background when there is no margin, the margin-aware fill otherwise.
    func setFill(_ color: NSColor, leftMargin: CGFloat) {
        if leftMargin > 0 {
            setWidth(leftMargin, type: .absoluteValueType, for: .margin, edge: .minX)
            backgroundColor = nil
            fillColor = color
        } else {
            backgroundColor = color
            fillColor = nil
        }
    }
}

extension NSAttributedString.Key {
    /// Marks the first character of a fenced code block; the layout manager draws its language badge.
    static let codeBadge = NSAttributedString.Key("SwashCodeBadgeKey")
    /// Marks the first character of an alert title; the layout manager draws the alert's icon before it.
    static let alertIcon = NSAttributedString.Key("SwashAlertIconKey")
}

struct AlertIconInfo {
    let type: AlertType
    let color: NSColor
    
    var symbolName: String {
        switch type {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "octagon.fill"
        }
    }
    
    var image: NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold).applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: type.title)?.withSymbolConfiguration(configuration)
    }
}

struct CodeBadgeInfo {
    let language: String?
    var title: String { (language?.isEmpty == false ? language! : "plain").uppercased() }
    
    static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: NSColor.tertiaryLabelColor,
        .kern: 0.6,
    ]
    
    var width: CGFloat { (title as NSString).size(withAttributes: Self.attributes).width + 4 }
    
    /// Badge rect in text-container coordinates for the line fragment holding the block's first line.
    func rect(in lineRect: NSRect) -> NSRect {
        let size = (title as NSString).size(withAttributes: Self.attributes)
        return NSRect(x: lineRect.maxX - size.width - 10, y: lineRect.minY + 1, width: size.width + 4, height: size.height + 2)
    }
}

/// A table or image the editor should collapse into an attachment.
struct EditorAttachmentRequest {
    enum Kind {
        case table(source: String, headers: [String], alignments: [TableAlignment], rows: [[String]])
        case image(alt: String, urlString: String, rawMarkdown: String, width: CGFloat?)
    }
    let range: NSRange
    let kind: Kind
}

final class MarkdownEditorStyler {
    static let baseFontSize: CGFloat = 14

    private struct InlineStyle {
        var size: CGFloat = MarkdownEditorStyler.baseFontSize
        var bold = false
        var italic = false
        var mono = false
        var color: NSColor? = nil
        var strike = false
        var link: URL? = nil
        var superscript = false
        var subscriptText = false
        var underline = false
        var highlight = false
        var keyboard = false
        var smallText = false
        
        /// Applies an enclosing inline HTML tag (<kbd>, <sub>, <mark>…).
        mutating func apply(_ html: InlineHTMLStyle) {
            switch html {
            case .keyboard: keyboard = true; mono = true
            case .lowered: subscriptText = true
            case .raised: superscript = true
            case .highlight: highlight = true
            case .underline: underline = true
            case .strikethrough: strike = true; color = .secondaryLabelColor
            case .bold: bold = true
            case .italic: italic = true
            case .small: smallText = true
            case .code: mono = true; if link == nil { color = .systemPurple }
            }
        }
    }
    
    private struct BlockContext {
        var indent: CGFloat = 0
        var listDepth = 0
        var textBlocks: [NSTextBlock] = []
        var inline = InlineStyle()
        /// Columns of leading indentation that belong to enclosing list items on continuation lines
        var hiddenIndentColumns = 0
    }

    private let storage: NSTextStorage
    private let text: NSString
    private let document: MarkdownDocument
    private var hidden: [NSRange] = []
    private(set) var attachments: [EditorAttachmentRequest] = []
    /// Code blocks, code spans, HTML and front matter (raw offsets), excluded from spellchecking.
    private(set) var codeRanges: [NSRange] = []

    init(storage: NSTextStorage, document: MarkdownDocument) {
        self.storage = storage
        self.text = storage.string as NSString
        self.document = document
    }

    /// Applies all styling. The caller has already reset attributes and wraps this in begin/endEditing.
    func style() {
        let context = BlockContext()
        for block in document.root.children {
            styleBlock(block, context)
        }
        for range in hidden {
            hide(range)
        }
    }

    // MARK: - Attribute helpers

    private var fullRange: NSRange { NSRange(location: 0, length: storage.length) }

    private func valid(_ range: NSRange) -> NSRange {
        NSIntersectionRange(range, fullRange)
    }

    private func hide(_ range: NSRange) {
        let r = valid(range)
        guard r.length > 0 else { return }
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: r)
        storage.addAttribute(.foregroundColor, value: NSColor.clear, range: r)
    }

    /// Queues a marker for hiding; when it ends its line, the newline is hidden too so the line collapses.
    private func hideMarker(_ range: NSRange, collapseLine: Bool = false) {
        guard range.length > 0 else { return }
        var r = range
        if collapseLine {
            let end = r.location + r.length
            if end < text.length && text.character(at: end) == 0x0A {
                r.length += 1
            }
        }
        hidden.append(r)
    }

    private func font(for style: InlineStyle) -> NSFont {
        var font: NSFont
        var size = style.size
        if style.smallText { size *= 0.85 }
        if style.subscriptText { size *= 0.75 }
        if style.keyboard { size -= 1 }
        if style.mono {
            font = NSFont.monospacedSystemFont(ofSize: max(1, size - 1), weight: style.bold ? .bold : .regular)
        } else {
            font = NSFont.systemFont(ofSize: size, weight: style.bold ? .bold : .regular)
        }
        if style.italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        if style.superscript {
            font = NSFont.systemFont(ofSize: max(9, style.size - 4), weight: .semibold)
        }
        return font
    }

    private func apply(_ style: InlineStyle, to range: NSRange) {
        let r = valid(range)
        guard r.length > 0 else { return }
        storage.addAttribute(.font, value: font(for: style), range: r)
        if let color = style.color {
            storage.addAttribute(.foregroundColor, value: color, range: r)
        }
        if style.strike {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        }
        if let url = style.link {
            storage.addAttribute(.link, value: url, range: r)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        }
        if style.superscript {
            storage.addAttribute(.baselineOffset, value: 4, range: r)
        }
        if style.subscriptText {
            storage.addAttribute(.baselineOffset, value: -3, range: r)
        }
        if style.underline {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        }
        if style.highlight {
            storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: r)
        }
        if style.keyboard {
            storage.addAttribute(.backgroundColor, value: NSColor.textColor.withAlphaComponent(0.08), range: r)
        }
    }

    private func paragraphStyle(_ context: BlockContext, lineSpacing: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.headIndent = context.indent
        p.firstLineHeadIndent = context.indent
        p.textBlocks = context.textBlocks
        p.lineSpacing = lineSpacing
        return p
    }

    private func setParagraphStyle(_ style: NSParagraphStyle, over range: NSRange) {
        // Paragraph attributes must cover whole paragraphs, including the trailing newline
        var r = text.paragraphRange(for: valid(range))
        r = valid(r)
        guard r.length > 0 else { return }
        storage.addAttribute(.paragraphStyle, value: style, range: r)
    }

    private func lineStart(of location: Int) -> Int {
        text.lineRange(for: NSRange(location: min(location, max(0, text.length - 1)), length: 0)).location
    }

    /// Hides leading whitespace (up to `maxColumns`, or all of it when nil) on each line in `range`
    /// after its first line.
    private func hideContinuationIndent(in range: NSRange, maxColumns: Int?, includeFirstLine: Bool = false) {
        guard range.length > 0 else { return }
        let end = range.location + range.length
        var line = lineStart(of: range.location)
        var first = true
        while line < end {
            let lineRange = text.lineRange(for: NSRange(location: line, length: 0))
            if !first || includeFirstLine {
                var i = line
                var columns = 0
                while i < lineRange.location + lineRange.length {
                    let c = text.character(at: i)
                    guard c == 0x20 || c == 0x09 else { break }
                    if let max = maxColumns, columns >= max { break }
                    columns += c == 0x09 ? 4 - (columns % 4) : 1
                    i += 1
                }
                if i > line { hidden.append(NSRange(location: line, length: i - line)) }
            }
            first = false
            if lineRange.length == 0 { break }
            line = lineRange.location + lineRange.length
        }
    }

    private func source(_ range: NSRange) -> String {
        text.substring(with: valid(range))
    }

    // MARK: - Blocks

    private func styleBlock(_ node: MarkdownNode, _ context: BlockContext) {
        switch node.kind {
        case .document:
            for child in node.children { styleBlock(child, context) }

        case .frontMatter:
            setParagraphStyle(paragraphStyle(context), over: node.range)
            apply(InlineStyle(size: 12, mono: true, color: .secondaryLabelColor), to: node.range)
            for marker in node.markers {
                apply(InlineStyle(size: 12, mono: true, color: .tertiaryLabelColor), to: marker)
            }
            codeRanges.append(node.range)

        case .paragraph:
            setParagraphStyle(paragraphStyle(context), over: node.range)
            apply(context.inline, to: node.range)
            hideContinuationIndent(in: node.range, maxColumns: nil)
            styleInlines(node, context.inline)

        case .heading(let level, let setext):
            var inline = context.inline
            inline.size = Self.headingSize(level)
            inline.bold = true
            setParagraphStyle(paragraphStyle(context), over: node.range)
            apply(inline, to: node.range)
            for marker in node.markers {
                hideMarker(marker, collapseLine: setext)
            }
            hideContinuationIndent(in: node.range, maxColumns: nil)
            styleInlines(node, inline)

        case .blockQuote, .alert:
            var inner = context
            let color: NSColor
            if case .alert(let type) = node.kind {
                color = Self.alertColor(type)
            } else {
                color = NSColor.controlAccentColor
                inner.inline.color = .secondaryLabelColor
                inner.inline.italic = true
            }
            let block = IndentedTextBlock()
            block.setFill(color.withAlphaComponent(0.07), leftMargin: context.indent)
            block.setValue(100, type: .percentageValueType, for: .width)
            block.setBorderColor(color, for: .minX)
            block.setWidth(3.0, type: .absoluteValueType, for: .border, edge: .minX)
            block.setWidth(6, type: .absoluteValueType, for: .padding)
            block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
            inner.textBlocks.append(block)
            inner.indent = 0
            setParagraphStyle(paragraphStyle(inner), over: node.range)
            apply(inner.inline, to: node.range)
            // Quote markers, and the alert's [!TYPE] marker shown as a coloured title
            for marker in node.markers {
                if case .alert(let type) = node.kind, source(marker).hasPrefix("[!") {
                    apply(InlineStyle(size: 13, bold: true, color: color), to: marker)
                    hideMarker(NSRange(location: marker.location, length: 2))
                    hideMarker(NSRange(location: marker.location + marker.length - 1, length: 1))
                    // Icon before the title, as in the Preview: indent the title line to make room
                    storage.addAttribute(.alertIcon, value: AlertIconInfo(type: type, color: color), range: NSRange(location: marker.location + 2, length: 1))
                    var titleContext = inner
                    titleContext.indent = 20
                    let titleLine = valid(text.paragraphRange(for: NSRange(location: marker.location, length: 0)))
                    storage.addAttribute(.paragraphStyle, value: paragraphStyle(titleContext), range: titleLine)
                } else {
                    hideMarker(marker)
                }
            }
            for child in node.children { styleBlock(child, inner) }

        case .list:
            for child in node.children { styleBlock(child, context) }

        case .listItem(let task):
            var inner = context
            inner.listDepth += 1
            inner.indent = context.indent + 24
            let markers = node.markers
            if let bullet = markers.first {
                let markerRange = markers.count > 1 ? NSUnionRange(bullet, markers[1]) : bullet
                let glyph: String
                var color: NSColor? = nil
                if let task = task {
                    glyph = task == .checked ? "☑" : "☐"
                    color = task == .checked ? .controlAccentColor : .secondaryLabelColor
                } else if let parent = node.parent, case .list(let ordered, _, _, _, _) = parent.kind, ordered {
                    glyph = source(bullet).trimmingCharacters(in: .whitespaces)
                } else {
                    glyph = ["•", "◦", "▪"][(inner.listDepth - 1) % 3]
                }
                hideMarker(markerRange)
                // Indentation before the marker on its own line
                let start = lineStart(of: bullet.location)
                if bullet.location > start,
                   text.substring(with: NSRange(location: start, length: bullet.location - start)).allSatisfy({ $0 == " " || $0 == "\t" }) {
                    hideMarker(NSRange(location: start, length: bullet.location - start))
                }
                let r = valid(markerRange)
                if r.length > 0 {
                    storage.addAttribute(.listMarker, value: ListMarkerInfo(text: glyph, indent: inner.indent, color: color), range: r)
                }
                // Continuation lines are indented to the item's content column in the source
                let contentColumn = bullet.location + bullet.length - lineStart(of: bullet.location)
                inner.hiddenIndentColumns = contentColumn
                hideContinuationIndent(in: node.range, maxColumns: contentColumn)
            }
            setParagraphStyle(paragraphStyle(inner), over: node.range)
            for (index, child) in node.children.enumerated() {
                var childContext = inner
                // A completed task's own text is dimmed; nested content keeps its colour
                if task == .checked && index == 0, case .paragraph = child.kind {
                    childContext.inline.color = .secondaryLabelColor
                }
                styleBlock(child, childContext)
            }

        case .codeBlock(let fenced, let info):
            let block = IndentedTextBlock()
            block.setFill(NSColor.textColor.withAlphaComponent(0.04), leftMargin: context.indent)
            block.setValue(100, type: .percentageValueType, for: .width)
            for edge: NSRectEdge in [.minX, .maxX, .minY, .maxY] {
                block.setBorderColor(NSColor.textColor.withAlphaComponent(0.12), for: edge)
            }
            block.setWidth(0.5, type: .absoluteValueType, for: .border)
            block.setWidth(3.0, type: .absoluteValueType, for: .border, edge: .minX)
            block.setWidth(8, type: .absoluteValueType, for: .padding)
            block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
            var inner = context
            inner.textBlocks.append(block)
            inner.indent = 0
            setParagraphStyle(paragraphStyle(inner, lineSpacing: 4), over: node.range)
            apply(InlineStyle(size: 14, mono: true, color: NSColor.labelColor.withAlphaComponent(0.85)), to: node.range)
            if fenced {
                for marker in node.markers { hideMarker(marker, collapseLine: true) }
                // Language badge, drawn at the top-right of the first visible line of the block
                if let opening = node.markers.first {
                    let firstContent = NSMaxRange(opening) + 1
                    let blockEnd = node.markers.count > 1 ? node.markers[1].location : NSMaxRange(node.range)
                    if firstContent < blockEnd, firstContent < text.length {
                        let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
                        let badge = CodeBadgeInfo(language: language)
                        storage.addAttribute(.codeBadge, value: badge, range: NSRange(location: firstContent, length: 1))
                        // Keep the first line's text clear of the badge
                        let firstLine = valid(text.paragraphRange(for: NSRange(location: firstContent, length: 0)))
                        if let style = (storage.attribute(.paragraphStyle, at: firstContent, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                            style.tailIndent = -(badge.width + 16)
                            storage.addAttribute(.paragraphStyle, value: style, range: firstLine)
                        }
                    }
                }
            } else {
                hideContinuationIndent(in: node.range, maxColumns: 4, includeFirstLine: true)
            }
            let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map { String($0).lowercased() }
            if language != "math" { highlightCode(in: node, language: language) }
            codeRanges.append(node.range)

        case .htmlBlock:
            setParagraphStyle(paragraphStyle(context), over: node.range)
            apply(InlineStyle(size: 14, mono: true, color: .secondaryLabelColor), to: node.range)
            codeRanges.append(node.range)

        case .thematicBreak:
            let block = NSTextBlock()
            block.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4)
            block.setValue(100, type: .percentageValueType, for: .width)
            block.setValue(1, type: .absoluteValueType, for: .height)
            var inner = context
            inner.textBlocks.append(block)
            setParagraphStyle(paragraphStyle(inner), over: node.range)
            let r = valid(node.range)
            if r.length > 0 {
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: r)
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 2), range: r)
            }

        case .table(let alignments):
            var headers: [String] = []
            var rows: [[String]] = []
            for section in node.children {
                switch section.kind {
                case .tableHead:
                    headers = section.firstChild?.children.map { source($0.range) } ?? []
                case .tableRow:
                    rows.append(section.children.map { source($0.range) })
                default:
                    break
                }
            }
            attachments.append(EditorAttachmentRequest(range: node.range, kind: .table(source: source(node.range), headers: headers, alignments: alignments, rows: rows)))

        case .footnoteDefinition:
            var inner = context
            inner.inline.size = 12
            inner.inline.color = .secondaryLabelColor
            if let marker = node.markers.first {
                apply(InlineStyle(size: 11, bold: true, color: .secondaryLabelColor), to: marker)
                hideMarker(NSRange(location: marker.location + 1, length: 1))   // the ^
            }
            hideContinuationIndent(in: node.range, maxColumns: 4)
            for child in node.children { styleBlock(child, inner) }

        case .linkReferenceDefinition:
            apply(InlineStyle(size: 12, color: .tertiaryLabelColor), to: node.range)

        default:
            for child in node.children { styleBlock(child, context) }
        }
    }

    // MARK: - Inlines

    private func styleInlines(_ node: MarkdownNode, _ style: InlineStyle) {
        let children = node.children
        let pairing = MarkdownInlineHTML.pairing(of: children)
        for (index, child) in children.enumerated() {
            if pairing.pairedTags.contains(index) {
                // Paired formatting tags are syntax, hidden like Markdown markers
                hideMarker(child.range)
                continue
            }
            var childStyle = style
            for html in pairing.styles[index] ?? [] { childStyle.apply(html) }
            styleInline(child, childStyle)
        }
    }

    private func styleInline(_ node: MarkdownNode, _ style: InlineStyle) {
        switch node.kind {
        case .text:
            apply(style, to: node.range)
            for marker in node.markers { hideMarker(marker) }   // escape backslashes
        case .softBreak:
            break
        case .hardBreak:
            // Hide the trailing spaces or backslash, never the newline itself
            for marker in node.markers {
                var r = marker
                while r.length > 0, [0x0A, 0x0D].contains(text.character(at: r.location + r.length - 1)) { r.length -= 1 }
                hideMarker(r)
            }
        case .code:
            var s = style
            s.mono = true
            if s.link == nil { s.color = .systemPurple }
            apply(s, to: node.range)
            for marker in node.markers { hideMarker(marker) }
            codeRanges.append(node.range)
        case .emphasis:
            var s = style
            s.italic = true
            for marker in node.markers { hideMarker(marker) }
            styleInlines(node, s)
        case .strong:
            var s = style
            s.bold = true
            for marker in node.markers { hideMarker(marker) }
            styleInlines(node, s)
        case .strikethrough:
            var s = style
            s.strike = true
            s.color = .secondaryLabelColor
            for marker in node.markers { hideMarker(marker) }
            styleInlines(node, s)
        case .link(let destination, _, _):
            var s = style
            s.color = .systemBlue
            s.link = Self.url(destination)
            for marker in node.markers { hideMarker(marker) }
            styleInlines(node, s)
        case .image(let destination, _):
            // Images inside tables are part of the table attachment
            if node.ancestors.contains(where: { if case .table = $0.kind { return true }; return false }) { return }
            attachments.append(EditorAttachmentRequest(range: node.range, kind: .image(alt: node.plainText, urlString: destination, rawMarkdown: source(node.range), width: nil)))
        case .htmlInline:
            if case .image(let src, let alt, let width) = InlineHTMLTag(node.literal).kind,
               !node.ancestors.contains(where: { if case .table = $0.kind { return true }; return false }) {
                attachments.append(EditorAttachmentRequest(range: node.range, kind: .image(alt: alt, urlString: src, rawMarkdown: source(node.range), width: width.map { CGFloat($0) })))
                return
            }
            var s = style
            s.color = .secondaryLabelColor
            apply(s, to: node.range)
            codeRanges.append(node.range)
        case .math:
            // TeX source in a distinct style; the $ delimiters stay visible but dim
            var s = style
            s.mono = true
            s.color = .systemTeal
            apply(s, to: node.range)
            for marker in node.markers { apply(InlineStyle(size: style.size, mono: true, color: .tertiaryLabelColor), to: marker) }
            codeRanges.append(node.range)
        case .footnoteReference:
            var s = style
            s.superscript = true
            s.color = .controlAccentColor
            apply(s, to: node.range)
            // Show the label only: hide "[^" and "]"
            hideMarker(NSRange(location: node.range.location, length: min(2, node.range.length)))
            if node.range.length > 2 {
                hideMarker(NSRange(location: node.range.location + node.range.length - 1, length: 1))
            }
        default:
            styleInlines(node, style)
        }
    }

    // MARK: - Code

    private func highlightCode(in node: MarkdownNode, language: String?) {
        guard let language = language else { return }
        let range = valid(node.range)
        var line = range.location
        let end = range.location + range.length
        while line < end {
            let lineRange = text.lineRange(for: NSRange(location: line, length: 0))
            var contentLength = lineRange.length
            if contentLength > 0 && text.character(at: lineRange.location + contentLength - 1) == 0x0A { contentLength -= 1 }
            let lineText = text.substring(with: NSRange(location: lineRange.location, length: contentLength))
            MarkdownCodeHighlighter.highlight(line: lineText, offset: lineRange.location, language: language, in: storage)
            if lineRange.length == 0 { break }
            line = lineRange.location + lineRange.length
        }
    }

    // MARK: - Lookups

    static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 20
        case 3: return 17
        case 4: return 15
        case 5: return 14
        default: return 13
        }
    }

    static func alertColor(_ type: AlertType) -> NSColor {
        switch type {
        case .note: return .systemBlue
        case .tip: return .systemGreen
        case .important: return .systemPurple
        case .warning: return .systemOrange
        case .caution: return .systemRed
        }
    }

    static func url(_ destination: String) -> URL? {
        URL(string: destination) ?? URL(string: MarkdownSyntax.normalizeURI(destination))
    }
}

/// Lightweight keyword / string / number / comment colouring for code block lines.
enum MarkdownCodeHighlighter {
    private static let keywordsByLanguage: [String: [String]] = [
        "javascript": ["func", "function", "let", "var", "const", "return", "class", "import", "if", "else", "for", "while", "in", "switch", "case", "break", "continue", "struct", "enum"],
        "swift": ["func", "function", "let", "var", "const", "return", "class", "import", "if", "else", "for", "while", "in", "switch", "case", "break", "continue", "struct", "enum"],
        "python": ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "in", "as", "try", "except", "lambda", "pass"],
        "css": ["body", "html", "div", "span", "p", "a", "img", "button", "input", "label", "form", "section", "header", "footer", "h1", "h2", "h3"],
        "bash": ["if", "then", "else", "elif", "fi", "for", "while", "in", "do", "done", "case", "esac", "function", "return", "local", "echo", "exit"],
        "sh": ["if", "then", "else", "elif", "fi", "for", "while", "in", "do", "done", "case", "esac", "function", "return", "local", "echo", "exit"],
    ]
    private static var keywordRegexes: [String: NSRegularExpression] = [:]
    private static let stringRegex = try! NSRegularExpression(pattern: "\"[^\"]*\"|'[^']*'")
    private static let numberRegex = try! NSRegularExpression(pattern: "\\b\\d+\\b")

    static func highlight(line: String, offset: Int, language: String?, in storage: NSTextStorage) {
        guard let lang = language?.lowercased() else { return }
        let full = NSRange(location: 0, length: storage.length)
        func color(_ range: NSRange, _ color: NSColor) {
            let r = NSIntersectionRange(NSRange(location: offset + range.location, length: range.length), full)
            if r.length > 0 { storage.addAttribute(.foregroundColor, value: color, range: r) }
        }
        let length = (line as NSString).length
        if ["python", "bash", "sh"].contains(lang), let hash = line.firstIndex(of: "#") {
            let start = line.utf16.distance(from: line.startIndex, to: hash)
            color(NSRange(location: start, length: length - start), .secondaryLabelColor)
            return
        }
        if ["javascript", "swift", "html", "css", "json"].contains(lang), line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            color(NSRange(location: 0, length: length), .secondaryLabelColor)
            return
        }
        let lineRange = NSRange(location: 0, length: length)
        if let words = keywordsByLanguage[lang] {
            let regex: NSRegularExpression
            if let cached = keywordRegexes[lang] {
                regex = cached
            } else {
                regex = try! NSRegularExpression(pattern: "\\b(" + words.joined(separator: "|") + ")\\b")
                keywordRegexes[lang] = regex
            }
            for m in regex.matches(in: line, options: [], range: lineRange) { color(m.range, .systemPink) }
        }
        for m in stringRegex.matches(in: line, options: [], range: lineRange) { color(m.range, .systemGreen) }
        for m in numberRegex.matches(in: line, options: [], range: lineRange) { color(m.range, .systemOrange) }
    }
}
