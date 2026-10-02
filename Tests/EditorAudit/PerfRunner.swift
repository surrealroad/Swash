import Foundation
import SwiftUI
import AppKit
func pump(_ s: Double = 0.2) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func findTextView(in v: NSView) -> NSTextView? { if let tv = v as? NSTextView { return tv }; for s in v.subviews { if let f = findTextView(in: s) { return f } }; return nil }
@main struct PerfRunner { static func main() {
    _ = NSApplication.shared
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
        let start = Date(); for _ in 0..<3 { c.highlightMarkdown(in: tv) }
        let ms = Date().timeIntervalSince(start) / 3 * 1000
        print("lines=\(md.components(separatedBy: "\n").count) chars=\(md.count) highlight-per-keystroke=\(Int(ms))ms")
    }
}}
