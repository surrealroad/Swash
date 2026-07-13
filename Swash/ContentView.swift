//
//  ContentView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case edit = "Editor"
    case split = "Split"
    case preview = "Preview"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .edit: return "text.alignleft"
        case .split: return "square.split.2x1"
        case .preview: return "eye"
        }
    }
}

enum MarkdownFlavor: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case slack = "Slack"
    
    var id: String { self.rawValue }
}

struct ContentView: View {
    @Binding var document: SwashDocument
    
    @State private var viewMode: ViewMode = .preview
    @State private var selectedRange: NSRange? = nil
    @State private var selectionRect: NSRect? = nil
    @AppStorage("markdownFlavor") private var markdownFlavor: MarkdownFlavor = .github

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if viewMode == .preview {
                    SwashTextView(
                        text: $document.text,
                        selectedRange: $selectedRange,
                        selectionRect: $selectionRect,
                        isStyled: true,
                        flavor: markdownFlavor
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(bubbleMenuOverlay)
                } else if viewMode == .edit {
                    SwashTextView(
                        text: $document.text,
                        selectedRange: $selectedRange,
                        selectionRect: $selectionRect,
                        isStyled: false,
                        flavor: markdownFlavor
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(bubbleMenuOverlay)
                } else if viewMode == .split {
                    HSplitView {
                        SwashTextView(
                            text: $document.text,
                            selectedRange: $selectedRange,
                            selectionRect: $selectionRect,
                            isStyled: false,
                            flavor: markdownFlavor
                        )
                        .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(bubbleMenuOverlay)
                        
                        MarkdownPreviewView(text: document.text, flavor: markdownFlavor)
                            .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Premium Bottom Status Bar
            statusView
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Layout", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Toggle layout modes: Editor only, Split, or Preview only")
            }
            
            ToolbarItem(placement: .primaryAction) {
                Picker("Flavor", selection: $markdownFlavor) {
                    ForEach(MarkdownFlavor.allCases) { flavor in
                        Text(flavor.rawValue).tag(flavor)
                    }
                }
                .pickerStyle(.menu)
                .help("Select Markdown format scheme: GitHub or Slack mrkdwn")
            }
        }
    }
    
