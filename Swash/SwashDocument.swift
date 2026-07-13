//
//  SwashDocument.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import UniformTypeIdentifiers

nonisolated struct SwashDocument: FileDocument {
    var text: String

    init(text: String = "Hello, world!") {
        self.text = text
    }

    static let readableContentTypes = [
        UTType(importedAs: "net.daringfireball.markdown"),
        UTType.plainText
    ]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8)!
        return .init(regularFileWithContents: data)
    }
}
