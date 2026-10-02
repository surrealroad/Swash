// Headless checks for RichContentRenderer: KaTeX and Mermaid render offline to images.
// Run via scripts/run_rich_render_tests.sh (sets SWASH_RENDER_RESOURCES to Swash/Rendering).
import AppKit
import SwiftUI

final class TextBox { var text: String; init(_ t: String) { text = t } }
var windows: [NSWindow] = []

func findTextView(in v: NSView) -> NSTextView? {
    if let tv = v as? NSTextView { return tv }
    for s in v.subviews { if let f = findTextView(in: s) { return f } }
    return nil
}

@MainActor
func wait(timeout: Double = 8, until condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return condition()
}

@MainActor
func snapshot(_ view: NSView, to url: URL) {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

/// Rich previews in the editor's storage: (character, info).
@MainActor
func previews(in tv: NSTextView) -> [(Int, RichPreviewInfo)] {
    var found: [(Int, RichPreviewInfo)] = []
    tv.textStorage?.enumerateAttribute(.richPreview, in: NSRange(location: 0, length: tv.textStorage?.length ?? 0), options: []) { value, range, _ in
        if let info = value as? RichPreviewInfo { found.append((range.location, info)) }
    }
    return found
}

@MainActor
func opaquePixelFraction(_ image: NSImage) -> Double {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
    let rep = NSBitmapImageRep(cgImage: cg)
    var opaque = 0, total = 0
    let step = max(1, min(rep.pixelsWide, rep.pixelsHigh) / 40)
    for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
        for x in stride(from: 0, to: rep.pixelsWide, by: step) {
            total += 1
            if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.1 { opaque += 1 }
        }
    }
    return total == 0 ? 0 : Double(opaque) / Double(total)
}

