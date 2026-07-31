//
//  InteractiveTableView.swift
//  Swash
//
//  Created by Jack James on 31/07/2026.
//

import SwiftUI
import AppKit

struct InteractiveTableView: View {
    let initialData: MarkdownTableData
    let flavor: MarkdownFlavor
    var isEditable: Bool = true
    var onChange: ((MarkdownTableData) -> Void)? = nil

    @State private var headers: [String]
    @State private var alignments: [TableAlignment]
    @State private var rows: [[String]]
    
    @State private var editingCell: CellIndex? = nil
    @State private var isHovered: Bool = false
    @State private var hoveredColumn: Int? = nil
    @State private var hoveredRow: Int? = nil

    struct CellIndex: Hashable {
        let row: Int // -1 for header, 0...N for rows
        let col: Int
    }

    init(tableData: MarkdownTableData, flavor: MarkdownFlavor, isEditable: Bool = true, onChange: ((MarkdownTableData) -> Void)? = nil) {
        self.initialData = tableData
        self.flavor = flavor
        self.isEditable = isEditable
        self.onChange = onChange
        
        _headers = State(initialValue: tableData.headers)
        _alignments = State(initialValue: tableData.alignments)
        _rows = State(initialValue: tableData.rows)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: true) {
                    // Main Table Container
                    VStack(spacing: 0) {
                        // Header Row
                        headerView
                        
                        Divider()
                            .background(Color.secondary.opacity(0.3))

                        // Data Rows
                        ForEach(0..<rows.count, id: \.self) { rowIndex in
                            rowView(for: rowIndex)
                            
                            if rowIndex < rows.count - 1 {
                                Divider()
                                    .background(Color.secondary.opacity(0.15))
                            }
                        }
                    }
                    .frame(minWidth: max(300, geometry.size.width), maxWidth: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .cornerRadius(6)
                }

            // Table Controls Footer (Visible when editable)
            if isEditable {
                HStack(spacing: 12) {
                    Button(action: { addRow() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add Row")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button(action: { addColumn() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add Column")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.top, 2)
                .opacity(isHovered || editingCell != nil ? 1.0 : 0.6)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: initialData) { newData in
            headers = newData.headers
            alignments = newData.alignments
            rows = newData.rows
        }
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack(spacing: 0) {
            ForEach(0..<headers.count, id: \.self) { colIndex in
                let alignment = colIndex < alignments.count ? alignments[colIndex] : .defaultAlignment
                
                HStack(spacing: 4) {
                    cellContent(text: headers[colIndex], index: CellIndex(row: -1, col: colIndex), isHeader: true)
                    
                    if isEditable && (hoveredColumn == colIndex || editingCell?.col == colIndex) {
                        Menu {
                            Button("Align Left") { setAlignment(.left, for: colIndex) }
                            Button("Align Center") { setAlignment(.center, for: colIndex) }
                            Button("Align Right") { setAlignment(.right, for: colIndex) }
                            Divider()
                            Button("Insert Column Left") { insertColumn(at: colIndex) }
                            Button("Insert Column Right") { insertColumn(at: colIndex + 1) }
                            if headers.count > 1 {
                                Divider()
                                Button("Delete Column", role: .destructive) { deleteColumn(at: colIndex) }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 14)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: 110, maxWidth: .infinity, alignment: frameAlignment(for: alignment))
                .onHover { hovering in
                    if hovering { hoveredColumn = colIndex }
                }
                .contextMenu {
                    if isEditable {
                        Button("Insert Column Left") { insertColumn(at: colIndex) }
                        Button("Insert Column Right") { insertColumn(at: colIndex + 1) }
                        if headers.count > 1 {
                            Button("Delete Column", role: .destructive) { deleteColumn(at: colIndex) }
                        }
                        Divider()
                        Menu("Alignment") {
                            Button("Left") { setAlignment(.left, for: colIndex) }
                            Button("Center") { setAlignment(.center, for: colIndex) }
                            Button("Right") { setAlignment(.right, for: colIndex) }
                        }
                    }
                }

                if colIndex < headers.count - 1 {
                    Divider()
                }
            }
        }
        .background(Color.secondary.opacity(0.12))
    }

    // MARK: - Row View
    private func rowView(for rowIndex: Int) -> some View {
        HStack(spacing: 0) {
            let row = rowIndex < rows.count ? rows[rowIndex] : []
            
            ForEach(0..<headers.count, id: \.self) { colIndex in
                let cellText = colIndex < row.count ? row[colIndex] : ""
                let alignment = colIndex < alignments.count ? alignments[colIndex] : .defaultAlignment

                cellContent(text: cellText, index: CellIndex(row: rowIndex, col: colIndex), isHeader: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minWidth: 110, maxWidth: .infinity, alignment: frameAlignment(for: alignment))
                    .contextMenu {
                        if isEditable {
                            Button("Insert Row Above") { insertRow(at: rowIndex) }
                            Button("Insert Row Below") { insertRow(at: rowIndex + 1) }
                            if rows.count > 1 {
                                Button("Delete Row", role: .destructive) { deleteRow(at: rowIndex) }
                            }
                            Divider()
                            Button("Insert Column Left") { insertColumn(at: colIndex) }
                            Button("Insert Column Right") { insertColumn(at: colIndex + 1) }
                            if headers.count > 1 {
                                Button("Delete Column", role: .destructive) { deleteColumn(at: colIndex) }
                            }
                        }
                    }

                if colIndex < headers.count - 1 {
                    Divider()
                }
            }
        }
        .background(rowIndex % 2 == 1 ? Color.secondary.opacity(0.04) : Color.clear)
    }

    // MARK: - Cell Content
    @ViewBuilder
    private func cellContent(text: String, index: CellIndex, isHeader: Bool) -> some View {
        if isEditable && editingCell == index {
            CellTextField(
                text: Binding(
                    get: { text },
                    set: { newText in updateCellText(newText, at: index) }
                ),
                flavor: flavor,
                onCommit: {
                    editingCell = nil
                },
                onNextCell: {
                    moveFocus(from: index, forward: true)
                },
                onPrevCell: {
                    moveFocus(from: index, forward: false)
                }
            )
            .font(.system(size: 13, weight: isHeader ? .bold : .regular))
        } else {
            InlineMarkdownText(text: text.isEmpty ? " " : text, flavor: flavor)
                .font(.system(size: 13, weight: isHeader ? .bold : .regular))
                .foregroundColor(.primary)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEditable {
                        editingCell = index
                    }
                }
        }
    }

    // MARK: - Helpers & Data Operations
    private func updateCellText(_ text: String, at index: CellIndex) {
        if index.row == -1 {
            if index.col < headers.count {
                headers[index.col] = text
            }
        } else {
            if index.row < rows.count {
                var row = rows[index.row]
                while row.count <= index.col { row.append("") }
                row[index.col] = text
                rows[index.row] = row
            }
        }
        notifyChange()
    }

    private func addRow() {
        let newRow = [String](repeating: "", count: headers.count)
        rows.append(newRow)
        notifyChange()
    }

    private func insertRow(at index: Int) {
        let newRow = [String](repeating: "", count: headers.count)
        let clampedIndex = min(max(0, index), rows.count)
        rows.insert(newRow, at: clampedIndex)
        notifyChange()
    }

    private func deleteRow(at index: Int) {
        guard rows.count > 1 && index < rows.count else { return }
        rows.remove(at: index)
        notifyChange()
    }

    private func addColumn() {
        headers.append("Header \(headers.count + 1)")
        alignments.append(.defaultAlignment)
        for i in 0..<rows.count {
            rows[i].append("")
        }
        notifyChange()
    }

    private func insertColumn(at colIndex: Int) {
        let clampedIndex = min(max(0, colIndex), headers.count)
        headers.insert("Header \(clampedIndex + 1)", at: clampedIndex)
        alignments.insert(.defaultAlignment, at: min(clampedIndex, alignments.count))
        for i in 0..<rows.count {
            if clampedIndex <= rows[i].count {
                rows[i].insert("", at: clampedIndex)
            } else {
                rows[i].append("")
            }
        }
        notifyChange()
    }

    private func deleteColumn(at colIndex: Int) {
        guard headers.count > 1 && colIndex < headers.count else { return }
        headers.remove(at: colIndex)
        if colIndex < alignments.count {
            alignments.remove(at: colIndex)
        }
        for i in 0..<rows.count {
            if colIndex < rows[i].count {
                rows[i].remove(at: colIndex)
            }
        }
        notifyChange()
    }

    private func setAlignment(_ alignment: TableAlignment, for colIndex: Int) {
        while alignments.count < headers.count {
            alignments.append(.defaultAlignment)
        }
        alignments[colIndex] = alignment
        notifyChange()
    }

    private func moveFocus(from current: CellIndex, forward: Bool) {
        let totalRows = rows.count
        let totalCols = headers.count
        
        if forward {
            if current.col + 1 < totalCols {
                editingCell = CellIndex(row: current.row, col: current.col + 1)
            } else if current.row + 1 < totalRows {
                editingCell = CellIndex(row: current.row + 1, col: 0)
            } else {
                addRow()
                editingCell = CellIndex(row: totalRows, col: 0)
            }
        } else {
            if current.col - 1 >= 0 {
                editingCell = CellIndex(row: current.row, col: current.col - 1)
            } else if current.row > -1 {
                editingCell = CellIndex(row: current.row - 1, col: totalCols - 1)
            }
        }
    }

    private func notifyChange() {
        let updatedData = MarkdownTableData(headers: headers, alignments: alignments, rows: rows)
        onChange?(updatedData)
    }

    private func frameAlignment(for alignment: TableAlignment) -> Alignment {
        switch alignment {
        case .left, .defaultAlignment: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private func alignmentIcon(for alignment: TableAlignment) -> String {
        switch alignment {
        case .left, .defaultAlignment: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .right: return "text.alignright"
        }
    }
}

// MARK: - Cell Text Field
struct CellTextField: View {
    @Binding var text: String
    var flavor: MarkdownFlavor
    var onCommit: () -> Void
    var onNextCell: () -> Void
    var onPrevCell: () -> Void

    var body: some View {
        CellTextView(
            text: $text,
            flavor: flavor,
            onCommit: onCommit,
            onNextCell: onNextCell,
            onPrevCell: onPrevCell
        )
        .frame(minHeight: 20)
    }
}

// MARK: - CellTextView with Live Inline Markdown Formatting
struct CellTextView: NSViewRepresentable {
    @Binding var text: String
    var flavor: MarkdownFlavor
    var onCommit: () -> Void
    var onNextCell: () -> Void
    var onPrevCell: () -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.focusRingType = .none
        textView.delegate = context.coordinator
        
        textView.string = text
        context.coordinator.highlightCellText(in: textView)
        
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        if textView.string != text {
            textView.string = text
            context.coordinator.highlightCellText(in: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CellTextView

        init(_ parent: CellTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlightCellText(in: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            NotificationCenter.default.post(name: .cellSelectionDidChange, object: nil, userInfo: [:])
            parent.onCommit()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            if range.length > 0 {
                if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    
                    let rectInWindow = textView.convert(rect, to: nil)
                    if let window = textView.window {
                        let localRect = window.contentView?.convert(rectInWindow, from: nil) ?? rectInWindow
                        NotificationCenter.default.post(name: .cellSelectionDidChange, object: nil, userInfo: [
                            "range": range,
                            "rect": localRect,
                            "text": textView.string
                        ])
                    }
                }
            } else {
                NotificationCenter.default.post(name: .cellSelectionDidChange, object: nil, userInfo: [:])
            }
        }

        func highlightCellText(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: textStorage.length)
            guard fullRange.length > 0 else { return }
            
            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor
            ], range: fullRange)
            
            func hideRange(_ range: NSRange) {
                let valid = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
                if valid.length > 0 {
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 0.01), range: valid)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: valid)
                }
            }
            
            // Inline code pills: `code`
            let codePattern = "`([^`]+)`"
            if let codeRegex = try? NSRegularExpression(pattern: codePattern, options: []) {
                let matches = codeRegex.matches(in: textView.string, options: [], range: fullRange)
                for match in matches {
                    let contentRange = match.range(at: 1)
                    textStorage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: contentRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: contentRange)
                    textStorage.addAttribute(.backgroundColor, value: NSColor.textColor.withAlphaComponent(0.06), range: match.range)
                    
                    hideRange(NSRange(location: match.range.location, length: 1))
                    hideRange(NSRange(location: match.range.location + match.range.length - 1, length: 1))
                }
            }
            
