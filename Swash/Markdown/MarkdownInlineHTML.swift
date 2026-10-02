//
//  MarkdownInlineHTML.swift
//  Swash
//
//  Pairs inline HTML tags (CommonMark parses each tag as its own `htmlInline` node) so the
//  editor and preview can render common formatting tags: <kbd>, <sub>, <sup>, <mark>, <u>,
//  <ins>, <s>, <del>, <b>, <strong>, <i>, <em>, <small>, <code>; plus <br>, <img> and comments.
//

import Foundation

enum InlineHTMLStyle: Hashable {
    case keyboard, lowered, raised, highlight, underline, strikethrough, bold, italic, small, code

    static func forTag(_ name: String) -> InlineHTMLStyle? {
        switch name {
        case "kbd": return .keyboard
        case "sub": return .lowered
        case "sup": return .raised
        case "mark": return .highlight
        case "u", "ins": return .underline
        case "s", "del", "strike": return .strikethrough
        case "b", "strong": return .bold
        case "i", "em": return .italic
        case "small": return .small
        case "code", "tt", "samp": return .code
        default: return nil
        }
    }
}

struct InlineHTMLTag {
    enum Kind: Equatable {
        case open(String)
        case close(String)
        case lineBreak
        case image(src: String, alt: String, width: Double?)
        case comment
        case other
    }
    let kind: Kind

    private static let openRegex = try! NSRegularExpression(pattern: "^<([A-Za-z][A-Za-z0-9-]*)(\\s[^>]*)?(/?)>$")
    private static let closeRegex = try! NSRegularExpression(pattern: "^</([A-Za-z][A-Za-z0-9-]*)\\s*>$")
    private static let attributeRegex = try! NSRegularExpression(pattern: "([A-Za-z_:][A-Za-z0-9:._-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+))")

    init(_ literal: String) {
        let ns = literal as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if literal.hasPrefix("<!--") {
            kind = .comment
        } else if let m = Self.closeRegex.firstMatch(in: literal, options: [], range: whole) {
            kind = .close(ns.substring(with: m.range(at: 1)).lowercased())
        } else if let m = Self.openRegex.firstMatch(in: literal, options: [], range: whole) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            let attributes = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            if name == "br" {
                kind = .lineBreak
            } else if name == "img" {
                let attrs = Self.attributes(attributes)
                if let src = attrs["src"], !src.isEmpty {
                    kind = .image(src: src, alt: attrs["alt"] ?? "", width: attrs["width"].flatMap { Double($0.replacingOccurrences(of: "px", with: "")) })
                } else {
                    kind = .other
                }
            } else if m.range(at: 3).length > 0 {
                kind = .other   // self-closing element we do not render
            } else {
                kind = .open(name)
            }
        } else {
            kind = .other
        }
    }

    static func attributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        let ns = text as NSString
        for m in attributeRegex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            for group in 2...4 where m.range(at: group).location != NSNotFound {
                result[name] = MarkdownSyntax.unescape(ns.substring(with: m.range(at: group)))
                break
            }
        }
        return result
    }
}

enum MarkdownInlineHTML {
    /// For each child index of an inline container: the HTML styles of the paired tags that enclose
    /// it, and which `htmlInline` children are the paired tags themselves.
    struct Pairing {
        var styles: [Int: Set<InlineHTMLStyle>] = [:]
        var pairedTags: Set<Int> = []
    }

    static func pairing(of children: [MarkdownNode]) -> Pairing {
        var pairing = Pairing()
        var stack: [(name: String, index: Int)] = []
        var spans: [(start: Int, end: Int, style: InlineHTMLStyle)] = []
        for (index, child) in children.enumerated() {
            guard case .htmlInline = child.kind else { continue }
            switch InlineHTMLTag(child.literal).kind {
            case .open(let name) where InlineHTMLStyle.forTag(name) != nil:
                stack.append((name, index))
            case .close(let name):
                if let openIndex = stack.lastIndex(where: { $0.name == name }), let style = InlineHTMLStyle.forTag(name) {
                    let open = stack[openIndex]
                    stack.removeSubrange(openIndex...)
                    spans.append((open.index, index, style))
                    pairing.pairedTags.insert(open.index)
                    pairing.pairedTags.insert(index)
                }
            default:
                break
            }
        }
        for span in spans where span.end > span.start + 1 {
            for i in (span.start + 1)..<span.end {
                pairing.styles[i, default: []].insert(span.style)
            }
        }
        return pairing
    }
}
