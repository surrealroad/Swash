//
//  SwashTextView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import AppKit

struct SwashTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange?
    @Binding var selectionRect: NSRect? // Bounding rect of selection in the local coordinate space of SwashTextView (SwiftUI top-left)
    var isStyled: Bool
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
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
        
        // Custom background and scrollview configs
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        
        // Monitor scrolling to dynamically reposition the floating bubble menu
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
        
        if textView.string != text {
            textView.string = text
        }
        
        // Re-run the styling/highlighting based on mode
        if isStyled {
            context.coordinator.highlightMarkdown(in: textView)
        } else {
            context.coordinator.applyPlainStyle(in: textView)
        }
        
        // Update selection if needed
        if let range = selectedRange, textView.selectedRange() != range {
            textView.setSelectedRange(range)
        }
        
        context.coordinator.isUpdatingFromSwiftUI = false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SwashTextView
        var isUpdatingFromSwiftUI = false
        var isHighlighting = false
        
        init(_ parent: SwashTextView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if !isUpdatingFromSwiftUI {
                parent.text = textView.string
                
                if parent.isStyled {
                    highlightMarkdown(in: textView)
                } else {
                    applyPlainStyle(in: textView)
                }
            }
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            updateSelectionRect(for: notification.object as? NSTextView)
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
            
            DispatchQueue.main.async {
                if range.length > 0 {
                    self.parent.selectedRange = range
                    
                    if let layoutManager = textView.layoutManager,
                       let textContainer = textView.textContainer {
                        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
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
        }
        
        // Intercept typing attributes inheritance so typing next to or inside hidden tags resets to normal size/color
        func textView(_ textView: NSTextView, shouldChangeTypingAttributes typingAttributes: [NSAttributedString.Key : Any] = [:], toAttributes newAttributes: [NSAttributedString.Key : Any] = [:]) -> [NSAttributedString.Key : Any] {
            var attrs = newAttributes
            if let font = attrs[.font] as? NSFont, font.pointSize < 1.0 {
                attrs[.font] = NSFont.systemFont(ofSize: 14, weight: .regular)
            }
            if let color = attrs[.foregroundColor] as? NSColor, color == .clear {
                attrs[.foregroundColor] = NSColor.textColor
            }
            return attrs
        }
        
        // Custom interactive high-fidelity Markdown inline styling
        func highlightMarkdown(in textView: NSTextView) {
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
                textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: range)
                textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            }
            
            // 2. Block-level parsing
            let lines = text.components(separatedBy: .newlines)
            var currentOffset = 0
            
            var inCodeBlock = false
            
            for line in lines {
                let lineLength = line.utf16.count
                let lineRange = NSRange(location: currentOffset, length: lineLength)
                
                if line.hasPrefix("```") {
                    inCodeBlock = !inCodeBlock
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: lineRange)
                    currentOffset += lineLength + 1
                    continue
                }
                
                if inCodeBlock {
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: lineRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(0.85), range: lineRange)
                    currentOffset += lineLength + 1
                    continue
                }
                
                if line.hasPrefix("# ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 24, weight: .bold), range: lineRange)
                    let hashRange = NSRange(location: currentOffset, length: min(lineLength, 2))
                    hideRange(hashRange)
                } else if line.hasPrefix("## ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 20, weight: .bold), range: lineRange)
                    let hashRange = NSRange(location: currentOffset, length: min(lineLength, 3))
                    hideRange(hashRange)
                } else if line.hasPrefix("### ") {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 17, weight: .bold), range: lineRange)
                    let hashRange = NSRange(location: currentOffset, length: min(lineLength, 4))
                    hideRange(hashRange)
                } else if line.hasPrefix("> ") {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
                    let italicFont = NSFontManager.shared.convert(defaultFont, toHaveTrait: .italicFontMask)
                    textStorage.addAttribute(.font, value: italicFont, range: lineRange)
                    let quoteRange = NSRange(location: currentOffset, length: min(lineLength, 2))
                    hideRange(quoteRange)
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("1. ") {
                    let bulletLen = line.hasPrefix("1. ") ? 3 : 2
                    let bulletRange = NSRange(location: currentOffset, length: min(lineLength, bulletLen))
                    textStorage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: bulletRange)
                }
                
                currentOffset += lineLength + 1
            }
            
            // 3. Inline style parsing via regexes
            // Bold: **text**
            applyRegex(pattern: "\\*\\*(.*?)\\*\\*", in: text) { matchRange, contentRange in
                let boldFont = NSFont.systemFont(ofSize: 14, weight: .bold)
                textStorage.addAttribute(.font, value: boldFont, range: contentRange)
                
                let leftStars = NSRange(location: matchRange.location, length: 2)
                let rightStars = NSRange(location: matchRange.location + matchRange.length - 2, length: 2)
                hideRange(leftStars)
                hideRange(rightStars)
            }
            
            // Italic: *text*
            applyRegex(pattern: "\\*([^*]+)\\*", in: text) { matchRange, contentRange in
                let italicFont = NSFontManager.shared.convert(defaultFont, toHaveTrait: .italicFontMask)
                textStorage.addAttribute(.font, value: italicFont, range: contentRange)
                let leftStar = NSRange(location: matchRange.location, length: 1)
                let rightStar = NSRange(location: matchRange.location + matchRange.length - 1, length: 1)
                hideRange(leftStar)
                hideRange(rightStar)
            }
            
            // Inline Code: `code`
            applyRegex(pattern: "`([^`]+)`", in: text) { matchRange, contentRange in
                textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: contentRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: contentRange)
                
                let leftQuote = NSRange(location: matchRange.location, length: 1)
                let rightQuote = NSRange(location: matchRange.location + matchRange.length - 1, length: 1)
                hideRange(leftQuote)
                hideRange(rightQuote)
            }
            
            // Links: [text](url)
            applyRegex(pattern: "\\[(.*?)\\]\\((.*?)\\)", in: text) { matchRange, contentRange in
                textStorage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: contentRange)
                
                let leftBracket = NSRange(location: matchRange.location, length: 1)
                let rightPartStart = contentRange.location + contentRange.length
                let rightPartLen = matchRange.location + matchRange.length - rightPartStart
                let rightPartRange = NSRange(location: rightPartStart, length: rightPartLen)
                
                hideRange(leftBracket)
                hideRange(rightPartRange)
            }
            
            textStorage.endEditing()
            isHighlighting = false
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
        }
        
        private func applyRegex(pattern: String, in text: String, action: (NSRange, NSRange) -> Void) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges >= 2 {
                    action(match.range(at: 0), match.range(at: 1))
                }
            }
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
