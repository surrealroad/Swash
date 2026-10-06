//
//  EditorClipboard.swift
//  Swash
//
//  Copy and paste for the iOS Edit Text editor, matching the macOS SwashNSTextView: copies carry
//  rich text (RTF and HTML) for other apps, plus the raw Markdown for Swash and plain-text apps;
//  pasted HTML or RTF is converted to Markdown.
//

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

enum EditorClipboard {
    /// Raw Markdown written by Swash's own copy, so copy and paste between Swash documents is lossless.
    static let swashMarkdownType = "com.surrealroad.swash.markdown"

    /// Markdown to insert for the pasteboard's contents, or nil to paste its plain text as usual.
    static func markdownForPaste(from pasteboard: UIPasteboard) -> String? {
        if let data = pasteboard.data(forPasteboardType: swashMarkdownType), let own = String(data: data, encoding: .utf8) { return own }
        let plain = pasteboard.string
        var html = pasteboard.data(forPasteboardType: UTType.html.identifier).flatMap { String(data: $0, encoding: .utf8) }
        if html == nil, let rtf = pasteboard.data(forPasteboardType: UTType.rtf.identifier),
           let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           let data = try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
            html = String(data: data, encoding: .utf8)
        }
        guard let source = html else { return nil }
        // Code editors put pre-formatted HTML on the pasteboard: keep their plain text (indentation intact)
        if plain != nil, source.range(of: "white-space:\\s*pre", options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let sourceURL = pasteboard.data(forPasteboardType: HTMLToMarkdown.chromiumSourceURLType).flatMap { String(data: $0, encoding: .utf8) }.flatMap(URL.init(string:))
        guard let markdown = HTMLToMarkdown.convert(source, sourceURL: sourceURL) else { return nil }
        // No formatting gained over the plain text: paste it as-is rather than backslash-escaped
        if let plain = plain {
            let unescaped = markdown.replacingOccurrences(of: "\\\\([\\\\*_`\\[\\]])", with: "$1", options: .regularExpression)
            func normalized(_ s: String) -> String { s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            if normalized(unescaped) == normalized(plain) { return nil }
        }
        return markdown
    }

    /// Puts the selection on the pasteboard as rich text plus its raw Markdown.
    static func copy(_ range: NSRange, from storage: NSTextStorage, to pasteboard: UIPasteboard = .general) {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        let raw = swashRawMarkdown(from: storage.attributedSubstring(from: range))
        var item: [String: Any] = [
            swashMarkdownType: Data(raw.utf8),
            UTType.utf8PlainText.identifier: raw,
        ]
        let formatted = cleanFormattedString(from: storage.attributedSubstring(from: range))
        let whole = NSRange(location: 0, length: formatted.length)
        if whole.length > 0 {
            if let rtf = try? formatted.data(from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                item[UTType.rtf.identifier] = rtf
            }
            if let html = try? formatted.data(from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]) {
                item[UTType.html.identifier] = html
            }
        }
        pasteboard.setItems([item])
    }

    /// The styled text without hidden markers or Swash-only attributes: list markers become text,
    /// tables become tab-separated text, and boxed blocks get a light background.
    private static func cleanFormattedString(from styled: NSAttributedString) -> NSAttributedString {
        let allowed: Set<NSAttributedString.Key> = [.font, .foregroundColor, .backgroundColor, .underlineStyle, .underlineColor,
                                                     .strikethroughStyle, .strikethroughColor, .link, .paragraphStyle, .attachment]
        let result = NSMutableAttributedString()
        styled.enumerateAttributes(in: NSRange(location: 0, length: styled.length), options: []) { attributes, range, _ in
            let hidden = (attributes[.font] as? UIFont).map { $0.pointSize < 1 } == true || (attributes[.foregroundColor] as? UIColor) == .clear
            if hidden {
                if let marker = attributes[.listMarker] as? ListMarkerInfo {
                    result.append(NSAttributedString(string: marker.text + " ", attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .bold)]))
                }
                return
            }
            if let table = attributes[.attachment] as? TableTextAttachment {
                let rows = [table.tableData.headers] + table.tableData.rows
                let text = rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\t") }.joined(separator: "\n")
                result.append(NSAttributedString(string: text, attributes: [.font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)]))
                return
            }
            let chunk = NSMutableAttributedString(attributedString: styled.attributedSubstring(from: range))
            let whole = NSRange(location: 0, length: chunk.length)
            for key in attributes.keys where !allowed.contains(key) { chunk.removeAttribute(key, range: whole) }
            // Default text colours are dropped so the text adapts to the target app
            if let color = attributes[.foregroundColor] as? UIColor, color == .label { chunk.removeAttribute(.foregroundColor, range: whole) }
            if attributes[.blockDecorations] != nil, attributes[.backgroundColor] == nil {
                chunk.addAttribute(.backgroundColor, value: UIColor.label.withAlphaComponent(0.04), range: whole)
            }
            result.append(chunk)
        }
        return result
    }
}
#endif