            // Bold: **text**
            let boldPattern = "\\*\\*([^*]+)\\*\\*"
            if let boldRegex = try? NSRegularExpression(pattern: boldPattern, options: []) {
                let matches = boldRegex.matches(in: textView.string, options: [], range: fullRange)
                for match in matches {
                    let contentRange = match.range(at: 1)
                    textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .bold), range: contentRange)
                    
                    hideRange(NSRange(location: match.range.location, length: 2))
                    hideRange(NSRange(location: match.range.location + match.range.length - 2, length: 2))
                }
            }
            
            // Italics: *text* or _text_
            let italicPattern = "(?<!\\*)\\*([^*]+)\\*(?!\\*)|(?<!_)_([^_]+)_(?!_)"
            if let italicRegex = try? NSRegularExpression(pattern: italicPattern, options: []) {
                let matches = italicRegex.matches(in: textView.string, options: [], range: fullRange)
                for match in matches {
                    let contentRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                    let italicFont = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13, weight: .regular), toHaveTrait: .italicFontMask)
                    textStorage.addAttribute(.font, value: italicFont, range: contentRange)
                    
                    hideRange(NSRange(location: match.range.location, length: 1))
                    hideRange(NSRange(location: match.range.location + match.range.length - 1, length: 1))
                }
            }
            
            // Links: [text](url)
            let linkPattern = "\\[([^\\]]+)\\]\\(([^\\)]+)\\)"
            if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []) {
                let matches = linkRegex.matches(in: textView.string, options: [], range: fullRange)
                for match in matches {
                    let textRange = match.range(at: 1)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
                    textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                    
                    hideRange(NSRange(location: match.range.location, length: 1))
                    let urlPartStart = textRange.location + textRange.length
                    let urlPartLen = (match.range.location + match.range.length) - urlPartStart
                    hideRange(NSRange(location: urlPartStart, length: urlPartLen))
                }
            }
            
            textStorage.endEditing()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onNextCell()
                return true
            } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onPrevCell()
                return true
            }
            return false
        }
    }
}

