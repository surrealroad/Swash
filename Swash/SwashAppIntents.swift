//
//  SwashAppIntents.swift
//  Swash
//

import AppIntents
import AppKit

enum MarkdownWrapperStyle: String, AppEnum {
    case codeBlock = "Code Block"
    case quoteBlock = "Quote Block"
    case header = "Header"
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Markdown Style"
    static var caseDisplayRepresentations: [MarkdownWrapperStyle: DisplayRepresentation] = [
        .codeBlock: "Code Block",
        .quoteBlock: "Quote Block",
        .header: "Header"
    ]
}

struct CreateDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Markdown Document"
    static var description = IntentDescription("Creates a new Markdown document in Swash.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Title", default: "Untitled Note")
    var title: String

    @Parameter(title: "Content")
    var content: String

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(title).md".replacingOccurrences(of: "/", with: "-")
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }
        
        return .result()
    }
}

struct GetWordCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Word & Character Count"
    static var description = IntentDescription("Calculates word, character, and line count for input Markdown text.")

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        let chars = text.count
        let lines = text.components(separatedBy: .newlines).count
        
        let summary = "\(words) words, \(chars) characters, \(lines) lines"
        return .result(value: summary)
    }
}

struct ConvertTextToMarkdownIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Text to Markdown Format"
    static var description = IntentDescription("Formats plain text as a Markdown code block, quote, or header.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Style", default: .codeBlock)
    var style: MarkdownWrapperStyle

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let formatted: String
        switch style {
        case .codeBlock:
            formatted = "```\n\(text)\n```"
        case .quoteBlock:
            formatted = text.components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
        case .header:
            formatted = "# \(text)"
        }
        return .result(value: formatted)
    }
}

struct SwashShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateDocumentIntent(),
            phrases: [
                "Create a new document in \(.applicationName)",
                "New \(.applicationName) note"
            ],
            shortTitle: "Create Document",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: GetWordCountIntent(),
            phrases: [
                "Count words with \(.applicationName)",
                "Get word count in \(.applicationName)"
            ],
            shortTitle: "Word Count",
            systemImageName: "text.word.spacing"
        )
    }
}
