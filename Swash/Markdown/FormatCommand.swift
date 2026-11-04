//
//  FormatCommand.swift
//  Swash
//
//  The format commands behind the Format menu, keyboard shortcuts and bubble menu, and their
//  mapping to the shared `@pixerate/markdown-conformance` manifest ids (`format.heading` +
//  `{level: 2}` ↔ `.heading(2)`). Foundation only, so the command-line runners can use it.
//

import Foundation

enum FormatCommand: Equatable {
    case bold, italic, strikethrough, code, link
    case heading(Int), paragraph
    case bulletList, numberedList, taskList, quote, codeBlock
    /// Turn the selected lines into a table, or a table back into text (the bubble menu's Table button).
    case table
    /// Make the selection a callout of the given type; nil turns a callout back into a plain quote.
    case callout(AlertType?)
    case footnote
    case tableOfContents

    /// The command for a manifest id and its parameters, or nil when Swash has no such command
    /// (or the parameters are invalid). `format.link`'s URL and `format.codeBlock`'s language
    /// are applied by the caller, so they don't change the command.
    init?(manifestID: String, params: [String: FormatParamValue] = [:]) {
        switch manifestID {
        case "format.bold": self = .bold
        case "format.italic": self = .italic
        case "format.strikethrough": self = .strikethrough
        case "format.code": self = .code
        case "format.link": self = .link
        case "format.heading":
            guard case .int(let level)? = params["level"], (1...6).contains(level) else { return nil }
            self = .heading(level)
        case "format.paragraph": self = .paragraph
        case "format.bulletList": self = .bulletList
        case "format.numberedList": self = .numberedList
        case "format.taskList": self = .taskList
        case "format.quote": self = .quote
        case "format.codeBlock": self = .codeBlock
        case "format.table": self = .table
        default: return nil
        }
    }

    /// The manifest id and parameters for this command; nil for Swash-only commands.
    var manifestInvocation: (id: String, params: [String: FormatParamValue])? {
        switch self {
        case .bold: return ("format.bold", [:])
        case .italic: return ("format.italic", [:])
        case .strikethrough: return ("format.strikethrough", [:])
        case .code: return ("format.code", [:])
        case .link: return ("format.link", [:])
        case .heading(let level): return ("format.heading", ["level": .int(level)])
        case .paragraph: return ("format.paragraph", [:])
        case .bulletList: return ("format.bulletList", [:])
        case .numberedList: return ("format.numberedList", [:])
        case .taskList: return ("format.taskList", [:])
        case .quote: return ("format.quote", [:])
        case .codeBlock: return ("format.codeBlock", [:])
        case .table: return ("format.table", [:])
        case .callout, .footnote, .tableOfContents: return nil
        }
    }

    /// The manifest entry for this command, if it has one.
    var definition: FormatCommandDefinition? {
        manifestInvocation.flatMap { FormatManifest.definition($0.id) }
    }

    /// The command's label in the manifest (`Heading 2` for a heading level); nil for Swash-only commands.
    var label: String? {
        guard let invocation = manifestInvocation, let definition = definition else { return nil }
        if let variant = definition.variants.first(where: { $0.params == invocation.params }) { return variant.label }
        let values = invocation.params.sorted { $0.key < $1.key }.map { $0.value.description }
        return ([definition.label] + values).joined(separator: " ")
    }

    /// The command's keyboard shortcut from the manifest, if any.
    var shortcut: FormatShortcut? {
        guard let invocation = manifestInvocation, let definition = definition else { return nil }
        if let variant = definition.variants.first(where: { $0.params == invocation.params }) { return variant.shortcut }
        return invocation.params.isEmpty ? definition.shortcut : nil
    }
}