    // Bubble menu overlay positioned relatively in local coordinates
    @ViewBuilder
    private var bubbleMenuOverlay: some View {
        GeometryReader { geometry in
            if let rect = selectionRect {
                let activeCodeFormat = determineActiveCodeFormat()
                let menuWidth: CGFloat = activeCodeFormat != nil ? 322 : 246
                let menuHeight: CGFloat = 40
                
                BubbleMenuView(
                    activeFormats: determineActiveFormats(),
                    activeCodeFormat: activeCodeFormat,
                    onAction: { action in
                        applyFormatting(action)
                    },
                    onSelectCodeFormat: { format in
                        applyCodeFormat(format)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .position(
                    x: {
                        if geometry.size.width <= menuWidth + 20 {
                            return geometry.size.width / 2
                        } else {
                            let halfWidth = menuWidth / 2
                            let minX = halfWidth + 10
                            let maxX = geometry.size.width - halfWidth - 10
                            return max(minX, min(rect.midX, maxX))
                        }
                    }(),
                    y: {
                        let spacing: CGFloat = 8
                        let showBelow = (rect.minY - menuHeight - spacing) < 0
                        let calculatedY: CGFloat
                        if showBelow {
                            calculatedY = rect.maxY + menuHeight / 2 + spacing
                        } else {
                            calculatedY = rect.minY - menuHeight / 2 - spacing
                        }
                        return max(menuHeight / 2 + 10, min(calculatedY, geometry.size.height - menuHeight / 2 - 10))
                    }()
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: selectionRect)
            }
        }
    }
    
    // Status panel rendering word/character count stats
    private var statusView: some View {
        HStack {
            HStack(spacing: 8) {
                Text(viewMode.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("•")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text(markdownFlavor == .slack ? "Slack mrkdwn" : "GitHub Markdown")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            let stats = calculateStats()
            Text("\(stats.words) words   •   \(stats.chars) characters")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        .overlay(
            Divider(), alignment: .top
        )
    }
    
    // Determine active formats for current selection
    private func determineActiveFormats() -> Set<FormatAction> {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return [] }
        
        var active = Set<FormatAction>()
        let fullText = document.text
        
        // Helper to check if selection or surrounding is wrapped
        func isWrapped(prefix: String, suffix: String) -> Bool {
            let selectedText = String(fullText[textRange])
            if selectedText.hasPrefix(prefix) && selectedText.hasSuffix(suffix) && selectedText.count >= (prefix.count + suffix.count) {
                return true
            }
            
            let startIdx = textRange.lowerBound
            let endIdx = textRange.upperBound
            if let prefixStart = fullText.index(startIdx, offsetBy: -prefix.count, limitedBy: fullText.startIndex),
               let suffixEnd = fullText.index(endIdx, offsetBy: suffix.count, limitedBy: fullText.endIndex) {
                let before = String(fullText[prefixStart..<startIdx])
                let after = String(fullText[endIdx..<suffixEnd])
                if before == prefix && after == suffix {
                    return true
                }
            }
            return false
        }
        
        // 1. Bold
        let boldPrefix = markdownFlavor == .slack ? "*" : "**"
        let boldSuffix = markdownFlavor == .slack ? "*" : "**"
        if isWrapped(prefix: boldPrefix, suffix: boldSuffix) {
            active.insert(.bold)
        }
        
        // 2. Italic
        let italicPrefix = markdownFlavor == .slack ? "_" : "*"
        let italicSuffix = markdownFlavor == .slack ? "_" : "*"
        if markdownFlavor == .github {
            let selectedText = String(fullText[textRange])
            let hasGithubItalic = (selectedText.hasPrefix("*") && !selectedText.hasPrefix("**") && selectedText.hasSuffix("*") && !selectedText.hasSuffix("**") && selectedText.count >= 2) ||
                                  (selectedText.hasPrefix("_") && selectedText.hasSuffix("_") && selectedText.count >= 2)
            
            var surroundingGithubItalic = false
            let startIdx = textRange.lowerBound
            let endIdx = textRange.upperBound
            if let prefixStart1 = fullText.index(startIdx, offsetBy: -1, limitedBy: fullText.startIndex),
               let suffixEnd1 = fullText.index(endIdx, offsetBy: 1, limitedBy: fullText.endIndex) {
                var hasPrevAsterisk = false
                if let prefixStart2 = fullText.index(startIdx, offsetBy: -2, limitedBy: fullText.startIndex) {
                    hasPrevAsterisk = fullText[prefixStart2] == "*"
                }
                var hasNextAsterisk = false
                if let suffixEnd2 = fullText.index(endIdx, offsetBy: 2, limitedBy: fullText.endIndex) {
                    hasNextAsterisk = fullText[suffixEnd2] == "*"
                }
                let before = String(fullText[prefixStart1..<startIdx])
                let after = String(fullText[endIdx..<suffixEnd1])
                if (before == "*" && after == "*" && !hasPrevAsterisk && !hasNextAsterisk) || (before == "_" && after == "_") {
                    surroundingGithubItalic = true
                }
            }
            if hasGithubItalic || surroundingGithubItalic {
                active.insert(.italic)
            }
        } else {
            if isWrapped(prefix: italicPrefix, suffix: italicSuffix) {
                active.insert(.italic)
            }
        }
        
        // 3. Code (Inline or Block)
        if determineActiveCodeFormat() != nil {
            active.insert(.code)
        }
        
        // 4. Strikethrough
        let strikePrefix = markdownFlavor == .slack ? "~" : "~~"
        let strikeSuffix = markdownFlavor == .slack ? "~" : "~~"
        if isWrapped(prefix: strikePrefix, suffix: strikeSuffix) {
            active.insert(.strikethrough)
        }
        
        // 5. Line-based blocks
        let lineRange = (fullText as NSString).lineRange(for: range)
        if let fullLineRange = Range(lineRange, in: fullText) {
            let lineText = String(fullText[fullLineRange]).trimmingCharacters(in: .whitespaces)
            if lineText.hasPrefix("# ") {
                active.insert(.h1)
            } else if lineText.hasPrefix("## ") {
                active.insert(.h2)
            } else if lineText.hasPrefix("> ") {
                active.insert(.quote)
            }
        }
        
        return active
    }
    
    // Apply formatting or toggle it off if already active
    private func applyFormatting(_ action: FormatAction) {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return }
        
        let fullText = document.text
        let selectedText = String(fullText[textRange])
        
        let activeFormats = determineActiveFormats()
        let isActive = activeFormats.contains(action)
        
        var formatted = ""
        var newSelectedRange: NSRange? = nil
        
        switch action {
        case .bold, .italic, .strikethrough:
            let prefix: String
            let suffix: String
            
            switch action {
            case .bold:
                prefix = markdownFlavor == .slack ? "*" : "**"
                suffix = markdownFlavor == .slack ? "*" : "**"
            case .italic:
                if markdownFlavor == .github {
                    let isUnderscore = selectedText.hasPrefix("_") && selectedText.hasSuffix("_")
                    var isSurroundingUnderscore = false
                    if let startIdx = fullText.index(textRange.lowerBound, offsetBy: -1, limitedBy: fullText.startIndex),
                       let endIdx = fullText.index(textRange.upperBound, offsetBy: 1, limitedBy: fullText.endIndex) {
                        isSurroundingUnderscore = fullText[startIdx] == "_" && fullText[endIdx] == "_"
                    }
                    if isUnderscore || isSurroundingUnderscore {
                        prefix = "_"
                        suffix = "_"
                    } else {
                        prefix = "*"
                        suffix = "*"
                    }
                } else {
                    prefix = "_"
                    suffix = "_"
                }
            case .strikethrough:
                prefix = markdownFlavor == .slack ? "~" : "~~"
                suffix = markdownFlavor == .slack ? "~" : "~~"
            default:
                prefix = ""
                suffix = ""
            }
            
            if isActive {
                // UNTOGGLE (remove formatting)
                if selectedText.hasPrefix(prefix) && selectedText.hasSuffix(suffix) && selectedText.count >= (prefix.count + suffix.count) {
                    let start = selectedText.index(selectedText.startIndex, offsetBy: prefix.count)
                    let end = selectedText.index(selectedText.endIndex, offsetBy: -suffix.count)
                    formatted = String(selectedText[start..<end])
                    
                    let newText = fullText.replacingCharacters(in: textRange, with: formatted)
                    document.text = newText
                    
                    newSelectedRange = NSRange(location: range.location, length: range.length - prefix.count - suffix.count)
                } else if let prefixStart = fullText.index(textRange.lowerBound, offsetBy: -prefix.count, limitedBy: fullText.startIndex),
                          let suffixEnd = fullText.index(textRange.upperBound, offsetBy: suffix.count, limitedBy: fullText.endIndex) {
                    let before = String(fullText[prefixStart..<textRange.lowerBound])
                    let after = String(fullText[textRange.upperBound..<suffixEnd])
                    
                    if before == prefix && after == suffix {
                        formatted = selectedText
                        let replaceRange = prefixStart..<suffixEnd
                        let newText = fullText.replacingCharacters(in: replaceRange, with: formatted)
                        document.text = newText
                        
                        newSelectedRange = NSRange(location: range.location - prefix.count, length: range.length)
                    }
                }
            } else {
                // TOGGLE ON (add formatting)
                formatted = "\(prefix)\(selectedText)\(suffix)"
                let newText = fullText.replacingCharacters(in: textRange, with: formatted)
                document.text = newText
                
                newSelectedRange = NSRange(location: range.location + prefix.count, length: range.length)
            }
            
        case .code:
            if isActive {
                if let stripped = getRawTextAndRangeForCode() {
                    let newText = fullText.replacingCharacters(in: stripped.replaceRange, with: stripped.rawText)
                    document.text = newText
                    
                    let startLocation = NSRange(stripped.replaceRange, in: fullText).location
                    newSelectedRange = NSRange(location: startLocation, length: stripped.rawText.utf16.count)
                }
            } else {
                formatted = "`\(selectedText)`"
                let newText = fullText.replacingCharacters(in: textRange, with: formatted)
                document.text = newText
                
                newSelectedRange = NSRange(location: range.location + 1, length: range.length)
            }
            
        case .h1, .h2, .quote:
            let lineRange = (fullText as NSString).lineRange(for: range)
            guard let fullLineRange = Range(lineRange, in: fullText) else { return }
            
            let lineText = String(fullText[fullLineRange])
            var cleanLine = lineText
            
            var removedPrefix = ""
            if cleanLine.hasPrefix("# ") {
                removedPrefix = "# "
                cleanLine.removeFirst(2)
            } else if cleanLine.hasPrefix("## ") {
                removedPrefix = "## "
                cleanLine.removeFirst(3)
            } else if cleanLine.hasPrefix("> ") {
                removedPrefix = "> "
                cleanLine.removeFirst(2)
            }
            
            let blockPrefix: String
            switch action {
            case .h1: blockPrefix = "# "
            case .h2: blockPrefix = "## "
            case .quote: blockPrefix = "> "
            default: blockPrefix = ""
            }
            
            if isActive {
                formatted = cleanLine
                let newText = fullText.replacingCharacters(in: fullLineRange, with: formatted)
                document.text = newText
                
                newSelectedRange = NSRange(location: range.location - removedPrefix.count, length: range.length)
            } else {
                formatted = "\(blockPrefix)\(cleanLine)"
                let newText = fullText.replacingCharacters(in: fullLineRange, with: formatted)
                document.text = newText
                
                let shift = blockPrefix.count - removedPrefix.count
                newSelectedRange = NSRange(location: range.location + shift, length: range.length)
            }
        }
        
        if let newRange = newSelectedRange, newRange.location >= 0 {
            selectedRange = newRange
        } else {
            selectedRange = nil
            selectionRect = nil
        }
    }
    
    private func isSelectionInsideCodeBlock() -> (inside: Bool, language: String?) {
        guard let range = selectedRange else { return (false, nil) }
        let fullText = document.text
        let nsText = fullText as NSString
        
        // Count ``` lines before the selected range
        let prefixText = nsText.substring(to: range.location)
        let lines = prefixText.components(separatedBy: .newlines)
        
        var count = 0
        var lastLang: String? = nil
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                count += 1
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                lastLang = lang.isEmpty ? nil : lang
            }
        }
        
        if count % 2 == 1 {
            return (true, lastLang)
        }
        return (false, nil)
    }
    
    private func determineActiveCodeFormat() -> CodeFormat? {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return nil }
        
        let fullText = document.text
        let selectedText = String(fullText[textRange])
        
        // Check if selected text is wrapped in a code block
        let trimmedSelected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSelected.hasPrefix("```") && trimmedSelected.hasSuffix("```") && trimmedSelected.count >= 6 {
            let lines = trimmedSelected.components(separatedBy: .newlines)
            if let firstLine = lines.first, firstLine.hasPrefix("```") {
                let lang = firstLine.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                if lang.isEmpty { return .plainBlock }
                return CodeFormat.allCases.first(where: { $0.languageSignifier == lang }) ?? .plainBlock
            }
            return .plainBlock
        }
        
        // Check if selection is inside a code block
        let insideCheck = isSelectionInsideCodeBlock()
        if insideCheck.inside {
            if let lang = insideCheck.language {
                return CodeFormat.allCases.first(where: { $0.languageSignifier == lang }) ?? .plainBlock
            }
            return .plainBlock
        }
        
        // Check if selected text is inline code
        if selectedText.hasPrefix("`") && selectedText.hasSuffix("`") && !selectedText.hasPrefix("```") && selectedText.count >= 2 {
            return .inline
        }
        
        // Check if selection is surrounded by `
        let startIdx = textRange.lowerBound
        let endIdx = textRange.upperBound
        if let prefixStart = fullText.index(startIdx, offsetBy: -1, limitedBy: fullText.startIndex),
           let suffixEnd = fullText.index(endIdx, offsetBy: 1, limitedBy: fullText.endIndex) {
            let before = String(fullText[prefixStart..<startIdx])
            let after = String(fullText[endIdx..<suffixEnd])
            if before == "`" && after == "`" {
                return .inline
            }
        }
        
        return nil
    }
    
