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
                            Image(systemName: alignmentIcon(for: alignment))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(.borderlessButton)
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

// MARK: - Editable Text Field helper for cell editing
struct CellTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onNextCell: () -> Void
    var onPrevCell: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.stringValue = text
        
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
        }
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CellTextField

        init(_ parent: CellTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let tf = obj.object as? NSTextField {
                parent.text = tf.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
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

// MARK: - NSTextAttachment & Provider for NSTextView Formatted Mode
final class TableTextAttachment: NSTextAttachment {
    static let fileTypeIdentifier = "com.surrealroad.swash.table"
    
    var tableData: MarkdownTableData
    var flavor: MarkdownFlavor
    var onUpdate: ((MarkdownTableData) -> Void)?
    
    init(tableData: MarkdownTableData, flavor: MarkdownFlavor, onUpdate: ((MarkdownTableData) -> Void)?) {
        self.tableData = tableData
        self.flavor = flavor
        self.onUpdate = onUpdate
        super.init(data: nil, ofType: Self.fileTypeIdentifier)
        self.fileType = Self.fileTypeIdentifier
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> NSRect {
        let width = lineFrag.width > 0 ? lineFrag.width : 500
        let rowCount = tableData.rows.count + 1
        let estimatedHeight = CGFloat(max(100, rowCount * 36 + 60))
        return NSRect(x: 0, y: 0, width: width, height: estimatedHeight)
    }
}

final class TableAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? TableTextAttachment else { return }
        
        let container = NSHostingView(rootView: InteractiveTableView(
            tableData: attachment.tableData,
            flavor: attachment.flavor,
            isEditable: true,
            onChange: { [weak attachment] newTableData in
                DispatchQueue.main.async {
                    attachment?.onUpdate?(newTableData)
                }
            }
        ))
        container.autoresizingMask = [.width]
        self.view = container
    }
    
    override var tracksTextAttachmentViewBounds: Bool {
        get { return true }
        set { }
    }
}

