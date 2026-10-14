//
//  EditorSupport.swift
//  Swash
//
//  Pieces shared by the macOS (NSTextView) and iOS (UITextView) Edit Text editors: list marker
//  attributes, the attachment protocol and the map between text-storage and raw-Markdown offsets.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    static let listMarker = NSAttributedString.Key("SwashListMarkerKey")
}

extension Notification.Name {
    static let cellSelectionDidChange = Notification.Name("cellSelectionDidChange")
    static let removeCurrentTable = Notification.Name("removeCurrentTable")
}

/// A list bullet, number or task checkbox drawn by the layout manager in place of the hidden marker.
struct ListMarkerInfo {
    let text: String
    let indent: CGFloat
    var color: PlatformColor? = nil
}

/// An attachment that stands in for a span of Markdown source (a table or an image).
protocol RawMarkdownAttachment: AnyObject {
    var rawMarkdown: String { get }
}

/// The markdown source an attachment stands in for, or nil for non-Swash attachments.
func swashRawMarkdown(for attachment: Any?) -> String? {
    (attachment as? RawMarkdownAttachment)?.rawMarkdown
}

/// Maps between text-storage offsets (where each table/image is a single attachment character)
/// and raw-markdown offsets (where it is its full source). All public selection ranges and all
/// edits coming from SwiftUI are expressed in raw-markdown offsets.
struct AttachmentOffsetMap {
    /// Storage location of each attachment and the UTF-16 length of the markdown it replaces, ascending.
    private(set) var spans: [(storage: Int, rawLength: Int)] = []

    static let identity = AttachmentOffsetMap()

    init() {}

    init(storage: NSAttributedString) {
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            if let raw = swashRawMarkdown(for: value) {
                for i in 0..<range.length {
                    spans.append((storage: range.location + i, rawLength: (raw as NSString).length))
                }
            }
        }
    }

    func rawLocation(forStorage location: Int) -> Int {
        var delta = 0
        for span in spans {
            guard span.storage < location else { break }
            delta += span.rawLength - 1
        }
        return location + delta
    }

    func rawRange(forStorage range: NSRange) -> NSRange {
        let start = rawLocation(forStorage: range.location)
        let end = rawLocation(forStorage: range.location + range.length)
        return NSRange(location: start, length: end - start)
    }

    /// A raw location inside an attachment's source snaps to the attachment's start (or end when `roundUp`).
    func storageLocation(forRaw location: Int, roundUp: Bool) -> Int {
        var delta = 0
        for span in spans {
            let rawStart = span.storage + delta
            if location <= rawStart { break }
            if location < rawStart + span.rawLength {
                return roundUp ? span.storage + 1 : span.storage
            }
            delta += span.rawLength - 1
        }
        return location - delta
    }

    func storageRange(forRaw range: NSRange) -> NSRange {
        let start = storageLocation(forRaw: range.location, roundUp: false)
        let end = storageLocation(forRaw: range.location + range.length, roundUp: range.length > 0)
        return NSRange(location: start, length: max(0, end - start))
    }
}

/// Replaces every Swash attachment in `storage` with the Markdown it stands for.
func swashRawMarkdown(from storage: NSAttributedString) -> String {
    let result = NSMutableString(string: storage.string)
    storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length), options: .reverse) { value, range, _ in
        if let markdown = swashRawMarkdown(for: value) {
            result.replaceCharacters(in: range, with: markdown)
        }
    }
    return result as String
}
