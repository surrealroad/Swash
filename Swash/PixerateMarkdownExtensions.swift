//
//  PixerateMarkdownExtensions.swift
//  Swash
//
//  What Swash adds on top of the PixerateMarkdown engine, until it moves into the package
//  (GOTCHAS #63): Confluence and Jira image pastes, link lookups and link URLs.
//

import Foundation
import PixerateMarkdown

extension HTMLToMarkdown {
    /// Pasteboard type where Chromium browsers record the page the HTML was copied from.
    static let chromiumSourceURLType = "org.chromium.source-url"

    /// `sourceURL` is the page it was copied from, used to link images that carry no URL of their own.
    static func convert(_ html: String, sourceURL: URL?) -> String? {
        convert(AtlassianMedia.addingImages(to: html, sourceURL: sourceURL))
    }
}

/// Confluence and Jira copy images as empty `data-node-type="media"` placeholders naming the
/// attachment rather than as <img> (GOTCHAS #58). Each placeholder gets an <img> linking to the
/// attachment's download URL on the page's site, which the converter then turns into an image.
enum AtlassianMedia {
    private static let openTag = try! NSRegularExpression(pattern: "<[A-Za-z][A-Za-z0-9-]*\\b[^>]*\\bdata-node-type\\s*=\\s*(?:\"media\"|'media')[^>]*>")
    private static let attributePattern = try! NSRegularExpression(pattern: "([A-Za-z_:][A-Za-z0-9_:.-]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")

    static func addingImages(to html: String, sourceURL: URL?) -> String {
        let ns = html as NSString
        var result = ""
        var last = 0
        for match in openTag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            result += ns.substring(with: NSRange(location: last, length: NSMaxRange(match.range) - last))
            if let image = image(for: attributes(of: tag), sourceURL: sourceURL) {
                result += "<img src=\"\(escapeAttribute(image.src))\" alt=\"\(escapeAttribute(image.alt))\">"
            }
            last = NSMaxRange(match.range)
        }
        return result + ns.substring(from: last)
    }

    private static func image(for attributes: [String: String], sourceURL: URL?) -> (src: String, alt: String)? {
        func attribute(_ key: String) -> String? {
            attributes[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        let alt = attribute("data-alt") ?? attribute("data-file-name") ?? ""
        if attribute("data-type") == "external", let url = attribute("data-url") {
            return (url, alt)
        }
        guard let fileName = attribute("data-file-name") ?? attribute("data-alt"),
              let encodedName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { return nil }
        let pageID = attribute("data-context-id")
            ?? attribute("data-collection").flatMap { $0.hasPrefix("contentId-") ? String($0.dropFirst("contentId-".count)) : nil }
        // Without the site or page, keep the file name so a downloaded copy beside the document resolves
        guard let pageID = pageID, let source = sourceURL, let scheme = source.scheme, let host = source.host else {
            return (encodedName, alt)
        }
        let port = source.port.map { ":\($0)" } ?? ""
        let context = source.path.hasPrefix("/wiki/") ? "/wiki" : ""
        return ("\(scheme)://\(host)\(port)\(context)/download/attachments/\(pageID)/\(encodedName)", alt)
    }

    private static func attributes(of tag: String) -> [String: String] {
        let ns = tag as NSString
        var attributes: [String: String] = [:]
        for match in attributePattern.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let valueRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            attributes[name] = decodeEntities(ns.substring(with: valueRange))
        }
        return attributes
    }

    private static let entity = try! NSRegularExpression(pattern: "&#?[A-Za-z0-9]+;")

    /// Attribute values decode character references only; backslashes are literal in HTML.
    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let ns = s as NSString
        var out = ""
        var last = 0
        for match in entity.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let reference = ns.substring(with: match.range)
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            out += MarkdownSyntax.decodeEntity(reference) ?? reference
            last = NSMaxRange(match.range)
        }
        return out + ns.substring(from: last)
    }

    private static func escapeAttribute(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

extension FormatCommandEdits {
    /// The destination of the link at `selection`, if there is one.
    static func activeLink(text: String, selection: NSRange) -> String? {
        let formatting = MarkdownFormatting(text: text)
        guard let node = formatting.link(at: selection), case .link(let destination, _, _) = node.kind else { return nil }
        return destination
    }
}

extension MarkdownSyntax {
    /// A link destination as a URL, normalising characters that `URL(string:)` rejects.
    static func url(_ destination: String) -> URL? {
        URL(string: destination) ?? URL(string: normalizeURI(destination))
    }
}
