// Headless checks for DocumentExporter: self-contained HTML and paginated PDF export.
// Run via scripts/run_export_tests.sh (sets SWASH_RENDER_RESOURCES to Swash/Rendering).
import AppKit
import PDFKit

@MainActor
func run() async {
    setvbuf(stdout, nil, _IONBF, 0)
    let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/export").absoluteURL
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    var failures = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }

    // A local image beside the document
    let docURL = out.appendingPathComponent("Sample.md")
    let pixel = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
        NSColor.systemRed.setFill(); rect.fill(); return true
    }
    if let tiff = pixel.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        try? png.write(to: out.appendingPathComponent("dot.png"))
    }
    let markdown = """
    # Export Sample

    Inline math $e^{i\\pi} + 1 = 0$ and a footnote.[^1]

    $$
    \\int_0^\\infty e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}
    $$

    > [!WARNING]
    > Alerts keep their colour.

    ```mermaid
    graph TD
      A[Start] --> B{Choice}
      B -->|Yes| C[Done]
    ```

    | Name | Value |
    | :--- | ---: |
    | One | 1 |

    - [x] Done
    - [ ] Not yet

    ![Dot](dot.png)

    [^1]: The footnote.
    """ + String(repeating: "\n\nFiller paragraph to push the document past one page. Lorem ipsum dolor sit amet, consectetur adipiscing elit.", count: 30)
    let source = DocumentExporter.Source(text: markdown, flavor: .github, fileURL: docURL, title: "Export Sample")

    let body = DocumentExporter.bodyHTML(for: source)
    check("alert markup", body.contains("markdown-alert markdown-alert-warning"))
    check("local image embedded", body.contains("src=\"data:image/png;base64,"))
    check("copy-as-HTML keeps image paths", DocumentExporter.bodyHTML(for: source, embedImages: false).contains("src=\"dot.png\""))
    check("remote images untouched", DocumentExporter.embeddedImageSource("https://example.com/a.png", folder: nil) == "https://example.com/a.png")

    do {
        let html = try await DocumentExporter.standaloneHTML(for: source)
        try html.write(to: out.appendingPathComponent("Sample.html"), atomically: true, encoding: .utf8)
        check("HTML has typeset math", html.contains("class=\"katex\""))
        check("HTML has display math", html.contains("math-display"))
        check("HTML embeds KaTeX fonts", html.contains("data:font/woff2;base64,"))
        check("HTML has Mermaid SVG", html.contains("<svg") && html.contains("class=\"mermaid\""))
        check("HTML has no scripts", !html.contains("<script"))
        check("HTML has footnotes", html.contains("class=\"footnotes\""))
        check("HTML is self-contained", !html.contains("href=\"katex") && !html.contains("src=\"dot.png\""))
    } catch {
        check("standalone HTML", false, error.localizedDescription)
    }

    let pdfURL = out.appendingPathComponent("Sample.pdf")
    try? FileManager.default.removeItem(at: pdfURL)
    do {
        try await DocumentExporter.exportPDF(source, to: pdfURL)
        let pdf = PDFDocument(url: pdfURL)
        check("PDF written", pdf != nil)
        let pages = pdf?.pageCount ?? 0
        check("PDF is paginated", pages >= 2, "\(pages) pages")
        let text = pdf?.string ?? ""
        check("PDF has the text", text.contains("Export Sample") && text.contains("Alerts keep their colour"))
        if let page = pdf?.page(at: 0) {
            let image = page.thumbnail(of: NSSize(width: 850, height: 1100), for: .mediaBox)
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: out.appendingPathComponent("Sample-page1.png"))
            }
        }
    } catch {
        check("PDF export", false, error.localizedDescription)
    }

    print(failures == 0 ? "All export checks passed" : "\(failures) export check(s) failed")
    exit(failures == 0 ? 0 : 1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in await run() }
app.run()
