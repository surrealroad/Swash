//
//  MarkdownHTMLRenderer.swift
//  Swash
//
//  Renders a MarkdownDocument to HTML in the same format as commonmark.js / cmark-gfm,
//  so the parser can be verified against the CommonMark and GFM spec examples.
//

import Foundation

struct MarkdownHTMLRenderer {
    private var buffer = ""
    private var lastOut = "\n"
    private var disableTags = 0
    private let document: MarkdownDocument
    private var footnoteNumbers: [String: Int] = [:]
    private var footnoteReferenceCounts: [String: Int] = [:]

    static func render(_ document: MarkdownDocument) -> String {
        var renderer = MarkdownHTMLRenderer(document: document)
        renderer.renderDocument()
        return renderer.buffer
    }

    private init(document: MarkdownDocument) {
        self.document = document
        for (index, label) in document.footnoteOrder.enumerated() {
            footnoteNumbers[label] = index + 1
        }
    }

    // MARK: Output primitives

    private mutating func lit(_ s: String) {
        guard !s.isEmpty else { return }
        buffer += s
        lastOut = s
    }

    private mutating func out(_ s: String) {
        lit(MarkdownSyntax.escapeHTML(s))
    }

    private mutating func cr() {
        if !lastOut.hasSuffix("\n") { lit("\n") }
    }

    private mutating func tag(_ name: String, _ attributes: [(String, String)] = [], selfClosing: Bool = false) {
        guard disableTags == 0 else { return }
        var s = "<" + name
        for (key, value) in attributes {
            s += value.isEmpty && key.hasPrefix("data-") ? " \(key)" : " \(key)=\"\(value)\""
        }
        if selfClosing { s += " /" }
        s += ">"
        lit(s)
    }

    // MARK: Document

    private mutating func renderDocument() {
        for child in document.root.children {
            render(child)
        }
        renderFootnotes()
    }

    private func isInTightList(_ paragraph: MarkdownNode) -> Bool {
        guard let item = paragraph.parent, case .listItem = item.kind,
              let list = item.parent, case .list(_, _, _, _, let tight) = list.kind else { return false }
        return tight
    }

    private mutating func renderChildren(_ node: MarkdownNode) {
        for child in node.children { render(child) }
    }

    private mutating func render(_ node: MarkdownNode) {
        switch node.kind {
        case .document:
            renderChildren(node)
        case .frontMatter, .linkReferenceDefinition, .footnoteDefinition:
            break
        case .paragraph:
            if isInTightList(node) {
                renderChildren(node)
            } else {
                cr()
                tag("p")
                renderChildren(node)
                tag("/p")
                cr()
            }
        case .heading(let level, _):
            cr()
            tag("h\(level)")
            renderChildren(node)
            tag("/h\(level)")
            cr()
        case .codeBlock(_, let info):
            let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            cr()
            tag("pre")
            tag("code", language.isEmpty ? [] : [("class", "language-" + MarkdownSyntax.escapeHTML(language))])
            out(node.literal)
            tag("/code")
            tag("/pre")
            cr()
        case .htmlBlock:
            cr()
            lit(node.literal)
            cr()
        case .thematicBreak:
            cr()
            tag("hr", selfClosing: true)
            cr()
        case .blockQuote, .alert:
            cr()
            tag("blockquote")
            cr()
            renderChildren(node)
            cr()
            tag("/blockquote")
            cr()
        case .list(let ordered, let start, _, _, _):
            let name = ordered ? "ol" : "ul"
            cr()
            tag(name, ordered && start != 1 ? [("start", String(start))] : [])
            cr()
            renderChildren(node)
            cr()
            tag("/" + name)
            cr()
        case .listItem(let task):
            tag("li")
            if let task = task {
                tag("input", task == .checked ? [("type", "checkbox"), ("checked", ""), ("disabled", "")] : [("type", "checkbox"), ("disabled", "")], selfClosing: true)
                lit(" ")
            }
            renderChildren(node)
            tag("/li")
            cr()
        case .table:
            cr()
            tag("table")
            cr()
            let rows = node.children
            for row in rows {
                if case .tableHead = row.kind {
                    tag("thead")
                    cr()
                    renderChildren(row)
                    tag("/thead")
                    cr()
                }
            }
            let body = rows.filter { if case .tableRow = $0.kind { return true }; return false }
            if !body.isEmpty {
                tag("tbody")
                cr()
                for row in body { render(row) }
                tag("/tbody")
                cr()
            }
            tag("/table")
            cr()
        case .tableHead:
            renderChildren(node)
        case .tableRow:
            tag("tr")
            cr()
            renderChildren(node)
            tag("/tr")
            cr()
        case .tableCell(let alignment, let isHeader):
            let name = isHeader ? "th" : "td"
            var attributes: [(String, String)] = []
            switch alignment {
            case .left: attributes = [("align", "left")]
            case .center: attributes = [("align", "center")]
            case .right: attributes = [("align", "right")]
            case .defaultAlignment: break
            }
            tag(name, attributes)
            renderChildren(node)
            tag("/" + name)
            cr()
        case .text:
            out(node.literal)
        case .softBreak:
            lit("\n")
        case .hardBreak:
            tag("br", selfClosing: true)
            cr()
        case .code:
            tag("code")
            out(node.literal)
            tag("/code")
        case .emphasis:
            tag("em"); renderChildren(node); tag("/em")
        case .strong:
            tag("strong"); renderChildren(node); tag("/strong")
        case .strikethrough:
            tag("del"); renderChildren(node); tag("/del")
        case .link(let destination, let title, _):
            var attributes = [("href", MarkdownSyntax.escapeHTML(MarkdownSyntax.normalizeURI(destination)))]
            if let title = title, !title.isEmpty { attributes.append(("title", MarkdownSyntax.escapeHTML(title))) }
            tag("a", attributes)
            renderChildren(node)
            tag("/a")
        case .image(let destination, let title):
            if disableTags == 0 {
                lit("<img src=\"" + MarkdownSyntax.escapeHTML(MarkdownSyntax.normalizeURI(destination)) + "\" alt=\"")
            }
            disableTags += 1
            renderChildren(node)
            disableTags -= 1
            if disableTags == 0 {
                if let title = title, !title.isEmpty { lit("\" title=\"" + MarkdownSyntax.escapeHTML(title)) }
                lit("\" />")
            }
        case .htmlInline:
            lit(node.literal)
        case .math:
            tag("span", [("class", "math math-inline")])
            out(node.literal)
            tag("/span")
        case .footnoteReference(let label):
            let normalized = MarkdownSyntax.normalizeLabel(label)
            let number = footnoteNumbers[normalized] ?? 0
            let count = (footnoteReferenceCounts[normalized] ?? 0) + 1
            footnoteReferenceCounts[normalized] = count
            let slug = MarkdownSyntax.normalizeURI(label)
            let id = count == 1 ? "fnref-\(slug)" : "fnref-\(slug)-\(count)"
            tag("sup", [("class", "footnote-ref")])
            tag("a", [("href", "#fn-\(slug)"), ("id", id), ("data-footnote-ref", "")])
            lit(String(number))
            tag("/a")
            tag("/sup")
        }
    }

