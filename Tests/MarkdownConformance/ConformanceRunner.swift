//
//  ConformanceRunner.swift
//  Swash
//
//  Runs the shared Markdown editing corpus from `@pixerate/markdown-conformance` against
//  Swash's editing engine (FormatCommandEdits, MarkdownFormatting, MarkdownEditingCommands).
//  Fixtures address raw Markdown (GOTCHAS #9), so the text and range are used directly.
//
//  `edit.*` commands model the editor's key handling: when a command returns nil, the text view
//  falls back to its default behaviour (Return inserts a newline, Backspace deletes, Tab inserts
//  a tab, Shift-Tab does nothing), so the runner applies that default too. Backspace runs with
//  the markers hidden, as in the Edit Text view the corpus describes.
//
//  Usage: run_conformance_tests.sh [--verbose] [--case ID]
//

import Foundation

struct ConformanceCase {
    let file: String
    let id: String
    let command: String
    let params: [String: Any]
    let input: String
    let expected: String
    let expectedNoop: Bool
    let skipReason: String?
}

/// Cases where Swash intentionally differs from the corpus, pending a `variants.swash` entry
/// upstream (Pixerate/editor). Keep this list short; every entry needs a reason.
/// Swash edits Markdown source: in Edit Text, blank lines are visible lines, so Return adds one
/// line and Backspace removes one line, rather than splitting or joining paragraphs.
let localSkips: [String: String] = [
    "enter-splits-paragraph": "Return in a paragraph inserts one line break (\"Hello \\n‸world\"); Swash doesn't add a blank line or trim the space",
    "enter-at-end-of-heading": "Return after a heading starts the next line (\"## Title\\n‸\"); the line is already a new paragraph, so no blank line is added",
    "backspace-joins-paragraphs": "Backspace at the start of a paragraph removes the blank line before it (\"Hello\\n‸world\"); a second Backspace joins the lines",
]

enum Marker {
    static let caret: unichar = 0x2038      // ‸
    static let rangeStart: unichar = 0x27E6 // ⟦
    static let rangeEnd: unichar = 0x27E7   // ⟧
}

/// Removes the selection markers and returns the text with the selection as a UTF-16 range.
func parseSelection(_ marked: String) -> (text: String, selection: NSRange)? {
    let units = Array(marked.utf16)
    var stripped: [unichar] = []
    var caret: Int?, start: Int?, end: Int?
    for unit in units {
        switch unit {
        case Marker.caret: guard caret == nil else { return nil }; caret = stripped.count
        case Marker.rangeStart: guard start == nil else { return nil }; start = stripped.count
        case Marker.rangeEnd: guard end == nil else { return nil }; end = stripped.count
        default: stripped.append(unit)
        }
    }
    let text = String(utf16CodeUnits: stripped, count: stripped.count)
    switch (caret, start, end) {
    case (let c?, nil, nil): return (text, NSRange(location: c, length: 0))
    case (nil, let s?, let e?) where e >= s: return (text, NSRange(location: s, length: e - s))
    default: return nil
    }
}

/// Puts the selection markers back into `text`.
func marked(_ text: String, selection: NSRange) -> String {
    let ns = text as NSString
    guard selection.location >= 0, NSMaxRange(selection) <= ns.length else { return text + " ⚠️ selection \(selection) out of bounds" }
    if selection.length == 0 {
        return ns.replacingCharacters(in: selection, with: "‸")
    }
    let withEnd = ns.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "⟧") as NSString
    return withEnd.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "⟦")
}

func paramValues(_ params: [String: Any]) -> [String: FormatParamValue] {
    var result: [String: FormatParamValue] = [:]
    for (key, value) in params {
        switch value {
        case is NSNull: result[key] = .null
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): result[key] = .bool(number.boolValue)
        case let number as NSNumber: result[key] = .int(number.intValue)
        case let string as String: result[key] = .string(string)
        default: break
        }
    }
    return result
}

enum Outcome {
    case edit(MarkdownEdit)
    case noEdit
    case unsupported(String)
}

/// The text view's default handling when a key command returns nil.
func fallback(_ command: String, text: String, selection: NSRange) -> MarkdownEdit? {
    let ns = text as NSString
    switch command {
    case "edit.newline":
        return MarkdownEdit(text: ns.replacingCharacters(in: selection, with: "\n"), selection: NSRange(location: selection.location + 1, length: 0))
    case "edit.indent":
        return MarkdownEdit(text: ns.replacingCharacters(in: selection, with: "\t"), selection: NSRange(location: selection.location + 1, length: 0))
    case "edit.backspace":
        if selection.length > 0 {
            return MarkdownEdit(text: ns.replacingCharacters(in: selection, with: ""), selection: NSRange(location: selection.location, length: 0))
        }
        guard selection.location > 0 else { return nil }
        let deleted = ns.rangeOfComposedCharacterSequence(at: selection.location - 1)
        return MarkdownEdit(text: ns.replacingCharacters(in: deleted, with: ""), selection: NSRange(location: deleted.location, length: 0))
    default:
        return nil
    }
}