    private func getRawTextAndRangeForCode() -> (rawText: String, replaceRange: Range<String.Index>)? {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return nil }
              
        let fullText = document.text
        let selectedText = String(fullText[textRange])
        
        // Case 1: Selected text itself has ``` block
        let trimmedSelected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSelected.hasPrefix("```") && trimmedSelected.hasSuffix("```") && trimmedSelected.count >= 6 {
            let lines = selectedText.components(separatedBy: .newlines)
            if lines.count >= 2 {
                var middleLines = lines
                middleLines.removeFirst()
                middleLines.removeLast()
                let raw = middleLines.joined(separator: "\n")
                return (raw, textRange)
            }
        }
        
        // Case 2: Selection is inside a ``` block
        let insideCheck = isSelectionInsideCodeBlock()
        if insideCheck.inside {
            let nsText = fullText as NSString
            let prefixText = nsText.substring(to: range.location)
            let suffixText = nsText.substring(from: range.location + range.length)
            
            let prefixLines = prefixText.components(separatedBy: .newlines)
            let suffixLines = suffixText.components(separatedBy: .newlines)
            
            var openingLineIndexInPrefix = -1
            for (idx, line) in prefixLines.enumerated().reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    openingLineIndexInPrefix = idx
                    break
                }
            }
            
            var closingLineIndexInSuffix = -1
            for (idx, line) in suffixLines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    closingLineIndexInSuffix = idx
                    break
                }
            }
            
            if openingLineIndexInPrefix != -1 && closingLineIndexInSuffix != -1 {
                let openingLines = prefixLines[0..<openingLineIndexInPrefix]
                let openingOffset = openingLines.joined(separator: "\n").utf16.count + (openingLines.isEmpty ? 0 : 1)
                
                let suffixLinesBeforeClosing = suffixLines[0...closingLineIndexInSuffix]
                let closingOffset = range.location + range.length + suffixLinesBeforeClosing.joined(separator: "\n").utf16.count
                
                let totalNSRange = NSRange(location: openingOffset, length: closingOffset - openingOffset)
                if let totalRange = Range(totalNSRange, in: fullText) {
                    let blockText = String(fullText[totalRange])
                    let lines = blockText.components(separatedBy: .newlines)
                    if lines.count >= 2 {
                        var middleLines = lines
                        middleLines.removeFirst()
                        middleLines.removeLast()
                        let raw = middleLines.joined(separator: "\n")
                        return (raw, totalRange)
                    }
                }
            }
        }
        
        // Case 3: Selected text itself has ` inline
        if selectedText.hasPrefix("`") && selectedText.hasSuffix("`") && !selectedText.hasPrefix("```") && selectedText.count >= 2 {
            let start = selectedText.index(selectedText.startIndex, offsetBy: 1)
            let end = selectedText.index(selectedText.endIndex, offsetBy: -1)
            return (String(selectedText[start..<end]), textRange)
        }
        
        // Case 4: Selection is surrounded by ` inline
        let startIdx = textRange.lowerBound
        let endIdx = textRange.upperBound
        if let prefixStart = fullText.index(startIdx, offsetBy: -1, limitedBy: fullText.startIndex),
           let suffixEnd = fullText.index(endIdx, offsetBy: 1, limitedBy: fullText.endIndex) {
            let before = String(fullText[prefixStart..<startIdx])
            let after = String(fullText[endIdx..<suffixEnd])
            if before == "`" && after == "`" {
                return (selectedText, prefixStart..<suffixEnd)
            }
        }
        
        return nil
    }
    
    private func applyCodeFormat(_ format: CodeFormat) {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return }
              
        let fullText = document.text
        let selectedText = String(fullText[textRange])
        
        let rawText: String
        let replaceRange: Range<String.Index>
        
        if let stripped = getRawTextAndRangeForCode() {
            rawText = stripped.rawText
            replaceRange = stripped.replaceRange
        } else {
            rawText = selectedText
            replaceRange = textRange
        }
        
        let formatted: String
        switch format {
        case .inline:
            formatted = "`\(rawText)`"
        case .plainBlock:
            formatted = "```\n\(rawText)\n```"
        default:
            let langStr = format.languageSignifier ?? ""
            formatted = "```\(langStr)\n\(rawText)\n```"
        }
        
        let newText = fullText.replacingCharacters(in: replaceRange, with: formatted)
        document.text = newText
        
        let startLocation = NSRange(replaceRange, in: fullText).location
        let newLocation: Int
        let newLength: Int
        
        switch format {
        case .inline:
            newLocation = startLocation + 1
            newLength = rawText.utf16.count
        case .plainBlock:
            newLocation = startLocation + 4
            newLength = rawText.utf16.count
        default:
            let langStr = format.languageSignifier ?? ""
            newLocation = startLocation + 4 + langStr.utf16.count
            newLength = rawText.utf16.count
        }
        
        selectedRange = NSRange(location: newLocation, length: newLength)
    }
    
    private func calculateStats() -> (words: Int, chars: Int) {
        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (0, 0) }
        
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        let chars = document.text.count
        
        return (words, chars)
    }
}

#Preview {
    ContentView(document: .constant(SwashDocument()))
}
