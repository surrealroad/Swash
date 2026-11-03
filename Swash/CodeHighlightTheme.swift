//
//  CodeHighlightTheme.swift
//  Swash
//
//  Colours for `CodeHighlighter` tokens in Light and Dark Mode, and the code that applies them to
//  the editor's text storage and the preview's attributed strings. Export uses the matching
//  `.tok-*` rules in `swash-export.css`.
//

import AppKit

enum CodeHighlightTheme {
    /// (light, dark) sRGB colours, close to Xcode's default themes.
    private static func hex(_ kind: CodeTokenKind) -> (light: UInt32, dark: UInt32) {
        switch kind {
        case .keyword, .literal: return (0xAD3DA4, 0xFF7AB2)
        case .type, .emphasis: return (0x703DAA, 0xDABAFF)
        case .builtin: return (0x3E8087, 0x67B7A4)
        case .function: return (0x326D74, 0x67B7A4)
        case .string, .regex: return (0xC41A16, 0xFC6A5D)
        case .number: return (0x1C00CF, 0xD0BF69)
        case .comment: return (0x5D6C79, 0x7F8C98)
        case .meta: return (0x643820, 0xFD8F3F)
        case .tag, .heading: return (0x0B4F79, 0x5DD8FF)
        case .attribute: return (0x815F03, 0xCC9768)
        case .property: return (0x0F68A0, 0x41A1C0)
        case .variable: return (0x326D74, 0xACF2E4)
        case .inserted: return (0x1A7F37, 0x7EE787)
        case .deleted: return (0xCF222E, 0xFF7B72)
        }
    }

    private static func color(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private static let resolved: [CodeTokenKind: (light: NSColor, dark: NSColor)] = {
        var table: [CodeTokenKind: (light: NSColor, dark: NSColor)] = [:]
        for kind in CodeTokenKind.allCases { let pair = hex(kind); table[kind] = (color(pair.light), color(pair.dark)) }
        return table
    }()

    private static let dynamic: [CodeTokenKind: NSColor] = {
        var table: [CodeTokenKind: NSColor] = [:]
        for kind in CodeTokenKind.allCases {
            let pair = resolved[kind]!
            table[kind] = NSColor(name: "swash.code.\(kind.rawValue)") { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? pair.dark : pair.light
            }
        }
        return table
    }()

    /// A colour that follows the appearance it is drawn in (for the editor's text storage).
    static func color(for kind: CodeTokenKind) -> NSColor { dynamic[kind]! }

    /// A fixed colour for one appearance (for views that already know their colour scheme).
    static func color(for kind: CodeTokenKind, dark: Bool) -> NSColor {
        let pair = resolved[kind]!
        return dark ? pair.dark : pair.light
    }
}

/// Applies `CodeHighlighter` tokens to attributed text.
enum MarkdownCodeHighlighter {
    /// Most tokens Edit Text colours in one code block (several hundred lines of typical code).
    static let editorTokenLimit = 5_000

    /// Colours a whole code string (the preview's code blocks, Quick Look).
    static func highlight(_ string: NSMutableAttributedString, language: String?, dark: Bool) {
        guard let language = CodeLanguage(name: language) else { return }
        let length = string.length
        for token in CodeHighlighter.tokens(for: string.string, language: language) where NSMaxRange(token.range) <= length {
            string.addAttribute(.foregroundColor, value: CodeHighlightTheme.color(for: token.kind, dark: dark), range: token.range)
        }
    }

    /// Colours one line of code in the text storage (the Slack editor path, which styles line by line).
    static func highlight(line: String, offset: Int, language: String?, in storage: NSTextStorage) {
        guard let language = CodeLanguage(name: language) else { return }
        let full = NSRange(location: 0, length: storage.length)
        for token in CodeHighlighter.tokens(for: line, language: language) {
            let r = NSIntersectionRange(NSRange(location: offset + token.range.location, length: token.range.length), full)
            if r.length > 0 { storage.addAttribute(.foregroundColor, value: CodeHighlightTheme.color(for: token.kind), range: r) }
        }
    }

    /// Colours a fenced code block in Edit Text. The block's code (`node.literal`) is tokenized as a
    /// whole, so block comments and multi-line strings are coloured across lines; each piece is then
    /// placed on its raw Markdown line (after any block-quote or list prefix). `apply` receives raw
    /// Markdown ranges.
    ///
    /// Blocks with more than `maximumTokens` tokens stay plain: AppKit finds the extent of the block's
    /// `NSTextBlock` by walking attribute runs, once per laid-out line, so every colour run makes
    /// typing in a long block slower (see GOTCHAS.md).
    static func highlight(block node: MarkdownNode, language: String?, source text: NSString, maximumTokens: Int = editorTokenLimit, apply: (NSRange, NSColor) -> Void) {
        guard let language = CodeLanguage(name: language), !node.literal.isEmpty else { return }
        let code = node.literal as NSString
        // Raw content lines: the lines of the block that aren't fence lines
        let range = NSIntersectionRange(node.range, NSRange(location: 0, length: text.length))
        var rawLines: [NSRange] = []
        var location = range.location
        let end = NSMaxRange(range)
        while location < end {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            var content = NSRange(location: lineRange.location, length: lineRange.length)
            while content.length > 0, [0x0A, 0x0D].contains(text.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            if !node.markers.contains(where: { NSIntersectionRange($0, lineRange).length > 0 || $0.location == lineRange.location }) {
                rawLines.append(content)
            }
            if lineRange.length == 0 { break }
            location = NSMaxRange(lineRange)
        }
        // Each literal line is the end of its raw line (the parser strips prefixes and indentation)
        var literalLines: [NSRange] = []
        var start = 0
        for i in 0..<code.length where code.character(at: i) == 0x0A {
            literalLines.append(NSRange(location: start, length: i - start))
            start = i + 1
        }
        if start < code.length { literalLines.append(NSRange(location: start, length: code.length - start)) }
        guard literalLines.count == rawLines.count else { return }
        var origins: [Int?] = []
        origins.reserveCapacity(literalLines.count)
        for (literal, raw) in zip(literalLines, rawLines) {
            let origin = NSMaxRange(raw) - literal.length
            if origin >= raw.location, literal.length == 0 || text.substring(with: NSRange(location: origin, length: literal.length)) == code.substring(with: literal) {
                origins.append(origin)
            } else {
                origins.append(nil)
            }
        }
        let tokens = CodeHighlighter.tokens(for: node.literal, language: language)
        guard tokens.count <= maximumTokens else { return }
        for segment in CodeHighlighter.lineSegments(tokens, in: code) {
            guard segment.line < origins.count, let origin = origins[segment.line] else { continue }
            apply(NSRange(location: origin + segment.column, length: segment.length), CodeHighlightTheme.color(for: segment.kind))
        }
    }
}
