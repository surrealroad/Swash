//
//  DocumentCommands.swift
//  Swash
//
//  Menu commands that act on the focused document window (copy links, outline) and the
//  focused values ContentView publishes for them.
//

import SwiftUI
import AppKit

enum DocumentCommand {
    case copyHeadingLink, copyMarkdownLink, copyFilePath
}

struct DocumentCommandHandlerKey: FocusedValueKey {
    typealias Value = (DocumentCommand) -> Void
}

struct DocumentFileURLKey: FocusedValueKey {
    typealias Value = URL
}

/// The focused document's view mode and a way to switch it, for the View menu.
struct ViewModeSelection {
    let current: ViewMode
    let select: (ViewMode) -> Void
}

struct ViewModeSelectionKey: FocusedValueKey {
    typealias Value = ViewModeSelection
}

extension FocusedValues {
    var viewModeSelection: ViewModeSelection? {
        get { self[ViewModeSelectionKey.self] }
        set { self[ViewModeSelectionKey.self] = newValue }
    }

    var documentCommandHandler: ((DocumentCommand) -> Void)? {
        get { self[DocumentCommandHandlerKey.self] }
        set { self[DocumentCommandHandlerKey.self] = newValue }
    }

    var documentFileURL: URL? {
        get { self[DocumentFileURLKey.self] }
        set { self[DocumentFileURLKey.self] = newValue }
    }
}

/// Edit menu "Copy …" items and the View menu's view modes and outline toggle.
struct DocumentMenuCommands: Commands {
    @FocusedValue(\.documentCommandHandler) private var handler
    @FocusedValue(\.viewModeSelection) private var viewMode
    @FocusedValue(\.documentFileURL) private var fileURL
    @AppStorage("showOutline") private var showOutline = false

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Heading Link") { handler?(.copyHeadingLink) }
                .keyboardShortcut("c", modifiers: [.command, .control])
                .disabled(handler == nil)
            Button("Copy as Markdown Link") { handler?(.copyMarkdownLink) }
                .disabled(handler == nil || fileURL == nil)
            Button("Copy File Path") { handler?(.copyFilePath) }
                .disabled(handler == nil || fileURL == nil)
        }
        CommandGroup(before: .toolbar) {
            ForEach(Array(ViewMode.menuOrder.enumerated()), id: \.element) { index, mode in
                Toggle(mode.rawValue, isOn: Binding(
                    get: { viewMode?.current == mode },
                    set: { if $0 { viewMode?.select(mode) } }
                ))
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .disabled(viewMode == nil)
            }
            Divider()
            Button(showOutline ? "Hide Outline" : "Show Outline") { showOutline.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
        }
    }
}

/// The text written by the "Copy …" commands, kept free of UI so it is easy to check.
enum DocumentLinkText {
    /// `[Heading](#anchor)` for the heading whose section contains `location`.
    static func headingLink(in outline: MarkdownOutline, at location: Int) -> String? {
        guard let index = outline.headingIndex(containing: location) else { return nil }
        let heading = outline.headings[index]
        return "[\(MarkdownOutline.escapeLinkText(heading.title))](#\(heading.anchor))"
    }

    /// `[Title](file:///…)` linking to the document file.
    static func markdownLink(title: String, fileURL: URL) -> String {
        "[\(MarkdownOutline.escapeLinkText(title))](\(fileURL.absoluteString))"
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
