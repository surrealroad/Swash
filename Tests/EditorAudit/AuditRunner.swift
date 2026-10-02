import Foundation
import SwiftUI
import AppKit

// Audit harness: loads markdown into the real SwashTextView (WYSIWYG "Edit Text" mode),
// dumps what the user actually sees (hidden markers removed) plus style runs,
// checks raw round-trip, and snapshots editor vs preview side by side.

final class TextBox { var text: String; init(_ t: String) { text = t } }

struct Probe { let id: String; let md: String }

func findTextView(in v: NSView) -> NSTextView? {
    if let tv = v as? NSTextView { return tv }
    for s in v.subviews { if let f = findTextView(in: s) { return f } }
    return nil
}

func pump(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

func isHidden(_ attrs: [NSAttributedString.Key: Any]) -> Bool {
    if let f = attrs[.font] as? NSFont, f.pointSize < 1 { return true }
    if let c = attrs[.foregroundColor] as? NSColor, c == .clear { return true }
    return false
}

func describe(_ attrs: [NSAttributedString.Key: Any]) -> String {
    var tags: [String] = []
    if let f = attrs[.font] as? NSFont {
        let traits = NSFontManager.shared.traits(of: f)
        if traits.contains(.boldFontMask) { tags.append("B") }
        if traits.contains(.italicFontMask) { tags.append("I") }
        if f.isFixedPitch || f.fontName.lowercased().contains("mono") { tags.append("MONO") }
        if f.pointSize != 14 { tags.append("\(Int(f.pointSize.rounded()))pt") }
    }
    if attrs[.strikethroughStyle] != nil { tags.append("S") }
    if let l = attrs[.link] { tags.append("LINK→\(l)") }
    if attrs[.baselineOffset] != nil { tags.append("SUP") }
    if let p = attrs[.paragraphStyle] as? NSParagraphStyle, !p.textBlocks.isEmpty { tags.append("BLOCK") }
    if let p = attrs[.paragraphStyle] as? NSParagraphStyle, p.headIndent > 0 { tags.append("indent\(Int(p.headIndent))") }
    if let m = attrs[.listMarker] as? ListMarkerInfo { tags.append("marker'\(m.text)'") }
    if let c = attrs[.foregroundColor] as? NSColor, c != NSColor.textColor {
        if c == NSColor.secondaryLabelColor { tags.append("dim") }
        else if c == NSColor.systemPurple { tags.append("purple") }
        else if c == NSColor.systemBlue { tags.append("blue") }
    }
    return tags.joined(separator: ",")
}

func visibleRender(_ storage: NSTextStorage) -> (visible: String, runs: [String]) {
    var visible = ""
    var runs: [String] = []
    storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attrs, range, _ in
        let s = (storage.string as NSString).substring(with: range)
        if let a = attrs[.attachment] {
            let tag = a is TableTextAttachment ? "[TABLE]" : (a is ImageTextAttachment ? "[IMAGE]" : "[ATTACH]")
            visible += tag; runs.append(tag); return
        }
        if isHidden(attrs) {
            if attrs[.listMarker] is ListMarkerInfo { visible += "‹\((attrs[.listMarker] as! ListMarkerInfo).text)›" }
            return
        }
        visible += s
        let d = describe(attrs)
        if !d.isEmpty && !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runs.append("\"\(s.replacingOccurrences(of: "\n", with: "⏎"))\"{\(d)}")
        }
    }
    return (visible, runs)
}

func makeEditor(_ box: TextBox, width: CGFloat = 600, flavor: MarkdownFlavor = .github) -> (NSHostingView<AnyView>, NSTextView?) {
    let binding = Binding<String>(get: { box.text }, set: { box.text = $0 })
    let editor = SwashTextView(text: binding, selectedRange: .constant(nil), selectionRect: .constant(nil),
                               scrollOriginY: .constant(0), isStyled: true, flavor: flavor)
    let host = NSHostingView(rootView: AnyView(editor.frame(width: width, height: 900)))
    host.frame = NSRect(x: 0, y: 0, width: width, height: 900)
    let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    host.layoutSubtreeIfNeeded()
    pump(0.25)
    return (host, findTextView(in: host))
}

