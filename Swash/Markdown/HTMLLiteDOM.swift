//
//  HTMLLiteDOM.swift
//  Swash
//
//  A small, forgiving HTML parser for platforms without Foundation's XMLDocument (iOS). It
//  exposes the subset of the XMLDocument / XMLNode / XMLElement API that HTMLToMarkdown uses,
//  so the converter has one implementation. Like `.documentTidyHTML`, it closes unclosed
//  elements, applies HTML's implied end tags (p, li, td, tr…), keeps script and style text raw,
//  and decodes character references.
//

import Foundation

final class HTMLLiteDocument {
    private let root: HTMLLiteElement

    /// Mirrors `XMLDocument(xmlString:options:)`; the options are accepted for source compatibility.
    init(xmlString: String, options: HTMLLiteDocument.Options = []) throws {
        var parser = HTMLLiteParser(xmlString)
        root = parser.parse()
    }

    struct Options: OptionSet {
        let rawValue: Int
        static let documentTidyHTML = Options(rawValue: 1 << 0)
        static let nodeLoadExternalEntitiesNever = Options(rawValue: 1 << 1)
    }

    /// The `<html>` element (created when the markup has none).
    func rootElement() -> HTMLLiteElement? {
        root.elements(forName: "html").first ?? root
    }
}

class HTMLLiteNode {
    enum Kind { case element, text }

    let kind: Kind
    /// Lower-case tag name for elements; nil for text.
    let name: String?
    fileprivate(set) var childNodes: [HTMLLiteNode] = []
    fileprivate weak var parent: HTMLLiteElement?
    fileprivate var text: String

    fileprivate init(kind: Kind, name: String?, text: String = "") {
        self.kind = kind
        self.name = name
        self.text = text
    }

    var children: [HTMLLiteNode]? {
        kind == .element ? childNodes : nil
    }

    /// Text content, concatenated through descendants for elements.
    var stringValue: String? {
        switch kind {
        case .text: return text
        case .element: return childNodes.map { $0.stringValue ?? "" }.joined()
        }
    }
}

final class HTMLLiteElement: HTMLLiteNode {
    fileprivate var attributes: [String: String] = [:]

    fileprivate init(name: String) {
        super.init(kind: .element, name: name)
    }

    final class Attribute {
        let stringValue: String?
        init(_ value: String) { stringValue = value }
    }

    func attribute(forName name: String) -> Attribute? {
        attributes[name.lowercased()].map { Attribute($0) }
    }

    func elements(forName name: String) -> [HTMLLiteElement] {
        childNodes.compactMap { $0 as? HTMLLiteElement }.filter { $0.name == name.lowercased() }
    }

    fileprivate func append(_ node: HTMLLiteNode) {
        node.parent = self
        childNodes.append(node)
    }
}

