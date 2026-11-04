//
//  PreviewViewController.swift
//  SwashQuickLookExtension
//
//  Created by Jack James on 01/08/2026.
//

import Cocoa
import Quartz
import QuickLookUI
import SwiftUI

class PreviewViewController: NSViewController, QLPreviewingController {

    /// Quick Look shows at most this much of a file, so pressing Space on a huge file stays instant.
    static let maximumPreviewBytes = 256 * 1024

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Reading, decoding and parsing happen off the main thread; only the view is built on it.
        // Math and Mermaid show as source: the extension doesn't bundle the WebKit renderer.
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let content = try Self.previewText(of: url)
                let document = MarkdownPreviewView.parse(content, flavor: .github)
                DispatchQueue.main.async {
                    let previewView = MarkdownPreviewView(text: content, flavor: .github, baseURL: url.deletingLastPathComponent(), preparsed: document)
                    let hostingController = NSHostingController(rootView: previewView)

                    self.addChild(hostingController)
                    hostingController.view.frame = self.view.bounds
                    hostingController.view.autoresizingMask = [.width, .height]
                    self.view.addSubview(hostingController.view)

                    handler(nil)
                }
            } catch {
                handler(error)
            }
        }
    }

    /// The start of the file as text, cut at a line break when it is longer than the limit, with a
    /// note saying how much is shown.
    static func previewText(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = try handle.read(upToCount: maximumPreviewBytes + 1) ?? Data()
        let truncated = data.count > maximumPreviewBytes
        if truncated {
            data = data.prefix(maximumPreviewBytes)
            if let lastNewline = data.lastIndex(of: 0x0A) {
                data = data.prefix(upTo: lastNewline)
            }
        }
        var content: String
        if let utf8String = String(data: data, encoding: .utf8) {
            content = utf8String
        } else if let latin1String = String(data: data, encoding: .isoLatin1) {
            content = latin1String
        } else {
            content = String(decoding: data, as: UTF8.self)
        }
        if truncated {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            let total = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            let shown = ByteCountFormatter.string(fromByteCount: Int64(maximumPreviewBytes), countStyle: .file)
            content += "\n\n---\n\n*Preview shows the first \(shown) of \(total). Open the file in Swash to see all of it.*\n"
        }
        return content
    }
}
