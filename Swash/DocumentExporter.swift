//
//  DocumentExporter.swift
//  Swash
//
//  Exports a document as a self-contained HTML file or a PDF, prints it, and copies it as rich
//  text or HTML. The Markdown is rendered to HTML with local images embedded, then an offscreen
//  WKWebView typesets math and Mermaid diagrams with the bundled KaTeX and Mermaid
//  (Swash/Rendering/swash-export.*), so exports match the Preview.
//

import Foundation
import WebKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class DocumentExporter: NSObject {
    struct Source {
        var text: String
        var flavor: MarkdownFlavor
        /// The document's file, for resolving relative image paths.
        var fileURL: URL?
        var title: String
    }

    enum ExportError: LocalizedError {
        case resourcesMissing
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .resourcesMissing: return "Swash’s rendering resources are missing."
            case .failed(let message): return message
            }
        }
    }

    // MARK: HTML

    /// The document body as HTML. Local images are embedded as data URLs when `embedImages` is set.
    static func bodyHTML(for source: Source, embedImages: Bool = true) -> String {
        let document = MarkdownPreviewView.parse(source.text, flavor: source.flavor)
        var options = MarkdownHTMLRenderer.Options()
        options.alertMarkup = true
        if embedImages {
            let folder = source.fileURL?.deletingLastPathComponent()
            options.imageSource = { embeddedImageSource($0, folder: folder) }
        }
        return MarkdownHTMLRenderer.render(document, options: options)
    }

    /// A self-contained HTML file: typeset math and diagrams, embedded images and inline styles.
    static func standaloneHTML(for source: Source) async throws -> String {
        let exporter = DocumentExporter()
        let result = try await exporter.typeset(source)
        var styles = try resourceText("swash-export.css")
        if result.usesKaTeX {
            styles += "\n" + (try katexStylesWithEmbeddedFonts())
        }
        return page(title: source.title, styles: styles, body: result.html)
    }

    /// HTML for the clipboard: the rendered body with the export styles, without typesetting.
    static func clipboardHTML(for source: Source) -> String {
        let styles = (try? resourceText("swash-export.css")) ?? ""
        return page(title: source.title, styles: styles, body: bodyHTML(for: source))
    }

    private static func page(title: String, styles: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Swash">
        <title>\(MarkdownSyntax.escapeHTML(title))</title>
        <style>
        \(styles)
        </style>
        </head>
        <body>
        <article class="swash-document">
        \(body)
        </article>
        </body>
        </html>

        """
    }

    /// A data URL for a local image, or the destination unchanged for remote images and missing files.
    static func embeddedImageSource(_ destination: String, folder: URL?) -> String {
        let normalized = MarkdownSyntax.normalizeURI(destination)
        let fileURL: URL?
        if let url = URL(string: destination) ?? URL(string: normalized), let scheme = url.scheme {
            fileURL = scheme == "file" ? url : nil
        } else if destination.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: destination.removingPercentEncoding ?? destination)
        } else if let folder {
            _ = FolderAccessManager.shared.ensureAccess(for: folder)
            fileURL = folder.appendingPathComponent(destination.removingPercentEncoding ?? destination)
        } else {
            fileURL = nil
        }
        guard let fileURL,
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 25_000_000,
              let data = try? Data(contentsOf: fileURL) else { return normalized }
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    // MARK: Resources

    private static func resourceURL(_ name: String) throws -> URL {
        guard let directory = RichContentRenderer.resourceDirectory else { throw ExportError.resourcesMissing }
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ExportError.resourcesMissing }
        return url
    }

    private static func resourceText(_ name: String) throws -> String {
        try String(contentsOf: resourceURL(name), encoding: .utf8)
    }

    /// KaTeX's stylesheet with each `url(KaTeX_….woff2)` replaced by the font as a data URL.
    private static func katexStylesWithEmbeddedFonts() throws -> String {
        let css = try resourceText("katex.min.css") as NSString
        let regex = try NSRegularExpression(pattern: #"url\((KaTeX_[A-Za-z0-9_-]+\.woff2)\)"#)
        let result = NSMutableString(string: css)
        for match in regex.matches(in: css as String, range: NSRange(location: 0, length: css.length)).reversed() {
            let name = css.substring(with: match.range(at: 1))
            guard let data = try? Data(contentsOf: resourceURL(name)) else { continue }
            result.replaceCharacters(in: match.range, with: "url(data:font/woff2;base64,\(data.base64EncodedString()))")
        }
        return result as String
    }

    // MARK: Typesetting

    struct TypesetResult {
        let html: String
        let usesKaTeX: Bool
    }

    private var webView: WKWebView?
    private var loadContinuation: CheckedContinuation<Void, Error>?
    #if os(macOS)
    /// Offscreen window the web view lives in while it is laid out and printed.
    private var hostWindow: NSWindow?
    private var printContinuation: CheckedContinuation<Bool, Never>?
    #endif

    /// Loads the export page in an offscreen web view and typesets the document into it.
    @discardableResult
    func typeset(_ source: Source) async throws -> TypesetResult {
        let page = try Self.resourceURL("swash-export.html")
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        #if os(iOS)
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        #endif
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 820, height: 1100), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        #if os(macOS)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 820, height: 1100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        hostWindow = window
        #endif

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        let value = try await view.callAsyncJavaScript(
            "return await swashTypeset(html, title)",
            arguments: ["html": Self.bodyHTML(for: source), "title": source.title],
            contentWorld: .page
        )
        guard let info = value as? [String: Any], let html = info["html"] as? String else {
            throw ExportError.failed("The document couldn’t be typeset.")
        }
        return TypesetResult(html: html, usesKaTeX: info["usesKaTeX"] as? Bool ?? false)
    }

    private func finishLoading(_ error: Error?) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    // MARK: PDF and printing

    #if os(macOS)
    /// Writes a paginated PDF of the document to `url`.
    static func exportPDF(_ source: Source, to url: URL) async throws {
        let exporter = DocumentExporter()
        try await exporter.typeset(source)
        let printInfo = exporter.printInfo()
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        guard try await exporter.runPrintOperation(printInfo, showPanels: false, in: nil) else {
            throw ExportError.failed("The PDF couldn’t be created.")
        }
    }

    /// Shows the print panel for the document, as a sheet on `window`.
    static func print(_ source: Source, window: NSWindow?) async throws {
        let exporter = DocumentExporter()
        try await exporter.typeset(source)
        _ = try await exporter.runPrintOperation(exporter.printInfo(), showPanels: true, in: window)
    }

    private func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 50
        info.bottomMargin = 50
        info.leftMargin = 46
        info.rightMargin = 46
        return info
    }

    /// WKWebView only prints through `runModal`; `run()` produces blank pages.
    private func runPrintOperation(_ info: NSPrintInfo, showPanels: Bool, in window: NSWindow?) async throws -> Bool {
        guard let webView, let host = hostWindow else { throw ExportError.failed("The document couldn’t be typeset.") }
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = showPanels
        operation.showsProgressPanel = showPanels
        operation.jobTitle = webView.title ?? ""
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling])
        // The operation's view needs a size, or it prints nothing
        operation.view?.frame = webView.bounds
        return await withCheckedContinuation { continuation in
            printContinuation = continuation
            operation.runModal(for: window ?? host, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    /// AppKit calls this on the print operation's own thread when no panel is shown.
    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.printContinuation?.resume(returning: success)
                self.printContinuation = nil
                self.hostWindow?.contentView = nil
                self.hostWindow = nil
            }
        }
    }
    #else
    /// A paginated PDF of the document, on the locale's usual paper size.
    static func exportPDF(_ source: Source) async throws -> Data {
        let exporter = DocumentExporter()
        try await exporter.typeset(source)
        guard let webView = exporter.webView else { throw ExportError.failed("The PDF couldn’t be created.") }
        let usesLetter = ["US", "CA", "MX", "PH", "CL", "CO"].contains(Locale.current.region?.identifier ?? "")
        let paper = usesLetter ? CGRect(x: 0, y: 0, width: 612, height: 792) : CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 46, dy: 50)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, [kCGPDFContextTitle as String: source.title])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// Shows the system print sheet for the document.
    static func print(_ source: Source) async throws {
        let exporter = DocumentExporter()
        try await exporter.typeset(source)
        guard let webView = exporter.webView else { return }
        let info = UIPrintInfo.printInfo()
        info.jobName = source.title
        info.outputType = .general
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printFormatter = webView.viewPrintFormatter()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // The exporter (and its web view) stays alive until the sheet is dismissed
            controller.present(animated: true) { _, _, _ in
                withExtendedLifetime(exporter) { continuation.resume() }
            }
        }
    }
    #endif

    // MARK: Clipboard

    /// Puts the document on the clipboard as rich text (HTML, plus RTF on the Mac) with the Markdown as plain text.
    static func copyRichText(_ source: Source) {
        let html = clipboardHTML(for: source)
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(html, forType: .html)
        if let data = html.data(using: .utf8),
           let attributed = NSAttributedString(html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil),
           let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]) {
            item.setData(rtf, forType: .rtf)
        }
        item.setString(source.text, forType: .string)
        pasteboard.writeObjects([item])
        #else
        UIPasteboard.general.items = [[
            UTType.html.identifier: html,
            UTType.utf8PlainText.identifier: source.text,
        ]]
        #endif
    }

    /// Puts the document's HTML source on the clipboard as plain text.
    static func copyHTML(_ source: Source) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(bodyHTML(for: source, embedImages: false), forType: .string)
    }
}

extension DocumentExporter: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoading(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoading(error)
    }

    /// Links in the page are inert: the exporter never navigates away from it.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.navigationType == .other ? .allow : .cancel
    }
}
