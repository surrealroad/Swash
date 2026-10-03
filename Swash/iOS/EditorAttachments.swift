//
//  EditorAttachments.swift
//  Swash
//
//  Image and table attachments for the iOS Edit Text editor (the macOS ones are in
//  SwashTextView.swift and InteractiveTableView.swift). A table attachment reserves space in the
//  text; StyledUITextView places the interactive SwiftUI table over that space.
//

#if os(iOS)
import SwiftUI
import UIKit

final class ImageTextAttachment: NSTextAttachment, RawMarkdownAttachment {
    static let fileTypeIdentifier = "com.surrealroad.swash.image"
    let alt: String
    let urlString: String
    let rawMarkdown: String

    init(image: UIImage, alt: String, urlString: String, rawMarkdown: String) {
        self.alt = alt
        self.urlString = urlString
        self.rawMarkdown = rawMarkdown
        super.init(data: nil, ofType: Self.fileTypeIdentifier)
        self.image = image
        self.bounds = CGRect(origin: .zero, size: image.size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class TableTextAttachment: NSTextAttachment, RawMarkdownAttachment {
    static let fileTypeIdentifier = "com.surrealroad.swash.table"

    var tableData: MarkdownTableData
    let flavor: MarkdownFlavor
    var onUpdate: ((MarkdownTableData) -> Void)?
    /// The exact source the table was parsed from, written back verbatim while the table is unedited.
    let originalMarkdown: String?
    private let originalTableData: MarkdownTableData
    /// The hosted table, created when the text view first lays the attachment out.
    var host: UIHostingController<InteractiveTableView>?
    /// Height of the hosted table at the last measured width; an estimate until then.
    var measuredHeight: CGFloat?

    var rawMarkdown: String {
        if let original = originalMarkdown, tableData == originalTableData {
            return original
        }
        return MarkdownParser.tableToMarkdown(headers: tableData.headers, alignments: tableData.alignments, rows: tableData.rows)
    }

    init(tableData: MarkdownTableData, flavor: MarkdownFlavor, originalMarkdown: String? = nil, onUpdate: ((MarkdownTableData) -> Void)?) {
        self.tableData = tableData
        self.flavor = flavor
        self.onUpdate = onUpdate
        self.originalMarkdown = originalMarkdown
        self.originalTableData = tableData
        super.init(data: nil, ofType: Self.fileTypeIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    nonisolated override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        MainActor.assumeIsolated {
            let width = lineFrag.width > 0 ? max(120, lineFrag.width - position.x) : 500
            let height = measuredHeight ?? CGFloat(max(100, (tableData.rows.count + 1) * 40 + 60))
            return CGRect(x: 0, y: 0, width: width, height: height)
        }
    }

    /// The table view draws itself; the attachment glyph stays blank.
    nonisolated override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> UIImage? {
        UIImage()
    }
}
#endif
