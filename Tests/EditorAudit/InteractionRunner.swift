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

var out = ""
func log(_ id: String, _ before: String, _ after: String, _ note: String = "") {
    out += "## \(id)\nBEFORE: \(before.debugDescription)\nAFTER:  \(after.debugDescription)\n\(note.isEmpty ? "" : "NOTE: \(note)\n")\n"
}

@main
struct InteractionRunner {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        // 1. Enter at end of bullet item
        do { let b = TextBox("- first item"); let tv = makeEditor(b); caretAfter("first item", in: tv)
             tv.insertNewline(nil); pump(); tv.insertText("second", replacementRange: tv.selectedRange()); pump()
             log("enter-continues-bullet-list", "- first item", b.text, "Notion/Typora: expect '- first item\\n- second'") }
        // 2. Enter at end of ordered item
        do { let b = TextBox("1. first"); let tv = makeEditor(b); caretAfter("first", in: tv)
             tv.insertNewline(nil); pump(); tv.insertText("second", replacementRange: tv.selectedRange()); pump()
             log("enter-continues-ordered-list", "1. first", b.text, "expect '1. first\\n2. second'") }
        // 3. Enter at end of task item
        do { let b = TextBox("- [x] done"); let tv = makeEditor(b); caretAfter("done", in: tv)
             tv.insertNewline(nil); pump(); tv.insertText("next", replacementRange: tv.selectedRange()); pump()
             log("enter-continues-task-list", "- [x] done", b.text, "expect '- [x] done\\n- [ ] next'") }
        // 4. Tab in list item
        do { let b = TextBox("- a\n- b"); let tv = makeEditor(b); caretAfter("- b", in: tv)
             tv.insertTab(nil); pump()
             log("tab-indents-list-item", "- a\n- b", b.text, "expect '- a\\n  - b'") }
        // 5. Enter in blockquote
        do { let b = TextBox("> quote"); let tv = makeEditor(b); caretAfter("quote", in: tv)
             tv.insertNewline(nil); pump(); tv.insertText("more", replacementRange: tv.selectedRange()); pump()
             log("enter-continues-quote", "> quote", b.text, "expect '> quote\\n> more'") }
        // 6. Backspace at visual start of heading text
        do { let b = TextBox("## Title"); let tv = makeEditor(b); caretBefore("Title", in: tv)
             tv.deleteBackward(nil); pump()
             log("backspace-at-heading-start", "## Title", b.text, "caret appears at start of 'Title'; Notion converts to paragraph; here a hidden char is deleted") }
        // 7. Backspace at visual start of bullet text
        do { let b = TextBox("- item"); let tv = makeEditor(b); caretBefore("item", in: tv)
             tv.deleteBackward(nil); pump()
             log("backspace-at-list-start", "- item", b.text, "expect list marker removed (paragraph 'item')") }
        // 8. Arrow keys across hidden markers: count presses to move from before 'x' to after 'y' in 'x **b** y'
        do { let b = TextBox("x **b** y"); let tv = makeEditor(b); caretAfter("x", in: tv)
             var presses = 0; let target = (tv.string as NSString).range(of: " y").location
             while tv.selectedRange().location < target && presses < 20 { tv.moveRight(nil); presses += 1 }
             log("arrow-keys-hidden-markers", "x **b** y", b.text, "visible chars between 'x' and ' y' = 3 (' b ' minus) ; moveRight presses needed = \(presses) (each hidden '*' costs an invisible keypress)") }
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
             log("undo-with-table-present", md, afterUndo, "after typing: \(afterType.debugDescription)\nexpected after undo: original text with 'Para'") }
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
             log("undo-plain", md, b.text, "expect 'Hello'") }
        // 13. Opening doc then typing: are untouched tables reformatted?
        do { let md = "|a|b|\n|-|-|\n|1|2|\n\nx"
             let b = TextBox(md); let tv = makeEditor(b); caretAfter("x", in: tv)
             tv.insertText("y", replacementRange: tv.selectedRange()); pump()
             log("typing-rewrites-untouched-table", md, b.text, "a single keystroke elsewhere normalises every table in the file") }
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
             log("paste-html", "(empty) + clipboard HTML '<b>Bold</b> and <a>link</a>'", b.text, "Notion converts to '**Bold** and [link](https://x.com)'") }
        // 16. Copy from WYSIWYG → plain-text clipboard content
        do { let md = "**bold** and [link](https://x.com)"
             let b = TextBox(md); let tv = makeEditor(b); tv.selectAll(nil); tv.copy(nil); pump()
             log("copy-plain-flavor", md, NSPasteboard.general.string(forType: .string) ?? "nil", "plain-text flavour should be raw markdown") }
        // 17. Typing '---' then Enter — live HR?
        do { let b = TextBox("Para\n"); let tv = makeEditor(b); tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
             tv.insertText("---", replacementRange: tv.selectedRange()); pump()
             log("type-hr-under-paragraph", "Para\\n + '---'", b.text, "'Para' immediately becomes a setext H2 and '---' disappears (no blank line)") }

        try? out.write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
        print(out)
    }
}
