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
    
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let data = try Data(contentsOf: url)
            let content: String
            if let utf8String = String(data: data, encoding: .utf8) {
                content = utf8String
            } else if let latin1String = String(data: data, encoding: .isoLatin1) {
                content = latin1String
            } else {
                content = String(decoding: data, as: UTF8.self)
            }
            
            DispatchQueue.main.async {
                let previewView = MarkdownPreviewView(text: content, flavor: .github)
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
