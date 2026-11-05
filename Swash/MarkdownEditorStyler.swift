//
//  MarkdownEditorStyler.swift
//  Swash
//
//  Styles the Edit Text (WYSIWYG) text storage from the shared Markdown AST: block layout,
//  inline formatting that composes (bold inside a heading keeps the heading size), hidden
//  syntax markers taken from exact node ranges, list markers by nesting depth, and
//  attachment requests for tables and images.
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif
import PixerateMarkdown

#if os(macOS)
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
#else
/// iOS has no NSTextBlock. Quotes, alerts, code blocks and rules carry their box as this attribute
/// (outermost first) over their paragraphs; the paragraph indents leave room for the border and
/// padding, and the layout manager paints the box behind the text.
final class BlockDecoration {
    enum Kind { case box, rule }
    let kind: Kind
    let fill: UIColor?
    let borderColor: UIColor?
    /// Border on every edge (0 for none) and on the left edge.
    let borderWidth: CGFloat
    let leftBorderWidth: CGFloat
    let padding: CGFloat
    /// Box edges, measured in from the text container's line-fragment edges.
    let left: CGFloat
    let right: CGFloat

    init(kind: Kind, fill: UIColor?, borderColor: UIColor?, borderWidth: CGFloat, leftBorderWidth: CGFloat, padding: CGFloat, left: CGFloat, right: CGFloat) {
        self.kind = kind
        self.fill = fill
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.leftBorderWidth = leftBorderWidth
        self.padding = padding
        self.left = left
        self.right = right
    }
}

extension NSAttributedString.Key {
    /// `[BlockDecoration]` over the paragraphs of a quote, alert, code block or rule (iOS).
    static let blockDecorations = NSAttributedString.Key("SwashBlockDecorationsKey")
}
#endif

/// Value of `.footnoteLink`.
struct FootnoteLink: Hashable {
    let label: String
    let isDefinition: Bool
}

extension NSAttributedString.Key {
    /// Marks the first character of a fenced code block; the layout manager draws its language badge.
    static let codeBadge = NSAttributedString.Key("SwashCodeBadgeKey")
    /// Marks the first character of an alert title; the layout manager draws the alert's icon before it.
    static let alertIcon = NSAttributedString.Key("SwashAlertIconKey")
    /// Marks a footnote reference or a definition's `[^label]:` marker; clicking it jumps to the other.
    static let footnoteLink = NSAttributedString.Key("SwashFootnoteLinkKey")
    /// Marks the last character of a display-math or Mermaid block; the layout manager draws the
    /// rendered formula or diagram in the paragraph spacing reserved below that line.
    static let richPreview = NSAttributedString.Key("SwashRichPreviewKey")
}

/// A rendered formula or diagram shown under its source in Edit Text.
struct RichPreviewInfo {
    let image: PlatformImage
    /// Display size (the image scaled down to fit the editor width).
    let size: CGSize
    /// Below 1 while a newer render is pending or when the current source fails to render.
    let alpha: CGFloat
    let error: String?
    
    static let spacing: CGFloat = 10
    static let errorHeight: CGFloat = 16
    static let errorAttributes: [NSAttributedString.Key: Any] = [
        .font: PlatformFont.systemFont(ofSize: 11),
        .foregroundColor: PlatformColor.systemOrange,
    ]
    
    /// Paragraph spacing reserved below the block's last line.
    var reservedHeight: CGFloat { size.height + Self.spacing * 2 + (error == nil ? 0 : Self.errorHeight) }
}

struct AlertIconInfo {
    let type: AlertType
    let color: PlatformColor
    
    var symbolName: String {
        switch type {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "octagon.fill"
        }
    }
    
    var image: PlatformImage? {
        #if os(macOS)
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold).applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: type.title)?.withSymbolConfiguration(configuration)
        #else
        let configuration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold).applying(UIImage.SymbolConfiguration(paletteColors: [color]))
        return UIImage(systemName: symbolName, withConfiguration: configuration)
        #endif
    }
}