func snapshot(_ view: NSView, to url: URL) {
    view.layoutSubtreeIfNeeded()
    pump(0.05)
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

func sideBySide(_ md: String, to url: URL) {
    let box = TextBox(md)
    let binding = Binding<String>(get: { box.text }, set: { box.text = $0 })
    let v = HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
            Text("EDIT TEXT (WYSIWYG)").font(.caption.bold()).padding(4)
            SwashTextView(text: binding, selectedRange: .constant(nil), selectionRect: .constant(nil),
                          scrollOriginY: .constant(0), isStyled: true, flavor: .github)
        }.frame(width: 420, height: 380)
        Divider()
        VStack(alignment: .leading, spacing: 0) {
            Text("PREVIEW (split view)").font(.caption.bold()).padding(4)
            MarkdownPreviewView(text: md, flavor: .github)
        }.frame(width: 420, height: 380)
    }.background(Color.white)
    let host = NSHostingView(rootView: v)
    host.frame = NSRect(x: 0, y: 0, width: 841, height: 380)
    let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    win.appearance = NSAppearance(named: .aqua)
    pump(0.3)
    snapshot(host, to: url)
}

let probes: [Probe] = [
    // Inline emphasis
    Probe(id: "em-basic", md: "*it* _it_ **b** __b__ ***bi*** ~~s~~"),
    Probe(id: "em-nested-italic-in-bold", md: "**bold with *italic* inside**"),
    Probe(id: "em-nested-bold-in-italic", md: "*italic with **bold** inside*"),
    Probe(id: "em-intraword", md: "snake_case_name and file__name__x and a*b*c"),
    Probe(id: "em-multiline", md: "**bold that\nspans lines**"),
    Probe(id: "em-escaped", md: "\\*not italic\\* and \\# not heading and 2 \\* 3"),
    Probe(id: "em-bold-in-heading", md: "## Heading with **bold** and `code`"),
    Probe(id: "em-link-in-bold", md: "**see [docs](https://a.com)**"),
    // Code
    Probe(id: "code-inline-with-emphasis-chars", md: "Call `__init__` and `a*b*c` and `[x](y)`"),
    Probe(id: "code-inline-double-backtick", md: "Use ``a `tick` here``"),
    Probe(id: "code-fenced-tilde", md: "~~~python\nprint('hi')  # comment\n~~~"),
    Probe(id: "code-fenced-with-markdown-inside", md: "```\n**not bold** and [not](link)\n# not heading\n```"),
    Probe(id: "code-indented", md: "Para\n\n    indented code **x**\n    line2"),
    Probe(id: "code-unclosed-fence", md: "```js\nconst a = 1\n\nStill code?"),
    Probe(id: "code-fence-language-visibility", md: "```swift\nlet x = 1\n```"),
    // Headings
    Probe(id: "h-all-levels", md: "# H1\n## H2\n### H3\n#### H4\n##### H5\n###### H6"),
    Probe(id: "h-closing-hashes", md: "## Title ##"),
    Probe(id: "h-setext", md: "Title\n=====\n\nSub\n---"),
    Probe(id: "h-no-space", md: "#NotAHeading"),
    Probe(id: "h-setext-false-positive-list", md: "- item one\n---\nafter"),
    // Lists
    Probe(id: "list-bullets-mixed", md: "- dash\n* star\n+ plus"),
    Probe(id: "list-nested", md: "- a\n  - b\n    - c\n- d"),
    Probe(id: "list-ordered-start", md: "3. three\n4. four\n10. ten"),
    Probe(id: "list-ordered-paren", md: "1) one\n2) two"),
    Probe(id: "list-continuation-paragraph", md: "- item first line\n  continued line\n\n  second paragraph in item\n- next"),
    Probe(id: "list-with-code-block", md: "1. step\n\n   ```bash\n   echo hi\n   ```\n2. next"),
    Probe(id: "list-tab-indented", md: "- a\n\t- tab nested"),
    Probe(id: "list-4space-nested", md: "1. a\n    1. four-space nested"),
    Probe(id: "task-basic", md: "- [ ] todo\n- [x] done\n  - [X] nested done"),
    Probe(id: "task-ordered", md: "1. [ ] ordered task"),
    // Quotes
    Probe(id: "quote-basic", md: "> quoted **bold** text"),
    Probe(id: "quote-nested", md: "> level 1\n>> level 2\n> > level 2 spaced"),
    Probe(id: "quote-lazy", md: "> start of quote\nlazy continuation"),
    Probe(id: "quote-no-space", md: ">tight quote"),
    Probe(id: "quote-indented", md: "  > indented quote"),
    Probe(id: "quote-with-list", md: "> - item in quote\n> - another"),
    Probe(id: "quote-with-heading", md: "> # Heading in quote"),
    Probe(id: "alert-note", md: "> [!NOTE]\n> Useful info **here**."),
    Probe(id: "alert-warning-inline", md: "> [!WARNING] Inline text"),
    // Links
    Probe(id: "link-inline-title", md: "[Swash](https://x.com \"Title\")"),
    Probe(id: "link-parens-url", md: "[wiki](https://en.wikipedia.org/wiki/Foo_(bar))"),
    Probe(id: "link-reference", md: "[full][ref] [collapsed][] [ref]\n\n[ref]: https://ref.com\n[collapsed]: https://c.com"),
    Probe(id: "link-autolink-angle", md: "<https://angle.com> and <me@mail.com>"),
    Probe(id: "link-bare", md: "https://bare.com, www.www.com and a@b.co."),
    Probe(id: "link-image-in-link", md: "[![badge](https://img.shields.io/x.svg)](https://ci.com)"),
    Probe(id: "link-brackets-in-text", md: "[a [nested] text](https://n.com)"),
    // Images
    Probe(id: "img-inline", md: "Before ![alt text](missing.png) after"),
    Probe(id: "img-in-table", md: "| A | B |\n|---|---|\n| ![i](x.png) | text |\n\nAfter table paragraph"),
    // Tables
    Probe(id: "table-basic", md: "| A | B |\n|:--|--:|\n| **1** | `2` |"),
    Probe(id: "table-no-outer-pipes", md: "A | B\n--|--\n1 | 2"),
    Probe(id: "table-pipe-in-text-false-positive", md: "Use a | b for OR\nand a-b for minus"),
    // Breaks / rules
    Probe(id: "hr-variants", md: "a\n\n***\n\n- - -\n\n___"),
    Probe(id: "hard-break-spaces", md: "line one  \nline two\\\nline three"),
    // Footnotes
    Probe(id: "footnote", md: "Text[^1] more[^note].\n\n[^1]: First.\n[^note]: Named **bold**."),
    // HTML & extensions
    Probe(id: "html-inline", md: "Press <kbd>⌘</kbd>+<kbd>B</kbd>, H<sub>2</sub>O, x<sup>2</sup>, line<br>break, <mark>hi</mark>"),
    Probe(id: "html-block-details", md: "<details>\n<summary>More</summary>\n\nHidden **content**\n\n</details>"),
    Probe(id: "html-comment", md: "Visible <!-- hidden comment --> text"),
    Probe(id: "math", md: "Inline $E=mc^2$ and block:\n\n$$\n\\int_0^1 x dx\n$$"),
    Probe(id: "mermaid", md: "```mermaid\ngraph TD; A-->B\n```"),
    Probe(id: "emoji-shortcode", md: "Ship it :rocket: :+1:"),
    Probe(id: "highlight-ext", md: "==highlighted== text"),
    Probe(id: "front-matter", md: "---\ntitle: Doc\ntags: [a, b]\n---\n\n# Body"),
    Probe(id: "definition-list", md: "Term\n: Definition"),
    Probe(id: "unicode-offsets", md: "👋🏽 **bold** é [link](https://u.com)"),
]

