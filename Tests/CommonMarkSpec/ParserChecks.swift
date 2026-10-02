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

    /// (markdown, selected substring or "|" caret marker, operation, expected markdown)
    private static let formattingCases: [(String, String, String, String)] = [
        ("Plain beta gamma.", "beta", "bold", "Plain **beta** gamma."),
        ("Plain **beta** gamma.", "beta", "bold", "Plain beta gamma."),
        ("Plain **be|ta** gamma.", "|", "bold", "Plain beta gamma."),
        ("an _emph_ word", "emph", "italic", "an emph word"),
        ("**bold text** plain", "text** pl", "bold", "**bold text pl**ain"),
        ("*italic with **bold** inside*", "bold", "bold", "*italic with bold inside*"),
        ("*italic*", "italic", "bold", "***italic***"),
        ("double click word then", "word ", "bold", "double click **word** then"),
        ("line one\nline two", "one\nline", "bold", "line **one**\n**line** two"),
        ("> first line\n> second line", "line\n> second", "bold", "> first **line**\n> **second** line"),
        ("- item one\n- item two", "one\n- item", "italic", "- item *one*\n- *item* two"),
        ("see [docs](https://a.com) here", "e [do", "bold", "se**e [docs](https://a.com)** here"),
        ("remove this text", "this", "strike", "remove ~~this~~ text"),
        ("call foo() now", "foo()", "code", "call `foo()` now"),
        ("a `b` c", "a `b` c", "code", "`a b c`"),
        ("use `x` here", "x", "code", "use x here"),
        ("tick ` inside", "tick ` inside", "code", "`` tick ` inside ``"),
        ("👋 beta", "beta", "bold", "👋 **beta**"),
        ("see docs here", "docs", "link:https://x.com", "see [docs](https://x.com) here"),
        ("see [do|cs](https://a.com) here", "|", "link:https://b.com", "see [docs](https://b.com) here"),
        ("see [**docs**](https://a.com) here", "docs", "unlink", "see **docs** here"),
        ("[full][ref]\n\n[ref]: /u", "full", "unlink", "full\n\n[ref]: /u"),
        ("go <https://a.c|om> now", "|", "unlink", "go https://a.com now"),
        ("![i](x.png) add link here", "link", "link:https://c.com", "![i](x.png) add [link](https://c.com) here"),
        ("> quoted line", "quoted", "bullet", "> - quoted line"),
        ("- a\n- b", "a\n- b", "numbered", "1. a\n2. b"),
        ("- [ ] task item", "task", "bullet", "- task item"),
        ("## Heading", "Heading", "quote", "> ## Heading"),
        ("> ## Heading", "Heading", "quote", "## Heading"),
        ("> > nested", "nested", "quote", "> nested"),
        ("## Heading", "Heading", "h4", "#### Heading"),
        ("## Heading", "Heading", "paragraph", "Heading"),
        ("- list item", "item", "h1", "# list item"),
        ("text\n```\ncode\n```", "text\n```\ncode", "bullet", "- text\n```\ncode\n```"),
    ]
    
    /// (markdown with | caret, key, expected markdown with | caret, or "default" for no edit)
    private static let editingCases: [(String, String, String)] = [
        ("- first|", "enter", "- first\n- |"),
        ("* star|", "enter", "* star\n* |"),
        ("1. first|", "enter", "1. first\n2. |"),
        ("1. a|\n2. b\n3. c", "enter", "1. a\n2. |\n3. b\n4. c"),
        ("3) three|", "enter", "3) three\n4) |"),
        ("- [x] done|", "enter", "- [x] done\n- [ ] |"),
        ("- spl|it", "enter", "- spl\n- |it"),
        ("> quote|", "enter", "> quote\n> |"),
        ("> - in quote|", "enter", "> - in quote\n> - |"),
        ("- a\n- |", "enter", "- a\n|"),
        ("- a\n  - |", "enter", "- a\n- |"),
        ("> a\n> |", "enter", "> a\n|"),
        ("plain|", "enter", "default"),
        ("## Heading|", "enter", "default"),
        ("```\n- not a list|\n```", "enter", "default"),
        ("- a\n- b|", "tab", "- a\n  - b|"),
        ("1. a\n2. b|", "tab", "1. a\n   2. b|"),
        ("- a\n  - b\n- c|", "tab", "- a\n  - b\n  - c|"),
        ("- only|", "tab", "default"),
        ("- a\n  - b|", "shift-tab", "- a\n- b|"),
        ("- a\n  - b\n    - c|", "shift-tab", "- a\n  - b\n  - c|"),
        ("- |item", "backspace", "|item"),
        ("## |Title", "backspace", "|Title"),
        ("- [ ] |todo", "backspace", "|todo"),
        ("  - |nested", "backspace", "  |nested"),
        ("> |quoted", "backspace", "|quoted"),
        ("> > |deep", "backspace", "> |deep"),
        ("- it|em", "backspace", "default"),
        ("plain |text", "backspace", "default"),
    ]
    
    private static func runEditing() -> Int {
        var failures = 0
        for (input, key, expected) in editingCases {
            let caret = (input as NSString).range(of: "|")
            let text = (input as NSString).replacingCharacters(in: caret, with: "")
            let selection = NSRange(location: caret.location, length: 0)
            let edit: MarkdownEdit?
            switch key {
            case "enter": edit = MarkdownEditingCommands.newline(text: text, selection: selection)
            case "tab": edit = MarkdownEditingCommands.indent(text: text, selection: selection)
            case "shift-tab": edit = MarkdownEditingCommands.outdent(text: text, selection: selection)
            default: edit = MarkdownEditingCommands.backspace(text: text, selection: selection)
            }
            let actual = edit.map { ($0.text as NSString).replacingCharacters(in: NSRange(location: $0.selection.location, length: 0), with: "|") } ?? "default"
            if actual != expected {
                failures += 1
                print("❌ editing \(key) on \(input.debugDescription): expected \(expected.debugDescription), got \(actual.debugDescription)")
            }
        }
        print("Editing command checks: \(failures == 0 ? "all passed" : "\(failures) failed") (\(editingCases.count) cases)")
        return failures
    }
    
    private static let htmlCases: [(String, String)] = [
        ("<b>Bold</b> and <a href=\"https://x.com\">link</a>", "**Bold** and [link](https://x.com)"),
        ("<h2>Title</h2><p>Para <em>it</em></p>", "## Title\n\nPara *it*"),
        ("<ul><li>a</li><li>b<ul><li>c</li></ul></li></ul>", "- a\n- b\n  - c"),
        ("<ol><li>one</li><li>two</li></ol>", "1. one\n2. two"),
        ("<ol start=\"3\"><li>three</li></ol>", "3. three"),
        ("<blockquote><p>q</p></blockquote>", "> q"),
        ("<pre><code class=\"language-swift\">let x = 1\n</code></pre>", "```swift\nlet x = 1\n```"),
        ("<p>a<br>b</p>", "a\\\nb"),
        ("<b style=\"font-weight:normal;\" id=\"docs-internal-guid-1\"><span style=\"font-weight:700\">Bold</span><span style=\"font-style:italic\"> it</span></b>", "**Bold** *it*"),
        ("<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>", "| A | B |\n| --- | --- |\n| 1 | 2 |"),
        ("<p>5 * 3 = 15_x</p>", "5 \\* 3 = 15\\_x"),
        ("<img src=\"a.png\" alt=\"pic\">", "![pic](a.png)"),
        ("<p>use <code>a*b</code> here</p>", "use `a*b` here"),
        ("<del>x</del>", "~~x~~"),
        ("<p><b>bold </b>next</p>", "**bold** next"),
        ("<em>a <strong>b</strong> c</em>", "*a **b** c*"),
        ("<ul><li><input type=\"checkbox\" checked> done</li><li><input type=\"checkbox\"> todo</li></ul>", "- [x] done\n- [ ] todo"),
        ("<p>one</p><hr><p>two</p>", "one\n\n---\n\ntwo"),
        ("<meta charset=\"utf-8\"><span>just text</span>", "just text"),
        ("<p>   spaced    out   </p>", "spaced out"),
    ]
    
    private static func runHTML() -> Int {
        var failures = 0
        for (html, expected) in htmlCases {
            let actual = HTMLToMarkdown.convert(html) ?? "nil"
            if actual != expected {
                failures += 1
                print("❌ html \(html.debugDescription): expected \(expected.debugDescription), got \(actual.debugDescription)")
            }
        }
        print("HTML paste conversion checks: \(failures == 0 ? "all passed" : "\(failures) failed") (\(htmlCases.count) cases)")
        return failures
    }
    
    private static func runFormatting() -> Int {
        var failures = 0
        for (markdown, select, operation, expected) in formattingCases {
            if ProcessInfo.processInfo.environment["SWASH_TRACE"] != nil { print("case \(operation) \(markdown.debugDescription)"); fflush(stdout) }
            var text = markdown
            var selection: NSRange
            if select == "|" {
                let caret = (text as NSString).range(of: "|")
                text = (text as NSString).replacingCharacters(in: caret, with: "")
                selection = NSRange(location: caret.location, length: 0)
            } else {
                selection = (text as NSString).range(of: select)
            }
            let f = MarkdownFormatting(text: text)
            let edit: MarkdownEdit?
            switch operation {
            case "bold": edit = f.toggle(.strong, selection: selection)
            case "italic": edit = f.toggle(.emphasis, selection: selection)
            case "strike": edit = f.toggle(.strikethrough, selection: selection)
            case "code": edit = f.toggle(.code, selection: selection)
            case "unlink": edit = f.removeLink(selection: selection)
            case "bullet": edit = f.toggleBlock(.bulletList, selection: selection)
            case "numbered": edit = f.toggleBlock(.numberedList, selection: selection)
            case "quote": edit = f.toggleBlock(.quote, selection: selection)
            case "paragraph": edit = f.toggleBlock(.paragraph, selection: selection)
            case "h1": edit = f.toggleBlock(.heading(1), selection: selection)
            case "h4": edit = f.toggleBlock(.heading(4), selection: selection)
            default:
                edit = operation.hasPrefix("link:") ? f.setLink(String(operation.dropFirst(5)), selection: selection) : nil
            }
            let result = edit?.text ?? text
            if result != expected {
                failures += 1
                print("❌ format \(operation) on \(markdown.debugDescription) [\(select.debugDescription)]: expected \(expected.debugDescription), got \(result.debugDescription)")
            } else if let edit = edit, NSMaxRange(edit.selection) > (edit.text as NSString).length {
                failures += 1
                print("❌ format \(operation) on \(markdown.debugDescription): selection \(edit.selection) out of bounds")
            }
        }
        print("Formatting engine checks: \(failures == 0 ? "all passed" : "\(failures) failed") (\(formattingCases.count) cases)")
        return failures
    }
    
    static func run() -> Int {
        var failures = runFormatting() + runEditing() + runHTML()
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