private struct HTMLLiteParser {
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr",
    ]
    private static let rawTextElements: Set<String> = ["script", "style", "textarea", "title"]
    /// Start tags that close an open element of the listed kinds (HTML's implied end tags).
    private static let impliedEnds: [String: Set<String>] = [
        "li": ["li"],
        "dt": ["dt", "dd"], "dd": ["dt", "dd"],
        "tr": ["tr", "td", "th"], "td": ["td", "th"], "th": ["td", "th"],
        "thead": ["tbody", "tfoot", "tr", "td", "th"], "tbody": ["thead", "tbody", "tfoot", "tr", "td", "th"],
        "tfoot": ["thead", "tbody", "tr", "td", "th"],
        "option": ["option"],
    ]
    private static let closesParagraph: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "dl", "fieldset", "figcaption", "figure",
        "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "main", "nav", "ol", "p", "pre",
        "section", "table", "ul",
    ]
    /// Elements that stop the search for an implied end (a nested list's `li` must not close the outer one).
    private static let scopeBoundaries: Set<String> = ["ul", "ol", "table", "dl", "blockquote", "div", "body", "html"]

    private let chars: [Character]
    private var index = 0

    init(_ html: String) {
        chars = Array(html)
    }

    mutating func parse() -> HTMLLiteElement {
        let document = HTMLLiteElement(name: "#document")
        var stack: [HTMLLiteElement] = [document]
        var textBuffer = ""

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            stack.last!.append(HTMLLiteNode(kind: .text, name: nil, text: Self.decodeEntities(textBuffer)))
            textBuffer = ""
        }

        while index < chars.count {
            let c = chars[index]
            guard c == "<" else {
                textBuffer.append(c)
                index += 1
                continue
            }
            if starts(with: "<!--") {
                flushText()
                skip(past: "-->")
                continue
            }
            if starts(with: "<!") || starts(with: "<?") {
                flushText()
                skip(past: ">")
                continue
            }
            if starts(with: "</") {
                index += 2
                let name = readName()
                skip(past: ">")
                guard !name.isEmpty else { continue }
                flushText()
                if name == "p", !stack.contains(where: { $0.name == "p" }) {
                    stack.last!.append(HTMLLiteElement(name: "p"))   // a stray </p> is an empty paragraph
                    continue
                }
                if let match = stack.lastIndex(where: { $0.name == name }), match > 0 {
                    stack.removeSubrange(match...)
                }
                continue
            }
            // Start tag
            let tagStart = index
            index += 1
            let name = readName()
            guard !name.isEmpty else {
                index = tagStart + 1
                textBuffer.append("<")
                continue
            }
            flushText()
            let element = HTMLLiteElement(name: name)
            let selfClosing = readAttributes(into: element)

            if Self.closesParagraph.contains(name), let p = stack.lastIndex(where: { $0.name == "p" }),
               !stack[p...].dropFirst().contains(where: { Self.scopeBoundaries.contains($0.name ?? "") }) {
                stack.removeSubrange(p...)
            }
            if let closes = Self.impliedEnds[name] {
                for i in stack.indices.reversed() {
                    let open = stack[i].name ?? ""
                    if closes.contains(open) {
                        stack.removeSubrange(i...)
                        break
                    }
                    if Self.scopeBoundaries.contains(open) { break }
                }
            }
            stack.last!.append(element)

            if Self.voidElements.contains(name) || selfClosing { continue }
            if Self.rawTextElements.contains(name) {
                let raw = readRawText(until: name)
                if !raw.isEmpty {
                    element.append(HTMLLiteNode(kind: .text, name: nil, text: name == "textarea" || name == "title" ? Self.decodeEntities(raw) : raw))
                }
                continue
            }
            stack.append(element)
        }
        flushText()
        return Self.normalized(document)
    }

    /// Wraps content in html/body like the tidy step, so callers can always look up `body`.
    private static func normalized(_ document: HTMLLiteElement) -> HTMLLiteElement {
        if document.elements(forName: "html").first != nil { return document }
        let html = HTMLLiteElement(name: "html")
        let body = HTMLLiteElement(name: "body")
        for child in document.childNodes { body.append(child) }
        html.append(body)
        let wrapper = HTMLLiteElement(name: "#document")
        wrapper.append(html)
        return wrapper
    }

    // MARK: Scanning

    private func starts(with prefix: String) -> Bool {
        var i = index
        for p in prefix {
            guard i < chars.count, chars[i].lowercased() == p.lowercased() else { return false }
            i += 1
        }
        return true
    }

    private mutating func skip(past terminator: String) {
        while index < chars.count {
            if starts(with: terminator) {
                index += terminator.count
                return
            }
            index += 1
        }
    }

    private mutating func readName() -> String {
        var name = ""
        while index < chars.count {
            let c = chars[index]
            if c.isLetter || c.isNumber || c == "-" || c == ":" || c == "_" {
                name.append(c)
                index += 1
            } else {
                break
            }
        }
        return name.lowercased()
    }

    private mutating func skipWhitespace() {
        while index < chars.count, chars[index].isWhitespace { index += 1 }
    }

    /// Reads attributes up to and including `>`; returns true for a `/>` self-closing tag.
    private mutating func readAttributes(into element: HTMLLiteElement) -> Bool {
        while index < chars.count {
            skipWhitespace()
            guard index < chars.count else { return false }
            let c = chars[index]
            if c == ">" {
                index += 1
                return false
            }
            if c == "/" {
                index += 1
                skipWhitespace()
                if index < chars.count, chars[index] == ">" {
                    index += 1
                    return true
                }
                continue
            }
            var name = ""
            while index < chars.count, !chars[index].isWhitespace, !"=>/".contains(chars[index]) {
                name.append(chars[index])
                index += 1
            }
            guard !name.isEmpty else {
                index += 1
                continue
            }
            skipWhitespace()
            var value = ""
            if index < chars.count, chars[index] == "=" {
                index += 1
                skipWhitespace()
                if index < chars.count, chars[index] == "\"" || chars[index] == "'" {
                    let quote = chars[index]
                    index += 1
                    while index < chars.count, chars[index] != quote {
                        value.append(chars[index])
                        index += 1
                    }
                    index += 1
                } else {
                    while index < chars.count, !chars[index].isWhitespace, chars[index] != ">" {
                        value.append(chars[index])
                        index += 1
                    }
                }
            }
            let key = name.lowercased()
            if element.attributes[key] == nil {
                element.attributes[key] = Self.decodeEntities(value)
            }
        }
        return false
    }

    private mutating func readRawText(until name: String) -> String {
        var raw = ""
        while index < chars.count {
            if starts(with: "</" + name) {
                index += 2 + name.count
                skip(past: ">")
                return raw
            }
            raw.append(chars[index])
            index += 1
        }
        return raw
    }

    // MARK: Character references

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            guard text[i] == "&", let semicolon = text[i...].prefix(40).firstIndex(of: ";") else {
                out.append(text[i])
                i = text.index(after: i)
                continue
            }
            let body = String(text[text.index(after: i)..<semicolon])
            if let decoded = decodeReference(body) {
                out += decoded
                i = text.index(after: semicolon)
            } else {
                out.append("&")
                i = text.index(after: i)
            }
        }
        return out
    }

    private static func decodeReference(_ body: String) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits)
            }
            guard let v = value, v != 0, let scalar = Unicode.Scalar(v) else { return value == nil ? nil : "\u{FFFD}" }
            return String(Character(scalar))
        }
        return MarkdownEntities.decode(body)
    }
}
