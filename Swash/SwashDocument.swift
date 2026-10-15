//
//  SwashDocument.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType("net.daringfireball.markdown") ?? UTType(importedAs: "net.daringfireball.markdown")
}

struct SwashDocument: FileDocument {
    var text: String
    var flavor: MarkdownFlavor

    init(text: String = "", flavor: MarkdownFlavor? = nil) {
        self.text = text
        self.flavor = flavor ?? MarkdownParser.detectFlavor(text)
    }

    static let readableContentTypes: [UTType] = [
        .markdown,
        .plainText,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        UTType(filenameExtension: "mdown") ?? .plainText,
        UTType(filenameExtension: "mkdn") ?? .plainText,
        UTType(filenameExtension: "mkd") ?? .plainText,
        UTType(filenameExtension: "mdwn") ?? .plainText,
        UTType(filenameExtension: "mdtext") ?? .plainText,
        UTType(filenameExtension: "mdtxt") ?? .plainText,
        UTType(filenameExtension: "rmd") ?? .plainText
    ]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let string = SwashDocument.decode(data) else {
            throw CocoaError(.fileReadUnknownStringEncoding)
        }
        text = string
        flavor = MarkdownParser.detectFlavor(string)
    }
    
    /// UTF-8, else UTF-16 with a byte-order mark, else whatever legacy encoding Foundation detects
    /// (Windows Latin 1 and Mac Roman are the usual ones). Saving always writes UTF-8.
    static func decode(_ data: Data) -> String? {
        if let string = String(data: data, encoding: .utf8) { return string }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        var converted: NSString?
        let suggestions = [String.Encoding.windowsCP1252, .macOSRoman, .isoLatin1].map { NSNumber(value: $0.rawValue) }
        let encoding = NSString.stringEncoding(for: data,
                                               encodingOptions: [.suggestedEncodingsKey: suggestions, .allowLossyKey: false],
                                               convertedString: &converted,
                                               usedLossyConversion: nil)
        return encoding != 0 ? converted as String? : nil
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