struct CodeBadgeInfo {
    let language: String?
    var title: String { (language?.isEmpty == false ? language! : "plain").uppercased() }
    
    static let attributes: [NSAttributedString.Key: Any] = [
        .font: PlatformFont.systemFont(ofSize: 10, weight: .semibold),
        .foregroundColor: PlatformColor.tertiaryTextColor,
        .kern: 0.6,
    ]
    
    var width: CGFloat { (title as NSString).size(withAttributes: Self.attributes).width + 4 }
    
    /// Badge rect in text-container coordinates for the line fragment holding the block's first line.
    func rect(in lineRect: CGRect) -> CGRect {
        let size = (title as NSString).size(withAttributes: Self.attributes)
        return CGRect(x: lineRect.maxX - size.width - 10, y: lineRect.minY + 1, width: size.width + 4, height: size.height + 2)
    }
}

/// A table, image or diagram the editor should collapse into an attachment.
struct EditorAttachmentRequest {
    enum Kind {
        case table(source: String, headers: [String], alignments: [TableAlignment], rows: [[String]])
        case image(alt: String, urlString: String, rawMarkdown: String, width: CGFloat?)
        case mermaid(source: String, rawMarkdown: String)
    }
    let range: NSRange
    let kind: Kind
}

final class MarkdownEditorStyler {
    /// Body text size at the default typography (see `EditorTypography`).
    static let baseFontSize: CGFloat = EditorTypography.defaultTextSize
    /// Text sizes are designed for the Mac; iOS reads at a larger size (17 pt body text).
    #if os(macOS)
    static let fontScale: CGFloat = 1
    #else
    static let fontScale: CGFloat = 17.0 / 14.0
    #endif

    private struct InlineStyle {
        var size: CGFloat = MarkdownEditorStyler.baseFontSize
        var bold = false
        var italic = false
        var mono = false
        var color: PlatformColor? = nil
        var strike = false
        var link: URL? = nil
        var superscript = false
        var subscriptText = false
        var underline = false
        var highlight = false
        var keyboard = false
        var smallText = false
        
        /// Applies an enclosing inline HTML tag (<kbd>, <sub>, <mark>…).
        mutating func apply(_ html: InlineHTMLStyle, accent: PlatformColor) {
            switch html {
            case .keyboard: keyboard = true; mono = true
            case .lowered: subscriptText = true
            case .raised: superscript = true
            case .highlight: highlight = true
            case .underline: underline = true
            case .strikethrough: strike = true; color = .secondaryTextColor
            case .bold: bold = true
            case .italic: italic = true
            case .small: smallText = true
            case .code: mono = true; if link == nil { color = accent }
            }
        }
    }
    
    private struct BlockContext {
        var indent: CGFloat = 0
        var listDepth = 0
        var isTightList = false
        #if os(macOS)
        var textBlocks: [NSTextBlock] = []
        #else
        var decorations: [BlockDecoration] = []
        /// Left and right insets of the innermost box's content (its edges, borders and padding).
        var boxLeft: CGFloat = 0
        var boxRight: CGFloat = 0
        #endif
        var inline = InlineStyle()
        /// Columns of leading indentation that belong to enclosing list items on continuation lines
        var hiddenIndentColumns = 0
    }

    private let storage: NSTextStorage
    /// The raw Markdown (what the AST ranges index). The storage may differ outside the region being
    /// styled (collapsed attachments), so writes go to `raw location - storageShift`.
    private let text: NSString
    private let storageShift: Int
    private let document: MarkdownDocument
    /// Font family, text size and accent colours (the defaults give the original styling).
    var typography = EditorTypography()
    private var hidden: [NSRange] = []
    private(set) var attachments: [EditorAttachmentRequest] = []
    /// Code blocks, code spans, HTML and front matter (raw offsets), excluded from spellchecking.
    private(set) var codeRanges: [NSRange] = []
    
