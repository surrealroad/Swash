import Foundation
import SwiftUI
import AppKit

final class TextBox { var text: String; init(_ t: String) { text = t } }
func pump(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func findTextView(in v: NSView) -> NSTextView? {
    if let tv = v as? NSTextView { return tv }
    for s in v.subviews { if let f = findTextView(in: s) { return f } }
    return nil
}

var windows: [NSWindow] = []
func makeEditor(_ box: TextBox) -> NSTextView {
    let binding = Binding<String>(get: { box.text }, set: { box.text = $0 })
    let editor = SwashTextView(text: binding, selectedRange: .constant(nil), selectionRect: .constant(nil),
                               scrollOriginY: .constant(0), isStyled: true, flavor: .github)
    let host = NSHostingView(rootView: editor.frame(width: 600, height: 600))
    host.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
    let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    win.contentView = host
    windows.append(win)
    host.layoutSubtreeIfNeeded()
    pump(0.3)
    let tv = findTextView(in: host)!
    win.makeFirstResponder(tv)
    return tv
}

func caretAfter(_ needle: String, in tv: NSTextView) {
    let r = (tv.string as NSString).range(of: needle)
    tv.setSelectedRange(NSRange(location: r.location + r.length, length: 0))
}
func caretBefore(_ needle: String, in tv: NSTextView) {
    let r = (tv.string as NSString).range(of: needle)
    tv.setSelectedRange(NSRange(location: r.location, length: 0))
}

// Key commands are sent with doCommand(by:) so the text view delegate sees them, exactly as key presses do
var out = ""
var failures: [String] = []
/// Records a probe. When `expect` is given the probe is a regression assertion.
func log(_ id: String, _ before: String, _ after: String, _ note: String = "", expect: String? = nil) {
    out += "## \(id)\nBEFORE: \(before.debugDescription)\nAFTER:  \(after.debugDescription)\n\(note.isEmpty ? "" : "NOTE: \(note)\n")\n"
    if let expected = expect, expected != after {
        failures.append("\(id): expected \(expected.debugDescription), got \(after.debugDescription)")
    }
}

@main
struct InteractionRunner {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        // 1. Enter at end of bullet item
        do { let b = TextBox("- first item"); let tv = makeEditor(b); caretAfter("first item", in: tv)
             tv.doCommand(by: #selector(NSResponder.insertNewline(_:))); pump(); tv.insertText("second", replacementRange: tv.selectedRange()); pump()
             log("enter-continues-bullet-list", "- first item", b.text, expect: "- first item\n- second") }
        // 2. Enter at end of ordered item
        do { let b = TextBox("1. first"); let tv = makeEditor(b); caretAfter("first", in: tv)
             tv.doCommand(by: #selector(NSResponder.insertNewline(_:))); pump(); tv.insertText("second", replacementRange: tv.selectedRange()); pump()
             log("enter-continues-ordered-list", "1. first", b.text, expect: "1. first\n2. second") }
        // 3. Enter at end of task item
        do { let b = TextBox("- [x] done"); let tv = makeEditor(b); caretAfter("done", in: tv)
             tv.doCommand(by: #selector(NSResponder.insertNewline(_:))); pump(); tv.insertText("next", replacementRange: tv.selectedRange()); pump()
             log("enter-continues-task-list", "- [x] done", b.text, expect: "- [x] done\n- [ ] next") }
        // 4. Tab in list item
        do { let b = TextBox("- a\n- b"); let tv = makeEditor(b); caretAfter("- b", in: tv)
             tv.doCommand(by: #selector(NSResponder.insertTab(_:))); pump()
             log("tab-indents-list-item", "- a\n- b", b.text, expect: "- a\n  - b") }
        // 5. Enter in blockquote
        do { let b = TextBox("> quote"); let tv = makeEditor(b); caretAfter("quote", in: tv)
             tv.doCommand(by: #selector(NSResponder.insertNewline(_:))); pump(); tv.insertText("more", replacementRange: tv.selectedRange()); pump()
             log("enter-continues-quote", "> quote", b.text, expect: "> quote\nmore".replacingOccurrences(of: "\nmore", with: "\n> more")) }
        // 6. Backspace at visual start of heading text
        do { let b = TextBox("## Title"); let tv = makeEditor(b); caretBefore("Title", in: tv)
             tv.doCommand(by: #selector(NSResponder.deleteBackward(_:))); pump()
             log("backspace-at-heading-start", "## Title", b.text, expect: "Title") }
        // 7. Backspace at visual start of bullet text
        do { let b = TextBox("- item"); let tv = makeEditor(b); caretBefore("item", in: tv)
             tv.doCommand(by: #selector(NSResponder.deleteBackward(_:))); pump()
             log("backspace-at-list-start", "- item", b.text, expect: "item") }
        // 8. Arrow keys across hidden markers: count presses to move from before 'x' to after 'y' in 'x **b** y'
        do { let b = TextBox("x **b** y"); let tv = makeEditor(b); caretAfter("x", in: tv)
             var presses = 0; let target = (tv.string as NSString).range(of: " y").location
             while tv.selectedRange().location < target && presses < 20 { tv.moveRight(nil); presses += 1 }
             log("arrow-keys-hidden-markers", "x **b** y", "presses=\(presses)", "one press per visible character", expect: "presses=3") }
        // 9. Typing right after a bold run: does new text inherit bold / land inside markers?
        do { let b = TextBox("**bold** tail"); let tv = makeEditor(b); caretAfter("bold", in: tv)
             tv.insertText("X", replacementRange: tv.selectedRange()); pump()
             log("type-at-end-of-bold", "**bold** tail", b.text, "caret visually after 'bold' sits before hidden '**' so text lands inside bold") }
        // 10. Undo after typing in a document containing a table
        do { let md = "| A | B |\n|---|---|\n| 1 | 2 |\n\nPara"
             let b = TextBox(md); let tv = makeEditor(b); caretAfter("Para", in: tv)
             tv.insertText("graph", replacementRange: tv.selectedRange()); pump()
             let afterType = b.text
             tv.undoManager?.undo(); pump()
             let afterUndo = b.text
             log("undo-with-table-present", md, afterUndo, "after typing: \(afterType.debugDescription)", expect: md) }
        // 11. Undo after typing in a doc with an image
        do { let md = "![alt](missing.png)\n\nHello"
             let b = TextBox(md); let tv = makeEditor(b); caretAfter("Hello", in: tv)
             tv.insertText(" world", replacementRange: tv.selectedRange()); pump()
             let afterType = b.text
             tv.undoManager?.undo(); pump()
             log("undo-with-image-present", md, b.text, "after typing: \(afterType.debugDescription)") }
        // 12. Undo of plain typing (no attachments)
        do { let md = "Hello"
             let b = TextBox(md); let tv = makeEditor(b); caretAfter("Hello", in: tv)
             tv.insertText(" world", replacementRange: tv.selectedRange()); pump()
             tv.undoManager?.undo(); pump()
             log("undo-plain", md, b.text, expect: "Hello") }
        // 13. Opening doc then typing: are untouched tables reformatted?
        do { let md = "|a|b|\n|-|-|\n|1|2|\n\nx"
             let b = TextBox(md); let tv = makeEditor(b); caretAfter("x", in: tv)
             tv.insertText("y", replacementRange: tv.selectedRange()); pump()
             log("typing-rewrites-untouched-table", md, b.text, "untouched tables must round-trip verbatim", expect: md + "y") }
        // 14. Selection coordinates vs raw markdown (attachments collapse to 1 char)
        do { let md = "![alt](missing.png) target word"
             let b = TextBox(md); let tv = makeEditor(b)
             let r = (tv.string as NSString).range(of: "target")
             let rawR = (md as NSString).range(of: "target")
             log("selection-offset-drift", md, md, "'target' is at storage offset \(r.location) but raw-markdown offset \(rawR.location); ContentView applies bubble actions to document.text using storage offsets → wrong span") }
        // 15. Paste rich text (HTML) into WYSIWYG
        do { let b = TextBox(""); let tv = makeEditor(b)
             let pb = NSPasteboard.general; pb.clearContents()
             pb.setString("<b>Bold</b> and <a href=\"https://x.com\">link</a>", forType: .html)
             pb.setString("Bold and link", forType: .string)
             tv.paste(nil); pump()
             log("paste-html", "(empty) + clipboard HTML '<b>Bold</b> and <a>link</a>'", b.text, expect: "**Bold** and [link](https://x.com)") }
        // 15b. Plain-equivalent HTML pastes as plain text; code-editor HTML keeps its indentation
        do { let b = TextBox(""); let tv = makeEditor(b)
             let pb = NSPasteboard.general; pb.clearContents()
             pb.setString("<p>5 * 3 = 15</p>", forType: .html); pb.setString("5 * 3 = 15", forType: .string)
             tv.paste(nil); pump()
             log("paste-plain-equivalent-html", "<p>5 * 3 = 15</p>", b.text, expect: "5 * 3 = 15") }
        do { let b = TextBox(""); let tv = makeEditor(b)
             let pb = NSPasteboard.general; pb.clearContents()
             pb.setString("<div style=\"white-space: pre;\"><div><span>func a() {</span></div><div><span>    return 1</span></div></div>", forType: .html)
             pb.setString("func a() {\n    return 1", forType: .string)
             tv.paste(nil); pump()
             log("paste-code-editor-html", "VS Code-style HTML", b.text, expect: "func a() {\n    return 1") }
        // 15d. RTF (TextEdit, Pages) converts through HTML
        do { let b = TextBox(""); let tv = makeEditor(b)
             let rich = NSMutableAttributedString(string: "Bold and italic text")
             rich.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: 0, length: 4))
             rich.addAttribute(.font, value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask), range: NSRange(location: 9, length: 6))
             let rtf = try! rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
             let pb = NSPasteboard.general; pb.clearContents()
             pb.setData(rtf, forType: .rtf); pb.setString(rich.string, forType: .string)
             tv.paste(nil); pump()
             log("paste-rtf", "RTF: **Bold** and *italic* text", b.text, expect: "**Bold** and *italic* text") }
        // 15c. Copy within Swash pastes the exact Markdown (tables and images included)
        do { let md = "| A | B |\n|---|---|\n| ![i](x.png) | **b** |\n\nPara *x*"
             let src = TextBox(md); let tv1 = makeEditor(src); tv1.selectAll(nil); tv1.copy(nil); pump()
             let dst = TextBox(""); let tv2 = makeEditor(dst); tv2.paste(nil); pump()
             log("copy-paste-roundtrip", md, dst.text, expect: md) }
        // 16. Copy from WYSIWYG → plain-text clipboard content
        do { let md = "**bold** and [link](https://x.com)"
             let b = TextBox(md); let tv = makeEditor(b); tv.selectAll(nil); tv.copy(nil); pump()
             log("copy-plain-flavor", md, NSPasteboard.general.string(forType: .string) ?? "nil", "plain-text flavour should be raw markdown") }
        // 17. Typing '---' then Enter — live HR?
        do { let b = TextBox("Para\n"); let tv = makeEditor(b); tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
             tv.insertText("---", replacementRange: tv.selectedRange()); pump()
             log("type-hr-under-paragraph", "Para\\n + '---'", b.text, "'Para' immediately becomes a setext H2 and '---' disappears (no blank line)") }

        // 18. Consecutive keystrokes after a table keep the caret in place
        do { let md = "| A | B |\n|---|---|\n| 1 | 2 |\n\nPara"
             let b = TextBox(md); let tv = makeEditor(b); caretAfter("Para", in: tv)
             for ch in ["a", "b", "c"] { tv.insertText(ch, replacementRange: tv.selectedRange()); pump() }
             log("consecutive-typing-after-table", md, b.text, expect: md + "abc") }
        // 19. Consecutive keystrokes between two images
        do { let md = "![a](x.png) mid ![b](y.png) end"
             let b = TextBox(md); let tv = makeEditor(b); caretAfter("mid", in: tv)
             for ch in ["1", "2"] { tv.insertText(ch, replacementRange: tv.selectedRange()); pump() }
             tv.undoManager?.undo(); pump()
             let afterUndo = b.text
             tv.undoManager?.redo(); pump()
             log("typing-undo-redo-between-images", md, b.text, "after undo: \(afterUndo.debugDescription)", expect: "![a](x.png) mid12 ![b](y.png) end")
             if afterUndo != md { failures.append("typing-undo-redo-between-images: undo expected original, got \(afterUndo.debugDescription)") } }

        // 22. Arrow keys back across hidden markers, and a click at line start lands on the content
        do { let b = TextBox("x **b** y"); let tv = makeEditor(b); caretAfter("y", in: tv)
             var presses = 0; let target = (tv.string as NSString).range(of: "x").location + 1
             while tv.selectedRange().location > target && presses < 20 { tv.doCommand(by: #selector(NSResponder.moveLeft(_:))); presses += 1 }
             log("arrow-left-hidden-markers", "x **b** y", "presses=\(presses)", expect: "presses=4") }
        do { let b = TextBox("## Title"); let tv = makeEditor(b); tv.setSelectedRange(NSRange(location: 0, length: 0)); pump()
             tv.insertText("New ", replacementRange: tv.selectedRange()); pump()
             log("click-line-start-types-into-heading", "## Title", b.text, expect: "## New Title") }
        do { let b = TextBox("```\ncode\n```\nafter"); let tv = makeEditor(b); caretAfter("code", in: tv)
             tv.doCommand(by: #selector(NSResponder.moveRight(_:))); pump()
             tv.insertText("X", replacementRange: tv.selectedRange()); pump()
             log("arrow-over-collapsed-fence-line", "```\ncode\n```\nafter", b.text, expect: "```\ncode\n```\nXafter") }
        
        // 23. Clicking a task checkbox toggles it (and undo restores it)
        func clickCheckbox(_ tv: NSTextView, line index: Int) {
            guard let lm = tv.layoutManager, let storage = tv.textStorage else { return }
            var markers: [NSRange] = []
            storage.enumerateAttribute(.listMarker, in: NSRange(location: 0, length: storage.length)) { v, r, _ in if v != nil { markers.append(r) } }
            guard index < markers.count else { return }
            let r = markers[index]
            let glyph = lm.glyphIndexForCharacter(at: NSMaxRange(r))
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let contentX = lineRect.minX + lm.location(forGlyphAt: glyph).x
            let containerPoint = NSPoint(x: contentX - 14, y: lineRect.midY)
            let viewPoint = NSPoint(x: containerPoint.x + tv.textContainerOrigin.x, y: containerPoint.y + tv.textContainerOrigin.y)
            let windowPoint = tv.convert(viewPoint, to: nil)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: 0,
                                           windowNumber: tv.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            tv.mouseDown(with: event)
        }
        do { let md = "- [ ] first\n- [x] second"
             let b = TextBox(md); let tv = makeEditor(b)
             clickCheckbox(tv, line: 0); pump()
             let afterFirst = b.text
             clickCheckbox(tv, line: 1); pump()
             let afterSecond = b.text
             tv.undoManager?.undo(); pump()
             log("checkbox-click-toggles", md, afterFirst + " | " + afterSecond + " | undo: " + b.text,
                 expect: "- [x] first\n- [x] second | - [x] first\n- [ ] second | undo: - [x] first\n- [x] second") }
        
        // 24. "/" on an empty line opens the block menu; the chosen block replaces the slash
        SwashTextView.Coordinator.blockMenuPresenter = { _, _, choose in choose(.heading2) }
        do { let b = TextBox("Intro\n"); let tv = makeEditor(b)
             tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
             tv.insertText("/", replacementRange: tv.selectedRange()); pump(0.3)
             tv.insertText("Title", replacementRange: tv.selectedRange()); pump()
             log("slash-menu-heading", "Intro\n + '/' → Heading 2", b.text, expect: "Intro\n## Title") }
        SwashTextView.Coordinator.blockMenuPresenter = { _, _, choose in choose(.todoList) }
        do { let b = TextBox("- a\n- "); let tv = makeEditor(b)
             tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
             tv.insertText("/", replacementRange: tv.selectedRange()); pump(0.3)
             tv.insertText("task", replacementRange: tv.selectedRange()); pump()
             log("slash-menu-in-list-item", "- a\n- + '/' → To-do", b.text, expect: "- a\n- [ ] task") }
        var presented = false
        SwashTextView.Coordinator.blockMenuPresenter = { _, _, choose in presented = true; choose(nil) }
        do { let b = TextBox("and/or"); let tv = makeEditor(b); caretAfter("and", in: tv)
             tv.insertText("/", replacementRange: tv.selectedRange()); pump(0.3)
             log("slash-mid-sentence-no-menu", "and/or", "\(b.text) presented=\(presented)", expect: "and//or presented=false") }
        do { let b = TextBox(""); let tv = makeEditor(b)
             tv.insertText("/", replacementRange: tv.selectedRange()); pump(0.3)
             log("slash-menu-dismissed-keeps-slash", "'/' then Escape", "\(b.text) presented=\(presented)", expect: "/ presented=true") }
        
        // 25. Code block language badge: shown, and clicking it changes the fence's language
        SwashTextView.Coordinator.languageMenuPresenter = { _, _, _, choose in choose(.some("python")) }
        do { let md = "Intro\n\n```swift\nlet x = 1\n```"
             let b = TextBox(md); let tv = makeEditor(b)
             var badges: [String] = []
             var badgeRange = NSRange(location: NSNotFound, length: 0)
             tv.textStorage!.enumerateAttribute(.codeBadge, in: NSRange(location: 0, length: tv.textStorage!.length)) { v, r, _ in
                 if let info = v as? CodeBadgeInfo { badges.append(info.title); badgeRange = r } }
             if badgeRange.location != NSNotFound, let lm = tv.layoutManager {
                 let lineRect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: badgeRange.location), effectiveRange: nil)
                 let rect = CodeBadgeInfo(language: "swift").rect(in: lineRect)
                 let viewPoint = NSPoint(x: rect.midX + tv.textContainerOrigin.x, y: rect.midY + tv.textContainerOrigin.y)
                 let event = NSEvent.mouseEvent(with: .leftMouseDown, location: tv.convert(viewPoint, to: nil), modifierFlags: [], timestamp: 0,
                                                windowNumber: tv.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                 tv.mouseDown(with: event); pump()
             }
             log("code-language-badge", md, "badges=\(badges) | \(b.text)", expect: "badges=[\"SWIFT\"] | Intro\n\n```python\nlet x = 1\n```") }
        
        // 26. Incremental restyling must match a full restyle exactly
        func fingerprint(_ tv: NSTextView) -> String {
            guard let storage = tv.textStorage else { return "" }
            var out = ""
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attrs, range, _ in
                let text = (storage.string as NSString).substring(with: range)
                var parts = [text.debugDescription]
                if let f = attrs[.font] as? NSFont { parts.append("\(f.fontName)@\(f.pointSize)") }
                if let c = attrs[.foregroundColor] as? NSColor { parts.append(c.description) }
                if let p = attrs[.paragraphStyle] as? NSParagraphStyle { parts.append("p\(p.headIndent)/\(p.firstLineHeadIndent)/\(p.tailIndent)/\(p.textBlocks.count)") }
                if let m = attrs[.listMarker] as? ListMarkerInfo { parts.append("m\(m.text)@\(m.indent)") }
                if attrs[.link] != nil { parts.append("link") }
                if attrs[.strikethroughStyle] != nil { parts.append("strike") }
                if let a = attrs[.attachment] { parts.append(a is TableTextAttachment ? "TABLE" : "IMAGE") }
                if attrs[.codeBadge] != nil { parts.append("badge") }
                out += parts.joined(separator: " ") + "\n"
            }
            return out
        }
        let base = "# Title\n\nIntro with **bold** and ![img](x.png) here.\n\n- one\n- two\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n> quote\n\n```swift\nlet x = 1\n```\n\nLast paragraph."
        let scenarios: [(String, String, String, Bool)] = [
            ("type in paragraph", "Intro with", " more", true),
            ("make bold", "Last", "**", true),
            ("open a fence", "Intro", "\n```\n", true),
            ("type in list", "- one", " item", true),
            ("new list item", "- two", "\n- three", true),
            ("setext underline", "Last paragraph.", "\n---", true),
            ("type in quote", "> quote", " text", true),
            ("before table", "- two", "\n\nPara before table", true),
            ("in code", "let x", "y", true),
            ("at start", "# Title", "!", true),
            ("at end", "Last paragraph.", " End", true),
            ("add reference definition", "Last paragraph.", "\n\n[r]: https://r.com", false),
        ]
        for (name, anchor, insertion, expectIncremental) in scenarios {
            let b = TextBox(base); let tv = makeEditor(b)
            let coordinator = tv.delegate as! SwashTextView.Coordinator
            caretAfter(anchor, in: tv)
            let before = coordinator.incrementalPassCount
            tv.insertText(insertion, replacementRange: tv.selectedRange()); pump(0.3)
            let usedIncremental = coordinator.incrementalPassCount > before
            let incremental = fingerprint(tv)
            coordinator.forceFullRestyle = true
            coordinator.highlightMarkdown(in: tv); pump(0.1)
            let full = fingerprint(tv)
            let same = incremental == full
            log("incremental-\(name.replacingOccurrences(of: " ", with: "-"))", "\(anchor) + \(insertion.debugDescription)",
                "path=\(usedIncremental ? "incremental" : "full") matchesFull=\(same)",
                same ? "" : "first difference: \(zip(incremental.split(separator: "\n"), full.split(separator: "\n")).first(where: { $0 != $1 }).map { "\($0) vs \($1)" } ?? "length")",
                expect: "path=\(expectIncremental ? "incremental" : "full") matchesFull=true")
        }
        
        // 20. Enter on an empty item leaves the list; Backspace with the caret before the hidden marker
        do { let b = TextBox("- a\n- b"); let tv = makeEditor(b); caretAfter("b", in: tv)
             tv.doCommand(by: #selector(NSResponder.insertNewline(_:))); pump(); tv.doCommand(by: #selector(NSResponder.insertNewline(_:))); pump()
             tv.insertText("after", replacementRange: tv.selectedRange()); pump()
             log("enter-twice-exits-list", "- a\n- b", b.text, expect: "- a\n- b\nafter") }
        do { let b = TextBox("- item"); let tv = makeEditor(b); tv.setSelectedRange(NSRange(location: 0, length: 0))
             tv.doCommand(by: #selector(NSResponder.deleteBackward(_:))); pump()
             log("backspace-at-line-start-before-hidden-marker", "- item", b.text, expect: "item") }
        // 21. Structural edits are undoable
        do { let b = TextBox("- a"); let tv = makeEditor(b); caretAfter("a", in: tv)
             tv.doCommand(by: #selector(NSResponder.insertNewline(_:))); pump(); tv.undoManager?.undo(); pump()
             log("enter-continuation-undo", "- a", b.text, expect: "- a") }

        try? out.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
        print(out)
        print(failures.isEmpty ? "INTERACTION: all expectations passed" : "INTERACTION FAILURES:\n" + failures.joined(separator: "\n"))
        exit(failures.isEmpty ? 0 : 1)
    }
}
