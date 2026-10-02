import Foundation
import SwiftUI
import AppKit

// Hosts the real ContentView (Edit Text mode is the default .preview ViewMode),
// drives selection on the NSTextView, then invokes the bubble menu's own action closures
// (captured via TestHooks injected by run_audit.sh) and records the resulting markdown.
// SwiftUI does not populate its accessibility tree in-process, and System Events UI
// scripting needs assistive access, so this is the reliable way to exercise the menu.

final class DocBox: ObservableObject { @Published var doc: SwashDocument; init(_ d: SwashDocument) { doc = d } }
struct Root: View {
    @ObservedObject var box: DocBox
    var body: some View { ContentView(document: $box.doc) }
}

func pump(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func findTextView(in v: NSView) -> NSTextView? {
    if let tv = v as? NSTextView, tv.isEditable, tv.enclosingScrollView?.frame.width ?? 0 > 300 { return tv }
    for s in v.subviews { if let f = findTextView(in: s) { return f } }
    return nil
}

func snapshot(_ win: NSWindow, _ url: URL) {
    guard let v = win.contentView?.superview ?? win.contentView else { return }
    v.layoutSubtreeIfNeeded(); pump(0.1)
    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
    v.cacheDisplay(in: v.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

var out = ""
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

struct Case { let id: String; let md: String; let select: String; let press: String?; var arg: String? = nil; var expect: String? = nil; var expectUndo: String? = nil }
var failures: [String] = []

let cases: [Case] = [
    Case(id: "undo-bold", md: "Plain beta gamma.", select: "beta", press: "bold", expectUndo: "Plain beta gamma."),
    Case(id: "undo-bold-after-table", md: "| A | B |\n|---|---|\n| 1 | 2 |\n\nSelect target word here.", select: "target", press: "bold", expectUndo: "| A | B |\n|---|---|\n| 1 | 2 |\n\nSelect target word here."),
    Case(id: "undo-link-after-image", md: "![i](x.png) add link here", select: "link", press: "LINK", arg: "https://c.com", expectUndo: "![i](x.png) add link here"),
    Case(id: "undo-heading", md: "Plain beta gamma.", select: "beta", press: "H", arg: "2", expectUndo: "Plain beta gamma."),

    Case(id: "ctx-plain", md: "Plain paragraph with alpha beta gamma.", select: "beta", press: nil),
    Case(id: "bold-plain", md: "Plain paragraph with alpha beta gamma.", select: "beta", press: "bold", expect: "Plain paragraph with alpha **beta** gamma."),
    Case(id: "bold-toggle-off", md: "Plain **beta** gamma.", select: "beta", press: "bold", expect: "Plain beta gamma."),
    Case(id: "bold-after-image", md: "![logo](missing.png) Select target word here.", select: "target", press: "bold", expect: "![logo](missing.png) Select **target** word here."),
    Case(id: "bold-after-table", md: "| A | B |\n|---|---|\n| 1 | 2 |\n\nSelect target word here.", select: "target", press: "bold", expect: "| A | B |\n|---|---|\n| 1 | 2 |\n\nSelect **target** word here."),
    Case(id: "bold-after-link", md: "A [link](https://example.com/long/path) then target word.", select: "target", press: "bold", expect: "A [link](https://example.com/long/path) then **target** word."),
    Case(id: "italic-on-bold", md: "Plain **beta** gamma.", select: "beta", press: "italic"),
    Case(id: "italic-detect-underscore", md: "an _emph_ word", select: "emph", press: "italic", expect: "an emph word"),
    Case(id: "bold-partial-overlap", md: "**bold text** plain", select: "text pl", press: "bold"),
    Case(id: "bold-multiline", md: "line one\nline two", select: "one\nline", press: "bold", expect: "line **one**\n**line** two"),
    Case(id: "bold-with-trailing-space", md: "double click word then", select: "word ", press: "bold", expect: "double click **word** then"),
    Case(id: "ctx-list", md: "- list item one\n- list item two", select: "item one", press: nil),
    Case(id: "numbered-from-bullets", md: "- list item one\n- list item two", select: "item one\n- list item", press: "numberedList", expect: "1. list item one\n2. list item two"),
    Case(id: "bullet-off", md: "- list item one", select: "item", press: "bulletList", expect: "list item one"),
    Case(id: "ctx-heading", md: "## Heading Here", select: "Heading", press: nil),
    Case(id: "heading-level-change", md: "## Heading Here", select: "Heading", press: "H", arg: "4", expect: "#### Heading Here"),
    Case(id: "heading-toggle-off", md: "## Heading Here", select: "Heading", press: "heading", expect: "Heading Here"),
    Case(id: "heading-on-list", md: "- list item one", select: "item", press: "heading"),
    Case(id: "quote-on-heading", md: "## Heading Here", select: "Heading", press: "quote", expect: "> ## Heading Here"),
    Case(id: "ctx-quote", md: "> quoted line here", select: "quoted", press: nil),
    Case(id: "quote-off", md: "> quoted line here", select: "quoted", press: "quote"),
    Case(id: "bullet-in-quote", md: "> quoted line here", select: "quoted", press: "bulletList", expect: "> - quoted line here"),
    Case(id: "ctx-task", md: "- [ ] task item", select: "task", press: nil),
    Case(id: "bullet-on-task", md: "- [ ] task item", select: "task", press: "bulletList", expect: "- task item"),
    Case(id: "numbered-on-task", md: "- [ ] task item", select: "task", press: "numberedList"),
    Case(id: "ctx-ordered-paren", md: "1) first item", select: "first", press: nil),
    Case(id: "ctx-alert", md: "> [!NOTE]\n> alert body", select: "alert", press: nil),
    Case(id: "ctx-code-block", md: "```swift\nlet x = 1\n```", select: "let", press: nil),
    Case(id: "code-lang-change", md: "```swift\nlet x = 1\n```", select: "let", press: "CODE", arg: "python", expect: "```python\nlet x = 1\n```"),
    Case(id: "code-block-off", md: "```swift\nlet x = 1\n```", select: "let", press: "code", expect: "let x = 1"),
    Case(id: "ctx-tilde-code-block", md: "~~~swift\nlet x = 1\n~~~", select: "let", press: nil),
    Case(id: "ctx-unknown-lang", md: "```rust\nfn main() {}\n```", select: "main", press: nil),
    Case(id: "ctx-inline-code", md: "call `foo()` now", select: "foo()", press: nil),
    Case(id: "inline-code-to-block", md: "call `foo()` now", select: "foo()", press: "CODE", arg: "swift", expect: "call \n```swift\nfoo()\n```\n now"),
    Case(id: "code-multiline-inline", md: "line one\nline two", select: "one\nline", press: "code", expect: "line \n```\none\nline\n```\n two"),
    Case(id: "ctx-link", md: "see [docs](https://a.com) here", select: "docs", press: nil),
    Case(id: "link-edit", md: "see [docs](https://a.com) here", select: "docs", press: "LINK", arg: "https://b.com", expect: "see [docs](https://b.com) here"),
    Case(id: "link-add-after-image", md: "![i](x.png) add link here", select: "link", press: "LINK", arg: "https://c.com", expect: "![i](x.png) add [link](https://c.com) here"),
    Case(id: "ctx-pipe-text", md: "Use a | b for OR", select: "OR", press: nil),
    Case(id: "table-from-text", md: "Name  Age\nBob  30", select: "Name  Age\nBob  30", press: "table"),
    Case(id: "bold-merge-overlap", md: "**bold text** plain", select: "text** pl", press: "bold", expect: "**bold text pl**ain"),
    Case(id: "bold-off-inside-italic", md: "*italic with **bold** inside*", select: "bold", press: "bold", expect: "*italic with bold inside*"),
    Case(id: "italic-on-bold-partial", md: "**bold words here**", select: "words", press: "italic", expect: "**bold *words* here**"),
    Case(id: "link-edit-reference", md: "[full][ref]\n\n[ref]: https://a.com", select: "full", press: "LINK", arg: "https://b.com", expect: "[full](https://b.com)\n\n[ref]: https://a.com"),
    Case(id: "ctx-list-in-quote", md: "> - item in quote", select: "item", press: nil),
    Case(id: "ctx-heading-in-quote", md: "> ## Heading", select: "Heading", press: nil),
    Case(id: "ctx-alert-body", md: "> [!TIP]\n> tip body", select: "body", press: nil),
    Case(id: "heading-in-list-item", md: "- list item", select: "list", press: "H", arg: "2", expect: "## list item"),
    Case(id: "strike-plain", md: "remove this text", select: "this", press: "strikethrough", expect: "remove ~~this~~ text"),
]

@main
struct BubbleRunner {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for c in cases where CommandLine.arguments.count < 3 || c.id.hasPrefix(CommandLine.arguments[2]) {
            let box = DocBox(SwashDocument(text: c.md, flavor: .github))
            let host = NSHostingView(rootView: Root(box: box))
            let win = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 500), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            win.contentView = host
            win.makeKeyAndOrderFront(nil)
            pump(0.6)
            guard let tv = findTextView(in: host) else { out += "## \(c.id)\nno text view\n\n"; continue }
            win.makeFirstResponder(tv)
            let r = (tv.string as NSString).range(of: c.select)
            TestHooks.state = "NO MENU"; TestHooks.onAction = nil; tv.setSelectedRange(r)
            NotificationCenter.default.post(name: NSTextView.didChangeSelectionNotification, object: tv)
            pump(0.5)
            snapshot(win, outDir.appendingPathComponent("\(c.id)-menu.png"))
            out += "## \(c.id)\nINPUT: \(c.md.debugDescription)  SELECT: \(c.select.debugDescription) (storage range \(r))\n"
            out += "STATE: \(TestHooks.state)\n"
            let expectedContexts = ["ctx-tilde-code-block": "context=codeBlock", "ctx-ordered-paren": "context=listItem", "ctx-pipe-text": "context=standard", "ctx-task": "context=listItem", "ctx-inline-code": "code=inline",
                                    "ctx-list-in-quote": "context=listItem", "ctx-heading-in-quote": "context=heading", "ctx-alert-body": "context=blockquote", "ctx-heading": "heading=H2", "ctx-link": "link=https://a.com", "ctx-plain": "context=standard"]
            if let ctx = expectedContexts[c.id], !TestHooks.state.contains(ctx) {
                failures.append("\(c.id): expected \(ctx), got \(TestHooks.state)")
            }
            if let press = c.press {
                let actions: [String: FormatAction] = ["bold": .bold, "italic": .italic, "code": .code, "strikethrough": .strikethrough, "heading": .heading, "quote": .quote, "bulletList": .bulletList, "numberedList": .numberedList, "table": .table]
                if press == "H" { TestHooks.onHeading?(Int(c.arg!)!) }
                else if press == "CODE" { TestHooks.onCode?(CodeFormat.allCases.first { $0.languageSignifier == c.arg } ?? .inline) }
                else if press == "LINK" { TestHooks.onLink?(c.arg!) }
                else if let a = actions[press] { TestHooks.onAction?(a) }
                pump(0.6)
                out += "PRESSED \(press)\(c.arg.map { "(" + $0 + ")" } ?? "") → RESULT: \(box.doc.text.debugDescription)\n"
                if let expected = c.expect, box.doc.text != expected {
                    failures.append("\(c.id): expected \(expected.debugDescription), got \(box.doc.text.debugDescription)")
                }
                snapshot(win, outDir.appendingPathComponent("\(c.id)-after.png"))
                if c.id.hasPrefix("undo-") {
                    win.makeFirstResponder(tv)
                    let canUndo = tv.undoManager?.canUndo ?? false
                    tv.undoManager?.undo(); pump(0.5)
                    out += "UNDO (canUndo=\(canUndo)) → \(box.doc.text.debugDescription)\n"
                    if let expected = c.expectUndo, box.doc.text != expected {
                        failures.append("\(c.id): undo expected \(expected.debugDescription), got \(box.doc.text.debugDescription)")
                    }
                }
            }
            out += "\n"
            win.orderOut(nil)
        }
        try? out.write(to: outDir.appendingPathComponent("bubble.md"), atomically: true, encoding: .utf8)
        print(out)
        print(failures.isEmpty ? "BUBBLE: all expectations passed" : "BUBBLE FAILURES:\n" + failures.joined(separator: "\n"))
        exit(failures.isEmpty ? 0 : 1)
    }
}