    // Rendered math and Mermaid (KaTeX / mermaid.js via RichContentRenderer)
    /// Whether rendered previews use the dark appearance.
    var richPreviewDark = false
    /// Widest a rendered preview is drawn; wider ones are scaled down.
    var richPreviewMaxWidth: CGFloat = 640
    /// Last good render per block (raw location of the block): shown dimmed while the edited source
    /// re-renders or fails, so the layout does not jump on every keystroke. Read and updated by the pass.
    var richPreviewMemory: [Int: RichContentRenderer.Rendered] = [:]
    /// Renders requested by this pass that were not ready: (raw block location, request).
    private(set) var pendingRichPreviews: [(location: Int, request: RichContentRenderer.Request)] = []
    /// Identifies the editor, so a block's newer render request replaces its older queued one.
    var richPreviewOwner: ObjectIdentifier? = nil

    typealias RichPreviewSlot = RichContentRenderer.RichPreviewSlot

    /// `storageShift`: raw offset minus storage offset for the region being styled (0 when the storage
    /// holds the raw text throughout).
    init(storage: NSTextStorage, document: MarkdownDocument, storageShift: Int = 0) {
        self.storage = storage
        self.text = document.source as NSString
        self.storageShift = storageShift
        self.document = document
    }
    
    /// Applies all styling. The caller has already reset attributes and wraps this in begin/endEditing.
    func style() {
        style(blocks: document.root.children)
    }
    
    /// Styles only the given top-level blocks (incremental restyling).
    func style(blocks: [MarkdownNode]) {
        var context = BlockContext()
        context.inline.size = typography.textSize
        for block in blocks {
            styleBlock(block, context)
        }
        for range in hidden {
            hide(range)
        }
        #if os(iOS)
        padBoxes()
        #endif
    }
    
    /// Code-like ranges of the whole document (raw offsets), sorted: code, HTML, math and front matter
    /// are excluded from spellchecking.
    static func spellcheckExclusions(in document: MarkdownDocument) -> [NSRange] {
        var ranges: [NSRange] = []
        document.root.walk { node in
            switch node.kind {
            case .codeBlock, .htmlBlock, .frontMatter, .code, .htmlInline, .math: ranges.append(node.range)
            default: break
            }
        }
        return ranges.sorted { $0.location < $1.location }
    }

    // MARK: - Attribute helpers

    private var fullRange: NSRange { NSRange(location: 0, length: storage.length) }
    
