//
//  MarkdownSyntax.swift
//  Swash
//
//  Shared CommonMark lexical helpers: character classes, HTML patterns, escaping,
//  entity decoding, label and URI normalisation.
//

import Foundation

enum MarkdownSyntax {
    // MARK: Character classes

    static func isASCIIPunctuation(_ c: UInt16) -> Bool {
        (c >= 0x21 && c <= 0x2F) || (c >= 0x3A && c <= 0x40) || (c >= 0x5B && c <= 0x60) || (c >= 0x7B && c <= 0x7E)
    }

    /// CommonMark "Unicode whitespace": Zs, tab, line feed, form feed, carriage return.
    static func isUnicodeWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0C, 0x0D, 0x20: return true
        default: return scalar.properties.generalCategory == .spaceSeparator
        }
    }

    /// CommonMark 0.31 "Unicode punctuation": general categories P* and S*.
    static func isUnicodePunctuation(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII { return isASCIIPunctuation(UInt16(scalar.value)) }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    // MARK: Regular expressions

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are compile-time constants
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    static let tagName = "[A-Za-z][A-Za-z0-9-]*"
    static let attributeName = "[a-zA-Z_:][a-zA-Z0-9:._-]*"
    static let unquotedValue = "[^\"'=<>`\\x00-\\x20]+"
    static let attributeValue = "(?:" + unquotedValue + "|'[^']*'|\"[^\"]*\")"
    static let attribute = "(?:\\s+" + attributeName + "(?:\\s*=\\s*" + attributeValue + ")?)"
    static let openTag = "<" + tagName + attribute + "*\\s*/?>"
    static let closeTag = "</" + tagName + "\\s*[>]"
    static let htmlComment = "<!-->|<!--->|<!--[\\s\\S]*?-->"
    static let processingInstruction = "[<][?][\\s\\S]*?[?][>]"
    static let declaration = "<![A-Za-z]+[^>]*>"
    static let cdata = "<!\\[CDATA\\[[\\s\\S]*?\\]\\]>"

    static let htmlTagRegex = regex("^(?:" + openTag + "|" + closeTag + "|" + htmlComment + "|" + processingInstruction + "|" + declaration + "|" + cdata + ")")

    private static let htmlBlockOpenRegexes: [NSRegularExpression] = [
        regex("."),
        regex("^<(?:script|pre|textarea|style)(?:\\s|>|$)", .caseInsensitive),
        regex("^<!--"),
        regex("^<[?]"),
        regex("^<![A-Za-z]"),
        regex("^<!\\[CDATA\\["),
        regex("^<[/]?(?:address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[123456]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)(?:\\s|[/]?[>]|$)", .caseInsensitive),
        regex("^(?:" + openTag + "|" + closeTag + ")\\s*$", .caseInsensitive),
    ]

    private static let htmlBlockCloseRegexes: [NSRegularExpression] = [
        regex("."),
        regex("</(?:script|pre|textarea|style)>", .caseInsensitive),
        regex("-->"),
        regex("\\?>"),
        regex(">"),
        regex("\\]\\]>"),
    ]

    static func htmlBlockOpen(_ type: Int, _ line: String) -> Bool {
        let r = htmlBlockOpenRegexes[type]
        return r.firstMatch(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    static func htmlBlockClose(_ type: Int, _ line: String) -> Bool {
        let r = htmlBlockCloseRegexes[type]
        return r.firstMatch(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    // MARK: Escapes and entities

    /// Decodes an entity reference such as `&amp;`, `&#35;` or `&#x22;`; nil if invalid.
    static func decodeEntity(_ entity: String) -> String? {
        guard entity.hasPrefix("&"), entity.hasSuffix(";"), entity.count >= 3 else { return nil }
        let body = entity.dropFirst().dropLast()
        if body.hasPrefix("#") {
            let numeric = body.dropFirst()
            let value: UInt32?
            if numeric.hasPrefix("x") || numeric.hasPrefix("X") {
                let hex = numeric.dropFirst()
                guard (1...6).contains(hex.count) else { return nil }
                value = UInt32(hex, radix: 16)
            } else {
                guard (1...7).contains(numeric.count) else { return nil }
                value = UInt32(numeric, radix: 10)
            }
            guard let code = value else { return nil }
            if code == 0 { return "\u{FFFD}" }
            guard let scalar = Unicode.Scalar(code) else { return "\u{FFFD}" }
            return String(Character(scalar))
        }
        return MarkdownEntities.decode(String(body))
    }

    private static let entityOrEscape = regex("\\\\[!\"#$%&'()*+,./:;<=>?@\\[\\\\\\]^_`{|}~-]|&(?:#[xX][a-fA-F0-9]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});")

    /// Resolves backslash escapes and entity references (used for link destinations, titles, info strings).
    static func unescape(_ s: String) -> String {
        guard s.contains("\\") || s.contains("&") else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in entityOrEscape.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let token = ns.substring(with: m.range)
            if token.hasPrefix("\\") {
                out += String(token.dropFirst())
            } else {
                out += decodeEntity(token) ?? token
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    /// Link label normalisation: strip brackets' content whitespace, collapse runs, Unicode case fold.
    static func normalizeLabel(_ label: String) -> String {
        let collapsed = label.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
        return collapsed.lowercased().uppercased()
    }

    // MARK: HTML output helpers

    static func escapeHTML(_ s: String) -> String {
        guard s.contains(where: { $0 == "&" || $0 == "<" || $0 == ">" || $0 == "\"" }) else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }

    /// Percent-encodes a URL the way commonmark.js does (existing `%XX` escapes are preserved).
    /// A link destination as a URL, normalising characters that `URL(string:)` rejects.
    static func url(_ destination: String) -> URL? {
        URL(string: destination) ?? URL(string: normalizeURI(destination))
    }

    static func normalizeURI(_ uri: String) -> String {
        let safe = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789;/?:@&=+$,-_.!~*'()#".utf8)
        let bytes = Array(uri.utf8)
        var out = ""
        var i = 0
        func isHex(_ b: UInt8) -> Bool { (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66) }
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x25, i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]) {
                out += String(decoding: bytes[i...(i + 2)], as: UTF8.self)
                i += 3
                continue
            }
            if safe.contains(b) {
                out.append(Character(Unicode.Scalar(b)))
            } else {
                out += String(format: "%%%02X", b)
            }
            i += 1
        }
        return out
    }
}
