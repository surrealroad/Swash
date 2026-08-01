//
//  ContentView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case edit = "Source"
    case preview = "Formatted"
    case split = "Split"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .edit: return "text.alignleft"
        case .preview: return "character.cursor.ibeam"
        case .split: return "square.split.2x1"
        }
    }
    
    var tooltip: String {
        switch self {
        case .edit: return "Show source"
        case .preview: return "Edit text"
        case .split: return "Side-by-side view"
        }
    }
}





struct BubbleMenuSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

struct ContentView: View {
    @Binding var document: SwashDocument
    
    @State private var viewMode: ViewMode = .preview
    @State private var selectedRange: NSRange? = nil
    @State private var selectionRect: NSRect? = nil
    @State private var cellSelectionRect: NSRect? = nil
    @State private var cellActiveFormats: Set<FormatAction> = []
    @State private var bubbleMenuSize: CGSize = CGSize(width: 414, height: 40)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if viewMode == .preview {
                    SwashTextView(
                        text: $document.text,
                        selectedRange: $selectedRange,
                        selectionRect: $selectionRect,
                        isStyled: true,
                        flavor: document.flavor
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(bubbleMenuOverlay)
                } else if viewMode == .edit {
                    SwashTextView(
                        text: $document.text,
                        selectedRange: $selectedRange,
                        selectionRect: $selectionRect,
                        isStyled: false,
                        flavor: document.flavor
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
                            flavor: document.flavor
                        )
                        .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(bubbleMenuOverlay)
                        
                        MarkdownPreviewView(text: document.text, flavor: document.flavor)
                            .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Premium Bottom Status Bar
            statusView
        }
        .frame(minWidth: 600, idealWidth: 800, minHeight: 600, idealHeight: 750)
        .toolbar(id: "mainToolbar") {
            ToolbarItem(id: "flexibleSpace", placement: .automatic) {
                Spacer()
            }
            
            ToolbarItem(id: "viewMode_edit", placement: .primaryAction) {
                Toggle(isOn: Binding(
                    get: { viewMode == .edit },
                    set: { if $0 { viewMode = .edit } }
                )) {
                    Label(ViewMode.edit.rawValue, systemImage: ViewMode.edit.icon)
                }
                .toggleStyle(.button)
                .help(ViewMode.edit.tooltip)
            }
            
            ToolbarItem(id: "viewMode_preview", placement: .primaryAction) {
                Toggle(isOn: Binding(
                    get: { viewMode == .preview },
                    set: { if $0 { viewMode = .preview } }
                )) {
                    Label(ViewMode.preview.rawValue, systemImage: ViewMode.preview.icon)
                }
                .toggleStyle(.button)
                .help(ViewMode.preview.tooltip)
            }
            
            ToolbarItem(id: "viewMode_split", placement: .primaryAction) {
                Toggle(isOn: Binding(
                    get: { viewMode == .split },
                    set: { if $0 { viewMode = .split } }
                )) {
                    Label(ViewMode.split.rawValue, systemImage: ViewMode.split.icon)
                }
                .toggleStyle(.button)
                .help(ViewMode.split.tooltip)
            }
            
            ToolbarItem(id: "flavorPicker", placement: .primaryAction) {
                Picker("Flavor", selection: Binding(
                    get: { document.flavor },
                    set: { newFlavor in
                        let oldFlavor = document.flavor
                        if oldFlavor != newFlavor {
                            var updatedDoc = document
                            updatedDoc.text = MarkdownParser.convert(document.text, from: oldFlavor, to: newFlavor)
                            updatedDoc.flavor = newFlavor
                            document = updatedDoc
                        }
                    }
                )) {
                    ForEach(MarkdownFlavor.allCases) { flavor in
                        Text(flavor.rawValue).tag(flavor)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .help("Select Markdown format scheme (converting raw text format in place)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cellSelectionDidChange)) { notification in
            if let userInfo = notification.userInfo, let rect = userInfo["rect"] as? NSRect {
                self.cellSelectionRect = rect
                if let formats = userInfo["formats"] as? Set<FormatAction> {
                    self.cellActiveFormats = formats
                } else {
                    self.cellActiveFormats = []
                }
            } else {
                self.cellSelectionRect = nil
                self.cellActiveFormats = []
            }
        }
    }
    
    // Bubble menu overlay positioned relatively in local coordinates
    @ViewBuilder
    private var bubbleMenuOverlay: some View {
        GeometryReader { geometry in
            if let rect = selectionRect ?? cellSelectionRect {
                let activeCodeFormat = determineActiveCodeFormat()
                let activeHeadingLevel = determineActiveHeadingLevel()
                let bubbleContext = determineBubbleMenuContext()
                let activeLink = LinkDetector.findLink(at: selectedRange, in: document.text, flavor: document.flavor)
                let measuredWidth = bubbleMenuSize.width > 0 ? bubbleMenuSize.width : (activeCodeFormat != nil ? 426 : 380)
                let measuredHeight = bubbleMenuSize.height > 0 ? bubbleMenuSize.height : 40
                
                BubbleMenuView(
                    activeFormats: cellSelectionRect != nil ? cellActiveFormats : determineActiveFormats(),
                    activeCodeFormat: activeCodeFormat,
                    activeHeadingLevel: activeHeadingLevel,
                    activeLink: activeLink,
                    context: bubbleContext,
                    onAction: { action in
                        if cellSelectionRect != nil {
                            if action == .table {
                                NotificationCenter.default.post(name: .removeCurrentTable, object: nil)
                                cellSelectionRect = nil
                            } else {
                                NotificationCenter.default.post(name: .applyCellFormatting, object: nil, userInfo: ["action": action])
                            }
                        } else {
                            applyFormatting(action)
                        }
                    },
                    onSelectCodeFormat: { format in
                        applyCodeFormat(format)
                    },
                    onSelectHeadingLevel: { level in
                        applyHeadingLevel(level)
                    },
                    onApplyLink: { url in
                        applyLink(url: url, activeLink: activeLink)
                    },
                    onRemoveLink: {
                        removeLink(activeLink: activeLink)
                    }
                )
                .background(
                    GeometryReader { menuGeo in
                        Color.clear.preference(key: BubbleMenuSizePreferenceKey.self, value: menuGeo.size)
                    }
                )
                .onPreferenceChange(BubbleMenuSizePreferenceKey.self) { newSize in
                    if newSize.width > 0 && newSize.height > 0 && newSize != bubbleMenuSize {
                        bubbleMenuSize = newSize
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .position(
                    x: {
                        let padding: CGFloat = 12
                        if geometry.size.width <= measuredWidth + (padding * 2) {
                            return geometry.size.width / 2
                        } else {
                            let halfWidth = measuredWidth / 2
                            let minX = halfWidth + padding
                            let maxX = geometry.size.width - halfWidth - padding
                            return max(minX, min(rect.midX, maxX))
                        }
                    }(),
                    y: {
                        let spacing: CGFloat = 8
                        let padding: CGFloat = 8
                        let showBelow = (rect.minY - measuredHeight - spacing) < padding
                        let calculatedY: CGFloat
                        if showBelow {
                            calculatedY = rect.maxY + measuredHeight / 2 + spacing
                        } else {
                            calculatedY = rect.minY - measuredHeight / 2 - spacing
                        }
                        let halfHeight = measuredHeight / 2
                        let minY = halfHeight + padding
                        let maxY = geometry.size.height - halfHeight - padding
                        return max(minY, min(calculatedY, maxY))
                    }()
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: selectionRect)
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: activeCodeFormat)
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
                
                Text(document.flavor.displayName)
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
        let boldPrefix = document.flavor == .slack ? "*" : "**"
        let boldSuffix = document.flavor == .slack ? "*" : "**"
        if isWrapped(prefix: boldPrefix, suffix: boldSuffix) {
            active.insert(.bold)
        }
        
        // 2. Italic
        let italicPrefix = document.flavor == .slack ? "_" : "*"
        let italicSuffix = document.flavor == .slack ? "_" : "*"
        if document.flavor == .github || document.flavor == .commonMark || document.flavor == .original {
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
        let strikePrefix = document.flavor == .slack ? "~" : "~~"
        let strikeSuffix = document.flavor == .slack ? "~" : "~~"
        if isWrapped(prefix: strikePrefix, suffix: strikeSuffix) {
            active.insert(.strikethrough)
        }
        
        // 5. Line-based blocks
        let lineRange = (fullText as NSString).lineRange(for: range)
        if let fullLineRange = Range(lineRange, in: fullText) {
            let lineText = String(fullText[fullLineRange]).trimmingCharacters(in: .whitespaces)
            if lineText.hasPrefix("###### ") {
                active.insert(.h6)
                active.insert(.heading)
            } else if lineText.hasPrefix("##### ") {
                active.insert(.h5)
                active.insert(.heading)
            } else if lineText.hasPrefix("#### ") {
                active.insert(.h4)
                active.insert(.heading)
            } else if lineText.hasPrefix("### ") {
                active.insert(.h3)
                active.insert(.heading)
            } else if lineText.hasPrefix("## ") {
                active.insert(.h2)
                active.insert(.heading)
            } else if lineText.hasPrefix("# ") {
                active.insert(.h1)
                active.insert(.heading)
            } else if lineText.hasPrefix("> ") {
                active.insert(.quote)
            } else if lineText.hasPrefix("- ") || lineText.hasPrefix("* ") || lineText.hasPrefix("+ ") {
                active.insert(.bulletList)
            } else if let _ = lineText.range(of: "^[0-9]+\\.\\s+", options: .regularExpression) {
                active.insert(.numberedList)
            }
        }
        
        return active
    }
    
    private func determineActiveHeadingLevel() -> Int? {
        guard let range = selectedRange else { return nil }
        let fullText = document.text
        let lineRange = (fullText as NSString).lineRange(for: range)
        guard let fullLineRange = Range(lineRange, in: fullText) else { return nil }
        let lineText = String(fullText[fullLineRange]).trimmingCharacters(in: .whitespaces)
        
        if lineText.hasPrefix("###### ") { return 6 }
        if lineText.hasPrefix("##### ") { return 5 }
        if lineText.hasPrefix("#### ") { return 4 }
        if lineText.hasPrefix("### ") { return 3 }
        if lineText.hasPrefix("## ") { return 2 }
        if lineText.hasPrefix("# ") { return 1 }
        return nil
    }
    
    private func determineSmartHeadingLevel() -> Int {
        guard let range = selectedRange else { return 1 }
        let fullText = document.text as NSString
        let location = range.location
        guard location > 0 && fullText.length > 0 else { return 1 }
        
        let precedingText = fullText.substring(to: min(location, fullText.length))
        let lines = precedingText.components(separatedBy: .newlines)
        
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("###### ") {
                return 6
            } else if trimmed.hasPrefix("##### ") {
                return 5
            } else if trimmed.hasPrefix("#### ") {
                return 4
            } else if trimmed.hasPrefix("### ") {
                return 3
            } else if trimmed.hasPrefix("## ") {
                return 2
            } else if trimmed.hasPrefix("# ") {
                return 2
            }
        }
        return 1
    }
    
    private func determineBubbleMenuContext() -> BubbleMenuContext {
        if determineActiveCodeFormat() != nil || isSelectionInsideCodeBlock().inside {
            return .codeBlock
        }
        
        guard let range = selectedRange else { return .standard }
        let fullText = document.text
        let lineRange = (fullText as NSString).lineRange(for: range)
        guard let fullLineRange = Range(lineRange, in: fullText) else { return .standard }
        let lineText = String(fullText[fullLineRange]).trimmingCharacters(in: .whitespaces)
        
        if lineText.hasPrefix("|") || lineText.hasSuffix("|") || lineText.contains(" | ") {
            return .tableCell
        }
        
        if lineText.hasPrefix("#") {
            let hashes = lineText.prefix(while: { $0 == "#" })
            if hashes.count >= 1 && hashes.count <= 6 && lineText.dropFirst(hashes.count).hasPrefix(" ") {
                return .heading
            }
        }
        
        if lineText.hasPrefix("> ") {
            return .blockquote
        }
        
        if lineText.hasPrefix("- ") || lineText.hasPrefix("* ") || lineText.hasPrefix("+ ") || lineText.range(of: "^[0-9]+\\.\\s+", options: .regularExpression) != nil {
            return .listItem
        }
        
        return .standard
    }
    
    private func applyHeadingLevel(_ level: Int) {
        guard let range = selectedRange else { return }
        let fullText = document.text
        let lineRange = (fullText as NSString).lineRange(for: range)
        guard let fullLineRange = Range(lineRange, in: fullText) else { return }
        
        let lineText = String(fullText[fullLineRange])
        var cleanLine = lineText
        var removedPrefix = ""
        
        if cleanLine.hasPrefix("###### ") {
            removedPrefix = "###### "
            cleanLine.removeFirst(7)
        } else if cleanLine.hasPrefix("##### ") {
            removedPrefix = "##### "
            cleanLine.removeFirst(6)
        } else if cleanLine.hasPrefix("#### ") {
            removedPrefix = "#### "
            cleanLine.removeFirst(5)
        } else if cleanLine.hasPrefix("### ") {
            removedPrefix = "### "
            cleanLine.removeFirst(4)
        } else if cleanLine.hasPrefix("## ") {
            removedPrefix = "## "
            cleanLine.removeFirst(3)
        } else if cleanLine.hasPrefix("# ") {
            removedPrefix = "# "
            cleanLine.removeFirst(2)
        } else if cleanLine.hasPrefix("> ") {
            removedPrefix = "> "
            cleanLine.removeFirst(2)
        } else if cleanLine.hasPrefix("- ") || cleanLine.hasPrefix("* ") || cleanLine.hasPrefix("+ ") {
            removedPrefix = String(cleanLine.prefix(2))
            cleanLine.removeFirst(2)
        } else if let matchRange = cleanLine.range(of: "^[0-9]+\\.\\s+", options: .regularExpression) {
            let matchLen = cleanLine[matchRange].count
            removedPrefix = String(cleanLine.prefix(matchLen))
            cleanLine.removeFirst(matchLen)
        }
        
        let blockPrefix = String(repeating: "#", count: level) + " "
        let formatted = "\(blockPrefix)\(cleanLine)"
        let newText = fullText.replacingCharacters(in: fullLineRange, with: formatted)
        document.text = newText
        
        let shift = blockPrefix.count - removedPrefix.count
        if range.location + shift >= 0 {
            selectedRange = NSRange(location: range.location + shift, length: range.length)
        }
    }
    
    private func convertSelectedTextToTableMarkdown(_ text: String) -> String {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return """
            | Header 1 | Header 2 |
            | :--- | :--- |
            | Cell 1 | Cell 2 |
            """
        }
        
        let rawLines = cleanText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !rawLines.isEmpty else {
            return """
            | Header 1 | Header 2 |
            | :--- | :--- |
            | Cell 1 | Cell 2 |
            """
        }
        
        var parsedRows: [[String]] = []
        for line in rawLines {
            var cells: [String] = []
            if line.contains("|") {
                cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else if line.contains("\t") {
                cells = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            } else {
                if let regex = try? NSRegularExpression(pattern: "\\s{2,}") {
                    let nsLine = line as NSString
                    let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
                    var lastIndex = 0
                    for match in matches {
                        let cellRange = NSRange(location: lastIndex, length: match.range.location - lastIndex)
                        let cellText = nsLine.substring(with: cellRange).trimmingCharacters(in: .whitespaces)
                        if !cellText.isEmpty {
                            cells.append(cellText)
                        }
                        lastIndex = match.range.location + match.range.length
                    }
                    if lastIndex < nsLine.length {
                        let remaining = nsLine.substring(from: lastIndex).trimmingCharacters(in: .whitespaces)
                        if !remaining.isEmpty {
                            cells.append(remaining)
                        }
                    }
                }
                if cells.isEmpty {
                    cells = [line]
                }
            }
            if !cells.isEmpty {
                parsedRows.append(cells)
            }
        }
        
        guard !parsedRows.isEmpty else {
            return """
            | Header 1 | Header 2 |
            | :--- | :--- |
            | Cell 1 | Cell 2 |
            """
        }
        
        let maxCols = max(2, parsedRows.map { $0.count }.max() ?? 2)
        
        var headers = parsedRows.removeFirst()
        while headers.count < maxCols {
            headers.append("Header \(headers.count + 1)")
        }
        
        var rows: [[String]] = []
        if parsedRows.isEmpty {
            rows.append(Array(repeating: "", count: maxCols))
        } else {
            for var row in parsedRows {
                while row.count < maxCols {
                    row.append("")
                }
                rows.append(row)
            }
        }
        
        var markdownLines: [String] = []
        markdownLines.append("| " + headers.joined(separator: " | ") + " |")
        markdownLines.append("| " + Array(repeating: ":---", count: maxCols).joined(separator: " | ") + " |")
        for row in rows {
            markdownLines.append("| " + row.joined(separator: " | ") + " |")
        }
        
        return markdownLines.joined(separator: "\n")
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
        case .heading:
            if determineActiveHeadingLevel() != nil {
                // Toggle heading OFF
                let lineRange = (fullText as NSString).lineRange(for: range)
                guard let fullLineRange = Range(lineRange, in: fullText) else { return }
                let lineText = String(fullText[fullLineRange])
                var cleanLine = lineText
                var removedPrefix = ""
                
                if cleanLine.hasPrefix("###### ") {
                    removedPrefix = "###### "
                    cleanLine.removeFirst(7)
                } else if cleanLine.hasPrefix("##### ") {
                    removedPrefix = "##### "
                    cleanLine.removeFirst(6)
                } else if cleanLine.hasPrefix("#### ") {
                    removedPrefix = "#### "
                    cleanLine.removeFirst(5)
                } else if cleanLine.hasPrefix("### ") {
                    removedPrefix = "### "
                    cleanLine.removeFirst(4)
                } else if cleanLine.hasPrefix("## ") {
                    removedPrefix = "## "
                    cleanLine.removeFirst(3)
                } else if cleanLine.hasPrefix("# ") {
                    removedPrefix = "# "
                    cleanLine.removeFirst(2)
                }
                
                let newText = fullText.replacingCharacters(in: fullLineRange, with: cleanLine)
                document.text = newText
                newSelectedRange = NSRange(location: max(0, range.location - removedPrefix.count), length: range.length)
            } else {
                // Toggle heading ON with smart level based on context
                let targetLevel = determineSmartHeadingLevel()
                applyHeadingLevel(targetLevel)
                return
            }
            
        case .h1: applyHeadingLevel(1); return
        case .h2: applyHeadingLevel(2); return
        case .h3: applyHeadingLevel(3); return
        case .h4: applyHeadingLevel(4); return
        case .h5: applyHeadingLevel(5); return
        case .h6: applyHeadingLevel(6); return
            
        case .bold, .italic, .strikethrough:
            let prefix: String
            let suffix: String
            
            switch action {
            case .bold:
                prefix = document.flavor == .slack ? "*" : "**"
                suffix = document.flavor == .slack ? "*" : "**"
            case .italic:
                if document.flavor == .github || document.flavor == .commonMark || document.flavor == .original {
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
                prefix = document.flavor == .slack ? "~" : "~~"
                suffix = document.flavor == .slack ? "~" : "~~"
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
            
        case .quote, .bulletList, .numberedList:
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
            } else if cleanLine.hasPrefix("### ") {
                removedPrefix = "### "
                cleanLine.removeFirst(4)
            } else if cleanLine.hasPrefix("#### ") {
                removedPrefix = "#### "
                cleanLine.removeFirst(5)
            } else if cleanLine.hasPrefix("##### ") {
                removedPrefix = "##### "
                cleanLine.removeFirst(6)
            } else if cleanLine.hasPrefix("###### ") {
                removedPrefix = "###### "
                cleanLine.removeFirst(7)
            } else if cleanLine.hasPrefix("> ") {
                removedPrefix = "> "
                cleanLine.removeFirst(2)
            } else if cleanLine.hasPrefix("- ") || cleanLine.hasPrefix("* ") || cleanLine.hasPrefix("+ ") {
                removedPrefix = String(cleanLine.prefix(2))
                cleanLine.removeFirst(2)
            } else if let matchRange = cleanLine.range(of: "^[0-9]+\\.\\s+", options: .regularExpression) {
                let matchLen = cleanLine[matchRange].count
                removedPrefix = String(cleanLine.prefix(matchLen))
                cleanLine.removeFirst(matchLen)
            }
            
            let blockPrefix: String
            switch action {
            case .quote: blockPrefix = "> "
            case .bulletList: blockPrefix = "- "
            case .numberedList: blockPrefix = "1. "
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
        case .table:
            if cellSelectionRect != nil {
                NotificationCenter.default.post(name: .removeCurrentTable, object: nil)
                cellSelectionRect = nil
                return
            }
            let tableTemplate = convertSelectedTextToTableMarkdown(selectedText)
            let newText = fullText.replacingCharacters(in: textRange, with: tableTemplate)
            document.text = newText
            newSelectedRange = NSRange(location: range.location, length: tableTemplate.utf16.count)
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
    
    private func applyLink(url: String, activeLink: DetectedLink?) {
        let fullText = document.text
        
        if let link = activeLink {
            // EDITING existing link
            let updatedText: String
            if document.flavor == .slack {
                updatedText = "<\(url)|\(link.text)>"
            } else {
                updatedText = "[\(link.text)](\(url))"
            }
            
            if let replaceRange = Range(link.fullRange, in: fullText) {
                let newText = fullText.replacingCharacters(in: replaceRange, with: updatedText)
                document.text = newText
                selectedRange = NSRange(location: link.fullRange.location, length: (updatedText as NSString).length)
            }
        } else if let range = selectedRange, let textRange = Range(range, in: fullText) {
            // ADDING link to selected text
            let selectedText = String(fullText[textRange])
            let displayText = selectedText.isEmpty ? url : selectedText
            let insertedText: String
            if document.flavor == .slack {
                insertedText = "<\(url)|\(displayText)>"
            } else {
                insertedText = "[\(displayText)](\(url))"
            }
            
            let newText = fullText.replacingCharacters(in: textRange, with: insertedText)
            document.text = newText
            selectedRange = NSRange(location: range.location, length: (insertedText as NSString).length)
        }
    }
    
    private func removeLink(activeLink: DetectedLink?) {
        guard let link = activeLink,
              let replaceRange = Range(link.fullRange, in: document.text) else { return }
        
        let newText = document.text.replacingCharacters(in: replaceRange, with: link.text)
        document.text = newText
        selectedRange = NSRange(location: link.fullRange.location, length: (link.text as NSString).length)
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