    /// Reserves space below a display-math or Mermaid block's last line for its rendering, which the
    /// layout manager draws there; requests the render when it is not cached yet.
    private func addRichPreview(_ node: MarkdownNode, kind: RichContentRenderer.Kind) {
        guard RichContentRenderer.isAvailable, !node.literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // The block's content: between the opening and closing fences
        guard let opening = node.markers.first else { return }
        let contentStart = min(NSMaxRange(opening) + 1, NSMaxRange(node.range))
        let contentEnd = node.markers.count > 1 ? node.markers[node.markers.count - 1].location : NSMaxRange(node.range)
        var last = contentEnd - 1
        while last >= contentStart, last < text.length, text.character(at: last) == 0x0A || text.character(at: last) == 0x0D { last -= 1 }
        guard last >= contentStart, last < text.length else { return }
        
        let fontSize: CGFloat = typography.scaled(kind == .mermaid ? 13 : 16)
        let request = RichContentRenderer.Request(kind: kind, source: node.literal, dark: richPreviewDark, fontSize: fontSize)
        let location = node.range.location
        var image: RichContentRenderer.Rendered? = nil
        var alpha: CGFloat = 1
        var error: String? = nil
        switch RichContentRenderer.cachedOrRequest(request, owner: richPreviewOwner.map { RichPreviewSlot(owner: $0, location: location) }) {
        case .rendered(let rendered)?:
            image = rendered
            richPreviewMemory[location] = rendered
        case .failed(let message)?:
            image = richPreviewMemory[location]
            alpha = 0.35
            error = message.components(separatedBy: .newlines).first ?? message
        case nil:
            image = richPreviewMemory[location]
            alpha = 0.6
            pendingRichPreviews.append((location, request))
        }
        guard image != nil || error != nil else { return }
        
        var size = image?.image.size ?? .zero
        if size.width > richPreviewMaxWidth, size.width > 0 {
            size = CGSize(width: richPreviewMaxWidth, height: (size.height * richPreviewMaxWidth / size.width).rounded())
        }
        let info = RichPreviewInfo(image: image?.image ?? PlatformImage(), size: image == nil ? .zero : size, alpha: alpha, error: error)
        let anchor = valid(NSRange(location: last, length: 1))
        guard anchor.length > 0 else { return }
        storage.addAttribute(.richPreview, value: info, range: anchor)
        let line = valid(text.paragraphRange(for: NSRange(location: last, length: 0)))
        if let style = (storage.attribute(.paragraphStyle, at: anchor.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
            style.paragraphSpacing += info.reservedHeight
            storage.addAttribute(.paragraphStyle, value: style, range: line)
        }
    }
    
    /// Maps a raw range to the storage, clipped to the storage bounds.
    private func valid(_ range: NSRange) -> NSRange {
        NSIntersectionRange(NSRange(location: range.location - storageShift, length: range.length), fullRange)
    }
    
    /// Clips a raw range to the raw text.
    private func rawClamp(_ range: NSRange) -> NSRange {
        NSIntersectionRange(range, NSRange(location: 0, length: text.length))
    }

    private func hide(_ range: NSRange) {
        let r = valid(range)
        guard r.length > 0 else { return }
        storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: 0.01), range: r)
        storage.addAttribute(.foregroundColor, value: PlatformColor.clear, range: r)
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

    private func font(for style: InlineStyle) -> PlatformFont {
        var font: PlatformFont
        var size = style.size * Self.fontScale
        if style.smallText { size *= 0.85 }
        if style.subscriptText { size *= 0.75 }
        if style.keyboard { size -= 1 }
        if style.mono {
            font = PlatformFont.monospacedSystemFont(ofSize: max(1, size - 1), weight: style.bold ? .bold : .regular)
        } else {
            font = typography.font(ofSize: size, weight: style.bold ? .bold : .regular)
        }
        if style.italic {
            font = PlatformFont.italicVariant(of: font)
        }
        if style.superscript {
            font = typography.font(ofSize: max(9, style.size - 4) * Self.fontScale, weight: .semibold)
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
            storage.addAttribute(.backgroundColor, value: PlatformColor.systemYellow.withAlphaComponent(0.35), range: r)
        }
        if style.keyboard {
            storage.addAttribute(.backgroundColor, value: PlatformColor.textColor.withAlphaComponent(0.08), range: r)
        }
    }