// MARK: - Custom NSHostingView for Scroll Wheel Passthrough
final class TableHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let currentEvent = NSApp.currentEvent, currentEvent.type == .scrollWheel {
            if abs(currentEvent.deltaY) >= abs(currentEvent.deltaX) {
                return self
            }
        }
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.deltaY) >= abs(event.deltaX) {
            var current: NSView? = self.superview
            var parentScrollView: NSScrollView? = nil
            while current != nil {
                if let sv = current as? NSScrollView, sv !== self {
                    parentScrollView = sv
                    break
                }
                current = current?.superview
            }
            if let sv = parentScrollView {
                sv.scrollWheel(with: event)
            } else {
                self.nextResponder?.scrollWheel(with: event)
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - NSTextAttachment & Cell for TextKit 1 NSTextView Formatted Mode
final class TableAttachmentCell: NSTextAttachmentCell {
    var hostingView: TableHostingView<InteractiveTableView>?
    var tableData: MarkdownTableData
    var flavor: MarkdownFlavor
    var onUpdate: ((MarkdownTableData) -> Void)?
    
    init(tableData: MarkdownTableData, flavor: MarkdownFlavor, onUpdate: ((MarkdownTableData) -> Void)?) {
        self.tableData = tableData
        self.flavor = flavor
        self.onUpdate = onUpdate
        super.init(textCell: "")
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    nonisolated override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> NSRect {
        let width = lineFrag.width > 0 ? lineFrag.width : 500
        let rowCount = tableData.rows.count + 1
        let estimatedHeight = CGFloat(max(100, rowCount * 36 + 60))
        return NSRect(x: 0, y: 0, width: width, height: estimatedHeight)
    }
    
    nonisolated override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let parentView = controlView as? NSTextView else { return }
        
        MainActor.assumeIsolated {
            if self.hostingView == nil {
                let hv = TableHostingView(rootView: InteractiveTableView(
                    tableData: self.tableData,
                    flavor: self.flavor,
                    isEditable: true,
                    onChange: { [weak self, weak parentView] newTableData in
                        DispatchQueue.main.async {
                            self?.tableData = newTableData
                            self?.onUpdate?(newTableData)
                            
                            if let parentView = parentView, let layoutManager = parentView.layoutManager, let textStorage = parentView.textStorage {
                                let fullRange = NSRange(location: 0, length: textStorage.length)
                                textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
                                    if (value as? TableTextAttachment)?.cell === self {
                                        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                                        layoutManager.invalidateDisplay(forCharacterRange: range)
                                        parentView.needsLayout = true
                                        parentView.needsDisplay = true
                                    }
                                }
                            }
                        }
                    }
                ))
                self.hostingView = hv
                parentView.addSubview(hv, positioned: .above, relativeTo: nil)
            }
            
            if let hv = self.hostingView {
                if hv.superview != parentView {
                    parentView.addSubview(hv, positioned: .above, relativeTo: nil)
                }
                if hv.frame != cellFrame {
                    hv.frame = cellFrame
                }
            }
        }
    }
}

final class TableTextAttachment: NSTextAttachment {
    static let fileTypeIdentifier = "com.surrealroad.swash.table"
    
    var tableData: MarkdownTableData
    var flavor: MarkdownFlavor
    var onUpdate: ((MarkdownTableData) -> Void)?
    var cell: TableAttachmentCell
    
    init(tableData: MarkdownTableData, flavor: MarkdownFlavor, onUpdate: ((MarkdownTableData) -> Void)?) {
        self.tableData = tableData
        self.flavor = flavor
        self.onUpdate = onUpdate
        
        let cell = TableAttachmentCell(tableData: tableData, flavor: flavor, onUpdate: onUpdate)
        self.cell = cell
        
        super.init(data: nil, ofType: Self.fileTypeIdentifier)
        self.attachmentCell = cell
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

