//
//  HTMLToMarkdown.swift
//  Swash
//
//  Converts pasted HTML (browsers, Google Docs, Pages, Word) into CommonMark/GFM.
//

import Foundation

#if !os(macOS) || SWASH_HTML_LITE
// Foundation's XMLDocument (with its tidy-HTML option) is macOS-only; elsewhere the converter
// runs on HTMLLiteDOM, which offers the same API.
private typealias XMLDocument = HTMLLiteDocument
private typealias XMLNode = HTMLLiteNode
private typealias XMLElement = HTMLLiteElement
#endif

enum HTMLToMarkdown {
    /// Pasteboard type where Chromium browsers record the page the HTML was copied from.
    static let chromiumSourceURLType = "org.chromium.source-url"

    /// Converts an HTML document or fragment to Markdown; nil when it holds no convertible content.
    /// `sourceURL` is the page it was copied from, used to link images that carry no URL of their own.
    static func convert(_ html: String, sourceURL: URL? = nil) -> String? {
        let wrapped = html.range(of: "<html", options: .caseInsensitive) == nil ? "<html><body>\(html)</body></html>" : html
        guard let document = try? XMLDocument(xmlString: wrapped, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let root = document.rootElement() else { return nil }
        let body = root.elements(forName: "body").first ?? root
        let blocks = Converter(sourceURL: sourceURL).blocks(of: body, listDepth: 0)
        let markdown = blocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return markdown.isEmpty ? nil : markdown
    }

    private struct InlineStyle {
        var bold = false
        var italic = false
        var strike = false
        var code = false
    }

    private struct Converter {
        private static let blockElements: Set<String> = [
            "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre",
            "table", "hr", "section", "article", "header", "footer", "main", "figure", "dl", "dt", "dd", "body",
        ]
        private static let skipped: Set<String> = ["script", "style", "head", "meta", "title", "link", "noscript", "template"]

        let sourceURL: URL?

        private func name(_ node: XMLNode) -> String { node.name?.lowercased() ?? "" }

        private func isBlock(_ node: XMLNode) -> Bool {
            node.kind == .element && Self.blockElements.contains(name(node))
        }

        private func containsBlocks(_ node: XMLNode) -> Bool {
            (node.children ?? []).contains { isBlock($0) }
        }

        // MARK: Blocks

        func blocks(of node: XMLNode, listDepth: Int) -> [String] {
            var result: [String] = []
            var pendingInline: [XMLNode] = []
            func flushInline() {
                let text = inline(pendingInline, style: InlineStyle()).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { result.append(text) }
                pendingInline.removeAll()
            }
            for child in node.children ?? [] {
                if child.kind == .element, Self.skipped.contains(name(child)) { continue }
                if isBlock(child) {
                    flushInline()
                    result.append(contentsOf: block(child, listDepth: listDepth))
                } else {
                    pendingInline.append(child)
                }
            }
            flushInline()
            return result
        }

        private func block(_ element: XMLNode, listDepth: Int) -> [String] {
            let tag = name(element)
            switch tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(String(tag.dropFirst())) ?? 1
                let text = inlineContent(element).replacingOccurrences(of: "\n", with: " ")
                return text.isEmpty ? [] : [String(repeating: "#", count: level) + " " + text]
            case "p":
                let text = inlineContent(element)
                return text.isEmpty ? [] : [text]
            case "ul", "ol":
                return [list(element, ordered: tag == "ol", depth: listDepth)]
            case "blockquote":
                let inner = blocks(of: element, listDepth: 0).joined(separator: "\n\n")
                guard !inner.isEmpty else { return [] }
                return [inner.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")]
            case "pre":
                var language = ""
                let codeElement = (element.children ?? []).first { name($0) == "code" }
                for candidate in [codeElement, element].compactMap({ $0 as? XMLElement }) {
                    if let cls = candidate.attribute(forName: "class")?.stringValue,
                       let lang = cls.split(separator: " ").first(where: { $0.hasPrefix("language-") || $0.hasPrefix("lang-") }) {
                        language = String(lang.split(separator: "-", maxSplits: 1).last ?? "")
                        break
                    }
                }
                var code = (codeElement ?? element).stringValue ?? ""
                while code.hasSuffix("\n") { code.removeLast() }
                let longestRun = code.components(separatedBy: CharacterSet(charactersIn: "`").inverted).map { $0.count }.max() ?? 0
                let fence = String(repeating: "`", count: max(3, longestRun + 1))
                return ["\(fence)\(language)\n\(code)\n\(fence)"]
            case "table":
                return table(element).map { [$0] } ?? []
            case "hr":
                return ["---"]
            case "li":
                return [list(element, ordered: false, depth: listDepth, singleItem: true)]
            default:
                if let image = (element as? XMLElement).flatMap(atlassianMedia) { return [image] }
                // Generic containers (div, section…): paragraphs, or nested blocks
                if containsBlocks(element) {
                    return blocks(of: element, listDepth: listDepth)
                }
                let text = inlineContent(element)
                return text.isEmpty ? [] : [text]
            }
        }

        private func list(_ element: XMLNode, ordered: Bool, depth: Int, singleItem: Bool = false) -> String {
            let items = singleItem ? [element] : (element.children ?? []).filter { name($0) == "li" }
            var start = 1
            if ordered, let s = (element as? XMLElement)?.attribute(forName: "start")?.stringValue, let n = Int(s) { start = n }
            var lines: [String] = []
            for (index, item) in items.enumerated() {
                let marker = ordered ? "\(start + index). " : "- "
                let pad = String(repeating: " ", count: marker.count)
                // Task list items rendered as checkboxes
                var taskPrefix = ""
                if let input = (item.children ?? []).first(where: { name($0) == "input" }) as? XMLElement,
                   input.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" {
                    taskPrefix = input.attribute(forName: "checked") != nil ? "[x] " : "[ ] "
                }
                let parts = blocks(of: item, listDepth: depth + 1)
                guard !parts.isEmpty else { lines.append(marker.trimmingCharacters(in: .whitespaces)); continue }
                for (i, part) in parts.enumerated() {
                    let partLines = part.components(separatedBy: "\n")
                    for (j, line) in partLines.enumerated() {
                        if i == 0 && j == 0 {
                            lines.append(marker + taskPrefix + line)
                        } else {
                            lines.append(line.isEmpty ? "" : pad + line)
                        }
                    }
                    let isNestedList = i + 1 < parts.count && parts[i + 1].range(of: "^\\s*(?:[-*+]|[0-9]+\\.) ", options: .regularExpression) != nil
                    if i + 1 < parts.count && !isNestedList { lines.append("") }
                }
            }
            return lines.joined(separator: "\n")
        }

        private func table(_ element: XMLNode) -> String? {
            var rows: [[String]] = []
            func collect(_ node: XMLNode) {
                for child in node.children ?? [] {
                    switch name(child) {
                    case "tr":
                        let cells = (child.children ?? []).filter { ["td", "th"].contains(name($0)) }.map {
                            inlineContent($0).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")
                        }
                        if !cells.isEmpty { rows.append(cells) }
                    case "thead", "tbody", "tfoot":
                        collect(child)
                    default:
                        break
                    }
                }
            }
            collect(element)
            guard let header = rows.first else { return nil }
            let columns = rows.map { $0.count }.max() ?? header.count
            func line(_ cells: [String]) -> String {
                "| " + (cells + Array(repeating: "", count: max(0, columns - cells.count))).joined(separator: " | ") + " |"
            }
            var out = [line(header), "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |"]
            out += rows.dropFirst().map(line)
            return out.joined(separator: "\n")
        }

        // MARK: Inlines

        private func inlineContent(_ element: XMLNode) -> String {
            inline(element.children ?? [], style: InlineStyle()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func styleAttributes(_ element: XMLElement, _ style: InlineStyle) -> InlineStyle {
            var s = style
            guard let css = element.attribute(forName: "style")?.stringValue?.lowercased().replacingOccurrences(of: " ", with: "") else { return s }
            if css.contains("font-weight:bold") || css.range(of: "font-weight:[6-9]00", options: .regularExpression) != nil { s.bold = true }
            if css.contains("font-weight:normal") || css.contains("font-weight:400") { s.bold = false }
            if css.contains("font-style:italic") { s.italic = true }
            if css.contains("line-through") { s.strike = true }
            return s
        }

        func inline(_ nodes: [XMLNode], style: InlineStyle) -> String {
            var out = ""
            for node in nodes {
                out += inline(node, style: style)
            }
            return out
        }

        private func inline(_ node: XMLNode, style: InlineStyle) -> String {
            if node.kind == .text {
                let raw = node.stringValue ?? ""
                if style.code { return raw }
                return escape(collapseWhitespace(raw))
            }
            guard node.kind == .element, let element = node as? XMLElement else { return "" }
            let tag = name(element)
            if Self.skipped.contains(tag) { return "" }
            if let image = atlassianMedia(element) { return image }
            var s = styleAttributes(element, style)
            switch tag {
            case "br":
                return "\\\n"
            case "img":
                let src = element.attribute(forName: "src")?.stringValue ?? ""
                let alt = element.attribute(forName: "alt")?.stringValue ?? ""
                return src.isEmpty ? "" : "![\(escape(alt))](\(destination(src)))"
            case "a":
                let text = inline(element.children ?? [], style: s).trimmingCharacters(in: .whitespaces)
                guard let href = element.attribute(forName: "href")?.stringValue, !href.isEmpty, !href.hasPrefix("javascript:") else { return text }
                return "[\(text.isEmpty ? href : text)](\(destination(href)))"
            case "code", "kbd", "samp", "tt":
                s.code = true
                let text = inline(element.children ?? [], style: s)
                guard !text.isEmpty else { return "" }
                let longestRun = text.components(separatedBy: CharacterSet(charactersIn: "`").inverted).map { $0.count }.max() ?? 0
                let fence = String(repeating: "`", count: longestRun + 1)
                let pad = longestRun > 0 || text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
                return fence + pad + text + pad + fence
            case "strong", "b":
                // Google Docs wraps whole fragments in <b style="font-weight:normal">
                let explicitNormal = element.attribute(forName: "style")?.stringValue?.contains("normal") ?? false
                if !explicitNormal { s.bold = true }
            case "em", "i", "cite", "var":
                s.italic = true
            case "del", "s", "strike":
                s.strike = true
            default:
                break
            }
            let content = inline(element.children ?? [], style: s)
            return wrap(content, adding: s, over: style)
        }

        /// Wraps `content` in the delimiters for styles turned on at this element, keeping
        /// surrounding whitespace outside the delimiters.
        private func wrap(_ content: String, adding s: InlineStyle, over parent: InlineStyle) -> String {
            var open = "", close = ""
            if s.strike && !parent.strike { open += "~~"; close = "~~" + close }
            if s.bold && !parent.bold { open += "**"; close = "**" + close }
            if s.italic && !parent.italic { open += "*"; close = "*" + close }
            guard !open.isEmpty else { return content }
            let leading = String(content.prefix(while: { $0 == " " }))
            let trailing = String(content.reversed().prefix(while: { $0 == " " }))
            let core = content.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return content }
            return leading + open + core + close + trailing
        }

        private func collapseWhitespace(_ s: String) -> String {
            var out = ""
            var lastWasSpace = false
            for c in s {
                if c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\u{00A0}" {
                    if !lastWasSpace { out.append(" ") }
                    lastWasSpace = true
                } else {
                    out.append(c)
                    lastWasSpace = false
                }
            }
            return out
        }

        /// Escapes characters that would otherwise start Markdown formatting.
        private func escape(_ s: String) -> String {
            var out = ""
            for c in s {
                if "\\*_`[]".contains(c) { out.append("\\") }
                out.append(c)
            }
            return out
        }

        /// Confluence and Jira copy images as empty `data-node-type="media"` placeholders naming the
        /// attachment rather than as <img>: link them to the attachment's download URL on the page's site.
        private func atlassianMedia(_ element: XMLElement) -> String? {
            func attribute(_ key: String) -> String? {
                element.attribute(forName: key)?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
            }
            guard attribute("data-node-type") == "media" else { return nil }
            let alt = attribute("data-alt") ?? attribute("data-file-name") ?? ""
            if attribute("data-type") == "external", let url = attribute("data-url") {
                return "![\(escape(alt))](\(destination(url)))"
            }
            guard let fileName = attribute("data-file-name") ?? attribute("data-alt"),
                  let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { return nil }
            let pageID = attribute("data-context-id")
                ?? attribute("data-collection").flatMap { $0.hasPrefix("contentId-") ? String($0.dropFirst("contentId-".count)) : nil }
            // Without the site or page, keep the file name so a downloaded copy beside the document resolves
            guard let pageID = pageID, let source = sourceURL, let scheme = source.scheme, let host = source.host else {
                return "![\(escape(alt))](\(encodedName))"
            }
            let port = source.port.map { ":\($0)" } ?? ""
            let context = source.path.hasPrefix("/wiki/") ? "/wiki" : ""
            return "![\(escape(alt))](\(scheme)://\(host)\(port)\(context)/download/attachments/\(pageID)/\(encodedName))"
        }

        private func destination(_ url: String) -> String {
            url.contains(" ") || url.contains("(") || url.contains(")") ? "<\(url)>" : url
        }
    }
}
