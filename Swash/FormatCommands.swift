//
//  FormatCommands.swift
//  Swash
//
//  Keyboard shortcuts and the Format menu. Commands are delivered to the focused document's
//  ContentView, which applies them with the same logic as the bubble menu.
//

import SwiftUI
import AppKit
import PixerateMarkdown

extension FormatCommand {
    /// Maps a key-down event to a command, using the manifest's shortcuts (letters by character,
    /// digits and punctuation by key code, so shifted keys work on any layout).
    static func command(for event: NSEvent) -> FormatCommand? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: FormatShortcut.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return FormatManifest.command(charactersIgnoringModifiers: event.charactersIgnoringModifiers, keyCode: event.keyCode, modifiers: modifiers)
    }
}

extension FormatShortcut {
    var keyEquivalent: KeyEquivalent { KeyEquivalent(key) }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
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

/// The Format menu; shortcuts mirror the editor's key handling (both come from FormatManifest).
struct FormatMenuCommands: Commands {
    @FocusedValue(\.formatCommandHandler) private var handler
    @FocusedValue(\.markdownFlavorSelection) private var flavorSelection
    
    var body: some Commands {
        CommandMenu("Format") {
            // Commands, labels, order and shortcuts come from the shared manifest (FormatManifest.generated.swift)
            ForEach(Array(Self.menuGroups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(Array(group.enumerated()), id: \.offset) { _, entry in
                    item(entry)
                }
            }
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
    
    /// The manifest's menu commands, split into its groups (in order of first appearance).
    private static let menuGroups: [[FormatMenuEntry]] = {
        var groups: [[FormatMenuEntry]] = []
        for entry in FormatManifest.entries(for: .menu) {
            if let last = groups.last?.last, last.group == entry.group {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups
    }()

    @ViewBuilder
    private func item(_ entry: FormatMenuEntry) -> some View {
        if let shortcut = entry.shortcut {
            Button(entry.label) { handler?(entry.command) }
                .keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
                .disabled(handler == nil)
        } else {
            Button(entry.label) { handler?(entry.command) }
                .disabled(handler == nil)
        }
    }
}
