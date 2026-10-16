//
//  FormatCommands.swift
//  Swash
//
//  Keyboard shortcuts and the Format menu. Commands are delivered to the focused document's
//  ContentView, which applies them with the same logic as the bubble menu.
//

import SwiftUI
import AppKit

enum FormatCommand: Equatable {
    case bold, italic, strikethrough, code, link
    case heading(Int), paragraph
    case bulletList, numberedList, taskList, quote, codeBlock
    /// Make the selection a callout of the given type; nil turns a callout back into a plain quote.
    case callout(AlertType?)
    case footnote
    case tableOfContents
    
    /// Maps a key-down event to a command (key codes for digits/punctuation, so shifted keys work on any layout).
    static func command(for event: NSEvent) -> FormatCommand? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control) else { return nil }
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (key, shift, option) {
        case ("b", false, false): return .bold
        case ("i", false, false): return .italic
        case ("e", false, false): return .code
        case ("k", false, false): return .link
        case ("x", true, false): return .strikethrough
        default: break
        }
        switch (event.keyCode, shift, option) {
        case (18, false, true): return .heading(1)   // ⌥⌘1
        case (19, false, true): return .heading(2)   // ⌥⌘2
        case (20, false, true): return .heading(3)   // ⌥⌘3
        case (29, false, true): return .paragraph    // ⌥⌘0
        case (8, false, true): return .codeBlock     // ⌥⌘C
        case (28, true, false): return .bulletList   // ⇧⌘8
        case (26, true, false): return .numberedList // ⇧⌘7
        case (25, true, false): return .taskList     // ⇧⌘9
        case (47, true, false): return .quote        // ⇧⌘.
        default: return nil
        }
    }
}

struct FormatCommandHandlerKey: FocusedValueKey {
    typealias Value = (FormatCommand) -> Void
}

extension FocusedValues {
    var formatCommandHandler: ((FormatCommand) -> Void)? {
        get { self[FormatCommandHandlerKey.self] }
        set { self[FormatCommandHandlerKey.self] = newValue }
    }
}

/// The focused document's Markdown flavor and a request to switch it (ContentView asks how to convert).
struct MarkdownFlavorSelection {
    let current: MarkdownFlavor
    let select: (MarkdownFlavor) -> Void
}

struct MarkdownFlavorSelectionKey: FocusedValueKey {
    typealias Value = MarkdownFlavorSelection
}

extension FocusedValues {
    var markdownFlavorSelection: MarkdownFlavorSelection? {
        get { self[MarkdownFlavorSelectionKey.self] }
        set { self[MarkdownFlavorSelectionKey.self] = newValue }
    }
}

/// The Format menu; shortcuts mirror the editor's key handling.
struct FormatMenuCommands: Commands {
    @FocusedValue(\.formatCommandHandler) private var handler
    @FocusedValue(\.markdownFlavorSelection) private var flavorSelection
    
    var body: some Commands {
        CommandMenu("Format") {
            item("Bold", .bold, "b")
            item("Italic", .italic, "i")
            item("Strikethrough", .strikethrough, "x", [.command, .shift])
            item("Inline Code", .code, "e")
            item("Link…", .link, "k")
            Divider()
            item("Heading 1", .heading(1), "1", [.command, .option])
            item("Heading 2", .heading(2), "2", [.command, .option])
            item("Heading 3", .heading(3), "3", [.command, .option])
            item("Paragraph", .paragraph, "0", [.command, .option])
            Divider()
            item("Bullet List", .bulletList, "8", [.command, .shift])
            item("Numbered List", .numberedList, "7", [.command, .shift])
            item("To-do List", .taskList, "9", [.command, .shift])
            item("Quote", .quote, ".", [.command, .shift])
            item("Code Block", .codeBlock, "c", [.command, .option])
            Menu("Callout") {
                ForEach(AlertType.allCases, id: \.self) { type in
                    Button(type.title) { handler?(.callout(type)) }
                }
                Divider()
                Button("Plain Quote") { handler?(.callout(nil)) }
            }
            .disabled(handler == nil)
            Divider()
            Button("Insert Footnote") { handler?(.footnote) }
                .disabled(handler == nil)
            Picker("Markdown Flavor", selection: Binding(
                get: { flavorSelection?.current ?? .github },
                set: { flavorSelection?.select($0) }
            )) {
                ForEach(MarkdownFlavor.allCases) { flavor in
                    Text(flavor.displayName).tag(flavor)
                }
            }
            .disabled(flavorSelection == nil)
            Divider()
            Button("Insert Table of Contents") { handler?(.tableOfContents) }
                .disabled(handler == nil)
        }
    }
    
    private func item(_ title: String, _ command: FormatCommand, _ key: Character, _ modifiers: EventModifiers = .command) -> some View {
        Button(title) { handler?(command) }
            .keyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
            .disabled(handler == nil)
    }
}