    private func paragraphStyle(
        _ context: BlockContext,
        lineSpacing: CGFloat = 5,
        paragraphSpacing: CGFloat = 0,
        paragraphSpacingBefore: CGFloat = 0
    ) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        #if os(macOS)
        p.headIndent = context.indent
        p.firstLineHeadIndent = context.indent
        p.textBlocks = context.textBlocks
        #else
        p.headIndent = context.boxLeft + context.indent
        p.firstLineHeadIndent = context.boxLeft + context.indent
        if context.boxRight > 0 { p.tailIndent = -context.boxRight }
        #endif
        p.lineSpacing = lineSpacing
        p.paragraphSpacing = paragraphSpacing
        p.paragraphSpacingBefore = paragraphSpacingBefore
        return p
    }

    private func setParagraphStyle(
        _ context: BlockContext,
        lineSpacing: CGFloat = 5,
        paragraphSpacing: CGFloat = 0,
        paragraphSpacingBefore: CGFloat = 0,
        over range: NSRange
    ) {
        // Paragraph attributes must cover whole paragraphs, including the trailing newline
        let r = valid(text.paragraphRange(for: rawClamp(range)))
        guard r.length > 0 else { return }
        let style = paragraphStyle(context, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing, paragraphSpacingBefore: paragraphSpacingBefore)
        storage.addAttribute(.paragraphStyle, value: style, range: r)
        #if os(iOS)
        if !context.decorations.isEmpty {
            storage.addAttribute(.blockDecorations, value: context.decorations, range: r)
        }
        #endif
    }

    // MARK: - Block boxes

    /// Starts a bordered, padded box (quote, alert, code block) inside `context`, indented by the
    /// context's own indentation.
    private func pushBox(_ context: inout BlockContext, over range: NSRange, fill: PlatformColor, borderColor: PlatformColor,
                         borderWidth: CGFloat, leftBorderWidth: CGFloat, padding: CGFloat, leftPadding: CGFloat) {
        #if os(macOS)
        let block = IndentedTextBlock()
        block.setFill(fill, leftMargin: context.indent)
        block.setValue(100, type: .percentageValueType, for: .width)
        if borderWidth > 0 {
            for edge: NSRectEdge in [.minX, .maxX, .minY, .maxY] {
                block.setBorderColor(borderColor, for: edge)
            }
            block.setWidth(borderWidth, type: .absoluteValueType, for: .border)
        } else {
            block.setBorderColor(borderColor, for: .minX)
        }
        block.setWidth(leftBorderWidth, type: .absoluteValueType, for: .border, edge: .minX)
        block.setWidth(padding, type: .absoluteValueType, for: .padding)
        block.setWidth(leftPadding, type: .absoluteValueType, for: .padding, edge: .minX)
        context.textBlocks.append(block)
        #else
        let left = context.boxLeft + context.indent
        let decoration = BlockDecoration(kind: .box, fill: fill, borderColor: borderColor, borderWidth: borderWidth,
                                         leftBorderWidth: leftBorderWidth, padding: padding, left: left, right: context.boxRight)
        context.decorations.append(decoration)
        context.boxLeft = left + leftBorderWidth + leftPadding
        context.boxRight += borderWidth + padding
        boxes.append((decoration, range))
        #endif
        context.indent = 0
    }

    /// A horizontal rule across the context's width.
    private func pushRule(_ context: inout BlockContext, over range: NSRange) {
        #if os(macOS)
        let block = NSTextBlock()
        block.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.25)
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setValue(1, type: .absoluteValueType, for: .height)
        context.textBlocks.append(block)
        #else
        let decoration = BlockDecoration(kind: .rule, fill: UIColor.separatorLineColor.withAlphaComponent(0.25), borderColor: nil, borderWidth: 0,
                                         leftBorderWidth: 0, padding: 6, left: context.boxLeft + context.indent, right: context.boxRight)
        context.decorations.append(decoration)
        boxes.append((decoration, range))
        #endif
    }

    #if os(iOS)
    /// Boxes started by this pass and the raw ranges they cover.
    private var boxes: [(decoration: BlockDecoration, range: NSRange)] = []

    /// NSTextBlock pads a box above its first line and below its last; here that space is paragraph
    /// spacing, which the layout manager includes when it paints the box.
    private func padBoxes() {
        for (decoration, range) in boxes {
            let r = valid(text.paragraphRange(for: rawClamp(range)))
            guard r.length > 0 else { continue }
            let first = (storage.string as NSString).paragraphRange(for: NSRange(location: r.location, length: 0))
            let last = (storage.string as NSString).paragraphRange(for: NSRange(location: max(r.location, NSMaxRange(r) - 1), length: 0))
            adjustParagraphStyle(in: first) { $0.paragraphSpacingBefore += decoration.padding }
            adjustParagraphStyle(in: last) { $0.paragraphSpacing += decoration.padding }
        }
    }

    private func adjustParagraphStyle(in range: NSRange, _ change: (NSMutableParagraphStyle) -> Void) {
        let r = NSIntersectionRange(range, fullRange)
        guard r.length > 0 else { return }
        let style = ((storage.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        change(style)
        storage.addAttribute(.paragraphStyle, value: style, range: r)
    }
    #endif

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
        text.substring(with: rawClamp(range))
    }

    // MARK: - Blocks

    private func styleBlock(_ node: MarkdownNode, _ context: BlockContext) {
        switch node.kind {
        case .document:
            for child in node.children { styleBlock(child, context) }

        case .frontMatter:
            setParagraphStyle(context, lineSpacing: 3, paragraphSpacing: 6, over: node.range)
            apply(InlineStyle(size: typography.scaled(12), mono: true, color: .secondaryTextColor), to: node.range)
            for marker in node.markers {
                apply(InlineStyle(size: typography.scaled(12), mono: true, color: .tertiaryTextColor), to: marker)
            }
            codeRanges.append(node.range)

        case .paragraph:
            let inList = context.listDepth > 0
            let lineSpacing: CGFloat = 5
            let paragraphSpacing: CGFloat = inList ? (context.isTightList ? 6 : 4) : 4
            setParagraphStyle(context, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing, over: node.range)
            apply(context.inline, to: node.range)
            hideContinuationIndent(in: node.range, maxColumns: nil)
            styleInlines(node, context.inline)

        case .heading(let level, let setext):
            var inline = context.inline
            inline.size = typography.scaled(Self.headingSize(level))
            inline.bold = true
            let spacingBefore: CGFloat
            let spacingAfter: CGFloat
            let lineSpacing: CGFloat
            switch level {
            case 1:
                spacingBefore = 18
                spacingAfter = 8
                lineSpacing = 4
            case 2:
                spacingBefore = 14
                spacingAfter = 6
                lineSpacing = 4
            case 3:
                spacingBefore = 10
                spacingAfter = 4
                lineSpacing = 3
            default:
                spacingBefore = 8
                spacingAfter = 4
                lineSpacing = 3
            }
            setParagraphStyle(context, lineSpacing: lineSpacing, paragraphSpacing: spacingAfter, paragraphSpacingBefore: spacingBefore, over: node.range)
            apply(inline, to: node.range)
            for marker in node.markers {
                hideMarker(marker, collapseLine: setext)
            }
            hideContinuationIndent(in: node.range, maxColumns: nil)
            styleInlines(node, inline)

        case .blockQuote, .alert:
            var inner = context
            let color: PlatformColor
            if case .alert(let type) = node.kind {
                color = Self.alertColor(type)
            } else {
                color = typography.accentColor
                inner.inline.color = .secondaryTextColor
                inner.inline.italic = true
            }
            pushBox(&inner, over: node.range, fill: color.withAlphaComponent(0.07), borderColor: color,
                    borderWidth: 0, leftBorderWidth: 3, padding: 6, leftPadding: 10)
            setParagraphStyle(inner, lineSpacing: 5, paragraphSpacing: 6, paragraphSpacingBefore: 4, over: node.range)
            apply(inner.inline, to: node.range)
            // Quote markers, and the alert's [!TYPE] marker shown as a coloured title
            for marker in node.markers {
                if case .alert(let type) = node.kind, source(marker).hasPrefix("[!") {
                    apply(InlineStyle(size: typography.scaled(13), bold: true, color: color), to: marker)
                    hideMarker(NSRange(location: marker.location, length: 2))
                    hideMarker(NSRange(location: marker.location + marker.length - 1, length: 1))
                    // Icon before the title, as in the Preview: indent the title line to make room
                    let iconRange = valid(NSRange(location: marker.location + 2, length: 1))
                    if iconRange.length > 0 { storage.addAttribute(.alertIcon, value: AlertIconInfo(type: type, color: color), range: iconRange) }
                    var titleContext = inner
                    titleContext.indent = 20
                    let titleLine = valid(text.paragraphRange(for: NSRange(location: marker.location, length: 0)))
                    storage.addAttribute(.paragraphStyle, value: paragraphStyle(titleContext, lineSpacing: 4, paragraphSpacing: 4), range: titleLine)
                } else {
                    hideMarker(marker)
                }
            }
            for child in node.children { styleBlock(child, inner) }

        case .list(_, _, _, _, let tight):
            var listContext = context
            listContext.isTightList = tight
            for child in node.children { styleBlock(child, listContext) }

        case .listItem(let task):
            var inner = context
            inner.listDepth += 1
            inner.indent = context.indent + 24
            let markers = node.markers
            if let bullet = markers.first {
                let markerRange = markers.count > 1 ? NSUnionRange(bullet, markers[1]) : bullet
                let glyph: String
                var color: PlatformColor? = nil
                if let task = task {
                    glyph = task == .checked ? "☑" : "☐"
                    color = task == .checked ? typography.accentColor : .secondaryTextColor
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
            let itemSpacing: CGFloat = inner.isTightList ? 6 : 4
            setParagraphStyle(inner, lineSpacing: 5, paragraphSpacing: itemSpacing, over: node.range)
            for (index, child) in node.children.enumerated() {
                var childContext = inner
                // A completed task's own text is dimmed; nested content keeps its colour
                if task == .checked && index == 0, case .paragraph = child.kind {
                    childContext.inline.color = .secondaryTextColor
                }
                styleBlock(child, childContext)
            }

        case .codeBlock(let fenced, let info):
            let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map { String($0).lowercased() }
            if language == "mermaid" {
                setParagraphStyle(context, lineSpacing: 0, paragraphSpacing: 8, paragraphSpacingBefore: 8, over: node.range)
                attachments.append(EditorAttachmentRequest(range: node.range, kind: .mermaid(source: node.literal, rawMarkdown: source(node.range))))
                codeRanges.append(node.range)
                return
            }
            var inner = context
            pushBox(&inner, over: node.range, fill: PlatformColor.textColor.withAlphaComponent(0.04), borderColor: PlatformColor.textColor.withAlphaComponent(0.12),
                    borderWidth: 0.5, leftBorderWidth: 3, padding: 8, leftPadding: 12)
            setParagraphStyle(inner, lineSpacing: 4, paragraphSpacing: 6, paragraphSpacingBefore: 4, over: node.range)
            apply(InlineStyle(size: typography.scaled(14), mono: true, color: PlatformColor.primaryTextColor.withAlphaComponent(0.85)), to: node.range)
            if fenced {
                for marker in node.markers { hideMarker(marker, collapseLine: true) }
                // Language badge, drawn at the top-right of the first visible line of the block
                if let opening = node.markers.first {
                    let firstContent = NSMaxRange(opening) + 1
                    let blockEnd = node.markers.count > 1 ? node.markers[1].location : NSMaxRange(node.range)
                    if firstContent < blockEnd, firstContent < text.length {
                        let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
                        let badge = CodeBadgeInfo(language: language)
                        let badgeRange = valid(NSRange(location: firstContent, length: 1))
                        if badgeRange.length > 0 { storage.addAttribute(.codeBadge, value: badge, range: badgeRange) }
                        // Keep the first line's text clear of the badge
                        let firstLine = valid(text.paragraphRange(for: NSRange(location: firstContent, length: 0)))
                        if badgeRange.length > 0,
                           let style = (storage.attribute(.paragraphStyle, at: badgeRange.location, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                            style.tailIndent -= badge.width + 16
                            storage.addAttribute(.paragraphStyle, value: style, range: firstLine)
                        }
                    }
                }
            } else {
                hideContinuationIndent(in: node.range, maxColumns: 4, includeFirstLine: true)
            }
            if language != "math" { highlightCode(in: node, language: language) }
            if language == "math" { addRichPreview(node, kind: .displayMath) }
            codeRanges.append(node.range)

        case .htmlBlock:
            setParagraphStyle(context, lineSpacing: 4, paragraphSpacing: 4, over: node.range)
            // A line holding just an <img> tag (what the image menu writes for a resized image) is an image
            if case .image(let src, let alt, let width) = InlineHTMLTag(node.literal.trimmingCharacters(in: .whitespacesAndNewlines)).kind {
                attachments.append(EditorAttachmentRequest(range: node.range, kind: .image(alt: alt, urlString: src, rawMarkdown: source(node.range), width: width.map { CGFloat($0) })))
                break
            }
            apply(InlineStyle(size: typography.scaled(14), mono: true, color: .secondaryTextColor), to: node.range)
            codeRanges.append(node.range)

        case .thematicBreak:
            var inner = context
            pushRule(&inner, over: node.range)
            setParagraphStyle(inner, lineSpacing: 0, paragraphSpacing: 0, paragraphSpacingBefore: 0, over: node.range)
            let r = valid(node.range)
            if r.length > 0 {
                storage.addAttribute(.foregroundColor, value: PlatformColor.clear, range: r)
                storage.addAttribute(.font, value: PlatformFont.systemFont(ofSize: 2), range: r)
            }

        case .table(let alignments):
            setParagraphStyle(context, lineSpacing: 0, paragraphSpacing: 8, paragraphSpacingBefore: 8, over: node.range)
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
            inner.inline.size = typography.scaled(12)
            inner.inline.color = .secondaryTextColor
            if let marker = node.markers.first {
                apply(InlineStyle(size: typography.scaled(11), bold: true, color: .secondaryTextColor), to: marker)
                hideMarker(NSRange(location: marker.location + 1, length: 1))   // the ^
                if case .footnoteDefinition(let label) = node.kind {
                    let r = valid(marker)
                    if r.length > 0 { storage.addAttribute(.footnoteLink, value: FootnoteLink(label: label, isDefinition: true), range: r) }
                }
            }
            hideContinuationIndent(in: node.range, maxColumns: 4)
            setParagraphStyle(inner, lineSpacing: 4, paragraphSpacing: 4, over: node.range)
            for child in node.children { styleBlock(child, inner) }

        case .linkReferenceDefinition:
            setParagraphStyle(context, lineSpacing: 3, paragraphSpacing: 3, over: node.range)
            apply(InlineStyle(size: typography.scaled(12), color: .tertiaryTextColor), to: node.range)

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
            for html in pairing.styles[index] ?? [] { childStyle.apply(html, accent: typography.accentColor) }
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
            if s.link == nil { s.color = typography.accentColor }
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
            s.color = .secondaryTextColor
            for marker in node.markers { hideMarker(marker) }
            styleInlines(node, s)
        case .link(let destination, _, _):
            var s = style
            s.color = typography.linkColor
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
            s.color = .secondaryTextColor
            apply(s, to: node.range)
            codeRanges.append(node.range)
        case .math:
            // TeX source in a distinct style; the $ delimiters stay visible but dim
            var s = style
            s.mono = true
            s.color = .systemTeal
            apply(s, to: node.range)
            for marker in node.markers { apply(InlineStyle(size: style.size, mono: true, color: .tertiaryTextColor), to: marker) }
            codeRanges.append(node.range)
        case .footnoteReference(let label):
            var s = style
            s.superscript = true
            s.color = typography.accentColor
            apply(s, to: node.range)
            let linkRange = valid(node.range)
            if linkRange.length > 0 { storage.addAttribute(.footnoteLink, value: FootnoteLink(label: label, isDefinition: false), range: linkRange) }
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
        MarkdownCodeHighlighter.highlight(block: node, language: language, source: text) { range, color in
            let r = valid(range)
            if r.length > 0 { storage.addAttribute(.foregroundColor, value: color, range: r) }
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

    static func alertColor(_ type: AlertType) -> PlatformColor {
        switch type {
        case .note: return .systemBlue
        case .tip: return .systemGreen
        case .important: return .systemPurple
        case .warning: return .systemOrange
        case .caution: return .systemRed
        }
    }

    static func url(_ destination: String) -> URL? {
        MarkdownSyntax.url(destination)
    }
}