@main
struct AuditRunner {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "audit-out")
        try? FileManager.default.createDirectory(at: outDir.appendingPathComponent("shots"), withIntermediateDirectories: true)
        var report = ""
        var failures: [String] = []
        // Visible-text expectations for fixed behaviour (markers hidden, code literal)
        let expectedVisible: [String: String] = [
            "code-inline-with-emphasis-chars": "Call __init__ and a*b*c and [x](y)",
            "code-inline-double-backtick": "Use a `tick` here",
            "code-indented": "Para\n\nindented code **x**\nline2",
            "img-in-table": "[TABLE]\n\nAfter table paragraph",
            // Phase 3: inline HTML (tags hidden, content styled)
            "html-inline": "Press ⌘+B, H2O, x2, line<br>break, hi",
            // Phase 1: AST-driven styling
            "em-nested-italic-in-bold": "bold with italic inside",
            "em-nested-bold-in-italic": "italic with bold inside",
            "em-multiline": "bold that\nspans lines",
            "em-escaped": "*not italic* and # not heading and 2 * 3",
            "h-setext-false-positive-list": "‹•›item one\n\nafter",
            "list-nested": "‹•›a\n‹◦›b\n‹▪›c\n‹•›d",
            "list-4space-nested": "‹1.›a\n‹1.›four-space nested",
            "list-continuation-paragraph": "‹•›item first line\ncontinued line\n\nsecond paragraph in item\n‹•›next",
            "task-ordered": "‹☐›ordered task",
            "quote-nested": "level 1\nlevel 2\nlevel 2 spaced",
            "quote-no-space": "tight quote",
            "quote-with-list": "‹•›item in quote\n‹•›another",
            "alert-note": "NOTE\nUseful info here.",
            "link-parens-url": "wiki",
            "link-reference": "full collapsed ref\n\n[ref]: https://ref.com\n[collapsed]: https://c.com",
            "link-autolink-angle": "https://angle.com and me@mail.com",
            "link-image-in-link": "[IMAGE]",
            "hard-break-spaces": "line one\nline two\nline three",
            "footnote": "Text1 morenote.\n\n[1]: First.\n[note]: Named bold.",
        ]
        for p in probes {
            let box = TextBox(p.md)
            let (host, tvOpt) = makeEditor(box)
            guard let tv = tvOpt, let storage = tv.textStorage else { report += "## \(p.id)\nNO TEXTVIEW\n\n"; continue }
            let (visible, runs) = visibleRender(storage)
            let coord = tv.delegate as? SwashTextView.Coordinator
            let raw = coord?.buildRawMarkdown(from: storage) ?? "?"
            report += "## \(p.id)\nINPUT:   \(p.md.debugDescription)\nVISIBLE: \(visible.debugDescription)\nRUNS:    \(runs.joined(separator: " "))\n"
            if raw != p.md {
                report += "ROUNDTRIP MISMATCH: \(raw.debugDescription)\n"
                failures.append("\(p.id): raw markdown did not round-trip: \(raw.debugDescription)")
            }
            if let expected = expectedVisible[p.id], expected != visible {
                failures.append("\(p.id): expected visible \(expected.debugDescription), got \(visible.debugDescription)")
            }
            let blocks = MarkdownDocument.parse(p.md).root.children.map { "\($0.kind)".components(separatedBy: "(").first ?? "" }
            report += "PREVIEW BLOCKS: \(blocks.joined(separator: " | "))\n\n"
            _ = host
            sideBySide(p.md, to: outDir.appendingPathComponent("shots/\(p.id).png"))
        }
        // Slack mrkdwn keeps its own (legacy) styling path
        let slack = TextBox("*bold* _italic_ ~strike~ `code` <https://s.com|site>\n> quote\n- item")
        let (slackHost, slackView) = makeEditor(slack, flavor: .slack)
        if let tv = slackView, let storage = tv.textStorage {
            let (visible, runs) = visibleRender(storage)
            report += "## slack-basic\nVISIBLE: \(visible.debugDescription)\nRUNS:    \(runs.joined(separator: " "))\n\n"
            let expected = "bold italic strike code site\nquote\n‹•›item"
            if visible != expected { failures.append("slack-basic: expected visible \(expected.debugDescription), got \(visible.debugDescription)") }
        }
        _ = slackHost
        try? report.write(to: outDir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        print(report)
        print(failures.isEmpty ? "RENDER: all expectations passed" : "RENDER FAILURES:\n" + failures.joined(separator: "\n"))
        exit(failures.isEmpty ? 0 : 1)
    }
}
