//
//  FormatManifest.swift
//  Swash
//
//  Types for the format-command manifest shared with the Pixerate editor
//  (`@pixerate/markdown-conformance`). The data itself is generated into
//  `FormatManifest.generated.swift` by `scripts/generate_format_manifest.mjs`; the Format menu,
//  bubble menu and keyboard shortcuts read it from here. Foundation only.
//

import Foundation

/// Where a command is offered. The generator fails on a surface not listed here.
enum FormatSurface: String, Hashable {
    case bubble
    case menu
    case palette
    case keyboardBar
}

/// When a command is enabled. Each condition is implemented once, in
/// `MarkdownFormatting.satisfies(_:selection:)`; the generator fails on a condition not listed here.
enum FormatCondition: String, Hashable {
    case notInCode
    case inTable
    case hasSelection
}

/// A command parameter value from the manifest or a fixture.
enum FormatParamValue: Hashable, CustomStringConvertible {
    case int(Int)
    case string(String)
    case bool(Bool)
    case null

    var description: String {
        switch self {
        case .int(let value): return String(value)
        case .string(let value): return value
        case .bool(let value): return String(value)
        case .null: return "null"
        }
    }

    /// The string value, or nil for `null` (and non-strings).
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// A keyboard chord from the manifest (`Mod+Shift+8`): `Mod` is ⌘ and `Alt` is ⌥.
struct FormatShortcut: Hashable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
    }

    /// The unshifted key, lowercased (`8`, `.`, `b`).
    let key: Character
    let modifiers: Modifiers
    /// The chord as written in the manifest.
    let chord: String

    /// Letters are matched by character, so they follow the keyboard layout; digits and
    /// punctuation are matched by key code, because Shift changes the character they type.
    var keyCode: UInt16? { key.isLetter ? nil : Self.keyCodes[key] }

    /// ANSI virtual key codes (`kVK_ANSI_*`) for the digit and punctuation keys.
    static let keyCodes: [Character: UInt16] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42, ";": 41, "'": 39, ",": 43, ".": 47, "/": 44, "`": 50,
    ]

    /// The chord with macOS modifier symbols, in the standard order (⌃⌥⇧⌘).
    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + String(key).uppercased()
    }

    /// Whether a key press matches: the same modifiers, and the same key (by character for
    /// letters, by key code for digits and punctuation).
    func matches(charactersIgnoringModifiers characters: String?, keyCode: UInt16, modifiers pressed: Modifiers) -> Bool {
        guard pressed == modifiers else { return false }
        if let code = self.keyCode { return code == keyCode }
        return characters?.lowercased() == String(key)
    }
}

/// A parameterised form of a command with its own shortcut (`format.heading` with `level=1`).
struct FormatCommandVariant {
    let params: [String: FormatParamValue]
    let label: String
    let shortcut: FormatShortcut
}

/// One command from the manifest.
struct FormatCommandDefinition {
    let id: String
    let label: String
    let group: String
    let surfaces: Set<FormatSurface>
    let enabledWhen: [FormatCondition]
    let shortcut: FormatShortcut?
    let variants: [FormatCommandVariant]
}

/// A code-block language from the manifest.
struct CodeLanguage: Hashable {
    let id: String
    let label: String
    let shortLabel: String?

    /// The compact label for the bubble menu.
    var compactLabel: String { shortLabel ?? label }
}

/// A command as offered on a surface: a concrete `FormatCommand` with its label and shortcut.
struct FormatMenuEntry {
    let command: FormatCommand
    let label: String
    let group: String
    let shortcut: FormatShortcut?
}

extension FormatManifest {
    static func definition(_ id: String) -> FormatCommandDefinition? {
        commands.first { $0.id == id }
    }

    /// The commands offered on `surface`, in manifest order. Parameterised commands are listed
    /// once per variant (Heading 1–3), plus the plain command when it needs no parameters.
    static func entries(for surface: FormatSurface) -> [FormatMenuEntry] {
        commands.filter { $0.surfaces.contains(surface) }.flatMap { definition -> [FormatMenuEntry] in
            var result = definition.variants.compactMap { variant -> FormatMenuEntry? in
                FormatCommand(manifestID: definition.id, params: variant.params).map {
                    FormatMenuEntry(command: $0, label: variant.label, group: definition.group, shortcut: variant.shortcut)
                }
            }
            if let command = FormatCommand(manifestID: definition.id) {
                result.append(FormatMenuEntry(command: command, label: definition.label, group: definition.group, shortcut: definition.shortcut))
            }
            return result
        }
    }

    /// Every command that has a keyboard shortcut.
    static let shortcutBindings: [(command: FormatCommand, shortcut: FormatShortcut)] = commands.flatMap { definition in
        var result: [(FormatCommand, FormatShortcut)] = definition.variants.compactMap { variant in
            FormatCommand(manifestID: definition.id, params: variant.params).map { ($0, variant.shortcut) }
        }
        if let shortcut = definition.shortcut, let command = FormatCommand(manifestID: definition.id) {
            result.append((command, shortcut))
        }
        return result
    }

    /// The command bound to a key press, if any.
    static func command(charactersIgnoringModifiers characters: String?, keyCode: UInt16, modifiers: FormatShortcut.Modifiers) -> FormatCommand? {
        shortcutBindings.first { $0.shortcut.matches(charactersIgnoringModifiers: characters, keyCode: keyCode, modifiers: modifiers) }?.command
    }
}

// MARK: - Conditions

extension MarkdownFormatting {
    /// Whether `condition` holds for the selection (raw-Markdown UTF-16 offsets).
    func satisfies(_ condition: FormatCondition, selection: NSRange) -> Bool {
        switch condition {
        case .notInCode:
            return codeSpan(containing: selection) == nil && codeBlock(containing: selection) == nil
        case .inTable:
            return isInTable(selection)
        case .hasSelection:
            return selection.length > 0
        }
    }

    /// Whether every `enabledWhen` condition of the command holds. Swash-only commands are always enabled.
    func isEnabled(_ command: FormatCommand, selection: NSRange) -> Bool {
        (command.definition?.enabledWhen ?? []).allSatisfy { satisfies($0, selection: selection) }
    }
}
