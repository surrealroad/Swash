import Foundation
import SwiftUI
import AppKit
func pump(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func findTextView(in v: NSView) -> NSTextView? { if let tv = v as? NSTextView { return tv }; for s in v.subviews { if let f = findTextView(in: s) { return f } }; return nil }
@main struct PerfRunner { static func main() {
    _ = NSApplication.shared
    // End-to-end keystroke latency (edit → restyle → layout) on a large mixed document
    do {
        let section = "## Section\n\nSome **bold** and *italic* text with a [link](https://x.com) and `code`.\n\n- item one\n- item two\n\n| A | B |\n|---|---|\n| 1 | ![i](x.png) |\n\n```swift\nlet x = 1\n```\n\n"
        var t = String(repeating: section, count: 150)
        let b = Binding<String>(get: { t }, set: { t = $0 })
        let host = NSHostingView(rootView: SwashTextView(text: b, selectedRange: .constant(nil), selectionRect: .constant(nil), isStyled: true, flavor: .github).frame(width: 600, height: 600))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false); win.contentView = host
        pump(0.8)
        let tv = findTextView(in: host)!; let c = tv.delegate as! SwashTextView.Coordinator
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        let middle = (tv.string as NSString).length / 2
        tv.setSelectedRange(NSRange(location: middle, length: 0))
        var total = 0.0
        for ch in ["a", "b", "c", "d", "e"] {
            let start = Date()
            tv.insertText(ch, replacementRange: tv.selectedRange())
            c.highlightMarkdown(in: tv)
            tv.layoutManager!.ensureLayout(for: tv.textContainer!)
            total += Date().timeIntervalSince(start)
            pump(0.05)
        }
        let average = total / 5 * 1000
        print("keystroke-latency lines=\(t.components(separatedBy: "\n").count) avg=\(Int(average))ms (edit + incremental restyle + layout)")
        // Budget: was ~70 ms with full restyling on every keystroke
        if average > 50 { print("PERF FAILURE: keystroke latency \(Int(average))ms exceeds 50ms budget"); exit(1) }
    }
    // Structural keys on a large document: Backspace and Enter in an ordinary paragraph should
    // not parse the whole document (they did, ~17 ms at 4,400 lines)
    do {
        let section = "## Section\n\nSome **bold** and *italic* text with a [link](https://x.com) and `code`.\n\n- item one\n- item two\n\n```swift\nlet x = 1\n```\n\n"
        let text = String(repeating: section, count: 400)
        let ns = text as NSString
        let paragraph = ns.range(of: "Some **bold**", options: [], range: NSRange(location: ns.length / 2, length: ns.length / 2))
        let caret = NSRange(location: paragraph.location + 5, length: 0)
        let item = ns.range(of: "item one", options: [], range: NSRange(location: ns.length / 2, length: ns.length / 2))
        func time(_ body: () -> Void) -> Double {
            let start = Date(); for _ in 0..<10 { body() }; return Date().timeIntervalSince(start) / 10 * 1000
        }
        let backspace = time { _ = MarkdownEditingCommands.backspace(text: text, selection: caret, markersHidden: true) }
        let enter = time { _ = MarkdownEditingCommands.newline(text: text, selection: caret) }
        let listEnter = time { _ = MarkdownEditingCommands.newline(text: text, selection: NSRange(location: NSMaxRange(item), length: 0)) }
        print(String(format: "structural-keys lines=%d backspace=%.2fms enter=%.2fms enter-in-list=%.1fms", text.components(separatedBy: "\n").count, backspace, enter, listEnter))
        if backspace > 2 || enter > 2 { print("PERF FAILURE: Backspace/Enter in a paragraph parse the document"); exit(1) }
    }
    // Typing next to a local image: the image must come from the cache, not the disk, on every pass
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("swash-perf-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("photo.png"))
        let body = String(repeating: "Paragraph text that is long enough to wrap a little in the editor.\n\n", count: 40)
        var t = body + "![photo](photo.png)\nCaption typed here\n\n" + body
        let b = Binding<String>(get: { t }, set: { t = $0 })
        let host = NSHostingView(rootView: SwashTextView(text: b, selectedRange: .constant(nil), selectionRect: .constant(nil), isStyled: true, flavor: .github, baseURL: folder.appendingPathComponent("doc.md")).frame(width: 600, height: 600))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false); win.contentView = host
        pump(0.8)
        let tv = findTextView(in: host)!; let c = tv.delegate as! SwashTextView.Coordinator
        let caption = (tv.string as NSString).range(of: "Caption typed here")
        tv.setSelectedRange(NSRange(location: NSMaxRange(caption), length: 0))
        var total = 0.0
        for ch in ["a", "b", "c", "d", "e"] {
            let start = Date()
            tv.insertText(ch, replacementRange: tv.selectedRange())
            c.highlightMarkdown(in: tv)
            tv.layoutManager!.ensureLayout(for: tv.textContainer!)
            total += Date().timeIntervalSince(start)
            pump(0.05)
        }
        print("keystroke-next-to-image lines=162 avg=\(Int(total / 5 * 1000))ms (2400×1600 PNG in the restyled block)")
        try? FileManager.default.removeItem(at: folder)
    }
    // Slack mrkdwn restyles the whole document per pass
    do {
        let section = "*Bold* and _italic_ with ~strike~ and `code` <https://s.com|a link>\n> quoted [!NOTE] text\n- [ ] task item\n1. numbered\n[^1]: footnote\n\n"
        var t = String(repeating: section, count: 150)
        let b = Binding<String>(get: { t }, set: { t = $0 })
        let host = NSHostingView(rootView: SwashTextView(text: b, selectedRange: .constant(nil), selectionRect: .constant(nil), isStyled: true, flavor: .slack).frame(width: 600, height: 600))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false); win.contentView = host
        pump(0.5)
        let tv = findTextView(in: host)!; let c = tv.delegate as! SwashTextView.Coordinator
        let start = Date(); for _ in 0..<3 { c.forceFullRestyle = true; c.highlightMarkdown(in: tv) }
        print("slack lines=\(t.components(separatedBy: "\n").count) full-restyle=\(Int(Date().timeIntervalSince(start) / 3 * 1000))ms")
    }
    // Split view: the preview while typing quickly. Measures CPU time for a burst of keystrokes,
    // so it includes every preview rebuild and re-measure, plus the final one after the pause
    do {
        final class Box: ObservableObject { @Published var text: String; init(_ t: String) { text = t } }
        struct Preview: View { @ObservedObject var box: Box; var body: some View { MarkdownPreviewView(text: box.text, flavor: .github) } }
        let section = "## Section\n\nSome **bold** and *italic* text with a [link](https://x.com) and `code`.\n\n- item one\n- item two\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n```swift\nlet x = 1\n```\n\n"
        let box = Box(String(repeating: section, count: 60))
        let host = NSHostingView(rootView: Preview(box: box).frame(width: 600, height: 600))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false); win.contentView = host
        pump(1.0)
        let cpuStart = clock()
        let wallStart = Date()
        for ch in "abcdefghij" {
            box.text += String(ch)
            pump(0.03)
        }
        pump(0.5)
        let cpu = Double(clock() - cpuStart) / Double(CLOCKS_PER_SEC) * 1000
        print("split-preview-typing lines=\(box.text.components(separatedBy: "\n").count) keystrokes=10 cpu=\(Int(cpu))ms wall=\(Int(Date().timeIntervalSince(wallStart) * 1000))ms")
    }
    let section = "## Section\n\nSome **bold** and *italic* text with a [link](https://x.com) and `code`.\n\n- item one\n- item two\n\n```swift\nlet x = 1\n```\n\n"
    for n in [10, 50, 200] {
        let md = String(repeating: section, count: n)
        var t = md
        let b = Binding<String>(get: { t }, set: { t = $0 })
        let host = NSHostingView(rootView: SwashTextView(text: b, selectedRange: .constant(nil), selectionRect: .constant(nil), isStyled: true, flavor: .github).frame(width: 600, height: 600))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 600)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false); win.contentView = host
        pump(0.5)
        let tv = findTextView(in: host)!; let c = tv.delegate as! SwashTextView.Coordinator
        let start = Date(); for _ in 0..<3 { c.forceFullRestyle = true; c.highlightMarkdown(in: tv) }
        let ms = Date().timeIntervalSince(start) / 3 * 1000
        print("lines=\(md.components(separatedBy: "\n").count) chars=\(md.count) full-restyle=\(Int(ms))ms")
        // Budget: must stay roughly linear (was 27 s at 2,200 lines before code ranges were precomputed)
        if n == 200 && ms > 500 { print("PERF FAILURE: \(Int(ms))ms exceeds 500ms budget at 2,200 lines"); exit(1) }
    }
}}
