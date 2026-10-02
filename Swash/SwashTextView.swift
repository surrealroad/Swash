//
//  SwashTextView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import AppKit

func logDebug(_ message: String) {
    // No-op in production. Diagnostics disabled.
}

extension NSAttributedString.Key {
    static let listMarker = NSAttributedString.Key("SwashListMarkerKey")
}

extension Notification.Name {
    static let cellSelectionDidChange = Notification.Name("cellSelectionDidChange")
    static let removeCurrentTable = Notification.Name("removeCurrentTable")
}

/// The markdown source an attachment stands in for, or nil for non-Swash attachments.
func swashRawMarkdown(for attachment: Any?) -> String? {
    if let table = attachment as? TableTextAttachment { return table.rawMarkdown }
    if let image = attachment as? ImageTextAttachment { return image.rawMarkdown }
    return nil
}

/// Maps between text-storage offsets (where each table/image is a single attachment character)
/// and raw-markdown offsets (where it is its full source). All public selection ranges and all
/// edits coming from SwiftUI are expressed in raw-markdown offsets.
struct AttachmentOffsetMap {
    /// Storage location of each attachment and the UTF-16 length of the markdown it replaces, ascending.
    private(set) var spans: [(storage: Int, rawLength: Int)] = []

    static let identity = AttachmentOffsetMap()

    init() {}

    init(storage: NSAttributedString) {
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            if let raw = swashRawMarkdown(for: value) {
                for i in 0..<range.length {
                    spans.append((storage: range.location + i, rawLength: (raw as NSString).length))
                }
            }
        }
    }

    func rawLocation(forStorage location: Int) -> Int {
        var delta = 0
        for span in spans {
            guard span.storage < location else { break }
            delta += span.rawLength - 1
        }
        return location + delta
    }

    func rawRange(forStorage range: NSRange) -> NSRange {
        let start = rawLocation(forStorage: range.location)
        let end = rawLocation(forStorage: range.location + range.length)
        return NSRange(location: start, length: end - start)
    }

    /// A raw location inside an attachment's source snaps to the attachment's start (or end when `roundUp`).
    func storageLocation(forRaw location: Int, roundUp: Bool) -> Int {
        var delta = 0
        for span in spans {
            let rawStart = span.storage + delta
            if location <= rawStart { break }
            if location < rawStart + span.rawLength {
                return roundUp ? span.storage + 1 : span.storage
            }
            delta += span.rawLength - 1
        }
        return location - delta
    }

    func storageRange(forRaw range: NSRange) -> NSRange {
        let start = storageLocation(forRaw: range.location, roundUp: false)
        let end = storageLocation(forRaw: range.location + range.length, roundUp: range.length > 0)
        return NSRange(location: start, length: max(0, end - start))
    }
}

/// Lets SwiftUI views apply document edits through the live text view, so they are undoable and
/// keep the editor's selection, scroll position and styling intact.
final class SwashEditorController {
    weak var textView: NSTextView?
    weak var coordinator: SwashTextView.Coordinator?
    private var cachedFormatting: MarkdownFormatting?
    
    /// Parsed formatting state for `text`, reused until the text changes.
    func formatting(for text: String) -> MarkdownFormatting {
        if let cached = cachedFormatting, cached.text == text { return cached }
        let formatting = MarkdownFormatting(text: text)
        cachedFormatting = formatting
        return formatting
    }

    /// The live editor selection in raw-markdown offsets (the published binding omits plain carets).
    var currentRawSelection: NSRange? {
        guard let textView = textView, let coordinator = coordinator else { return nil }
        return coordinator.rawRange(forStorage: textView.selectedRange(), in: textView)
    }
    
    /// Applies `newText` as a minimal edit to the live editor. Returns false when no editor is attached,
    /// in which case the caller should assign the document text directly.
    @discardableResult
    func apply(newText: String, selection: NSRange?, actionName: String) -> Bool {
        guard let textView = textView, let coordinator = coordinator, textView.window != nil else { return false }
        coordinator.applyEdit(in: textView, newRawText: newText, rawSelection: selection, actionName: actionName)
        return true
    }
}

struct ListMarkerInfo {
    let text: String
    let indent: CGFloat
    var color: NSColor? = nil
}

final class SwashLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        
        guard let textStorage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        
        textStorage.enumerateAttribute(.listMarker, in: charRange, options: []) { value, range, _ in
            if let markerInfo = value as? ListMarkerInfo {
                let glyphRange = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let lineRect = lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                
                let font = NSFont.systemFont(ofSize: 13, weight: .regular)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: markerInfo.color ?? NSColor.secondaryLabelColor
                ]
                
                let markerSize = (markerInfo.text as NSString).size(withAttributes: attrs)
                // Position the marker just left of where the item's text actually starts, so it also
                // lines up inside quotes, alerts and other text blocks with their own padding
                let contentGlyph = min(glyphRange.location + glyphRange.length, max(0, numberOfGlyphs - 1))
                let contentX = lineRect.origin.x + location(forGlyphAt: contentGlyph).x
                let x = origin.x + (contentX > 0 ? contentX : markerInfo.indent) - markerSize.width - 10
                let y = origin.y + lineRect.origin.y + (lineRect.height - markerSize.height) / 2
                
                let drawRect = CGRect(x: x, y: y, width: markerSize.width + 4, height: markerSize.height)
                (markerInfo.text as NSString).draw(in: drawRect, withAttributes: attrs)
            }
        }
    }
}