func run(_ c: ConformanceCase, text: String, selection: NSRange) -> Outcome {
    let params = paramValues(c.params)
    switch c.command {
    case "edit.newline", "edit.indent", "edit.outdent", "edit.backspace":
        let edit: MarkdownEdit?
        switch c.command {
        case "edit.newline": edit = MarkdownEditingCommands.newline(text: text, selection: selection)
        case "edit.indent": edit = MarkdownEditingCommands.indent(text: text, selection: selection)
        case "edit.outdent": edit = MarkdownEditingCommands.outdent(text: text, selection: selection)
        default: edit = MarkdownEditingCommands.backspace(text: text, selection: selection, markersHidden: true)
        }
        if let edit = edit ?? fallback(c.command, text: text, selection: selection) { return .edit(edit) }
        return .noEdit
    case "format.link":
        let url = params["url"]?.stringValue
        return FormatCommandEdits.link(url, text: text, selection: selection).map(Outcome.edit) ?? .noEdit
    case "format.codeBlock" where params["language"] != nil:
        let language = params["language"]?.stringValue
        return FormatCommandEdits.codeBlock(language: language, text: text, selection: selection).map(Outcome.edit) ?? .noEdit
    default:
        guard c.command.hasPrefix("format."), let command = FormatCommand(manifestID: c.command, params: params) else {
            return .unsupported("no Swash command for \(c.command) \(c.params)")
        }
        return FormatCommandEdits.edit(for: command, text: text, selection: selection).map(Outcome.edit) ?? .noEdit
    }
}

func loadCases(from directory: URL) -> [ConformanceCase] {
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        .filter { $0.hasSuffix(".json") }.sorted()
    guard !files.isEmpty else {
        print("❌ No fixtures in \(directory.path). Run `npm ci` first.")
        exit(2)
    }
    var cases: [ConformanceCase] = []
    for file in files {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["cases"] as? [[String: Any]] else {
            print("❌ Could not load \(file)")
            exit(2)
        }
        for item in list {
            guard let id = item["id"] as? String, let command = item["command"] as? String,
                  let input = item["input"] as? String, let expected = item["expected"] as? String else {
                print("❌ \(file): malformed case \(item["id"] ?? "?")")
                exit(2)
            }
            let variants = item["variants"] as? [String: Any]
            let skip = item["skip"] as? [String: Any]
            cases.append(ConformanceCase(
                file: file, id: id, command: command,
                params: item["params"] as? [String: Any] ?? [:],
                input: input,
                expected: variants?["swash"] as? String ?? expected,
                expectedNoop: item["expectedNoop"] as? Bool ?? false,
                skipReason: (skip?["swash"] as? String) ?? localSkips[id].map { "\($0) (local skip)" }
            ))
        }
    }
    return cases
}

@main
struct ConformanceRunner {
    static func main() {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            print("usage: conformance-runner <fixtures dir> [--verbose] [--case ID]")
            exit(2)
        }
        let verbose = args.contains("--verbose")
        let only = args.firstIndex(of: "--case").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let cases = loadCases(from: URL(fileURLWithPath: args[1]))
        for id in localSkips.keys.sorted() where !cases.contains(where: { $0.id == id }) {
            print("⚠️  local skip \(id) matches no case; remove it from localSkips")
        }

        var passed = 0, failed = 0, skipped = 0
        // The code-language menu maps manifest languages onto CodeHighlighter's (GOTCHAS #43).
        for language in FormatManifest.codeLanguages where CodeLanguage(name: language.id) == nil {
            failed += 1
            print("❌ manifest code language \(language.id) has no CodeLanguage; add it to CodeHighlighter")
        }
        var perFile: [String: (pass: Int, total: Int)] = [:]
        for c in cases {
            if let only = only, c.id != only { continue }
            if let reason = c.skipReason {
                skipped += 1
                print("⏭  [\(c.id)] skipped: \(reason)")
                continue
            }
            var stat = perFile[c.file] ?? (0, 0)
            stat.total += 1
            func failure(_ message: String) {
                failed += 1
                print("❌ [\(c.id)] \(c.file) \(c.command)\(c.params.isEmpty ? "" : " \(c.params)")")
                print("   input:    \(c.input.debugDescription)")
                print("   expected: \(c.expected.debugDescription)\(c.expectedNoop ? " (no-op)" : "")")
                print("   actual:   \(message)")
            }
            guard let input = parseSelection(c.input) else { failure("invalid selection markers in input"); perFile[c.file] = stat; continue }
            guard let expected = parseSelection(c.expected) else { failure("invalid selection markers in expected"); perFile[c.file] = stat; continue }
            let ok: Bool
            switch run(c, text: input.text, selection: input.selection) {
            case .unsupported(let reason):
                failure(reason); perFile[c.file] = stat; continue
            case .noEdit:
                ok = c.expectedNoop
                if !ok { failure("no edit") }
            case .edit(let edit):
                let actual = marked(edit.text, selection: edit.selection)
                ok = edit.text == expected.text && edit.selection == expected.selection
                if !ok { failure(actual.debugDescription) }
            }
            if ok {
                passed += 1
                stat.pass += 1
                if verbose || only != nil { print("✅ [\(c.id)]") }
            }
            perFile[c.file] = stat
        }
        print("")
        for file in perFile.keys.sorted() {
            let s = perFile[file]!
            print(String(format: "  %-24@ %3d/%3d", file as NSString, s.pass, s.total))
        }
        print("\nMarkdown conformance (@pixerate/markdown-conformance \(FormatManifest.version)): \(passed) passed, \(failed) failed, \(skipped) skipped")
        exit(failed == 0 ? 0 : 1)
    }
}
