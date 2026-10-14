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

/// Semantic colours under one name on both platforms (UIKit spells them `label`, `tintColor`…).
extension NSColor {
    static var primaryTextColor: NSColor { .labelColor }
    static var secondaryTextColor: NSColor { .secondaryLabelColor }
    static var tertiaryTextColor: NSColor { .tertiaryLabelColor }
    static var accentTintColor: NSColor { .controlAccentColor }
    static var separatorLineColor: NSColor { .separatorColor }
}

extension NSFont {
    /// The italic variant of `font` (the font itself when the family has none).
    static func italicVariant(of font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
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
    static var primaryTextColor: UIColor { .label }
    static var secondaryTextColor: UIColor { .secondaryLabel }
    static var tertiaryTextColor: UIColor { .tertiaryLabel }
    static var accentTintColor: UIColor { .tintColor }
    static var separatorLineColor: UIColor { .separator }
}

extension UIFont {
    /// The italic variant of `font` (the font itself when the family has none).
    static func italicVariant(of font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) else { return font }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }
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
