//
//  ParserChecks.swift
//  Swash
//
//  Checks beyond HTML conformance that the WYSIWYG editor depends on: exact syntax-marker
//  ranges, Swash extensions (alerts, front matter, ordered task items), robustness under
//  random input, and linear-time behaviour on pathological input.
//

import Foundation

enum ParserChecks {
    /// (markdown, node description, expected marker substrings in order)
    private static let markerCases: [(String, String, [String])] = [
        ("**bold**", "strong", ["**", "**"]),
        ("*it* and _it_", "emphasis", ["*", "*"]),
        ("***both***", "emphasis", ["*", "*"]),
        ("***both***", "strong", ["**", "**"]),
        ("~~gone~~", "strikethrough", ["~~", "~~"]),
        ("`code`", "code", ["`", "`"]),
        ("`` a `b` c ``", "code", ["`` ", " ``"]),
        ("## Title ##", "heading", ["## ", " ##"]),
        ("Title\n===", "heading", ["==="]),
        ("> quote\n> more", "blockQuote", ["> ", "> "]),
        ("- item", "listItem", ["- "]),
        ("10) item", "listItem", ["10) "]),
        ("- [x] done", "listItem", ["- ", "[x] "]),
        ("1. [ ] ordered task", "listItem", ["1. ", "[ ] "]),
        ("[text](https://a.com \"T\")", "link", ["[", "](https://a.com \"T\")"]),
        ("[text][ref]\n\n[ref]: /u", "link", ["[", "][ref]"]),
        ("[ref]\n\n[ref]: /u", "link", ["[", "]"]),
        ("![alt](img.png)", "image", ["![", "](img.png)"]),
        ("[![badge](b.svg)](https://ci)", "link", ["[", "](https://ci)"]),
        ("[![badge](b.svg)](https://ci)", "image", ["![", "](b.svg)"]),
        ("<https://angle.com>", "link", ["<", ">"]),
        ("a\\*b", "text", ["\\"]),
        ("line  \nnext", "hardBreak", ["  \n"]),
        ("line\\\nnext", "hardBreak", ["\\"]),
        ("```swift\nlet x\n```", "codeBlock", ["```swift", "```"]),
        ("---", "thematicBreak", ["---"]),
        ("> [!NOTE]\n> body", "alert", ["> ", "> ", "[!NOTE]"]),
        ("Text[^1]\n\n[^1]: Note", "footnoteReference", ["[^1]"]),
        ("[^1]: Note", "footnoteDefinition", ["[^1]: "]),
        ("<kbd>B</kbd>", "htmlInline", ["<kbd>"]),
        ("| a | b |\n|---|---|\n| 1 | 2 |", "table", ["|---|---|"]),
        ("| a | b |\n|---|---|\n| 1 | 2 |", "tableRow", ["|", "|", "|"]),
        ("---\ntitle: Doc\n---\n# Body", "frontMatter", ["---", "---"]),
    ]

    static func run() -> Int {
        var failures = 0
        // 1. Marker ranges
        for (markdown, nodeName, expected) in markerCases {
            let document = MarkdownDocument.parse(markdown)
            let ns = markdown as NSString
            var found: [String]? = nil
            document.root.walk { node in
                guard found == nil else { return }
                let name = "\(node.kind)".components(separatedBy: "(").first ?? ""
                if name == nodeName && !node.markers.isEmpty {
                    found = node.markers.map { ns.substring(with: $0) }
                }
            }
            if found != expected {
                failures += 1
                print("❌ markers \(markdown.debugDescription) \(nodeName): expected \(expected), got \(found ?? [])")
            }
        }
        // Swash extensions
        let extensionCases: [(String, String)] = [
            ("> [!WARNING]\n> Careful **now**.", "alert(Swash.AlertType.warning)|alert(main.AlertType.warning)"),
            ("---\ntitle: Doc\ntags: [a]\n---\n\n# Body", "frontMatter"),
            ("---\n\n# Not front matter\n\n---", "thematicBreak"),
            ("1. [x] ordered task", "listItem(task: Optional(Swash.TaskState.checked))|listItem(task: Optional(main.TaskState.checked))"),
        ]
        for (markdown, expectedKind) in extensionCases {
            let document = MarkdownDocument.parse(markdown)
            let first = document.root.firstChild.map { "\($0.kind)" } ?? "nil"
            let firstDeep = document.root.firstChild?.firstChild.map { "\($0.kind)" } ?? "nil"
            if !expectedKind.split(separator: "|").contains(where: { first.hasPrefix($0) || firstDeep.hasPrefix($0) }) {
                failures += 1
                print("❌ extension \(markdown.debugDescription): expected \(expectedKind), got \(first) / \(firstDeep)")
            }
        }
        print("Marker and extension checks: \(failures == 0 ? "all passed" : "\(failures) failed") (\(markerCases.count + extensionCases.count) cases)")

        // 2. Fuzzing: random markdown-ish input must parse with valid, nested ranges
        var generator = SplitMix64(seed: 0x5157A5)
        let alphabet = Array("ab *_~`#>-+=|:[]()!<>&;\\\n\n  \t1.)x^\"'/@w.")
        var fuzzFailures = 0
        for _ in 0..<3000 {
            let length = Int(generator.next() % 120)
            var text = ""
            for _ in 0..<length { text.append(alphabet[Int(generator.next() % UInt64(alphabet.count))]) }
            let document = MarkdownDocument.parse(text)
            if let problem = SpecRunner.structureProblem(document) {
                fuzzFailures += 1
                if fuzzFailures <= 5 { print("❌ fuzz \(text.debugDescription): \(problem)") }
            }
        }
        print("Fuzz (3000 random inputs): \(fuzzFailures == 0 ? "no problems" : "\(fuzzFailures) problems")")
        failures += fuzzFailures

        // 3. Pathological inputs must stay fast (CommonMark pathological test patterns)
        let pathological: [(String, String)] = [
            ("nested brackets", String(repeating: "[", count: 5000) + "a" + String(repeating: "]", count: 5000)),
            ("unclosed brackets", String(repeating: "[a", count: 5000)),
            ("emphasis openers", String(repeating: "*a ", count: 5000)),
            ("mismatched emphasis", String(repeating: "*a **a ", count: 3000)),
            ("nested quotes", String(repeating: ">", count: 2000) + " a"),
            ("backticks", String(repeating: "`a``", count: 3000)),
            ("link openers", String(repeating: "[a](", count: 3000)),
            ("underscores", String(repeating: "_a ", count: 5000)),
            ("long document", String(repeating: "## Head *x*\n\nPara **b** [l](u) `c`\n\n- item\n\n", count: 1000)),
        ]
        for (name, input) in pathological {
            let start = Date()
            _ = MarkdownDocument.parse(input)
            let ms = Date().timeIntervalSince(start) * 1000
            let ok = ms < 2000
            if !ok { failures += 1 }
            print(String(format: "  %@ %-20@ %7.1f ms", ok ? "✓" : "❌", name as NSString, ms))
        }
        return failures
    }
}

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