    // MARK: Footnotes (cmark-gfm format)

    private mutating func renderFootnotes() {
        guard !document.footnoteOrder.isEmpty else { return }
        var definitions: [String: MarkdownNode] = [:]
        document.root.walk { node in
            if case .footnoteDefinition(let label) = node.kind {
                let normalized = MarkdownSyntax.normalizeLabel(label)
                if definitions[normalized] == nil { definitions[normalized] = node }
            }
        }
        cr()
        tag("section", [("class", "footnotes"), ("data-footnotes", "")])
        cr()
        tag("ol")
        cr()
        for (index, normalized) in document.footnoteOrder.enumerated() {
            guard let def = definitions[normalized], case .footnoteDefinition(let label) = def.kind else { continue }
            let slug = MarkdownSyntax.normalizeURI(label)
            let number = index + 1
            let references = max(1, footnoteReferenceCounts[normalized] ?? 1)
            tag("li", [("id", "fn-\(slug)")])
            cr()
            let children = def.children
            func backrefs(_ r: inout MarkdownHTMLRenderer) {
                for n in 1...references {
                    let target = n == 1 ? "fnref-\(slug)" : "fnref-\(slug)-\(n)"
                    let idx = n == 1 ? "\(number)" : "\(number)-\(n)"
                    if n > 1 { r.lit(" ") }
                    r.tag("a", [("href", "#\(target)"), ("class", "footnote-backref"), ("data-footnote-backref", ""),
                                ("data-footnote-backref-idx", idx), ("aria-label", "Back to reference \(idx)")])
                    r.lit("↩")
                    if n > 1 {
                        r.tag("sup", [("class", "footnote-ref")])
                        r.lit(String(n))
                        r.tag("/sup")
                    }
                    r.tag("/a")
                }
            }
            for (i, child) in children.enumerated() {
                if i == children.count - 1, case .paragraph = child.kind {
                    cr()
                    tag("p")
                    renderChildren(child)
                    lit(" ")
                    backrefs(&self)
                    tag("/p")
                    cr()
                } else {
                    render(child)
                }
            }
            if !(children.last.map { if case .paragraph = $0.kind { return true }; return false } ?? false) {
                backrefs(&self)
                cr()
            }
            tag("/li")
            cr()
        }
        tag("/ol")
        cr()
        tag("/section")
        cr()
    }
}
