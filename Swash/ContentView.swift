//
//  ContentView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import UniformTypeIdentifiers

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

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if self.window != nsView.window {
            DispatchQueue.main.async {
                self.window = nsView.window
            }
        }
    }
}

struct ContentView: View {
    @Binding var document: SwashDocument
    var fileURL: URL? = nil
    
    @State private var viewMode: ViewMode = .preview
    @State private var selectedRange: NSRange? = nil
    @State private var selectionRect: NSRect? = nil
    @State private var cellSelectionRect: NSRect? = nil
    @State private var cellActiveFormats: Set<FormatAction> = []
    @State private var bubbleMenuSize: CGSize = CGSize(width: 414, height: 40)
    
    @State private var window: NSWindow? = nil
    @State private var previousSingleWidth: CGFloat = 800
    @State private var previousSplitWidth: CGFloat = 1200
    @State private var scrollSync = ScrollSync()

    @ObservedObject private var folderAccessManager = FolderAccessManager.shared
    @State private var editor = SwashEditorController()
    @State private var dismissedFolderBanner: URL? = nil

    private var effectiveBaseURL: URL? {
        fileURL ?? window?.representedURL ?? (window.flatMap { NSDocumentController.shared.document(for: $0)?.fileURL })
    }

    private var unreadableFolderURL: URL? {
        guard let unreadable = MarkdownParser.unreadableRelativeFolder(in: document.text, baseURL: effectiveBaseURL) else {
            return nil
        }
        if dismissedFolderBanner == unreadable {
            return nil
        }
        return unreadable
    }

