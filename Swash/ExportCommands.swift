//
//  ExportCommands.swift
//  Swash
//
//  File › Export as PDF / HTML, Print, and Edit › Copy as Rich Text / HTML. The focused
//  document's view supplies the actions, which use DocumentExporter.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct DocumentExportActions {
    let exportPDF: () -> Void
    let exportHTML: () -> Void
    let print: () -> Void
    let copyRichText: () -> Void
    let copyHTML: () -> Void
}

struct DocumentExportActionsKey: FocusedValueKey {
    typealias Value = DocumentExportActions
}

extension FocusedValues {
    var documentExportActions: DocumentExportActions? {
        get { self[DocumentExportActionsKey.self] }
        set { self[DocumentExportActionsKey.self] = newValue }
    }
}

struct ExportCommands: Commands {
    @FocusedValue(\.documentExportActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…") { actions?.exportPDF() }
                .disabled(actions == nil)
            Button("Export as HTML…") { actions?.exportHTML() }
                .disabled(actions == nil)
            Divider()
            #if os(macOS)
            Button("Page Setup…") { NSApp.runPageLayout(nil) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            #endif
            Button("Print…") { actions?.print() }
                .keyboardShortcut("p")
                .disabled(actions == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy as Rich Text") { actions?.copyRichText() }
                .disabled(actions == nil)
            Button("Copy as HTML") { actions?.copyHTML() }
                .disabled(actions == nil)
        }
    }
}
