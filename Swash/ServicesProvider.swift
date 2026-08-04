//
//  ServicesProvider.swift
//  Swash
//

import AppKit
import Foundation

@objc class ServicesProvider: NSObject {
    @objc func createDocumentFromService(_ pboard: NSPasteboard, userData: String?, error: NSErrorPointer) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "Shared Note \(Date().formatted(date: .numeric, time: .standard)).md".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            NSDocumentController.shared.openDocument(withContentsOf: fileURL, display: true) { _, _, _ in }
        } catch {
            print("Failed to write service document: \(error)")
        }
    }
}
