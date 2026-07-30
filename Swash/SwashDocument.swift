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

    init(text: String = "Hello, world!", flavor: MarkdownFlavor? = nil) {
        self.text = text
        self.flavor = flavor ?? MarkdownParser.detectFlavor(text)
    }

    static let readableContentTypes: [UTType] = [
        .markdown,
        .plainText,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "markdown") ?? .plainText,
        UTType(filenameExtension: "mdown") ?? .plainText,
        UTType(filenameExtension: "mkdn") ?? .plainText
    ]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
        flavor = MarkdownParser.detectFlavor(string)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