@MainActor
func run() async {
    let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/rich-render")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }
    func save(_ image: NSImage, _ name: String) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: out.appendingPathComponent(name + ".png"))
    }
    check("resources found", RichContentRenderer.isAvailable)
    let renderer = RichContentRenderer.shared

    let cases: [(String, RichContentRenderer.Request)] = [
        ("inline-fraction", .init(kind: .inlineMath, source: "\\frac{a}{b} + \\sqrt{x^2+1}", dark: false)),
        ("display-integral", .init(kind: .displayMath, source: "\\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}", dark: false, fontSize: 15)),
        ("display-matrix-dark", .init(kind: .displayMath, source: "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}", dark: true, fontSize: 15)),
        ("chem", .init(kind: .inlineMath, source: "\\ce{H2O}", dark: false)),
        ("mermaid-flow", .init(kind: .mermaid, source: "graph TD\n  A[Start] --> B{Choice}\n  B -->|Yes| C[Done]\n  B -->|No| A", dark: false)),
        ("mermaid-sequence-dark", .init(kind: .mermaid, source: "sequenceDiagram\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi", dark: true)),
    ]
    for (name, request) in cases {
        let start = Date()
        let outcome = await renderer.render(request)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        switch outcome {
        case .rendered(let r):
            save(r.image, name)
            let fraction = opaquePixelFraction(r.image)
            check("\(name) renders", r.image.size.width > 4 && r.image.size.height > 4 && fraction > 0.005,
                  "\(Int(r.image.size.width))×\(Int(r.image.size.height))pt, baseline \(String(format: "%.1f", r.baseline)), ink \(String(format: "%.3f", fraction)), \(ms) ms")
            check("\(name) has a transparent background", fraction < 0.98)
        case .failed(let message):
            check("\(name) renders", false, message)
        }
    }

    // Inline math baseline sits inside the image, with some descent for the fraction
    if let r = await renderer.render(cases[0].1).rendered {
        check("inline baseline within image", r.baseline > 0 && r.baseline < r.image.size.height, "descent \(r.descent)")
    }
    // Cached results do not re-render
    let before = renderer.renderCount
    _ = await renderer.render(cases[1].1)
    check("cache hit avoids a second snapshot", renderer.renderCount == before)
    // Invalid input fails cleanly, and the renderer keeps working afterwards
    if case .failed(let message) = await renderer.render(.init(kind: .displayMath, source: "\\frac{", dark: false)) {
        check("invalid TeX fails cleanly", !message.isEmpty, message)
    } else { check("invalid TeX fails cleanly", false) }
    if case .failed(let message) = await renderer.render(.init(kind: .mermaid, source: "graph TD\n A -->", dark: false)) {
        check("invalid Mermaid fails cleanly", !message.isEmpty, String(message.prefix(80)))
    } else { check("invalid Mermaid fails cleanly", false) }
    check("renders after a failure", await renderer.render(.init(kind: .inlineMath, source: "x_1", dark: false)).rendered != nil)
    // Concurrent identical requests share one render
    let shared = RichContentRenderer.Request(kind: .inlineMath, source: "e^{i\\pi}+1=0", dark: false)
    let countBefore = renderer.renderCount
    async let a = renderer.render(shared)
    async let b = renderer.render(shared)
    let (ra, rb) = await (a, b)
    check("duplicate requests coalesce", ra.rendered != nil && rb.rendered != nil && renderer.renderCount == countBefore + 1)

    // MARK: Edit Text
    let source = "# Math\n\n$$\n\\sum_{i=1}^n i\n$$\n\nText after\n\n```mermaid\ngraph LR\n  A --> B\n```\n\nEnd\n"
    let box = TextBox(source)
    let binding = Binding<String>(get: { box.text }, set: { box.text = $0 })
    let editor = SwashTextView(text: binding, selectedRange: .constant(nil), selectionRect: .constant(nil),
                               scrollOriginY: .constant(0), isStyled: true, flavor: .github)
    let host = NSHostingView(rootView: editor.frame(width: 600, height: 700))
    host.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    windows.append(window)
    host.layoutSubtreeIfNeeded()
    let tv = findTextView(in: host)!
    window.makeFirstResponder(tv)
    let coordinator = tv.delegate as! SwashTextView.Coordinator
    let settled = await wait { previews(in: tv).count == 2 && previews(in: tv).allSatisfy { $0.1.alpha == 1 } && coordinator.pendingRichPreviews.isEmpty }
    check("editor shows rendered math and Mermaid", settled, "\(previews(in: tv).map { "\(Int($0.1.size.width))×\(Int($0.1.size.height)) α\($0.1.alpha)" })")
    check("rendering leaves the Markdown untouched", tv.string == source && box.text == source)
    if let (location, info) = previews(in: tv).first, let lm = tv.layoutManager {
        let style = tv.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        check("space is reserved below the formula", (style?.paragraphSpacing ?? 0) >= info.size.height, "spacing \(style?.paragraphSpacing ?? 0)")
        let after = (tv.string as NSString).range(of: "Text after")
        let mathLine = lm.lineFragmentUsedRect(forGlyphAt: lm.glyphIndexForCharacter(at: location), effectiveRange: nil)
        let afterLine = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: after.location), effectiveRange: nil)
        check("following text sits below the formula", afterLine.minY >= mathLine.maxY + info.size.height, "\(afterLine.minY) vs \(mathLine.maxY + info.size.height)")
    }
    snapshot(host, to: out.appendingPathComponent("editor.png"))

    // Editing the formula: the previous rendering stays (dimmed) until the new one lands
    let firstWidth = previews(in: tv).first?.1.size.width ?? 0
    let passes = coordinator.incrementalPassCount
    let caret = (tv.string as NSString).range(of: "^n i")
    tv.setSelectedRange(NSRange(location: NSMaxRange(caret), length: 0))
    tv.insertText(" + \\frac{1}{2}", replacementRange: tv.selectedRange())
    let newWidth = await wait { (previews(in: tv).first?.1.alpha ?? 0) == 1 && (previews(in: tv).first?.1.size.width ?? 0) > firstWidth + 5 }
    check("edited formula re-renders", newWidth, "width \(firstWidth) → \(previews(in: tv).first?.1.size.width ?? 0)")
    check("re-render restyles incrementally", coordinator.incrementalPassCount > passes, "\(coordinator.incrementalPassCount - passes) incremental passes")
    check("caret stays put after the re-render", tv.selectedRange().location == NSMaxRange(caret) + " + \\frac{1}{2}".utf16.count)

    // A broken formula keeps the last good rendering (dimmed) and shows the error
    tv.insertText(" \\frac{", replacementRange: tv.selectedRange())
    let showsError = await wait { previews(in: tv).first?.1.error != nil }
    let broken = previews(in: tv).first?.1
    check("invalid TeX shows its error", showsError, broken?.error ?? "")
    check("…over the last good rendering", (broken?.size.width ?? 0) > 0 && (broken?.alpha ?? 1) < 1)
    snapshot(host, to: out.appendingPathComponent("editor-error.png"))

    // Undo restores the source; renders never enter the undo stack
    tv.undoManager?.undo()
    tv.undoManager?.undo()
    _ = await wait(timeout: 2) { tv.string == source }
    check("undo returns to the original source", tv.string == source, tv.string.debugDescription)

    // MARK: Preview
    let preview = NSHostingView(rootView: MarkdownPreviewView(text: "Inline $e^{i\\pi} + 1 = 0$ math.\n\n## Heading with $x^2$\n\n" + source, flavor: .github).frame(width: 600, height: 700))
    preview.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
    let previewWindow = NSWindow(contentRect: preview.frame, styleMask: [.titled], backing: .buffered, defer: false)
    previewWindow.contentView = preview
    windows.append(previewWindow)
    // The Preview follows the system appearance, so the cache keys do too
    let dark = preview.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let inline = RichContentRenderer.Request(kind: .inlineMath, source: "e^{i\\pi} + 1 = 0", dark: dark, fontSize: 13)
    let previewReady = await wait { renderer.cached(inline)?.rendered != nil && renderer.cached(.init(kind: .mermaid, source: "graph LR\n  A --> B", dark: dark))?.rendered != nil }
    try? await Task.sleep(nanoseconds: 300_000_000)
    check("preview requests inline math and diagrams", previewReady)
    // Inline math in a heading renders at the heading's size (H2 = 20pt), not the body's
    let headingMath = RichContentRenderer.Request(kind: .inlineMath, source: "x^2", dark: dark, fontSize: 20)
    let headingReady = await wait { renderer.cached(headingMath)?.rendered != nil }
    let bodyMath = await renderer.render(.init(kind: .inlineMath, source: "x^2", dark: dark, fontSize: 13)).rendered
    let headingHeight = renderer.cached(headingMath)?.rendered?.image.size.height ?? 0
    check("heading inline math follows the heading size", headingReady && headingHeight > (bodyMath?.image.size.height ?? .infinity) * 1.3,
          "\(headingHeight)pt vs \(bodyMath?.image.size.height ?? 0)pt")
    snapshot(preview, to: out.appendingPathComponent("preview.png"))

    print("RICH RENDER: \(failures == 0 ? "all passed" : "\(failures) failed") (images in \(out.path))")
    exit(failures == 0 ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in await run() }
app.run()