class SwashNSTextView: NSTextView {
    var isStyled: Bool = true
    var flavor: MarkdownFlavor = .github
    /// Formatting shortcuts (⌘B, ⌘I, …), handled here so they take precedence over menu key equivalents.
    var onFormatCommand: ((FormatCommand) -> Void)?
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, let handler = onFormatCommand, let command = FormatCommand.command(for: event) {
            handler(command)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SwashFolderAccessGranted"), object: nil)
        guard let window = self.window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowUpdated), name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFolderAccessGranted), name: NSNotification.Name("SwashFolderAccessGranted"), object: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.handleWindowUpdated()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleFolderAccessGranted() {
        guard let coordinator = self.delegate as? SwashTextView.Coordinator else { return }
        if coordinator.parent.isStyled {
            coordinator.highlightMarkdown(in: self)
        }
    }
    
    @objc private func handleWindowUpdated() {
        guard let coordinator = self.delegate as? SwashTextView.Coordinator else { return }
        let winURL = self.window?.representedURL ?? (self.window.flatMap { NSDocumentController.shared.document(for: $0)?.fileURL })
        if let docURL = winURL, coordinator.lastBaseURL != docURL {
            coordinator.lastBaseURL = docURL
            if coordinator.parent.isStyled {
                coordinator.highlightMarkdown(in: self)
            }
        }
    }
    
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        if isStyled {
            return [.rtfd, .rtf, .html, .string]
        }
        return super.writablePasteboardTypes
    }
    
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        if isStyled {
            return copyFormattedWithRawFallback(range: selectedRange(), pasteboard: pboard)
        }
        return super.writeSelection(to: pboard, types: types)
    }
    
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if isStyled {
            return copyFormattedWithRawFallback(range: selectedRange(), pasteboard: pboard)
        }
        return super.writeSelection(to: pboard, type: type)
    }
    
    override func copy(_ sender: Any?) {
        if isStyled {
            _ = copyFormattedWithRawFallback(range: selectedRange(), pasteboard: NSPasteboard.general)
        } else {
            super.copy(sender)
        }
    }
    
    @discardableResult
    private func copyFormattedWithRawFallback(range: NSRange, pasteboard: NSPasteboard) -> Bool {
        guard range.length > 0, let textStorage = textStorage else { return false }
        
        pasteboard.clearContents()
        
        let item = NSPasteboardItem()
        
        // 1. Clean Formatted AttributedString (Rich Text) - Set FIRST so rich text types are prioritized
        let cleanFormattedAttrString = createCleanFormattedAttributedString(from: textStorage, range: range)
        let fullCleanRange = NSRange(location: 0, length: cleanFormattedAttrString.length)
        
        if fullCleanRange.length > 0 {
            // RTF
            if let rtfData = try? cleanFormattedAttrString.data(from: fullCleanRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                item.setData(rtfData, forType: .rtf)
            }
            
            // RTFD if attachments are present
            if cleanFormattedAttrString.containsAttachments(in: fullCleanRange) {
                if let rtfdData = try? cleanFormattedAttrString.data(from: fullCleanRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
                    item.setData(rtfdData, forType: .rtfd)
                }
            }
            
            // HTML
            if let htmlData = try? cleanFormattedAttrString.data(from: fullCleanRange, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
                item.setData(htmlData, forType: .html)
            }
        }
        
        // 2. Raw Markdown string (Fallback for plain-text applications) - Set LAST as fallback
        let rawMarkdown = buildRawMarkdownSubstring(from: textStorage, range: range)
        item.setString(rawMarkdown, forType: .string)
        
        return pasteboard.writeObjects([item])
    }
    
    private func buildRawMarkdownSubstring(from textStorage: NSTextStorage, range: NSRange) -> String {
        let selectedSubstring = textStorage.attributedSubstring(from: range)
        let result = NSMutableString(string: selectedSubstring.string)
        let fullRange = NSRange(location: 0, length: selectedSubstring.length)
        
        selectedSubstring.enumerateAttribute(.attachment, in: fullRange, options: .reverse) { value, attRange, _ in
            if let markdown = swashRawMarkdown(for: value) {
                result.replaceCharacters(in: attRange, with: markdown)
            }
        }
        return result as String
    }
    
    private func createCleanFormattedAttributedString(from textStorage: NSTextStorage, range: NSRange) -> NSAttributedString {
        let subAttrString = textStorage.attributedSubstring(from: range)
        let result = NSMutableAttributedString()
        let fullRange = NSRange(location: 0, length: subAttrString.length)
        
        let allowedKeys: Set<NSAttributedString.Key> = [
            .font,
            .foregroundColor,
            .backgroundColor,
            .underlineStyle,
            .underlineColor,
            .strikethroughStyle,
            .strikethroughColor,
            .link,
            .paragraphStyle,
            .attachment
        ]
        
        subAttrString.enumerateAttributes(in: fullRange, options: []) { attrs, runRange, _ in
            var isHiddenTag = false
            if let font = attrs[.font] as? NSFont, font.pointSize < 1.0 {
                isHiddenTag = true
            }
            if let color = attrs[.foregroundColor] as? NSColor, color == .clear {
                isHiddenTag = true
            }
            
            if !isHiddenTag {
                if let attachment = attrs[.attachment] as? TableTextAttachment {
                    let tableText = convertTableToFormattedText(attachment.tableData)
                    let tableAttr = NSAttributedString(string: tableText, attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    ])
                    result.append(tableAttr)
                } else if let attachment = attrs[.attachment] as? ImageTextAttachment {
                    let imageAttr = NSAttributedString(attachment: attachment)
                    result.append(imageAttr)
                } else {
                    let chunk = subAttrString.attributedSubstring(from: runRange)
                    let mutableChunk = NSMutableAttributedString(attributedString: chunk)
                    
                    let chunkRange = NSRange(location: 0, length: mutableChunk.length)
                    
                    // Strip non-standard / custom attributes (e.g. .listMarker) that break RTF serialization
                    mutableChunk.enumerateAttributes(in: chunkRange, options: []) { chunkAttrs, subRange, _ in
                        for key in chunkAttrs.keys {
                            if !allowedKeys.contains(key) {
                                mutableChunk.removeAttribute(key, range: subRange)
                            }
                        }
                    }
                    
                    // Remove default text colors so pasted text adapts cleanly to target apps
                    mutableChunk.enumerateAttribute(.foregroundColor, in: chunkRange, options: []) { colorValue, attrRange, _ in
                        if let color = colorValue as? NSColor {
                            if color == NSColor.textColor || color == NSColor.labelColor || color == NSColor.clear {
                                mutableChunk.removeAttribute(.foregroundColor, range: attrRange)
                            }
                        }
                    }
                    
                    // Strip textBlocks from paragraphStyle so code blocks don't export as RTF table cells in target apps
                    mutableChunk.enumerateAttribute(.paragraphStyle, in: chunkRange, options: []) { paraValue, subRange, _ in
                        if let para = paraValue as? NSParagraphStyle, !para.textBlocks.isEmpty {
                            let mutablePara = para.mutableCopy() as! NSMutableParagraphStyle
                            mutablePara.textBlocks = []
                            mutableChunk.addAttribute(.paragraphStyle, value: mutablePara, range: subRange)
                            
                            // Apply subtle background color fill for code blocks in rich text exports
                            if mutableChunk.attribute(.backgroundColor, at: subRange.location, effectiveRange: nil) == nil {
                                let codeBg = NSColor.textColor.withAlphaComponent(0.04)
                                mutableChunk.addAttribute(.backgroundColor, value: codeBg, range: subRange)
                            }
                        }
                    }
                    
                    result.append(mutableChunk)
                }
            } else {
                if let markerInfo = attrs[.listMarker] as? ListMarkerInfo {
                    let markerStr = "\(markerInfo.text) "
                    let font = NSFont.systemFont(ofSize: 14, weight: .bold)
                    let markerAttr = NSAttributedString(string: markerStr, attributes: [.font: font])
                    result.append(markerAttr)
                }
            }
        }
        
        return result
    }
    
    private func convertTableToFormattedText(_ data: MarkdownTableData) -> String {
        var lines: [String] = []
        let cleanHeaders = data.headers.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !cleanHeaders.isEmpty {
            lines.append(cleanHeaders.joined(separator: "\t"))
        }
        for row in data.rows {
            let cleanCells = row.map { $0.trimmingCharacters(in: .whitespaces) }
            lines.append(cleanCells.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }
}

final class ImageTextAttachment: NSTextAttachment {
    static let fileTypeIdentifier = "com.surrealroad.swash.image"
    let alt: String
    let urlString: String
    let rawMarkdown: String
    
    init(image: NSImage, alt: String, urlString: String, rawMarkdown: String) {
        self.alt = alt
        self.urlString = urlString
        self.rawMarkdown = rawMarkdown
        super.init(data: nil, ofType: Self.fileTypeIdentifier)
        self.image = image
        self.attachmentCell = NSTextAttachmentCell(imageCell: image)
        self.bounds = NSRect(origin: .zero, size: image.size)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct SwashTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange?
    @Binding var selectionRect: NSRect? // Bounding rect of selection in the local coordinate space of SwashTextView (SwiftUI top-left)
    @Binding var scrollOriginY: CGFloat
    var isStyled: Bool
    var flavor: MarkdownFlavor
    var baseURL: URL? = nil
    var onCommit: (() -> Void)? = nil
    var onNextCell: (() -> Void)? = nil
    var onPrevCell: (() -> Void)? = nil
    var controller: SwashEditorController? = nil
    var onFormatCommand: ((FormatCommand) -> Void)? = nil
    
    init(
        text: Binding<String>,
        selectedRange: Binding<NSRange?>,
        selectionRect: Binding<NSRect?>,
        scrollOriginY: Binding<CGFloat> = .constant(0),
        isStyled: Bool,
        flavor: MarkdownFlavor,
        baseURL: URL? = nil,
        onCommit: (() -> Void)? = nil,
        onNextCell: (() -> Void)? = nil,
        onPrevCell: (() -> Void)? = nil,
        controller: SwashEditorController? = nil,
        onFormatCommand: ((FormatCommand) -> Void)? = nil
    ) {
        self._text = text
        self._selectedRange = selectedRange
        self._selectionRect = selectionRect
        self._scrollOriginY = scrollOriginY
        self.isStyled = isStyled
        self.flavor = flavor
        self.baseURL = baseURL
        self.onCommit = onCommit
        self.onNextCell = onNextCell
        self.onPrevCell = onPrevCell
        self.controller = controller
        self.onFormatCommand = onFormatCommand
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        logDebug("[SwashTextView] makeNSView called")
        
        let textStorage = NSTextStorage()
        let layoutManager = SwashLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        
        let textView = SwashNSTextView(frame: .zero, textContainer: textContainer)
        textView.isStyled = isStyled
        textView.flavor = flavor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        
        // Premium typography and spacing styling
        textView.textColor = NSColor.textColor
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        
        // Set standard padding/margins for a clean writing interface
        textView.textContainerInset = NSSize(width: 20, height: 20)
        
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor
        scrollView.borderType = .noBorder
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView = scrollView else { return }
            let clipView = scrollView.contentView
            let targetPoint = NSPoint(x: clipView.bounds.origin.x, y: context.coordinator.parent.scrollOriginY)
            clipView.scroll(to: targetPoint)
            scrollView.reflectScrolledClipView(clipView)
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? SwashNSTextView else { return }
        textView.isStyled = isStyled
        textView.flavor = flavor
        textView.onFormatCommand = onFormatCommand
        
        context.coordinator.isUpdatingFromSwiftUI = true
        context.coordinator.parent = self
        context.coordinator.currentTextView = textView
        controller?.textView = textView
        controller?.coordinator = context.coordinator
        
        let currentRawText = isStyled ? context.coordinator.buildRawMarkdown(from: textView.textStorage ?? NSTextStorage()) : textView.string
        let normalizedTextView = currentRawText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let normalizedBinding = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        
        // Trim whitespaces and newlines for comparison to ignore trivial formatting differences
        let textChanged = (context.coordinator.lastStyledText != text) &&
                          (normalizedTextView.trimmingCharacters(in: .whitespacesAndNewlines) != normalizedBinding.trimmingCharacters(in: .whitespacesAndNewlines))
        
        let isFirstResponder = textView.window?.firstResponder == textView
        let hasSelection = textView.selectedRange().length > 0
        
        logDebug("[SwashTextView] updateNSView - textChanged: \(textChanged), isFirstResponder: \(isFirstResponder), hasSelection: \(hasSelection)")
        
        var textWasUpdated = false
        if textChanged {
            if let origin = textView.enclosingScrollView?.contentView.bounds.origin {
                context.coordinator.lastKnownScrollOrigin = origin
            }
            textView.string = text
            context.coordinator.invalidateOffsetMap()
            if let origin = context.coordinator.lastKnownScrollOrigin, let clipView = textView.enclosingScrollView?.contentView {
                clipView.scroll(to: origin)
                textView.enclosingScrollView?.reflectScrolledClipView(clipView)
            }
            textWasUpdated = true
        }
        
        let currentBaseURL = baseURL ?? textView.window?.representedURL ?? (textView.window.flatMap { NSDocumentController.shared.document(for: $0)?.fileURL })
        let baseChanged = (context.coordinator.lastBaseURL != currentBaseURL)
        
        // Highlight if the text was updated, if style parameters changed, if baseURL updated, or on first run.
        let needsHighlight = textWasUpdated ||
                             context.coordinator.lastStyledText == nil ||
                             context.coordinator.lastIsStyled != isStyled ||
                             context.coordinator.lastFlavor != flavor ||
                             (baseChanged && currentBaseURL != nil)
        
        logDebug("[SwashTextView] updateNSView - needsHighlight: \(needsHighlight), lastStyledText is Nil: \(context.coordinator.lastStyledText == nil)")
        
        if needsHighlight {
            DispatchQueue.main.async { [weak textView] in
                guard let textView = textView else { return }
                if context.coordinator.parent.isStyled {
                    context.coordinator.highlightMarkdown(in: textView)
                } else {
                    context.coordinator.applyPlainStyle(in: textView)
                }
            }
        }
        
        // Update selection if needed, preserving scroll position to prevent alt-tab jumping
        logDebug("[SwashTextView] updateNSView - selectedRange: \(String(describing: selectedRange)), textView.selectedRange(): \(textView.selectedRange())")
        if isFirstResponder, let rawRange = selectedRange,
           case let range = context.coordinator.storageRange(forRaw: rawRange, in: textView),
           textView.selectedRange() != range {
            logDebug("[SwashTextView] updateNSView - Setting selection to: \(range)")
            let savedOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            textView.setSelectedRange(range)
            if let origin = savedOrigin, let clipView = textView.enclosingScrollView?.contentView {
                clipView.scroll(to: origin)
                textView.enclosingScrollView?.reflectScrolledClipView(clipView)
            }
        }
        
        // Sync scroll position if modified externally
        let clipView = nsView.contentView
        if abs(clipView.bounds.origin.y - scrollOriginY) > 1.0 {
            context.coordinator.isProgrammaticScroll = true
            let origin = NSPoint(x: clipView.bounds.origin.x, y: scrollOriginY)
            clipView.scroll(to: origin)
            nsView.reflectScrolledClipView(clipView)
            DispatchQueue.main.async {
                context.coordinator.isProgrammaticScroll = false
            }
        }
        
        context.coordinator.isUpdatingFromSwiftUI = false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SwashTextView
        var isUpdatingFromSwiftUI = false
        var isProgrammaticScroll = false
        var isHighlighting = false
        var didAutoSelect = false
        
        var lastStyledText: String? = nil
        var lastIsStyled: Bool? = nil
        var lastFlavor: MarkdownFlavor? = nil
        var lastBaseURL: URL? = nil
        
        var lastKnownScrollOrigin: NSPoint? = nil
        weak var currentTextView: NSTextView? = nil
        
        /// Storage ↔ raw offset map; invalidated whenever the storage changes.
        private var cachedOffsetMap: AttachmentOffsetMap? = nil
        /// Code-block ranges in storage coordinates, refreshed on every styling pass (used by spellcheck).
        private var cachedStorageCodeBlocks: [NSRange] = []
        /// Code ranges of the raw text currently being styled.
        private var currentCodeRanges = MarkdownParser.CodeRanges()
        /// Raw-markdown selection to restore after the next styling pass.
        private var pendingRawSelection: NSRange? = nil
        private var editGeneration = 0
        private var highlightedGeneration = -1
        
        init(_ parent: SwashTextView) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(handleRemoveCurrentTable(_:)), name: .removeCurrentTable, object: nil)
            logDebug("[SwashTextView] Coordinator.init called")
        }
        
        private func convertTableToPlainText(_ data: MarkdownTableData) -> String {
            var lines: [String] = []
            
            let cleanHeaders = data.headers.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !cleanHeaders.isEmpty {
                lines.append(cleanHeaders.joined(separator: "    "))
            }
            
            for row in data.rows {
                let cleanCells = row.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !cleanCells.isEmpty {
                    lines.append(cleanCells.joined(separator: "    "))
                }
            }
            
            return lines.joined(separator: "\n")
        }

        @objc func handleRemoveCurrentTable(_ notification: Notification) {
            guard let textView = currentTextView else { return }
            guard let textStorage = textView.textStorage else { return }
            
            let savedScrollOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            var removed = false
            let fullRange = NSRange(location: 0, length: textStorage.length)
            
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, attachRange, stop in
                if let tableAttachment = value as? TableTextAttachment {
                    let plainText = self.convertTableToPlainText(tableAttachment.tableData)
                    textStorage.replaceCharacters(in: attachRange, with: plainText)
                    removed = true
                    stop.pointee = true
                }
            }
            textStorage.endEditing()
            
            for subview in textView.subviews {
                if NSStringFromClass(type(of: subview)).contains("TableHostingView") {
                    subview.removeFromSuperview()
                }
            }
            
            if removed {
                let updatedText = buildRawMarkdown(from: textStorage)
                self.parent.text = updatedText
                highlightMarkdown(in: textView)
                
                if let origin = savedScrollOrigin, let clipView = textView.enclosingScrollView?.contentView {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        clipView.scroll(to: origin)
                        textView.enclosingScrollView?.reflectScrolledClipView(clipView)
                    }
                }
            }
        }
        
        func buildRawMarkdown(from textStorage: NSTextStorage) -> String {
            let result = NSMutableString(string: textStorage.string)
            let fullRange = NSRange(location: 0, length: textStorage.length)
            
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: .reverse) { value, range, _ in
                if let markdown = swashRawMarkdown(for: value) {
                    result.replaceCharacters(in: range, with: markdown)
                }
            }
            return result as String
        }
        
        // MARK: - Storage ↔ Raw Offsets
        
        private var cachedLinkFormatting: MarkdownFormatting?
        
        /// Parsed document used to detect the link under the caret; reused until the text changes.
        private func linkFormatting(for text: String) -> MarkdownFormatting {
            if let cached = cachedLinkFormatting, cached.text == text { return cached }
            let formatting = MarkdownFormatting(text: text)
            cachedLinkFormatting = formatting
            return formatting
        }
        
        func invalidateOffsetMap() {
            cachedOffsetMap = nil
        }
        
        func offsetMap(for textView: NSTextView) -> AttachmentOffsetMap {
            guard parent.isStyled, let storage = textView.textStorage else { return .identity }
            if let map = cachedOffsetMap { return map }
            let map = AttachmentOffsetMap(storage: storage)
            cachedOffsetMap = map
            return map
        }
        
        func rawRange(forStorage range: NSRange, in textView: NSTextView) -> NSRange {
            offsetMap(for: textView).rawRange(forStorage: range)
        }
        
        func storageRange(forRaw range: NSRange, in textView: NSTextView) -> NSRange {
            let length = textView.textStorage?.length ?? 0
            let mapped = offsetMap(for: textView).storageRange(forRaw: range)
            let start = min(max(0, mapped.location), length)
            return NSRange(location: start, length: min(mapped.length, length - start))
        }
        
        /// Applies a whole-document rewrite as the smallest equivalent edit on the live text view,
        /// registering it with the undo manager and restoring `rawSelection` afterwards.
        func applyEdit(in textView: NSTextView, newRawText: String, rawSelection: NSRange?, actionName: String) {
            guard let storage = textView.textStorage else { return }
            let oldRaw = (parent.isStyled ? buildRawMarkdown(from: storage) : textView.string) as NSString
            let newRaw = newRawText as NSString
            guard oldRaw != newRaw else {
                if let selection = rawSelection { textView.setSelectedRange(storageRange(forRaw: selection, in: textView)) }
                return
            }
            
            // Common prefix / suffix in UTF-16 units, never splitting a surrogate pair
            let minLength = min(oldRaw.length, newRaw.length)
            var prefix = 0
            while prefix < minLength && oldRaw.character(at: prefix) == newRaw.character(at: prefix) { prefix += 1 }
            if prefix > 0 && CFStringIsSurrogateHighCharacter(oldRaw.character(at: prefix - 1)) { prefix -= 1 }
            var suffix = 0
            while suffix < minLength - prefix &&
                  oldRaw.character(at: oldRaw.length - 1 - suffix) == newRaw.character(at: newRaw.length - 1 - suffix) { suffix += 1 }
            if suffix > 0 && CFStringIsSurrogateLowCharacter(oldRaw.character(at: oldRaw.length - suffix)) { suffix -= 1 }
            
            let changedRaw = NSRange(location: prefix, length: oldRaw.length - prefix - suffix)
            let map = offsetMap(for: textView)
            // Attachments touched by the edit are replaced whole, by their (new) raw source
            let storageTarget = map.storageRange(forRaw: changedRaw)
            let expandedRaw = map.rawRange(forStorage: storageTarget)
            let delta = newRaw.length - oldRaw.length
            let replacement = newRaw.substring(with: NSRange(location: expandedRaw.location, length: expandedRaw.length + delta))
            
            guard textView.shouldChangeText(in: storageTarget, replacementString: replacement) else { return }
            let attributes = textView.typingAttributes
            storage.replaceCharacters(in: storageTarget, with: NSAttributedString(string: replacement, attributes: attributes))
            textView.didChangeText()
            textView.undoManager?.setActionName(actionName)
            
            if parent.isStyled {
                pendingRawSelection = rawSelection
                highlightMarkdown(in: textView)
            } else if let selection = rawSelection {
                let length = storage.length
                let start = min(selection.location, length)
                textView.setSelectedRange(NSRange(location: start, length: min(selection.length, length - start)))
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            cachedOffsetMap = nil
            if !isUpdatingFromSwiftUI {
                if parent.isStyled, let textStorage = textView.textStorage {
                    parent.text = buildRawMarkdown(from: textStorage)
                    editGeneration += 1
                    let generation = editGeneration
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self = self, let textView = textView else { return }
                        // Skip if a synchronous pass (e.g. a bubble-menu edit) already styled this revision
                        guard self.highlightedGeneration < generation else { return }
                        self.highlightMarkdown(in: textView)
                    }
                } else {
                    parent.text = textView.string
                    applyPlainStyle(in: textView)
                }
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            logDebug("[SwashTextView] textViewDidChangeSelection - range: \(textView.selectedRange())")
            
            // Only update selection if it wasn't triggered by SwiftUI itself
            if !isUpdatingFromSwiftUI {
                let isMouseDown = NSEvent.pressedMouseButtons & 1 != 0
                if isMouseDown {
                    // Defer updating selection rect until mouse is up/selection settles.
                    // This prevents SwiftUI overlays from rendering during an active click/drag gesture,
                    // which interrupts AppKit mouse tracking and causes automatic deselection.
                    NSObject.cancelPreviousPerformRequests(withTarget: self)
                    self.perform(#selector(deferredUpdateSelectionRect(_:)), with: textView, afterDelay: 0.15)
                } else {
                    updateSelectionRect(for: textView)
                }
            }
        }
        
        @objc func deferredUpdateSelectionRect(_ textView: NSTextView) {
            logDebug("[SwashTextView] deferredUpdateSelectionRect (mouse released/settled)")
            updateSelectionRect(for: textView)
        }
        
        @objc func scrollViewDidScroll(_ notification: Notification) {
            // Find current text view to recalculate selection rect during scrolling
            if let clipView = notification.object as? NSClipView,
               let scrollView = clipView.superview as? NSScrollView,
               let textView = scrollView.documentView as? NSTextView {
                lastKnownScrollOrigin = clipView.bounds.origin
                if !isUpdatingFromSwiftUI && !isProgrammaticScroll {
                    let y = clipView.bounds.origin.y
                    if abs(self.parent.scrollOriginY - y) > 0.5 {
                        DispatchQueue.main.async {
                            self.parent.scrollOriginY = y
                        }
                    }
                }
                updateSelectionRect(for: textView)
            }
        }
        
        private func updateSelectionRect(for textView: NSTextView?) {
            guard let textView = textView,
                  let scrollView = textView.enclosingScrollView else { return }
            
            let range = textView.selectedRange()
            logDebug("[SwashTextView] updateSelectionRect - range: \(range)")
            
            // Published selections and link ranges are in raw-markdown offsets
            let rawSelection = rawRange(forStorage: range, in: textView)
            let activeLink: (fullRange: NSRange, url: String)?
            if parent.flavor == .slack {
                activeLink = LinkDetector.findLink(at: rawSelection, in: parent.text, flavor: .slack).map { ($0.fullRange, $0.url) }
            } else if let node = linkFormatting(for: parent.text).link(at: rawSelection),
                      case .link(let destination, _, let kind) = node.kind, kind != .extendedAutolink {
                activeLink = (node.range, destination)
            } else {
                activeLink = nil
            }
            
            if range.length > 0 || activeLink != nil {
                self.parent.selectedRange = rawSelection
                
                let targetRange = (range.length > 0) ? range : (activeLink.map { storageRange(forRaw: $0.fullRange, in: textView) } ?? range)
                
                if let layoutManager = textView.layoutManager,
                   let textContainer = textView.textContainer {
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: targetRange, actualCharacterRange: nil)
                    var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    
                    // Add origin of the text container (margins)
                    let origin = textView.textContainerOrigin
                    rect.origin.x += origin.x
                    rect.origin.y += origin.y
                    
                    // Convert from textView local coordinates to NSScrollView contentView (NSClipView) coordinates
                    let rectInClipView = textView.convert(rect, to: scrollView.contentView)
                    
                    let scrollOffset = scrollView.contentView.bounds.origin
                    let swiftUIRect = NSRect(
                        x: rectInClipView.origin.x - scrollOffset.x,
                        y: rectInClipView.origin.y - scrollOffset.y,
                        width: rectInClipView.width,
                        height: rectInClipView.height
                    )
                    
                    let visibleY = rectInClipView.origin.y - scrollOffset.y
                    let viewportHeight = scrollView.contentView.bounds.height
                    
                    // Only publish selection rect if it is visible inside the scroll view viewport bounds
                    if visibleY >= 0 && visibleY + rectInClipView.height <= viewportHeight {
                        self.parent.selectionRect = swiftUIRect
                    } else {
                        self.parent.selectionRect = nil
                    }
                } else {
                    self.parent.selectionRect = nil
                }
            } else {
                self.parent.selectedRange = nil
                self.parent.selectionRect = nil
            }
        }
        
        // MARK: Caret atomicity
        
        /// True when the character at `index` is a hidden syntax marker (collapsed font or clear colour).
        private func isHiddenCharacter(_ index: Int, in storage: NSTextStorage) -> Bool {
            guard index >= 0, index < storage.length else { return false }
            if storage.attribute(.attachment, at: index, effectiveRange: nil) != nil { return false }
            if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont, font.pointSize < 1 { return true }
            if let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor, color == .clear { return true }
            return false
        }
        
        /// Keeps the caret from stopping on hidden markers: arrow steps skip a hidden run plus one visible
        /// character, and a caret placed inside (or at the start of a line's) hidden prefix moves to the content.
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldRange: NSRange, toCharacterRange newRange: NSRange) -> NSRange {
            guard parent.isStyled, !isHighlighting, !isUpdatingFromSwiftUI, newRange.length == 0, oldRange.length == 0,
                  let storage = textView.textStorage else { return newRange }
            let length = storage.length
            let ns = storage.string as NSString
            let old = oldRange.location
            let proposed = newRange.location
            
            /// Moves past hidden characters that start a line or follow other hidden characters
            /// (collapsed fence lines, block prefixes), so the caret rests on visible content.
            func snapForward(_ position: Int) -> Int {
                var i = position
                while i < length && isHiddenCharacter(i, in: storage) &&
                      (i == 0 || ns.character(at: i - 1) == 0x0A || isHiddenCharacter(i - 1, in: storage)) {
                    i += 1
                }
                return i
            }
            
            if proposed == old + 1 {
                var i = old
                if isHiddenCharacter(old, in: storage) {
                    // Step over the hidden run and then one visible character
                    while i < length && isHiddenCharacter(i, in: storage) { i += 1 }
                    if i < length { i += 1 }
                } else {
                    i = proposed
                }
                return NSRange(location: snapForward(min(i, length)), length: 0)
            }
            if proposed == old - 1, old > 0, isHiddenCharacter(old - 1, in: storage) {
                var i = old
                while i > 0 && isHiddenCharacter(i - 1, in: storage) { i -= 1 }
                if i > 0 { i -= 1 }
                return NSRange(location: max(0, i), length: 0)
            }
            if proposed != old - 1 {
                return NSRange(location: snapForward(proposed), length: 0)
            }
            return newRange
        }
        
        // Intercept typing attributes inheritance so typing next to or inside hidden tags resets to normal size/color
        func textView(_ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String : Any] = [:], toAttributes newTypingAttributes: [NSAttributedString.Key : Any] = [:]) -> [NSAttributedString.Key : Any] {
            var attrs = newTypingAttributes
            if let font = attrs[.font] as? NSFont, font.pointSize < 1.0 {
                attrs[.font] = NSFont.systemFont(ofSize: 14, weight: .regular)
            }
            if let color = attrs[.foregroundColor] as? NSColor, color == .clear {
                attrs[.foregroundColor] = NSColor.textColor
            }
            return attrs
        }
        
        // Key commands: table-cell navigation, then Notion-style structural editing
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let onCommit = parent.onCommit {
                    onCommit()
                    return true
                }
                return applyStructuralEdit(in: textView, actionName: "New Line") { MarkdownEditingCommands.newline(text: $0, selection: $1) }
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                if let onNextCell = parent.onNextCell {
                    onNextCell()
                    return true
                }
                return applyStructuralEdit(in: textView, actionName: "Indent") { MarkdownEditingCommands.indent(text: $0, selection: $1) }
            } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                if let onPrevCell = parent.onPrevCell {
                    onPrevCell()
                    return true
                }
                return applyStructuralEdit(in: textView, actionName: "Outdent") { MarkdownEditingCommands.outdent(text: $0, selection: $1) }
            } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                let hidden = parent.isStyled
                return applyStructuralEdit(in: textView, actionName: "Delete") { MarkdownEditingCommands.backspace(text: $0, selection: $1, markersHidden: hidden) }
            }
            return false
        }
        
        /// Runs a structural editing command on the raw Markdown; returns false to fall back to the default key behaviour.
        private func applyStructuralEdit(in textView: NSTextView, actionName: String, _ command: (String, NSRange) -> MarkdownEdit?) -> Bool {
            guard parent.onCommit == nil, let storage = textView.textStorage else { return false }
            let raw = parent.isStyled ? buildRawMarkdown(from: storage) : textView.string
            let rawSelection = rawRange(forStorage: textView.selectedRange(), in: textView)
            guard let edit = command(raw, rawSelection) else { return false }
            applyEdit(in: textView, newRawText: edit.text, rawSelection: edit.selection, actionName: actionName)
            return true
        }
        
        // Disable spellcheck inside code blocks
        func textView(_ textView: NSTextView, willCheckTextIn range: NSRange, options: [NSSpellChecker.OptionKey : Any], types: UnsafeMutablePointer<NSTextCheckingTypes>) -> [NSSpellChecker.OptionKey : Any] {
            if MarkdownParser.CodeRanges.anyIntersects(cachedStorageCodeBlocks, range) {
                types.pointee = 0
            }
            return options
        }
        
        // Intercept and prevent spelling underlines inside code blocks
        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range: NSRange) -> Int {
            if MarkdownParser.CodeRanges.anyIntersects(cachedStorageCodeBlocks, range) {
                return 0
            }
            return value
        }
        
        // Custom interactive high-fidelity Markdown inline styling
        func highlightMarkdown(in textView: NSTextView) {
            logDebug("[SwashTextView] highlightMarkdown called")
            guard let textStorage = textView.textStorage, !isHighlighting else { return }
            isHighlighting = true
            
            // Preserve scroll position to prevent jumps on focus loss/revert
            let currentScrollOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            let savedScrollOrigin = currentScrollOrigin ?? lastKnownScrollOrigin
            if let origin = currentScrollOrigin {
                lastKnownScrollOrigin = origin
            }
            
            // Clean up any old table subviews to prevent duplicate stacked views on revert or text update
            for subview in textView.subviews {
                if NSStringFromClass(type(of: subview)).contains("TableHostingView") {
                    subview.removeFromSuperview()
                }
            }
            
            // Remember the selection in raw-markdown offsets so it survives attachment rebuilding
            let savedRawSelection = pendingRawSelection ?? rawRange(forStorage: textView.selectedRange(), in: textView)
            pendingRawSelection = nil
            
            // Reconstruct raw text from any existing attachments so parsing is deterministic
            let rawText = buildRawMarkdown(from: textStorage)
            if textStorage.string != rawText {
                textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: rawText)
            }
            cachedOffsetMap = nil
            
            let text = textStorage.string
            let fullRange = NSRange(location: 0, length: textStorage.length)
            // Locate all code once per pass; every inline rule consults this instead of rescanning
            let codeRanges = MarkdownParser.codeRanges(in: text)
            currentCodeRanges = codeRanges
            
            textStorage.beginEditing()
            
            // 1. Reset everything to high-texture defaults
            let defaultFont = NSFont.systemFont(ofSize: 14, weight: .regular)
            let defaultColor = NSColor.textColor
            textStorage.setAttributes([
                .font: defaultFont,
                .foregroundColor: defaultColor
            ], range: fullRange)
            
            // Helper to hide markdown tags in Preview mode
            func hideRange(_ range: NSRange) {
                let valid = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
                if valid.length > 0 {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: valid)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: valid)
                }
            }
            
            // Simple syntax highlighting on code lines (Slack path)
            func highlightCodeLine(_ line: String, offset: Int, language: String?) {
                MarkdownCodeHighlighter.highlight(line: line, offset: offset, language: language, in: textStorage)
            }
            
            enum PendingAttachment {
                case table(range: NSRange, source: String, headers: [String], alignments: [TableAlignment], rows: [[String]])
                case image(range: NSRange, alt: String, urlString: String, rawMarkdown: String)
                
                var location: Int {
                    switch self {
                    case .table(let range, _, _, _, _): return range.location
                    case .image(let range, _, _, _): return range.location
                    }
                }
            }
            var pendingAttachments: [PendingAttachment] = []
            
            var styledCodeRanges: [NSRange]? = nil
            if parent.flavor != .slack {
                // CommonMark / GFM: style from the shared Markdown AST
                let document = MarkdownDocument.parse(text)
                let styler = MarkdownEditorStyler(storage: textStorage, document: document)
                styler.style()
                for request in styler.attachments {
                    switch request.kind {
                    case .table(let source, let headers, let alignments, let rows):
                        pendingAttachments.append(.table(range: request.range, source: source, headers: headers, alignments: alignments, rows: rows))
                    case .image(let alt, let urlString, let rawMarkdown):
                        pendingAttachments.append(.image(range: request.range, alt: alt, urlString: urlString, rawMarkdown: rawMarkdown))
                    }
                }
                styledCodeRanges = styler.codeRanges.sorted { $0.location < $1.location }
            } else {
                // Slack mrkdwn is not CommonMark: legacy line- and regex-based styling
                // 2. Block-level parsing
                let lines = text.components(separatedBy: .newlines)
                var currentOffset = 0
            
                var inCodeBlock = false
                var currentOpenFence: MarkdownParser.CodeFenceInfo? = nil
                var currentLanguage: String? = nil
                var currentBlockStyle: NSTextBlock? = nil
            
                var hideNextLineAsSetextDelimiter = false
                var activeAlertColor: NSColor? = nil
                var lineIndex = 0
                while lineIndex < lines.count {
                    let line = lines[lineIndex]
                    let lineLength = line.utf16.count
                    let lineRange = NSRange(location: currentOffset, length: lineLength)
                
                    if inCodeBlock {
                        if let fence = currentOpenFence, MarkdownParser.isClosingCodeFence(line, matching: fence) {
                            inCodeBlock = false
                            currentOpenFence = nil
                            currentLanguage = nil
                            currentBlockStyle = nil
                            hideRange(lineRange)
                            currentOffset += lineLength + 1
                            lineIndex += 1
                            continue
                        }
                    } else if let openFence = MarkdownParser.parseOpeningCodeFence(line) {
                        activeAlertColor = nil
                        inCodeBlock = true
                        currentOpenFence = openFence
                        currentLanguage = openFence.language?.lowercased()
                    
                        let block = NSTextBlock()
                        block.backgroundColor = NSColor.textColor.withAlphaComponent(0.04)
                    
                        // Force block to span 100% width of the text container
                        block.setValue(100, type: .percentageValueType, for: .width)
                    
                        let edges: [NSRectEdge] = [.minX, .maxX, .minY, .maxY]
                        for edge in edges {
                            block.setBorderColor(NSColor.textColor.withAlphaComponent(0.12), for: edge)
                        }
                    
                        block.setWidth(0.5, type: .absoluteValueType, for: .border)
                        block.setWidth(3.0, type: .absoluteValueType, for: .border, edge: .minX)
                        block.setWidth(8, type: .absoluteValueType, for: .padding)
                        block.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
                        currentBlockStyle = block
                    
                        hideRange(lineRange)
                        currentOffset += lineLength + 1
                        lineIndex += 1
                        continue
                    }
                
                    if inCodeBlock {
                        let valid = NSIntersectionRange(lineRange, NSRange(location: 0, length: textStorage.length))
                        if valid.length > 0 {
                            textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: valid)
                            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(0.85), range: valid)
                        
                            if let block = currentBlockStyle {
                                let para = NSMutableParagraphStyle()
                                para.textBlocks = [block]
                                para.lineSpacing = 4
                                textStorage.addAttribute(.paragraphStyle, value: para, range: valid)
                            }
                        }
                    
                        highlightCodeLine(line, offset: currentOffset, language: currentLanguage)
                    
                        currentOffset += lineLength + 1
                        lineIndex += 1
                        continue
                    }
                
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                    // Indented (4-space / tab) code block lines
                    if lineLength > 0, MarkdownParser.CodeRanges.anyIntersects(codeRanges.indentedBlocks, lineRange) {
                        activeAlertColor = nil
                        let valid = NSIntersectionRange(lineRange, NSRange(location: 0, length: textStorage.length))
                        if valid.length > 0 {
                            textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: valid)
                            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(0.85), range: valid)
                        }
                        currentOffset += lineLength + 1
                        lineIndex += 1
                        continue
                    }
                
                    // Detect Table Block
                    let isTableStart = trimmedLine.contains("|") && lineIndex + 1 < lines.count
                    if isTableStart {
                        let nextTrimmed = lines[lineIndex + 1].trimmingCharacters(in: .whitespaces)
                        let isDelimiter = nextTrimmed.contains("|") && nextTrimmed.contains("-")
                        if isDelimiter {
                            let headers = MarkdownParser.parseTableCells(trimmedLine)
                            let alignments = MarkdownParser.parseAlignments(nextTrimmed)
                        
                            if !headers.isEmpty {
                                activeAlertColor = nil
                                let tableStartOffset = currentOffset
                                var tableLineIdx = lineIndex + 2
                                var tableRows: [[String]] = []
                            
                                while tableLineIdx < lines.count {
                                    let rowLine = lines[tableLineIdx].trimmingCharacters(in: .whitespaces)
                                    if rowLine.contains("|") && !rowLine.isEmpty {
                                        tableRows.append(MarkdownParser.parseTableCells(rowLine))
                                        tableLineIdx += 1
                                    } else {
                                        break
                                    }
                                }
                            
                                // Calculate total character length of table block
                                var tableEndOffset = currentOffset
                                for i in lineIndex..<tableLineIdx {
                                    tableEndOffset += lines[i].utf16.count + 1
                                }
                                let tableTotalLen = min(textStorage.length - tableStartOffset, max(1, tableEndOffset - tableStartOffset - 1))
                                let tableFullRange = NSRange(location: tableStartOffset, length: tableTotalLen)
                            
                                let tableSource = (text as NSString).substring(with: tableFullRange)
                                pendingAttachments.append(.table(range: tableFullRange, source: tableSource, headers: headers, alignments: alignments, rows: tableRows))
                            
                                currentOffset = tableEndOffset
                                lineIndex = tableLineIdx
                                continue
                            }
                        }
                    }
                
                    if hideNextLineAsSetextDelimiter {
                        hideRange(lineRange)
                        hideNextLineAsSetextDelimiter = false
                        currentOffset += lineLength + 1
                        lineIndex += 1
                        continue
                    }
                
                    let validLineRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: textStorage.length))
                    if validLineRange.length > 0 {
                        if MarkdownParser.isThematicBreak(line) {
                            let block = NSTextBlock()
                            block.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4)
                            block.setValue(100, type: .percentageValueType, for: .width)
                            block.setValue(1, type: .absoluteValueType, for: .height)
                            let para = NSMutableParagraphStyle()
                            para.textBlocks = [block]
                            textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                            textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: validLineRange)
                            textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 2), range: validLineRange)
                        } else if let heading = MarkdownParser.parseATXHeading(line) {
                            let headingFontSize: CGFloat
                            switch heading.level {
                            case 1: headingFontSize = 24
                            case 2: headingFontSize = 20
                            case 3: headingFontSize = 17
                            case 4: headingFontSize = 15
                            case 5: headingFontSize = 14
                            default: headingFontSize = 13
                            }
                            textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: headingFontSize, weight: .bold), range: validLineRange)
                        
                            let leadingSpacesCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                            let hashPrefixCount = line.dropFirst(leadingSpacesCount).prefix(while: { $0 == "#" }).count
                            let spaceAfterHash = line.dropFirst(leadingSpacesCount + hashPrefixCount).hasPrefix(" ") ? 1 : 0
                            let hideLen = leadingSpacesCount + hashPrefixCount + spaceAfterHash
                            let hashRange = NSRange(location: currentOffset, length: min(lineLength, hideLen))
                            hideRange(hashRange)
                        
                            if let closingMatch = line.range(of: "(?:[ \\t]+#+[ \\t]*)$", options: .regularExpression) {
                                let closingNSRange = NSRange(closingMatch, in: line)
                                let absClosingRange = NSRange(location: currentOffset + closingNSRange.location, length: closingNSRange.length)
                                hideRange(absClosingRange)
                            }
                        } else if lineIndex + 1 < lines.count && !trimmedLine.isEmpty && lines[lineIndex + 1].trimmingCharacters(in: .whitespaces).range(of: "^ {0,3}=+[ \\t]*$", options: .regularExpression) != nil {
                            textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 24, weight: .bold), range: validLineRange)
                            hideNextLineAsSetextDelimiter = true
                        } else if lineIndex + 1 < lines.count && !trimmedLine.isEmpty && lines[lineIndex + 1].trimmingCharacters(in: .whitespaces).range(of: "^ {0,3}-+[ \\t]*$", options: .regularExpression) != nil {
                            textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20, weight: .bold), range: validLineRange)
                            hideNextLineAsSetextDelimiter = true
                        } else if line.hasPrefix("> ") || line == ">" {
                            let quoteContent = line.hasPrefix("> ") ? String(line.dropFirst(2)) : ""
                            let alertPattern = "^\\[\\!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\\]"
                            if let alertRegex = try? NSRegularExpression(pattern: alertPattern, options: [.caseInsensitive]),
                               let match = alertRegex.firstMatch(in: quoteContent, options: [], range: NSRange(location: 0, length: (quoteContent as NSString).length)) {
                                let typeStr = (quoteContent as NSString).substring(with: match.range(at: 1)).lowercased()
                                let calloutColor: NSColor
                                switch typeStr {
                                case "tip": calloutColor = NSColor.systemGreen
                                case "important": calloutColor = NSColor.systemPurple
                                case "warning": calloutColor = NSColor.systemOrange
                                case "caution": calloutColor = NSColor.systemRed
                                default: calloutColor = NSColor.systemBlue
                                }
                                activeAlertColor = calloutColor
                            
                                textStorage.addAttribute(.foregroundColor, value: calloutColor, range: validLineRange)
                                textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .bold), range: validLineRange)
                                let block = NSTextBlock()
                                block.backgroundColor = calloutColor.withAlphaComponent(0.08)
                                block.setValue(100, type: .percentageValueType, for: .width)
                                block.setBorderColor(calloutColor, for: .minX)
                                block.setWidth(4.0, type: .absoluteValueType, for: .border, edge: .minX)
                                block.setWidth(6, type: .absoluteValueType, for: .padding)
                                block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
                                let para = NSMutableParagraphStyle()
                                para.textBlocks = [block]
                                textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                                let quoteRange = NSRange(location: currentOffset, length: min(lineLength, 2))
                                hideRange(quoteRange)
                            } else if let alertColor = activeAlertColor {
                                let block = NSTextBlock()
                                block.backgroundColor = alertColor.withAlphaComponent(0.08)
                                block.setValue(100, type: .percentageValueType, for: .width)
                                block.setBorderColor(alertColor, for: .minX)
                                block.setWidth(4.0, type: .absoluteValueType, for: .border, edge: .minX)
                                block.setWidth(6, type: .absoluteValueType, for: .padding)
                                block.setWidth(10, type: .absoluteValueType, for: .padding, edge: .minX)
                                let para = NSMutableParagraphStyle()
                                para.textBlocks = [block]
                                textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                                textStorage.addAttribute(.font, value: defaultFont, range: validLineRange)
                                let quoteRange = NSRange(location: currentOffset, length: min(lineLength, line.hasPrefix("> ") ? 2 : 1))
                                hideRange(quoteRange)
                            } else {
                                textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: validLineRange)
                                let italicFont = NSFontManager.shared.convert(defaultFont, toHaveTrait: .italicFontMask)
                                textStorage.addAttribute(.font, value: italicFont, range: validLineRange)
                                let quoteRange = NSRange(location: currentOffset, length: min(lineLength, line.hasPrefix("> ") ? 2 : 1))
                                hideRange(quoteRange)
                            }
                        } else {
                            activeAlertColor = nil
                            let taskPattern = "^[-*+]\\s+\\[([ xX])\\]\\s*"
                            if let taskRegex = try? NSRegularExpression(pattern: taskPattern),
                               let taskMatch = taskRegex.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: (trimmedLine as NSString).length)) {
                                let leadingSpacesCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                                let fullMarkerLen = taskMatch.range(at: 0).length
                                let checkChar = (trimmedLine as NSString).substring(with: taskMatch.range(at: 1))
                                let isChecked = checkChar.lowercased() == "x"
                            
                                let rawMarkerRange = NSRange(location: currentOffset + leadingSpacesCount, length: min(lineLength - leadingSpacesCount, fullMarkerLen))
                                hideRange(rawMarkerRange)
                            
                                let indent = CGFloat((leadingSpacesCount / 2 + 1) * 20)
                                let para = NSMutableParagraphStyle()
                                para.headIndent = indent
                                para.firstLineHeadIndent = indent
                                textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                            
                                let markerGlyph = isChecked ? "☑" : "☐"
                                let markerColor = isChecked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor
                                textStorage.addAttribute(.listMarker, value: ListMarkerInfo(text: markerGlyph, indent: indent, color: markerColor), range: rawMarkerRange)
                            } else if let numMarkerRange = trimmedLine.range(of: "^[0-9]+[.)]\\s+", options: .regularExpression) {
                                let leadingSpacesCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                                let fullMarkerStr = String(trimmedLine[numMarkerRange])
                                let totalMarkerLen = fullMarkerStr.utf16.count
                            
                                let delimiterIdx = fullMarkerStr.firstIndex(where: { $0 == "." || $0 == ")" }) ?? fullMarkerStr.endIndex
                                let numberDotStr = String(fullMarkerStr[...delimiterIdx])
                            
                                let rawMarkerRange = NSRange(location: currentOffset + leadingSpacesCount, length: min(lineLength - leadingSpacesCount, totalMarkerLen))
                                hideRange(rawMarkerRange)
                            
                                let indent = CGFloat((leadingSpacesCount / 2 + 1) * 24)
                                let para = NSMutableParagraphStyle()
                                para.headIndent = indent
                                para.firstLineHeadIndent = indent
                                textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                            
                                textStorage.addAttribute(.listMarker, value: ListMarkerInfo(text: numberDotStr, indent: indent), range: rawMarkerRange)
                            } else if let listMarkerRange = trimmedLine.range(of: "^[-*+]\\s+", options: .regularExpression) {
                                let leadingSpacesCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                                let fullMarkerStr = String(trimmedLine[listMarkerRange])
                                let totalMarkerLen = fullMarkerStr.utf16.count
                            
                                let rawMarkerRange = NSRange(location: currentOffset + leadingSpacesCount, length: min(lineLength - leadingSpacesCount, totalMarkerLen))
                                hideRange(rawMarkerRange)
                            
                                let indent = CGFloat((leadingSpacesCount / 2 + 1) * 20)
                                let para = NSMutableParagraphStyle()
                                para.headIndent = indent
                                para.firstLineHeadIndent = indent
                                textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                            
                                textStorage.addAttribute(.listMarker, value: ListMarkerInfo(text: "•", indent: indent), range: rawMarkerRange)
                            } else if let fnDefMatch = try? NSRegularExpression(pattern: "^ {0,3}\\[\\^([^\\]]+)\\]:\\s*(.*)$").firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: (trimmedLine as NSString).length)) {
                                let leadingSpacesCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                                let fullPrefixLen = fnDefMatch.range(at: 0).length - fnDefMatch.range(at: 2).length
                            
                                // Style footnote definition line in formatted mode: 12pt secondary color, hanging indent
                                let fnFont = NSFont.systemFont(ofSize: 12, weight: .regular)
                                textStorage.addAttribute(.font, value: fnFont, range: validLineRange)
                                textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: validLineRange)
                            
                                let para = NSMutableParagraphStyle()
                                para.headIndent = 24
                                para.firstLineHeadIndent = 0
                                textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                            
                                // Style the marker: [label]:
                                let markerRangeInLine = NSRange(location: currentOffset + leadingSpacesCount, length: min(lineLength - leadingSpacesCount, fullPrefixLen))
                                let validMarker = NSIntersectionRange(markerRangeInLine, NSRange(location: 0, length: textStorage.length))
                                if validMarker.length > 0 {
                                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 11, weight: .bold), range: validMarker)
                                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: validMarker)
                                }
                            
                                // Hide the '^'
                                let caretRangeInLine = NSRange(location: currentOffset + leadingSpacesCount + 1, length: 1)
                                hideRange(caretRangeInLine)
                            }
                        }
                    }
                
                    currentOffset += lineLength + 1
                    lineIndex += 1
                }
            
                // Code spans (CommonMark backtick-run matching); contents are never further interpreted
                func styleCodeSpans() {
                    let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                    for span in codeRanges.spans where span.content.length > 0 {
                        let content = NSIntersectionRange(span.content, NSRange(location: 0, length: textStorage.length))
                        guard content.length > 0 else { continue }
                        textStorage.addAttribute(.font, value: monoFont, range: content)
                        textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: content)
                        hideRange(NSRange(location: span.full.location, length: span.content.location - span.full.location))
                        let contentEnd = span.content.location + span.content.length
                        hideRange(NSRange(location: contentEnd, length: span.full.location + span.full.length - contentEnd))
                    }
                }
            
                // 3. Inline style parsing via regexes
                // Slack inline styles
                // Slack Bold: *text*
                applyRegex(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", in: text) { matchRange, contentRange in
                    let boldFont = NSFont.systemFont(ofSize: 14, weight: .bold)
                    textStorage.addAttribute(.font, value: boldFont, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 1))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
                }
            
                // Slack Italic: _text_
                applyRegex(pattern: "(?<!_)(?<!\\w)_([^_\\n]+?)_(?!\\w)(?!_)", in: text) { matchRange, contentRange in
                    let italicFont = NSFontManager.shared.convert(defaultFont, toHaveTrait: .italicFontMask)
                    textStorage.addAttribute(.font, value: italicFont, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 1))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
                }
            
                // Slack Strikethrough: ~text~
                applyRegex(pattern: "(?<!~)~([^~\\n]+?)~(?!~)", in: text) { matchRange, contentRange in
                    textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 1))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
                }
            
                // Slack Inline Code: `code`
                styleCodeSpans()
            
                // Slack Links: <url|text>
                if let linkWithPipeRegex = try? NSRegularExpression(pattern: "(<(https?://[^>|\\n]+)\\|)([^>|\\n]+)(>)", options: []) {
                    let nsString = text as NSString
                    let matches = linkWithPipeRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges >= 5 {
                            let leftPart = match.range(at: 1)
                            let urlRange = match.range(at: 2)
                            let textRange = match.range(at: 3)
                            let rightPart = match.range(at: 4)
                            let urlString = nsString.substring(with: urlRange)
                        
                            let validUrl = NSIntersectionRange(urlRange, NSRange(location: 0, length: textStorage.length))
                            if validUrl.length > 0 {
                                textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: validUrl)
                                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: validUrl)
                                if let url = URL(string: urlString) {
                                    textStorage.addAttribute(.link, value: url, range: validUrl)
                                }
                            }
                        
                            textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: textRange)
                            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                            if let url = URL(string: urlString) {
                                textStorage.addAttribute(.link, value: url, range: textRange)
                            }
                            hideRange(leftPart)
                            hideRange(rightPart)
                        }
                    }
                }
            
                // Slack Links: <url>
                if let linkRegex = try? NSRegularExpression(pattern: "(<)(https?://[^>|\\n]+)(>)", options: []) {
                    let nsString = text as NSString
                    let matches = linkRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges >= 4 {
                            let leftPart = match.range(at: 1)
                            let urlRange = match.range(at: 2)
                            let rightPart = match.range(at: 3)
                            let urlString = nsString.substring(with: urlRange)
                            textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: urlRange)
                            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: urlRange)
                            if let url = URL(string: urlString) {
                                textStorage.addAttribute(.link, value: url, range: urlRange)
                            }
                            hideRange(leftPart)
                            hideRange(rightPart)
                        }
                    }
                }

                // Bare URLs, www. domains, and emails
                let urlPattern = "(?:https?://|www\\.)[^\\s<>\"'\\)]+|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"
                if let bareUrlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
                    let nsString = text as NSString
                    let matches = bareUrlRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        var matchRange = match.range(at: 0)
                        if codeRanges.excludes(matchRange) {
                            continue
                        }
                    
                        // Trim trailing punctuation if any (. , ; : ! ? ) ])
                        var str = nsString.substring(with: matchRange)
                        while let last = str.last, [".", ",", ";", ":", "!", "?", ")", "]", "\"", "'"].contains(last) {
                            str.removeLast()
                            matchRange.length -= 1
                        }
                        if matchRange.length == 0 { continue }
                    
                        let validMatch = NSIntersectionRange(matchRange, NSRange(location: 0, length: textStorage.length))
                        if validMatch.length > 0 {
                            var isHidden = false
                            if let font = textStorage.attribute(.font, at: validMatch.location, effectiveRange: nil) as? NSFont, font.pointSize < 1.0 {
                                isHidden = true
                            }
                            if !isHidden {
                                let urlString = nsString.substring(with: validMatch)
                                let targetUrlString: String
                                if urlString.hasPrefix("www.") {
                                    targetUrlString = "https://\(urlString)"
                                } else if urlString.contains("@") && !urlString.hasPrefix("http") {
                                    targetUrlString = "mailto:\(urlString)"
                                } else {
                                    targetUrlString = urlString
                                }
                                textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: validMatch)
                                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: validMatch)
                                if let url = URL(string: targetUrlString) ?? URL(string: targetUrlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
                                    textStorage.addAttribute(.link, value: url, range: validMatch)
                                }
                            }
                        }
                    }
                }
            
                // Extract link references for reference-style images
                var linkReferences: [String: String] = [:]
                for line in lines {
                    if let (label, url) = MarkdownParser.extractLinkReferenceDefinition(line) {
                        linkReferences[label] = url
                    }
                }
            
                // Images inside a table become part of the table attachment, never separate attachments
                let tableRanges: [NSRange] = pendingAttachments.compactMap {
                    if case .table(let range, _, _, _, _) = $0 { return range }
                    return nil
                }
                func isInsideTable(_ range: NSRange) -> Bool {
                    tableRanges.contains { NSIntersectionRange($0, range).length > 0 }
                }
            
                // Scan for Inline Images: ![alt](url)
                let inlineImgPattern = "!\\[(.*?)\\]\\((.*?)\\)"
                if let regex = try? NSRegularExpression(pattern: inlineImgPattern) {
                    let nsText = text as NSString
                    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
                    for match in matches {
                        let matchRange = match.range(at: 0)
                        if codeRanges.excludes(matchRange) || isInsideTable(matchRange) { continue }
                        let alt = nsText.substring(with: match.range(at: 1))
                        let urlStr = nsText.substring(with: match.range(at: 2))
                        let raw = nsText.substring(with: matchRange)
                        pendingAttachments.append(.image(range: matchRange, alt: alt, urlString: urlStr, rawMarkdown: raw))
                    }
                }
            
                // Scan for Reference-Style Images: ![alt][ref]
                let refImgPattern = "!\\[(.*?)\\]\\[(.*?)\\]"
                if let regex = try? NSRegularExpression(pattern: refImgPattern) {
                    let nsText = text as NSString
                    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
                    for match in matches {
                        let matchRange = match.range(at: 0)
                        if codeRanges.excludes(matchRange) || isInsideTable(matchRange) { continue }
                        let alt = nsText.substring(with: match.range(at: 1))
                        let refKey = nsText.substring(with: match.range(at: 2)).lowercased()
                        let targetKey = refKey.isEmpty ? alt.lowercased() : refKey
                        if let urlStr = linkReferences[targetKey] {
                            let raw = nsText.substring(with: matchRange)
                            pendingAttachments.append(.image(range: matchRange, alt: alt, urlString: urlStr, rawMarkdown: raw))
                        }
                    }
                }
            
                // Scan for Shortcut Reference-Style Images: ![alt]
                let shortcutImgPattern = "!\\[([^\\]\\^]+)\\](?![\\(\\[:])"
                if let regex = try? NSRegularExpression(pattern: shortcutImgPattern) {
                    let nsText = text as NSString
                    let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
                    for match in matches {
                        let matchRange = match.range(at: 0)
                        if codeRanges.excludes(matchRange) || isInsideTable(matchRange) { continue }
                        let alt = nsText.substring(with: match.range(at: 1))
                        if let urlStr = linkReferences[alt.lowercased()] {
                            let raw = nsText.substring(with: matchRange)
                            pendingAttachments.append(.image(range: matchRange, alt: alt, urlString: urlStr, rawMarkdown: raw))
                        }
                    }
                }
            
            }
            
            // 4. Sort all pending attachments descending by location and replace in reverse order
            pendingAttachments.sort { $0.location > $1.location }
            for item in pendingAttachments {
                switch item {
                case .table(let range, let source, let headers, let alignments, let rows):
                    let validRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
                    if validRange.length > 0 {
                        let tableData = MarkdownTableData(headers: headers, alignments: alignments, rows: rows)
                        var attachment: TableTextAttachment? = nil
                        attachment = TableTextAttachment(tableData: tableData, flavor: parent.flavor, originalMarkdown: source) { [weak self, weak textView] updatedData in
                            guard let self = self, let textView = textView, let textStorage = textView.textStorage, let attachment = attachment else { return }
                            attachment.tableData = updatedData
                            // The table's raw length may have changed
                            self.cachedOffsetMap = nil
                            self.parent.text = self.buildRawMarkdown(from: textStorage)
                        }
                        if let validAttachment = attachment {
                            let attrAttachment = NSMutableAttributedString(attachment: validAttachment)
                            attrAttachment.addAttributes([
                                .font: NSFont.systemFont(ofSize: 14),
                                .foregroundColor: NSColor.textColor
                            ], range: NSRange(location: 0, length: attrAttachment.length))
                            textStorage.replaceCharacters(in: validRange, with: attrAttachment)
                        }
                    }
                case .image(let range, let alt, let urlString, let rawMarkdown):
                    let validRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
                    if validRange.length > 0 {
                        let cleaned = MarkdownParser.cleanImageURLAndTitle(urlString)
                        let winURL = textView.window?.representedURL ?? (textView.window.flatMap { NSDocumentController.shared.document(for: $0)?.fileURL })
                        let resolved = MarkdownParser.resolveImage(urlString: cleaned.url, baseURL: parent.baseURL, windowURL: winURL)
                        let displayImage: NSImage
                        if let realImage = resolved {
                            displayImage = MarkdownParser.scaleImageForEditor(realImage, maxWidth: 550)
                        } else {
                            displayImage = MarkdownParser.placeholderImage(alt: alt)
                        }
                        let attachment = ImageTextAttachment(image: displayImage, alt: alt, urlString: urlString, rawMarkdown: rawMarkdown)
                        let attrAttachment = NSMutableAttributedString(attachment: attachment)
                        attrAttachment.addAttributes([
                            .font: NSFont.systemFont(ofSize: 14),
                            .foregroundColor: NSColor.textColor
                        ], range: NSRange(location: 0, length: attrAttachment.length))
                        textStorage.replaceCharacters(in: validRange, with: attrAttachment)
                    }
                }
            }
            
            textStorage.endEditing()
            isHighlighting = false
            cachedOffsetMap = nil
            highlightedGeneration = editGeneration
            
            let map = offsetMap(for: textView)
            cachedStorageCodeBlocks = (styledCodeRanges ?? codeRanges.blockRanges).map { map.storageRange(forRaw: $0) }
            let restoredSelection = storageRange(forRaw: savedRawSelection, in: textView)
            if textView.selectedRange() != restoredSelection {
                textView.setSelectedRange(restoredSelection)
            }
            
            if let origin = savedScrollOrigin, let clipView = textView.enclosingScrollView?.contentView {
                clipView.scroll(to: origin)
                textView.enclosingScrollView?.reflectScrolledClipView(clipView)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak textView] in
                    guard let clipView = textView?.enclosingScrollView?.contentView else { return }
                    clipView.scroll(to: origin)
                    textView?.enclosingScrollView?.reflectScrolledClipView(clipView)
                }
            }
            
            lastStyledText = text
            lastIsStyled = true
            lastFlavor = parent.flavor
            lastBaseURL = parent.baseURL ?? textView.window?.representedURL ?? (textView.window.flatMap { NSDocumentController.shared.document(for: $0)?.fileURL })
            
            let autoSelectRequested = ProcessInfo.processInfo.arguments.contains("--select-sample") || ProcessInfo.processInfo.environment["SWASH_AUTO_SELECT"] == "1"
            if autoSelectRequested && !didAutoSelect {
                didAutoSelect = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak textView] in
                    guard let self = self, let textView = textView else { return }
                    textView.window?.makeKeyAndOrderFront(nil)
                    textView.window?.makeFirstResponder(textView)
                    let str = textView.string
                    if let targetRange = str.range(of: "Native, High-Performance") {
                        let nsRange = NSRange(targetRange, in: str)
                        textView.setSelectedRange(nsRange)
                        self.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
                    }
                }
            }
        }
        
        func applyPlainStyle(in textView: NSTextView) {
            guard let textStorage = textView.textStorage, !isHighlighting else { return }
            isHighlighting = true
            
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.beginEditing()
            
            let monospaceFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
            textStorage.setAttributes([
                .font: monospaceFont,
                .foregroundColor: NSColor.textColor
            ], range: fullRange)
            
            textStorage.endEditing()
            isHighlighting = false
            cachedOffsetMap = nil
            cachedStorageCodeBlocks = MarkdownParser.codeRanges(in: textView.string).blockRanges
            
            lastStyledText = textView.string
            lastIsStyled = false
            lastFlavor = parent.flavor
            lastBaseURL = parent.baseURL ?? textView.window?.representedURL ?? (textView.window.flatMap { NSDocumentController.shared.document(for: $0)?.fileURL })
        }
        
        private func applyRegex(pattern: String, in text: String, action: (NSRange, NSRange) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let matchRange = match.range(at: 0)
                    if currentCodeRanges.excludes(matchRange) {
                        continue
                    }
                    action(matchRange, match.range(at: 1))
                }
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
