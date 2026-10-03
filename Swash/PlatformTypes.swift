//
//  PlatformTypes.swift
//  Swash
//
//  Type names and helpers shared by the macOS (AppKit) and iOS/iPadOS (UIKit) builds, so
//  rendering code can be written once. Platform-only behaviour stays behind #if os(...).
//

import SwiftUI

#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformImage = NSImage

extension NSColor {
    /// Secondary text colour under one name on both platforms (`secondaryLabel` in UIKit).
    static var secondaryTextColor: NSColor { .secondaryLabelColor }
}

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

enum PlatformPasteboard {
    static func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static var string: String? {
        NSPasteboard.general.string(forType: .string)
    }
}

#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformImage = UIImage

/// AppKit's semantic colour names, so shared views can use one spelling.
extension UIColor {
    static var textColor: UIColor { .label }
    static var windowBackgroundColor: UIColor { .systemBackground }
    static var textBackgroundColor: UIColor { .systemBackground }
    static var controlBackgroundColor: UIColor { .secondarySystemBackground }
    static var underPageBackgroundColor: UIColor { .secondarySystemBackground }
    static var secondaryTextColor: UIColor { .secondaryLabel }
}

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

extension UIImage {
    /// AppKit spelling of `UIImage(contentsOfFile:)` for file URLs.
    convenience init?(contentsOf url: URL) {
        guard url.isFileURL else { return nil }
        self.init(contentsOfFile: url.path)
    }
}

enum PlatformPasteboard {
    static func setString(_ string: String) {
        UIPasteboard.general.string = string
    }

    static var string: String? {
        UIPasteboard.general.string
    }
}
#endif