    var body: some View {
        VStack(spacing: 0) {
            if let folderURL = unreadableFolderURL {
                folderAccessBanner(for: folderURL)
            }
            
            ZStack(alignment: .topLeading) {
                if viewMode == .preview {
                    SwashTextView(
                        text: $document.text,
                        selectedRange: $selectedRange,
                        selectionRect: $selectionRect,
                        scrollSync: scrollSync,
                        isStyled: true,
                        flavor: document.flavor,
                        baseURL: effectiveBaseURL,
                        controller: editor,
                        onFormatCommand: { handleFormatCommand($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(bubbleMenuOverlay)
                } else if viewMode == .edit {
                    SwashTextView(
                        text: $document.text,
                        selectedRange: $selectedRange,
                        selectionRect: $selectionRect,
                        scrollSync: scrollSync,
                        isStyled: false,
                        flavor: document.flavor,
                        baseURL: effectiveBaseURL,
                        controller: editor,
                        onFormatCommand: { handleFormatCommand($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(bubbleMenuOverlay)
                } else if viewMode == .split {
                    HSplitView {
                        SwashTextView(
                            text: $document.text,
                            selectedRange: $selectedRange,
                            selectionRect: $selectionRect,
                            scrollSync: scrollSync,
                            isStyled: false,
                            flavor: document.flavor,
                            baseURL: effectiveBaseURL,
                            controller: editor,
                            onFormatCommand: { handleFormatCommand($0) }
                        )
                        .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(bubbleMenuOverlay)
                        
                        MarkdownPreviewView(text: document.text, flavor: document.flavor, baseURL: effectiveBaseURL, scrollSync: scrollSync)
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
            
            ToolbarItem(id: "viewMode", placement: .primaryAction) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .help(mode.tooltip)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose how the document is shown")
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
            
            ToolbarItem(id: "share", placement: .primaryAction) {
                ShareLink(
                    item: document.text,
                    subject: Text(documentTitle),
                    message: Text(document.text),
                    preview: SharePreview(Text(documentTitle), image: sharePreviewImage)
                ) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share raw Markdown text with other apps")
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
        .background(WindowAccessor(window: $window))
        .focusedSceneValue(\.formatCommandHandler, { handleFormatCommand($0) })
        .onChange(of: viewMode) { oldMode, newMode in
            handleViewModeChange(from: oldMode, to: newMode)
        }
    }
    
    private var documentTitle: String {
        if let title = window?.title, !title.isEmpty {
            let cleaned = title
                .components(separatedBy: " — ").first?
                .components(separatedBy: " - ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cleaned.isEmpty && cleaned != "Untitled" {
                return cleaned
            }
        }
        if let url = window?.representedURL {
            let name = url.deletingPathExtension().lastPathComponent
            if !name.isEmpty {
                return name
            }
        }
        let lines = document.text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return title
                }
            }
        }
        if let title = window?.title, !title.isEmpty {
            let cleaned = title
                .components(separatedBy: " — ").first?
                .components(separatedBy: " - ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return "Untitled"
    }

    private var sharePreviewImage: Image {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.isTemplate = false
        
        image.lockFocus()
        let docIcon = NSWorkspace.shared.icon(for: UTType(filenameExtension: "md") ?? .plainText)
        docIcon.isTemplate = false
        docIcon.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        image.unlockFocus()
        
        return Image(nsImage: image)
    }
    
    // Bubble menu overlay positioned relatively in local coordinates
    @ViewBuilder
    private var bubbleMenuOverlay: some View {
        GeometryReader { geometry in
            if let rect = selectionRect ?? cellSelectionRect {
                let activeCodeFormat = determineActiveCodeFormat()
                let activeHeadingLevel = determineActiveHeadingLevel()
                let bubbleContext = determineBubbleMenuContext()
                let activeLink = determineActiveLink()
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
    
    private func folderAccessBanner(for folderURL: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.accentColor)
            
            Text("Swash needs permission to access files in **\(folderURL.lastPathComponent)** to display linked images.")
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Button("Grant Access…") {
                FolderAccessManager.shared.promptForAccess(to: folderURL, window: window) { success in
                    if success {
                        dismissedFolderBanner = nil
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("GrantFolderAccessButton")
            
            Button(action: {
                dismissedFolderBanner = folderURL
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityIdentifier("DismissFolderAccessButton")
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
    
    // Determine active formats for current selection
    private func determineActiveFormats() -> Set<FormatAction> {
        if let formatting = astFormatting, let range = selectedRange {
            var active = Set<FormatAction>()
            if formatting.isActive(.strong, selection: range) { active.insert(.bold) }
            if formatting.isActive(.emphasis, selection: range) { active.insert(.italic) }
            if formatting.isActive(.strikethrough, selection: range) { active.insert(.strikethrough) }
            if determineActiveCodeFormat() != nil { active.insert(.code) }
            switch formatting.activeBlockFormat(selection: range) {
            case .bulletList?: active.insert(.bulletList)
            case .numberedList?: active.insert(.numberedList)
            case .heading(let level)?:
                active.insert(.heading)
                let levels: [FormatAction] = [.h1, .h2, .h3, .h4, .h5, .h6]
                if (1...6).contains(level) { active.insert(levels[level - 1]) }
            default: break
            }
            if formatting.isQuoted(selection: range) { active.insert(.quote) }
            return active
        }
        guard let range = selectedRange,
              let textRange = Range(inlineTargetRange(range), in: document.text) else { return [] }
        
        var active = Set<FormatAction>()
        let fullText = document.text
        
        // Multi-line selections: a format is active when every line segment carries it
        let segments = inlineLineSegments(in: range)
        if segments.count > 1 {
            let nsText = fullText as NSString
            for action in [FormatAction.bold, .italic, .strikethrough] {
                let (prefix, suffix) = inlineMarkers(for: action, selectedText: "")
                if segments.allSatisfy({ isSegment(nsText.substring(with: $0), wrappedBy: prefix, suffix) }) {
                    active.insert(action)
                }
            }
        }
        
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
        if let block = extractSelectedBlockLines(from: fullText, range: range) {
            let lines = block.lines
            let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let targetLines = nonEmptyLines.isEmpty ? lines : nonEmptyLines
            
            if !targetLines.isEmpty {
                let infos = targetLines.map { parseLinePrefix($0) }
                
                if infos.allSatisfy({ $0.kind == .bulletList }) {
                    active.insert(.bulletList)
                }
                if infos.allSatisfy({ $0.kind == .numberedList }) {
                    active.insert(.numberedList)
                }
                if infos.allSatisfy({ $0.kind == .quote }) {
                    active.insert(.quote)
                }
                if infos.allSatisfy({ if case .heading = $0.kind { return true }; return false }) {
                    active.insert(.heading)
                    if let firstKind = infos.first?.kind, infos.allSatisfy({ $0.kind == firstKind }) {
                        switch firstKind {
                        case .heading(1): active.insert(.h1)
                        case .heading(2): active.insert(.h2)
                        case .heading(3): active.insert(.h3)
                        case .heading(4): active.insert(.h4)
                        case .heading(5): active.insert(.h5)
                        case .heading(6): active.insert(.h6)
                        default: break
                        }
                    }
                }
            }
        }
        
        return active
    }
    
    // MARK: - Line & Block Helpers
    
    struct LinePrefixInfo {
        let leadingSpaces: String
        let rawPrefix: String
        let cleanLine: String
        let kind: Kind
        
        enum Kind: Equatable {
            case none
            case heading(level: Int)
            case quote
            case bulletList
            case numberedList
            case taskList
        }
    }
    
    private func parseLinePrefix(_ line: String) -> LinePrefixInfo {
        let leadingSpacesCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let leadingSpaces = String(line.prefix(leadingSpacesCount))
        let trimmed = String(line.dropFirst(leadingSpacesCount))
        
        if trimmed.hasPrefix("###### ") {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: "###### ", cleanLine: String(trimmed.dropFirst(7)), kind: .heading(level: 6))
        } else if trimmed.hasPrefix("##### ") {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: "##### ", cleanLine: String(trimmed.dropFirst(6)), kind: .heading(level: 5))
        } else if trimmed.hasPrefix("#### ") {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: "#### ", cleanLine: String(trimmed.dropFirst(5)), kind: .heading(level: 4))
        } else if trimmed.hasPrefix("### ") {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: "### ", cleanLine: String(trimmed.dropFirst(4)), kind: .heading(level: 3))
        } else if trimmed.hasPrefix("## ") {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: "## ", cleanLine: String(trimmed.dropFirst(3)), kind: .heading(level: 2))
        } else if trimmed.hasPrefix("# ") {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: "# ", cleanLine: String(trimmed.dropFirst(2)), kind: .heading(level: 1))
        } else if trimmed.hasPrefix("> ") {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: "> ", cleanLine: String(trimmed.dropFirst(2)), kind: .quote)
        } else if let taskRange = trimmed.range(of: "^[-*+]\\s+\\[[ xX]\\]\\s+", options: .regularExpression) {
            let prefixStr = String(trimmed[taskRange])
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: prefixStr, cleanLine: String(trimmed[taskRange.upperBound...]), kind: .taskList)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: String(trimmed.prefix(2)), cleanLine: String(trimmed.dropFirst(2)), kind: .bulletList)
        } else if let matchRange = trimmed.range(of: "^[0-9]+[.)]\\s+", options: .regularExpression) {
            let matchLen = trimmed[matchRange].count
            let prefixStr = String(trimmed.prefix(matchLen))
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: prefixStr, cleanLine: String(trimmed.dropFirst(matchLen)), kind: .numberedList)
        } else {
            return LinePrefixInfo(leadingSpaces: leadingSpaces, rawPrefix: "", cleanLine: trimmed, kind: .none)
        }
    }
    
    struct SelectedBlock {
        let lines: [String]
        let hasTrailingNewline: Bool
        let fullLineRange: Range<String.Index>
    }
    
    private func extractSelectedBlockLines(from fullText: String, range: NSRange) -> SelectedBlock? {
        let lineRange = (fullText as NSString).lineRange(for: range)
        guard let fullLineRange = Range(lineRange, in: fullText) else { return nil }
        
        var selectedSubstring = String(fullText[fullLineRange])
        let hasTrailingNewline = selectedSubstring.hasSuffix("\n")
        if hasTrailingNewline {
            selectedSubstring.removeLast()
            if selectedSubstring.hasSuffix("\r") {
                selectedSubstring.removeLast()
            }
        }
        
        let lines = selectedSubstring.components(separatedBy: "\n").map { line -> String in
            if line.hasSuffix("\r") { return String(line.dropLast()) }
            return line
        }
        
        return SelectedBlock(lines: lines, hasTrailingNewline: hasTrailingNewline, fullLineRange: fullLineRange)
    }
    
    private func determineActiveHeadingLevel() -> Int? {
        if let formatting = astFormatting, let range = selectedRange {
            if case .heading(let level)? = formatting.activeBlockFormat(selection: range) { return level }
            return nil
        }
        guard let range = selectedRange,
              let block = extractSelectedBlockLines(from: document.text, range: range) else { return nil }
        
        let nonEmptyLines = block.lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let targetLines = nonEmptyLines.isEmpty ? block.lines : nonEmptyLines
        guard !targetLines.isEmpty else { return nil }
        
        var foundLevel: Int? = nil
        for line in targetLines {
            let info = parseLinePrefix(line)
            if case .heading(let level) = info.kind {
                if foundLevel == nil {
                    foundLevel = level
                } else if foundLevel != level {
                    return nil
                }
            } else {
                return nil
            }
        }
        return foundLevel
    }
    
    private func determineSmartHeadingLevel() -> Int {
        guard let range = selectedRange else { return 1 }
        let fullText = document.text as NSString
        let location = range.location
        guard location > 0 && fullText.length > 0 else { return 1 }
        
        let precedingText = fullText.substring(to: min(location, fullText.length))
        let lines = precedingText.components(separatedBy: .newlines)
        
        for line in lines.reversed() {
            let info = parseLinePrefix(line)
            if case .heading(let level) = info.kind {
                if level == 1 { return 2 }
                return level
            }
        }
        return 1
    }
    
    private func determineBubbleMenuContext() -> BubbleMenuContext {
        if determineActiveCodeFormat() != nil || isSelectionInsideCodeBlock().inside {
            return .codeBlock
        }
        if let formatting = astFormatting, let range = selectedRange {
            if formatting.isInTable(range) { return .tableCell }
            let containers = formatting.inlineContainers(intersecting: range)
            guard !containers.isEmpty else { return .standard }
            func isHeading(_ n: MarkdownNode) -> Bool { if case .heading = n.kind { return true }; return false }
            func inList(_ n: MarkdownNode) -> Bool { n.ancestors.contains { if case .listItem = $0.kind { return true }; return false } }
            func inQuote(_ n: MarkdownNode) -> Bool {
                n.ancestors.contains { switch $0.kind { case .blockQuote, .alert: return true; default: return false } }
            }
            if containers.allSatisfy(isHeading) { return .heading }
            if containers.contains(where: inList) { return .listItem }
            if containers.contains(where: isHeading) { return .heading }
            if containers.contains(where: inQuote) { return .blockquote }
            return .standard
        }
        
        guard let range = selectedRange,
              let block = extractSelectedBlockLines(from: document.text, range: range) else { return .standard }
        
        let nonEmptyLines = block.lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let targetLines = nonEmptyLines.isEmpty ? block.lines : nonEmptyLines
        
        if selectionTouchesTable(range) {
            return .tableCell
        }
        
        let kinds = targetLines.map { parseLinePrefix($0).kind }
        if kinds.allSatisfy({ if case .heading = $0 { return true }; return false }) {
            return .heading
        }
        if kinds.allSatisfy({ if case .quote = $0 { return true }; return false }) {
            return .blockquote
        }
        if kinds.contains(where: { $0 == .bulletList || $0 == .numberedList || $0 == .taskList }) {
            return .listItem
        }
        if kinds.contains(where: { if case .heading = $0 { return true }; return false }) {
            return .heading
        }
        if kinds.contains(where: { if case .quote = $0 { return true }; return false }) {
            return .blockquote
        }
        
        return .standard
    }
    
    private func applyHeadingLevel(_ level: Int) {
        if let formatting = astFormatting, let range = selectedRange {
            if let edit = formatting.toggleBlock(.heading(level), selection: range) {
                commitEdit(edit.text, selection: edit.selection, actionName: "Heading \(level)")
            }
            return
        }
        guard let range = selectedRange,
              let block = extractSelectedBlockLines(from: document.text, range: range) else { return }
        
        let fullText = document.text
        let blockPrefix = String(repeating: "#", count: level) + " "
        
        var newLines: [String] = []
        var firstLineShift = 0
        for (index, line) in block.lines.enumerated() {
            let info = parseLinePrefix(line)
            newLines.append("\(info.leadingSpaces)\(blockPrefix)\(info.cleanLine)")
            if index == 0 {
                firstLineShift = blockPrefix.utf16.count - info.rawPrefix.utf16.count
            }
        }
        
        var formatted = newLines.joined(separator: "\n")
        if block.hasTrailingNewline { formatted += "\n" }
        
        let newText = fullText.replacingCharacters(in: block.fullLineRange, with: formatted)
        
        let oldNSRange = NSRange(block.fullLineRange, in: fullText)
        let newSelection: NSRange
        if range.length == 0 {
            newSelection = NSRange(location: max(0, range.location + firstLineShift), length: 0)
        } else {
            let newLen = (formatted as NSString).length - (block.hasTrailingNewline ? 1 : 0)
            newSelection = NSRange(location: oldNSRange.location, length: max(0, newLen))
        }
        commitEdit(newText, selection: newSelection, actionName: "Heading \(level)")
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

    // MARK: - Keyboard & Format Menu Commands
    
    /// Handles shortcuts and Format menu items using the live editor selection (carets included).
    private func handleFormatCommand(_ command: FormatCommand) {
        if let live = editor.currentRawSelection {
            selectedRange = live
        }
        guard let range = selectedRange else { return }
        switch command {
        case .bold: applyFormatting(.bold)
        case .italic: applyFormatting(.italic)
        case .strikethrough: applyFormatting(.strikethrough)
        case .code: applyFormatting(.code)
        case .codeBlock: applyCodeFormat(.plainBlock)
        case .heading(let level): applyHeadingLevel(level)
        case .quote: applyFormatting(.quote)
        case .bulletList: applyFormatting(.bulletList)
        case .numberedList: applyFormatting(.numberedList)
        case .paragraph, .taskList:
            guard let formatting = astFormatting else { return }
            let format: MarkdownBlockFormat = command == .paragraph ? .paragraph : .taskList
            if let edit = formatting.toggleBlock(format, selection: range) {
                commitEdit(edit.text, selection: edit.selection, actionName: command == .paragraph ? "Paragraph" : "To-do List")
            }
        case .link:
            promptForLink()
        }
    }
    
    /// ⌘K: asks for a URL (pre-filled from the current link or a URL on the clipboard) and applies it.
    private func promptForLink() {
        let current = determineActiveLink()
        let alert = NSAlert()
        alert.messageText = current == nil ? "Add Link" : "Edit Link"
        alert.addButton(withTitle: current == nil ? "Add" : "Update")
        alert.addButton(withTitle: "Cancel")
        if current != nil { alert.addButton(withTitle: "Remove Link") }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "https://example.com"
        if let url = current?.url {
            field.stringValue = url
        } else if let clip = NSPasteboard.general.string(forType: .string), let url = URL(string: clip), url.scheme != nil {
            field.stringValue = clip
        }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let respond: (NSApplication.ModalResponse) -> Void = { response in
            let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            switch response {
            case .alertFirstButtonReturn where !url.isEmpty: applyLink(url: url, activeLink: current)
            case .alertThirdButtonReturn: removeLink(activeLink: current)
            default: break
            }
        }
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }
    
    // MARK: - AST Formatting
    
    /// The parsed document for CommonMark/GFM flavors (Slack mrkdwn keeps the legacy string logic).
    private var astFormatting: MarkdownFormatting? {
        document.flavor == .slack ? nil : editor.formatting(for: document.text)
    }
    
    private func determineActiveLink() -> DetectedLink? {
        guard let formatting = astFormatting else {
            return LinkDetector.findLink(at: selectedRange, in: document.text, flavor: document.flavor)
        }
        guard let range = selectedRange, let node = formatting.link(at: range),
              case .link(let destination, _, let kind) = node.kind, kind != .extendedAutolink else { return nil }
        let textRange = formatting.linkTextRange(node)
        let text = (document.text as NSString).substring(with: textRange)
        return DetectedLink(fullRange: node.range, textRange: textRange, urlRange: node.range, text: text, url: destination, isBareURL: false)
    }
    
    /// Applies inline and block actions through the AST engine; returns false for actions it does not handle.
    private func applyASTFormatting(_ action: FormatAction, formatting: MarkdownFormatting, range: NSRange) -> Bool {
        var edit: MarkdownEdit? = nil
        switch action {
        case .bold: edit = formatting.toggle(.strong, selection: range)
        case .italic: edit = formatting.toggle(.emphasis, selection: range)
        case .strikethrough: edit = formatting.toggle(.strikethrough, selection: range)
        case .code:
            // Code blocks and existing spans use the code-format path; multi-line text becomes a block
            if determineActiveCodeFormat() != nil { return false }
            if formatting.segments(in: range).count > 1 {
                applyCodeFormat(.plainBlock)
                return true
            }
            edit = formatting.toggle(.code, selection: range)
        case .quote: edit = formatting.toggleBlock(.quote, selection: range)
        case .bulletList: edit = formatting.toggleBlock(.bulletList, selection: range)
        case .numberedList: edit = formatting.toggleBlock(.numberedList, selection: range)
        case .heading:
            if determineActiveHeadingLevel() != nil {
                edit = formatting.toggleBlock(.paragraph, selection: range)
            } else {
                applyHeadingLevel(determineSmartHeadingLevel())
                return true
            }
        case .h1, .h2, .h3, .h4, .h5, .h6, .table:
            return false
        }
        if let edit = edit {
            commitEdit(edit.text, selection: edit.selection, actionName: actionName(for: action))
        }
        return true
    }
    
    // MARK: - Editing Helpers
    
    /// Applies a bubble-menu edit. In the live editor this is a minimal, undoable text-view edit;
    /// without an attached editor (e.g. Preview-only) the document text is replaced directly.
    private func commitEdit(_ newText: String, selection: NSRange?, actionName: String) {
        if !editor.apply(newText: newText, selection: selection, actionName: actionName) {
            document.text = newText
        }
        if let selection = selection, selection.location >= 0 {
            selectedRange = selection
        } else {
            selectedRange = nil
            selectionRect = nil
        }
    }
    
    /// Selection with leading/trailing whitespace removed, so wrapping a double-clicked word
    /// (which includes its trailing space) produces valid emphasis such as `**word** `.
    private func trimmedInlineRange(_ range: NSRange) -> NSRange {
        let nsText = document.text as NSString
        guard range.location + range.length <= nsText.length else { return range }
        var start = range.location
        var end = range.location + range.length
        let whitespace = CharacterSet.whitespacesAndNewlines
        func isSpace(_ i: Int) -> Bool {
            guard let scalar = UnicodeScalar(nsText.character(at: i)) else { return false }
            return whitespace.contains(scalar)
        }
        while start < end && isSpace(start) { start += 1 }
        while end > start && isSpace(end - 1) { end -= 1 }
        return start == end ? range : NSRange(location: start, length: end - start)
    }
    
    /// The non-empty, whitespace-trimmed part of each selected line, excluding block markers
    /// (`- `, `> `, `## `…) for lines selected from their start.
    private func inlineLineSegments(in range: NSRange) -> [NSRange] {
        let nsText = document.text as NSString
        guard range.length > 0, range.location + range.length <= nsText.length else { return [] }
        var segments: [NSRange] = []
        let selectionEnd = range.location + range.length
        var lineStart = nsText.lineRange(for: NSRange(location: range.location, length: 0)).location
        while lineStart < selectionEnd {
            var contentsEnd = 0
            var lineEnd = 0
            nsText.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
            let line = nsText.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
            let info = parseLinePrefix(line)
            let markerEnd = lineStart + (info.leadingSpaces + info.rawPrefix).utf16.count
            let segStart = max(range.location, markerEnd)
            let segEnd = min(selectionEnd, contentsEnd)
            if segEnd > segStart {
                let trimmed = trimmedInlineRange(NSRange(location: segStart, length: segEnd - segStart))
                let text = nsText.substring(with: trimmed)
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    segments.append(trimmed)
                }
            }
            if lineEnd <= lineStart { break }
            lineStart = lineEnd
        }
        return segments
    }
    
    /// The span an inline format applies to: the selection's line segment (markers and
    /// surrounding whitespace excluded), or the raw selection for a caret.
    private func inlineTargetRange(_ range: NSRange) -> NSRange {
        inlineLineSegments(in: range).first ?? trimmedInlineRange(range)
    }
    
    private func inlineMarkers(for action: FormatAction, selectedText: String) -> (String, String) {
        let isSlack = document.flavor == .slack
        switch action {
        case .bold: return isSlack ? ("*", "*") : ("**", "**")
        case .strikethrough: return isSlack ? ("~", "~") : ("~~", "~~")
        case .italic:
            if isSlack { return ("_", "_") }
            return selectedText.hasPrefix("_") && selectedText.hasSuffix("_") ? ("_", "_") : ("*", "*")
        default: return ("", "")
        }
    }
    
    private func isSegment(_ text: String, wrappedBy prefix: String, _ suffix: String) -> Bool {
        guard text.count >= prefix.count + suffix.count + 1, text.hasPrefix(prefix), text.hasSuffix(suffix) else { return false }
        if prefix == "*" {
            // `*x*` but not `**x**`
            return !(text.hasPrefix("**") && text.hasSuffix("**"))
        }
        return true
    }
    
    /// True when the selection overlaps a real GFM table (header row + delimiter row), as opposed
    /// to prose that merely contains a `|` character.
    private func selectionTouchesTable(_ range: NSRange) -> Bool {
        let nsText = document.text as NSString
        let lines = document.text.components(separatedBy: "\n")
        let delimiterPattern = "^\\s*\\|?\\s*:?-+:?\\s*(\\|\\s*:?-+:?\\s*)*\\|?\\s*$"
        func isDelimiter(_ i: Int) -> Bool {
            i >= 0 && i < lines.count && lines[i].contains("-") &&
                lines[i].range(of: delimiterPattern, options: .regularExpression) != nil
        }
        let firstLine = nsText.substring(to: min(range.location, nsText.length)).components(separatedBy: "\n").count - 1
        let lastLine = nsText.substring(to: min(range.location + range.length, nsText.length)).components(separatedBy: "\n").count - 1
        for index in firstLine...max(firstLine, lastLine) where index < lines.count && lines[index].contains("|") {
            // Walk up through contiguous pipe rows looking for a header followed by a delimiter row
            var k = index
            while k >= 0 && lines[k].contains("|") {
                if isDelimiter(k + 1) || isDelimiter(k) { return true }
                k -= 1
            }
        }
        return false
    }
    
    // Apply formatting or toggle it off if already active
    private func applyFormatting(_ action: FormatAction) {
        guard let range = selectedRange,
              Range(range, in: document.text) != nil else { return }
        if let formatting = astFormatting, applyASTFormatting(action, formatting: formatting, range: range) {
            return
        }
        
        let fullText = document.text
        let activeFormats = determineActiveFormats()
        let isActive = activeFormats.contains(action)
        
        var newText: String? = nil
        var newSelectedRange: NSRange? = nil
        
        switch action {
        case .heading:
            if determineActiveHeadingLevel() != nil {
                // Toggle heading OFF
                guard let block = extractSelectedBlockLines(from: fullText, range: range) else { return }
                var newLines: [String] = []
                var firstLineShift = 0
                for (index, line) in block.lines.enumerated() {
                    let info = parseLinePrefix(line)
                    newLines.append("\(info.leadingSpaces)\(info.cleanLine)")
                    if index == 0 {
                        firstLineShift = -info.rawPrefix.utf16.count
                    }
                }
                var formatted = newLines.joined(separator: "\n")
                if block.hasTrailingNewline { formatted += "\n" }
                
                newText = fullText.replacingCharacters(in: block.fullLineRange, with: formatted)
                
                let oldNSRange = NSRange(block.fullLineRange, in: fullText)
                if range.length == 0 {
                    newSelectedRange = NSRange(location: max(0, range.location + firstLineShift), length: 0)
                } else {
                    let newLen = (formatted as NSString).length - (block.hasTrailingNewline ? 1 : 0)
                    newSelectedRange = NSRange(location: oldNSRange.location, length: max(0, newLen))
                }
            } else {
                // Toggle heading ON with smart level based on context
                applyHeadingLevel(determineSmartHeadingLevel())
                return
            }
            
        case .h1: applyHeadingLevel(1); return
        case .h2: applyHeadingLevel(2); return
        case .h3: applyHeadingLevel(3); return
        case .h4: applyHeadingLevel(4); return
        case .h5: applyHeadingLevel(5); return
        case .h6: applyHeadingLevel(6); return
            
        case .bold, .italic, .strikethrough:
            let segments = inlineLineSegments(in: range)
            if segments.count > 1 {
                // Emphasis cannot span lines: wrap (or unwrap) each line's segment separately
                let nsText = NSMutableString(string: fullText)
                let (prefix, suffix) = inlineMarkers(for: action, selectedText: "")
                for segment in segments.reversed() {
                    let text = nsText.substring(with: segment)
                    if isActive {
                        let inner = String(text.dropFirst(prefix.count).dropLast(suffix.count))
                        nsText.replaceCharacters(in: segment, with: inner)
                    } else {
                        nsText.replaceCharacters(in: segment, with: "\(prefix)\(text)\(suffix)")
                    }
                }
                newText = nsText as String
                let totalDelta = (nsText.length - (fullText as NSString).length)
                newSelectedRange = NSRange(location: range.location, length: max(0, range.length + totalDelta))
                break
            }
            
            let inlineRange = inlineTargetRange(range)
            guard let textRange = Range(inlineRange, in: fullText) else { return }
            let selectedText = String(fullText[textRange])
            var (prefix, suffix) = inlineMarkers(for: action, selectedText: selectedText)
            
            if action == .italic && document.flavor != .slack && !(selectedText.hasPrefix("_") && selectedText.hasSuffix("_")) {
                // Selection sits directly inside `_…_`?
                if textRange.lowerBound > fullText.startIndex, textRange.upperBound < fullText.endIndex,
                   fullText[fullText.index(before: textRange.lowerBound)] == "_",
                   fullText[textRange.upperBound] == "_" {
                    prefix = "_"
                    suffix = "_"
                }
            }
            
            if isActive {
                // UNTOGGLE (remove formatting)
                if selectedText.hasPrefix(prefix) && selectedText.hasSuffix(suffix) && selectedText.count >= (prefix.count + suffix.count) {
                    let start = selectedText.index(selectedText.startIndex, offsetBy: prefix.count)
                    let end = selectedText.index(selectedText.endIndex, offsetBy: -suffix.count)
                    newText = fullText.replacingCharacters(in: textRange, with: String(selectedText[start..<end]))
                    newSelectedRange = NSRange(location: inlineRange.location, length: inlineRange.length - prefix.utf16.count - suffix.utf16.count)
                } else if let prefixStart = fullText.index(textRange.lowerBound, offsetBy: -prefix.count, limitedBy: fullText.startIndex),
                          let suffixEnd = fullText.index(textRange.upperBound, offsetBy: suffix.count, limitedBy: fullText.endIndex),
                          String(fullText[prefixStart..<textRange.lowerBound]) == prefix,
                          String(fullText[textRange.upperBound..<suffixEnd]) == suffix {
                    newText = fullText.replacingCharacters(in: prefixStart..<suffixEnd, with: selectedText)
                    newSelectedRange = NSRange(location: inlineRange.location - prefix.utf16.count, length: inlineRange.length)
                }
            } else {
                // TOGGLE ON (add formatting)
                newText = fullText.replacingCharacters(in: textRange, with: "\(prefix)\(selectedText)\(suffix)")
                newSelectedRange = NSRange(location: inlineRange.location + prefix.utf16.count, length: inlineRange.length)
            }
            
        case .code:
            if isActive {
                if let stripped = getRawTextAndRangeForCode() {
                    newText = fullText.replacingCharacters(in: stripped.replaceRange, with: stripped.rawText)
                    let startLocation = NSRange(stripped.replaceRange, in: fullText).location
                    newSelectedRange = NSRange(location: startLocation, length: stripped.rawText.utf16.count)
                }
            } else if inlineLineSegments(in: range).count > 1 {
                // Code spans cannot span lines: a multi-line selection becomes a code block
                applyCodeFormat(.plainBlock)
                return
            } else {
                let inlineRange = inlineTargetRange(range)
                guard let textRange = Range(inlineRange, in: fullText) else { return }
                let selectedText = String(fullText[textRange])
                // Use a fence longer than any backtick run inside the selection
                let longestRun = selectedText.components(separatedBy: CharacterSet(charactersIn: "`").inverted).map { $0.count }.max() ?? 0
                let fence = String(repeating: "`", count: longestRun + 1)
                let padding = longestRun > 0 ? " " : ""
                newText = fullText.replacingCharacters(in: textRange, with: "\(fence)\(padding)\(selectedText)\(padding)\(fence)")
                newSelectedRange = NSRange(location: inlineRange.location + fence.utf16.count + padding.utf16.count, length: inlineRange.length)
            }
            
        case .quote, .bulletList, .numberedList:
            guard let block = extractSelectedBlockLines(from: fullText, range: range) else { return }
            let lines = block.lines
            
            var newLines: [String] = []
            var firstLineShift = 0
            
            if isActive {
                // UNTOGGLE (remove block formatting)
                for (index, line) in lines.enumerated() {
                    let info = parseLinePrefix(line)
                    newLines.append("\(info.leadingSpaces)\(info.cleanLine)")
                    if index == 0 {
                        firstLineShift = -info.rawPrefix.utf16.count
                    }
                }
            } else {
                // TOGGLE ON (apply block formatting)
                for (index, line) in lines.enumerated() {
                    let info = parseLinePrefix(line)
                    let blockPrefix: String
                    switch action {
                    case .quote: blockPrefix = "> "
                    case .bulletList: blockPrefix = "- "
                    case .numberedList: blockPrefix = "\(index + 1). "
                    default: blockPrefix = ""
                    }
                    newLines.append("\(info.leadingSpaces)\(blockPrefix)\(info.cleanLine)")
                    if index == 0 {
                        firstLineShift = blockPrefix.utf16.count - info.rawPrefix.utf16.count
                    }
                }
            }
            
            var formatted = newLines.joined(separator: "\n")
            if block.hasTrailingNewline { formatted += "\n" }
            
            newText = fullText.replacingCharacters(in: block.fullLineRange, with: formatted)
            
            let oldNSRange = NSRange(block.fullLineRange, in: fullText)
            if range.length == 0 {
                newSelectedRange = NSRange(location: max(0, range.location + firstLineShift), length: 0)
            } else {
                let newLen = (formatted as NSString).length - (block.hasTrailingNewline ? 1 : 0)
                newSelectedRange = NSRange(location: oldNSRange.location, length: max(0, newLen))
            }
        case .table:
            if cellSelectionRect != nil {
                NotificationCenter.default.post(name: .removeCurrentTable, object: nil)
                cellSelectionRect = nil
                return
            }
            guard let textRange = Range(range, in: fullText) else { return }
            let tableTemplate = convertSelectedTextToTableMarkdown(String(fullText[textRange]))
            newText = fullText.replacingCharacters(in: textRange, with: tableTemplate)
            newSelectedRange = NSRange(location: range.location, length: tableTemplate.utf16.count)
        }
        
        guard let resultText = newText else { return }
        commitEdit(resultText, selection: newSelectedRange, actionName: actionName(for: action))
    }
    
    private func actionName(for action: FormatAction) -> String {
        switch action {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .code: return "Code"
        case .strikethrough: return "Strikethrough"
        case .heading, .h1, .h2, .h3, .h4, .h5, .h6: return "Heading"
        case .quote: return "Quote"
        case .bulletList: return "Bullet List"
        case .numberedList: return "Numbered List"
        case .table: return "Table"
        }
    }
    
    private func isSelectionInsideCodeBlock() -> (inside: Bool, language: String?) {
        guard let range = selectedRange,
              let block = MarkdownParser.fencedCodeBlock(containing: range, in: document.text) else { return (false, nil) }
        return (true, block.language)
    }
    
    private func codeFormat(forLanguage language: String?) -> CodeFormat {
        guard let lang = language?.lowercased(), !lang.isEmpty else { return .plainBlock }
        return CodeFormat.allCases.first(where: { $0.languageSignifier == lang }) ?? .plainBlock
    }
    
    private func determineActiveCodeFormat() -> CodeFormat? {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return nil }
        
        let fullText = document.text
        let selectedText = String(fullText[textRange])
        
        // Check if selected text is wrapped in a code block
        let selectedLines = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        if selectedLines.count >= 2,
           let fence = MarkdownParser.parseOpeningCodeFence(selectedLines[0]),
           MarkdownParser.isClosingCodeFence(selectedLines[selectedLines.count - 1], matching: fence) {
            return codeFormat(forLanguage: fence.language)
        }
        
        // Check if selection is inside a code block
        let insideCheck = isSelectionInsideCodeBlock()
        if insideCheck.inside {
            return codeFormat(forLanguage: insideCheck.language)
        }
        
        // Check if the selection is (or is inside) a code span
        let trimmedRange = trimmedInlineRange(range)
        let spans = MarkdownParser.codeRanges(in: fullText).spans
        if spans.contains(where: { span in
            (trimmedRange.location >= span.content.location && trimmedRange.location + trimmedRange.length <= span.content.location + span.content.length) ||
            NSEqualRanges(span.full, trimmedRange)
        }) {
            return .inline
        }
        
        return nil
    }
    
    private func getRawTextAndRangeForCode() -> (rawText: String, replaceRange: Range<String.Index>)? {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return nil }
              
        let fullText = document.text
        let nsText = fullText as NSString
        let selectedText = String(fullText[textRange])
        
        // Case 1: Selected text itself is a fenced block
        let selectedLines = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        if selectedLines.count >= 2,
           let fence = MarkdownParser.parseOpeningCodeFence(selectedLines[0]),
           MarkdownParser.isClosingCodeFence(selectedLines[selectedLines.count - 1], matching: fence) {
            return (selectedLines.dropFirst().dropLast().joined(separator: "\n"), textRange)
        }
        
        // Case 2: Selection is inside a fenced block (``` or ~~~)
        if let block = MarkdownParser.fencedCodeBlock(containing: range, in: fullText),
           let blockRange = Range(block.fullRange, in: fullText) {
            return (nsText.substring(with: block.contentRange), blockRange)
        }
        
        // Case 3: Selection is, or is inside, a code span
        let trimmedRange = trimmedInlineRange(range)
        for span in MarkdownParser.codeRanges(in: fullText).spans {
            let insideContent = trimmedRange.location >= span.content.location &&
                trimmedRange.location + trimmedRange.length <= span.content.location + span.content.length
            if insideContent || NSEqualRanges(span.full, trimmedRange), let spanRange = Range(span.full, in: fullText) {
                return (nsText.substring(with: span.content), spanRange)
            }
        }
        
        return nil
    }
    
    private func applyCodeFormat(_ format: CodeFormat) {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return }
              
        let fullText = document.text
        let nsText = fullText as NSString
        
        let rawText: String
        let replaceRange: Range<String.Index>
        
        if let stripped = getRawTextAndRangeForCode() {
            rawText = stripped.rawText
            replaceRange = stripped.replaceRange
        } else {
            rawText = String(fullText[textRange])
            replaceRange = textRange
        }
        
        let replaceNSRange = NSRange(replaceRange, in: fullText)
        var formatted: String
        var contentOffset: Int
        switch format {
        case .inline:
            formatted = "`\(rawText)`"
            contentOffset = 1
        default:
            let openingFence = "```" + (format.languageSignifier ?? "")
            formatted = "\(openingFence)\n\(rawText)\n```"
            contentOffset = openingFence.utf16.count + 1
            // Fences must sit on their own lines
            let start = replaceNSRange.location
            let end = replaceNSRange.location + replaceNSRange.length
            if start > 0 && nsText.character(at: start - 1) != 0x0A {
                formatted = "\n" + formatted
                contentOffset += 1
            }
            if end < nsText.length && nsText.character(at: end) != 0x0A {
                formatted += "\n"
            }
        }
        
        let newText = fullText.replacingCharacters(in: replaceRange, with: formatted)
        let selection = NSRange(location: replaceNSRange.location + contentOffset, length: rawText.utf16.count)
        commitEdit(newText, selection: selection, actionName: format == .inline ? "Inline Code" : "Code Block")
    }
    
    private func applyLink(url: String, activeLink: DetectedLink?) {
        if let formatting = astFormatting, let range = selectedRange {
            if let edit = formatting.setLink(url, selection: activeLink?.fullRange ?? range) {
                commitEdit(edit.text, selection: edit.selection, actionName: activeLink == nil ? "Add Link" : "Edit Link")
            }
            return
        }
        let fullText = document.text
        
        if let link = activeLink {
            // EDITING existing link
            let updatedText = document.flavor == .slack ? "<\(url)|\(link.text)>" : "[\(link.text)](\(url))"
            if let replaceRange = Range(link.fullRange, in: fullText) {
                let newText = fullText.replacingCharacters(in: replaceRange, with: updatedText)
                commitEdit(newText, selection: NSRange(location: link.fullRange.location, length: (updatedText as NSString).length), actionName: "Edit Link")
            }
        } else if let range = selectedRange {
            // ADDING link to selected text
            let inlineRange = trimmedInlineRange(range)
            guard let textRange = Range(inlineRange, in: fullText) else { return }
            let selectedText = String(fullText[textRange])
            let displayText = selectedText.isEmpty ? url : selectedText
            let insertedText = document.flavor == .slack ? "<\(url)|\(displayText)>" : "[\(displayText)](\(url))"
            let newText = fullText.replacingCharacters(in: textRange, with: insertedText)
            commitEdit(newText, selection: NSRange(location: inlineRange.location, length: (insertedText as NSString).length), actionName: "Add Link")
        }
    }
    
    private func removeLink(activeLink: DetectedLink?) {
        if let formatting = astFormatting, let link = activeLink {
            if let edit = formatting.removeLink(selection: link.fullRange) {
                commitEdit(edit.text, selection: edit.selection, actionName: "Remove Link")
            }
            return
        }
        guard let link = activeLink,
              let replaceRange = Range(link.fullRange, in: document.text) else { return }
        
        let newText = document.text.replacingCharacters(in: replaceRange, with: link.text)
        commitEdit(newText, selection: NSRange(location: link.fullRange.location, length: (link.text as NSString).length), actionName: "Remove Link")
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
    
    private func handleViewModeChange(from oldMode: ViewMode, to newMode: ViewMode) {
        guard oldMode != newMode else { return }
        guard let window = self.window, !window.styleMask.contains(.fullScreen) else { return }
        
        if oldMode != .split && newMode == .split {
            // Entering split mode from single pane view
            let currentWidth = window.frame.width
            previousSingleWidth = currentWidth
            
            let targetWidth = max(previousSplitWidth, currentWidth * 1.5)
            animateWindowWidth(to: targetWidth, window: window)
        } else if oldMode == .split && newMode != .split {
            // Exiting split mode to single pane view
            let currentWidth = window.frame.width
            previousSplitWidth = currentWidth
            
            let targetWidth = max(600, min(previousSingleWidth, currentWidth * 0.67))
            animateWindowWidth(to: targetWidth, window: window)
        }
    }
    
    private func animateWindowWidth(to targetWidth: CGFloat, window: NSWindow) {
        let currentFrame = window.frame
        var adjustedTargetWidth = targetWidth
        
        if let screen = window.screen {
            let maxAllowedWidth = screen.visibleFrame.width
            adjustedTargetWidth = min(adjustedTargetWidth, maxAllowedWidth)
        }
        
        let deltaWidth = adjustedTargetWidth - currentFrame.width
        guard abs(deltaWidth) > 1 else { return }
        
        var newOriginX = currentFrame.origin.x - (deltaWidth / 2)
        
        if let screen = window.screen {
            let screenFrame = screen.visibleFrame
            if newOriginX < screenFrame.minX {
                newOriginX = screenFrame.minX
            } else if newOriginX + adjustedTargetWidth > screenFrame.maxX {
                newOriginX = screenFrame.maxX - adjustedTargetWidth
            }
        }
        
        let newFrame = NSRect(
            x: newOriginX,
            y: currentFrame.origin.y,
            width: adjustedTargetWidth,
            height: currentFrame.size.height
        )
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }
}

#Preview {
    ContentView(document: .constant(SwashDocument()))
}
