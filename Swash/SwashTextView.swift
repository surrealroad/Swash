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

struct ListMarkerInfo {
    let text: String
    let indent: CGFloat
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
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
                
                let markerSize = (markerInfo.text as NSString).size(withAttributes: attrs)
                let x = origin.x + markerInfo.indent - markerSize.width - 6
                let y = origin.y + lineRect.origin.y + (lineRect.height - markerSize.height) / 2
                
                let drawRect = CGRect(x: x, y: y, width: markerSize.width + 4, height: markerSize.height)
                (markerInfo.text as NSString).draw(in: drawRect, withAttributes: attrs)
            }
        }
    }
}

struct SwashTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange?
    @Binding var selectionRect: NSRect? // Bounding rect of selection in the local coordinate space of SwashTextView (SwiftUI top-left)
    var isStyled: Bool
    var flavor: MarkdownFlavor
    
    func makeNSView(context: Context) -> NSScrollView {
        logDebug("[SwashTextView] makeNSView called")
        
        let textStorage = NSTextStorage()
        let layoutManager = SwashLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
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
        textView.drawsBackground = false
        
        // Set standard padding/margins for a clean writing interface
        textView.textContainerInset = NSSize(width: 20, height: 20)
        
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        context.coordinator.isUpdatingFromSwiftUI = true
        context.coordinator.parent = self
        
        let normalizedTextView = textView.string.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let normalizedBinding = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        
        // Trim whitespaces and newlines for comparison to ignore trivial formatting differences
        let textChanged = normalizedTextView.trimmingCharacters(in: .whitespacesAndNewlines) != normalizedBinding.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let isFirstResponder = textView.window?.firstResponder == textView
        let hasSelection = textView.selectedRange().length > 0
        
        logDebug("[SwashTextView] updateNSView - textChanged: \(textChanged), isFirstResponder: \(isFirstResponder), hasSelection: \(hasSelection)")
        
        var textWasUpdated = false
        if textChanged {
            textView.string = text
            textWasUpdated = true
        }
        
        // Highlight if the text was updated, if style parameters changed, or on first run.
        let needsHighlight = textWasUpdated ||
                             context.coordinator.lastStyledText == nil ||
                             context.coordinator.lastIsStyled != isStyled ||
                             context.coordinator.lastFlavor != flavor
        
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
        
        // Update selection if needed
        logDebug("[SwashTextView] updateNSView - selectedRange: \(String(describing: selectedRange)), textView.selectedRange(): \(textView.selectedRange())")
        if let range = selectedRange, textView.selectedRange() != range {
            logDebug("[SwashTextView] updateNSView - Setting selection to: \(range)")
            textView.setSelectedRange(range)
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
        var isHighlighting = false
        
        var lastStyledText: String? = nil
        var lastIsStyled: Bool? = nil
        var lastFlavor: MarkdownFlavor? = nil
        
        init(_ parent: SwashTextView) {
            self.parent = parent
            logDebug("[SwashTextView] Coordinator.init called")
        }
        
        func buildRawMarkdown(from textStorage: NSTextStorage) -> String {
            let result = NSMutableString(string: textStorage.string)
            let fullRange = NSRange(location: 0, length: textStorage.length)
            
            textStorage.enumerateAttribute(.attachment, in: fullRange, options: .reverse) { value, range, _ in
                if let tableAttachment = value as? TableTextAttachment {
                    let markdown = MarkdownParser.tableToMarkdown(
                        headers: tableAttachment.tableData.headers,
                        alignments: tableAttachment.tableData.alignments,
                        rows: tableAttachment.tableData.rows
                    )
                    result.replaceCharacters(in: range, with: markdown)
                }
            }
            return result as String
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if !isUpdatingFromSwiftUI {
                if parent.isStyled, let textStorage = textView.textStorage {
                    parent.text = buildRawMarkdown(from: textStorage)
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self = self, let textView = textView else { return }
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
                updateSelectionRect(for: textView)
            }
        }
        
        private func updateSelectionRect(for textView: NSTextView?) {
            guard let textView = textView,
                  let scrollView = textView.enclosingScrollView else { return }
            
            let range = textView.selectedRange()
            logDebug("[SwashTextView] updateSelectionRect - range: \(range)")
            
            let text = textView.string
            let activeLink = LinkDetector.findLink(at: range, in: text, flavor: self.parent.flavor)
            
            if range.length > 0 || activeLink != nil {
                self.parent.selectedRange = range
                
                let targetRange = (range.length > 0) ? range : (activeLink?.fullRange ?? range)
                
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
        
        // Disable spellcheck inside code blocks
        func textView(_ textView: NSTextView, willCheckTextIn range: NSRange, options: [NSSpellChecker.OptionKey : Any], types: UnsafeMutablePointer<NSTextCheckingTypes>) -> [NSSpellChecker.OptionKey : Any] {
            if isRangeInCodeBlock(range, in: textView.string) {
                types.pointee = 0
            }
            return options
        }
        
        // Intercept and prevent spelling underlines inside code blocks
        func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range: NSRange) -> Int {
            if isRangeInCodeBlock(range, in: textView.string) {
                return 0
            }
            return value
        }
        
        private func isRangeInCodeBlock(_ range: NSRange, in text: String) -> Bool {
            var searchRange = NSRange(location: 0, length: text.utf16.count)
            var delimiterLocations: [Int] = []
            
            let nsString = text as NSString
            while searchRange.location < nsString.length {
                let r = nsString.range(of: "```", options: [], range: searchRange)
                if r.location == NSNotFound {
                    break
                }
                delimiterLocations.append(r.location)
                searchRange.location = r.location + r.length
                searchRange.length = nsString.length - searchRange.location
            }
            
            var i = 0
            while i < delimiterLocations.count {
                let start = delimiterLocations[i]
                let end: Int
                if i + 1 < delimiterLocations.count {
                    end = delimiterLocations[i + 1] + 3
                } else {
                    end = nsString.length
                }
                
                let blockRange = NSRange(location: start, length: end - start)
                if NSIntersectionRange(range, blockRange).length > 0 {
                    return true
                }
                i += 2
            }
            return false
        }
        
        // Custom interactive high-fidelity Markdown inline styling
        func highlightMarkdown(in textView: NSTextView) {
            logDebug("[SwashTextView] highlightMarkdown called")
            guard let textStorage = textView.textStorage, !isHighlighting else { return }
            isHighlighting = true
            
            let text = textView.string
            let fullRange = NSRange(location: 0, length: textStorage.length)
            
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
            
            // Helper to perform simple syntax highlighting on code lines
            func highlightCodeLine(_ line: String, offset: Int, language: String?) {
                guard let lang = language else { return }
                let lowerLang = lang.lowercased()
                
                // Common Comments
                if ["python", "bash", "sh"].contains(lowerLang) {
                    if let commentIdx = line.firstIndex(of: "#") {
                        let nsCommentStart = line.distance(from: line.startIndex, to: commentIdx)
                        let commentRange = NSRange(location: offset + nsCommentStart, length: line.utf16.count - nsCommentStart)
                        let valid = NSIntersectionRange(commentRange, NSRange(location: 0, length: textStorage.length))
                        if valid.length > 0 {
                            textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: valid)
                        }
                        return
                    }
                } else if ["javascript", "swift", "html", "css", "json"].contains(lowerLang) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") {
                        let valid = NSIntersectionRange(NSRange(location: offset, length: line.utf16.count), NSRange(location: 0, length: textStorage.length))
                        if valid.length > 0 {
                            textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: valid)
                        }
                        return
                    }
                }
                
                // Highlight keywords
                var keywords: [String] = []
                if ["javascript", "swift"].contains(lowerLang) {
                    keywords = ["func", "function", "let", "var", "const", "return", "class", "import", "if", "else", "for", "while", "in", "switch", "case", "break", "continue", "struct", "enum"]
                } else if lowerLang == "python" {
                    keywords = ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "in", "as", "try", "except", "lambda", "pass"]
                } else if lowerLang == "css" {
                    keywords = ["body", "html", "div", "span", "p", "a", "img", "button", "input", "label", "form", "section", "header", "footer", "h1", "h2", "h3"]
                } else if ["bash", "sh"].contains(lowerLang) {
                    keywords = ["if", "then", "else", "elif", "fi", "for", "while", "in", "do", "done", "case", "esac", "function", "return", "local", "echo", "exit"]
                }
                
                if !keywords.isEmpty {
                    let wordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
                    if let regex = try? NSRegularExpression(pattern: wordPattern, options: []) {
                        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count))
                        for match in matches {
                            let matchRange = NSRange(location: offset + match.range.location, length: match.range.length)
                            let valid = NSIntersectionRange(matchRange, NSRange(location: 0, length: textStorage.length))
                            if valid.length > 0 {
                                textStorage.addAttribute(.foregroundColor, value: NSColor.systemPink, range: valid)
                            }
                        }
                    }
                }
                
                // Highlight strings
                let stringPattern = "\"[^\"]*\"|'[^']*'"
                if let stringRegex = try? NSRegularExpression(pattern: stringPattern, options: []) {
                    let matches = stringRegex.matches(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count))
                    for match in matches {
                        let matchRange = NSRange(location: offset + match.range.location, length: match.range.length)
                        let valid = NSIntersectionRange(matchRange, NSRange(location: 0, length: textStorage.length))
                        if valid.length > 0 {
                            textStorage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: valid)
                        }
                    }
                }
                
                // Highlight numbers
                let numberPattern = "\\b\\d+\\b"
                if let numberRegex = try? NSRegularExpression(pattern: numberPattern, options: []) {
                    let matches = numberRegex.matches(in: line, options: [], range: NSRange(location: 0, length: line.utf16.count))
                    for match in matches {
                        let matchRange = NSRange(location: offset + match.range.location, length: match.range.length)
                        let valid = NSIntersectionRange(matchRange, NSRange(location: 0, length: textStorage.length))
                        if valid.length > 0 {
                            textStorage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: valid)
                        }
                    }
                }
            }
            
            NSTextAttachment.registerViewProviderClass(TableAttachmentViewProvider.self, forFileType: TableTextAttachment.fileTypeIdentifier)
            
            struct PendingTable {
                let range: NSRange
                let headers: [String]
                let alignments: [TableAlignment]
                let rows: [[String]]
            }
            var tablesToReplace: [PendingTable] = []
            
            // 2. Block-level parsing
            let lines = text.components(separatedBy: .newlines)
            var currentOffset = 0
            
            var inCodeBlock = false
            var currentLanguage: String? = nil
            var currentBlockStyle: NSTextBlock? = nil
            
            var lineIndex = 0
            while lineIndex < lines.count {
                let line = lines[lineIndex]
                let lineLength = line.utf16.count
                let lineRange = NSRange(location: currentOffset, length: lineLength)
                
                if line.hasPrefix("```") {
                    inCodeBlock = !inCodeBlock
                    if inCodeBlock {
                        let lang = line.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        currentLanguage = lang.isEmpty ? nil : lang
                        
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
                    } else {
                        currentLanguage = nil
                        currentBlockStyle = nil
                    }
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
                
                // Detect Table Block
                let isTableStart = trimmedLine.contains("|") && lineIndex + 1 < lines.count
                if isTableStart {
                    let nextTrimmed = lines[lineIndex + 1].trimmingCharacters(in: .whitespaces)
                    let isDelimiter = nextTrimmed.contains("|") && nextTrimmed.contains("-")
                    if isDelimiter {
                        let headers = MarkdownParser.parseTableCells(trimmedLine)
                        let alignments = MarkdownParser.parseAlignments(nextTrimmed)
                        
                        if !headers.isEmpty {
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
                            
                            tablesToReplace.append(PendingTable(range: tableFullRange, headers: headers, alignments: alignments, rows: tableRows))
                            
                            currentOffset = tableEndOffset
                            lineIndex = tableLineIdx
                            continue
                        }
                    }
                }
                
                let validLineRange = NSIntersectionRange(lineRange, NSRange(location: 0, length: textStorage.length))
                if validLineRange.length > 0 {
                    if line.hasPrefix("# ") {
                        textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 24, weight: .bold), range: validLineRange)
                        let hashRange = NSRange(location: currentOffset, length: min(lineLength, 2))
                        hideRange(hashRange)
                    } else if line.hasPrefix("## ") {
                        textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20, weight: .bold), range: validLineRange)
                        let hashRange = NSRange(location: currentOffset, length: min(lineLength, 3))
                        hideRange(hashRange)
                    } else if line.hasPrefix("### ") {
                        textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 17, weight: .bold), range: validLineRange)
                        let hashRange = NSRange(location: currentOffset, length: min(lineLength, 4))
                        hideRange(hashRange)
                    } else if line.hasPrefix("#### ") {
                        textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: validLineRange)
                        let hashRange = NSRange(location: currentOffset, length: min(lineLength, 5))
                        hideRange(hashRange)
                    } else if line.hasPrefix("> ") {
                        textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: validLineRange)
                        let italicFont = NSFontManager.shared.convert(defaultFont, toHaveTrait: .italicFontMask)
                        textStorage.addAttribute(.font, value: italicFont, range: validLineRange)
                        let quoteRange = NSRange(location: currentOffset, length: min(lineLength, 2))
                        hideRange(quoteRange)
                    } else {
                        if let listMarkerRange = trimmedLine.range(of: "^[-*+]\\s+", options: .regularExpression) {
                            let leadingSpacesCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                            let fullMarkerStr = String(trimmedLine[listMarkerRange])
                            let totalMarkerLen = fullMarkerStr.utf16.count
                            
                            // Hide raw list prefix text completely (making it 0 width and non-selectable)
                            let rawMarkerRange = NSRange(location: currentOffset + leadingSpacesCount, length: min(lineLength - leadingSpacesCount, totalMarkerLen))
                            hideRange(rawMarkerRange)
                            
                            let indent = CGFloat((leadingSpacesCount / 2 + 1) * 20)
                            let para = NSMutableParagraphStyle()
                            para.headIndent = indent
                            para.firstLineHeadIndent = indent
                            textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                            
                            // SwashLayoutManager draws a non-selectable "•" in the gutter margin
                            textStorage.addAttribute(.listMarker, value: ListMarkerInfo(text: "•", indent: indent), range: validLineRange)
                        } else if let numMarkerRange = trimmedLine.range(of: "^[0-9]+\\.\\s+", options: .regularExpression) {
                            let leadingSpacesCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                            let fullMarkerStr = String(trimmedLine[numMarkerRange])
                            let totalMarkerLen = fullMarkerStr.utf16.count
                            
                            let dotIdx = fullMarkerStr.firstIndex(of: ".") ?? fullMarkerStr.endIndex
                            let numberDotStr = String(fullMarkerStr[...dotIdx])
                            
                            // Hide raw list prefix text completely (making it 0 width and non-selectable)
                            let rawMarkerRange = NSRange(location: currentOffset + leadingSpacesCount, length: min(lineLength - leadingSpacesCount, totalMarkerLen))
                            hideRange(rawMarkerRange)
                            
                            let indent = CGFloat((leadingSpacesCount / 2 + 1) * 24)
                            let para = NSMutableParagraphStyle()
                            para.headIndent = indent
                            para.firstLineHeadIndent = indent
                            textStorage.addAttribute(.paragraphStyle, value: para, range: validLineRange)
                            
                            // SwashLayoutManager draws a non-selectable "1." in the gutter margin using standard text color
                            textStorage.addAttribute(.listMarker, value: ListMarkerInfo(text: numberDotStr, indent: indent), range: validLineRange)
                        }
                    }
                }
                
                currentOffset += lineLength + 1
                lineIndex += 1
            }
            
            // 3. Inline style parsing via regexes
            if parent.flavor == .slack {
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
                applyRegex(pattern: "`([^`\\n]+)`", in: text) { matchRange, contentRange in
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: contentRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 1))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
                }
                
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
                            
                            let validUrl = NSIntersectionRange(urlRange, NSRange(location: 0, length: textStorage.length))
                            if validUrl.length > 0 {
                                textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: validUrl)
                                textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: validUrl)
                            }
                            
                            textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: textRange)
                            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
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
                            textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: urlRange)
                            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: urlRange)
                            hideRange(leftPart)
                            hideRange(rightPart)
                        }
                    }
                }
            } else {
                // GitHub / Standard Markdown
                
                // Bold: **text**
                applyRegex(pattern: "(?<!\\*)\\*\\*([^*\\n]+?)\\*\\*(?!\\*)", in: text) { matchRange, contentRange in
                    let boldFont = NSFont.systemFont(ofSize: 14, weight: .bold)
                    textStorage.addAttribute(.font, value: boldFont, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 2))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 2, length: 2))
                }
                
                // Italic: *text* (single asterisk only)
                applyRegex(pattern: "(?<!\\*)\\*([^*\\n]+?)\\*(?!\\*)", in: text) { matchRange, contentRange in
                    let italicFont = NSFontManager.shared.convert(defaultFont, toHaveTrait: .italicFontMask)
                    textStorage.addAttribute(.font, value: italicFont, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 1))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
                }
                
                // Italic: _text_
                applyRegex(pattern: "(?<!_)(?<!\\w)_([^_\\n]+?)_(?!\\w)(?!_)", in: text) { matchRange, contentRange in
                    let italicFont = NSFontManager.shared.convert(defaultFont, toHaveTrait: .italicFontMask)
                    textStorage.addAttribute(.font, value: italicFont, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 1))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
                }
                
                // Strikethrough: ~~text~~
                applyRegex(pattern: "~~(?=\\S)([^~\\n]+?)(?<=\\S)~~", in: text) { matchRange, contentRange in
                    textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 2))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 2, length: 2))
                }
                
                // Inline Code: `code`
                applyRegex(pattern: "`([^`\\n]+)`", in: text) { matchRange, contentRange in
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: contentRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: contentRange)
                    hideRange(NSRange(location: matchRange.location, length: 1))
                    hideRange(NSRange(location: matchRange.location + matchRange.length - 1, length: 1))
                }
                
                // Links: [text](url)
                applyRegex(pattern: "\\[(.*?)\\]\\((.*?)\\)", in: text) { matchRange, contentRange in
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: contentRange)
                    textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                    
                    let leftBracket = NSRange(location: matchRange.location, length: 1)
                    let rightPartStart = contentRange.location + contentRange.length
                    let rightPartLen = matchRange.location + matchRange.length - rightPartStart
                    let rightPartRange = NSRange(location: rightPartStart, length: rightPartLen)
                    
                    hideRange(leftBracket)
                    hideRange(rightPartRange)
                }
            }
            
            // Bare URLs for both flavors: https?://...
            if let bareUrlRegex = try? NSRegularExpression(pattern: "https?://[^\\s<>\"'\\)]+", options: []) {
                let nsString = text as NSString
                let matches = bareUrlRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                for match in matches {
                    var matchRange = match.range(at: 0)
                    if isRangeInCodeBlock(matchRange, in: text) {
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
                            textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: validMatch)
                            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: validMatch)
                        }
                    }
                }
            }
            
            // 4. Replace Table Blocks with InteractiveTableView attachments (in reverse order)
            for table in tablesToReplace.reversed() {
                let validRange = NSIntersectionRange(table.range, NSRange(location: 0, length: textStorage.length))
                if validRange.length > 0 {
                    let tableData = MarkdownTableData(headers: table.headers, alignments: table.alignments, rows: table.rows)
                    var attachment: TableTextAttachment? = nil
                    attachment = TableTextAttachment(tableData: tableData, flavor: parent.flavor) { [weak self, weak textView] updatedData in
                        guard let self = self, let textView = textView, let textStorage = textView.textStorage, let attachment = attachment else { return }
                        attachment.tableData = updatedData
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
            }
            
            textStorage.endEditing()
            isHighlighting = false
            
            lastStyledText = text
            lastIsStyled = true
            lastFlavor = parent.flavor
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
            
            lastStyledText = textView.string
            lastIsStyled = false
            lastFlavor = parent.flavor
        }
        
        private func applyRegex(pattern: String, in text: String, action: (NSRange, NSRange) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let matchRange = match.range(at: 0)
                    if isRangeInCodeBlock(matchRange, in: text) {
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
