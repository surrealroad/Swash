//
//  EditorTypography.swift
//  Swash
//
//  The reader-facing typography settings (font, text size, line width and colour theme), shared by
//  the Edit Text styler, the source editor and the Preview. Stored in UserDefaults; the defaults
//  reproduce the original hard-coded look exactly (system font, 14 pt, full width, system accent).
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum TypographyFont: String, CaseIterable, Identifiable {
    case system
    case serif
    case mono

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .serif: return "Serif (New York)"
        case .mono: return "Monospaced"
        }
    }
}

enum TypographyLineWidth: String, CaseIterable, Identifiable {
    case full
    case readable

    var id: String { rawValue }
    var title: String { self == .full ? "Full width" : "Readable column" }
}

/// Accent colours for the editor and preview. All are system colours (or dynamic colours), so they
/// follow Light and Dark Mode.
enum EditorTheme: String, CaseIterable, Identifiable {
    case system
    case graphite
    case ocean
    case forest
    case rose
    case paper

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System Accent"
        case .graphite: return "Graphite"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .rose: return "Rose"
        case .paper: return "Paper"
        }
    }

    /// Accent for code, quotes, tasks, footnotes and links; nil keeps each view's original colour.
    var accent: PlatformColor? {
        switch self {
        case .system: return nil
        case .graphite: return .systemGray
        case .ocean: return .systemTeal
        case .forest: return .systemGreen
        case .rose: return .systemPink
        case .paper: return .systemBrown
        }
    }

    /// Page colour; nil keeps the standard text background.
    var background: PlatformColor? {
        self == .paper ? Self.paperBackground : nil
    }

    /// One instance, so the editor can tell when its background already matches.
    private static let paperBackground = PlatformColor.appearanceAware(
        light: PlatformColor(srgbRed: 0.98, green: 0.955, blue: 0.9, alpha: 1),
        dark: PlatformColor(srgbRed: 0.16, green: 0.145, blue: 0.125, alpha: 1)
    )
}

struct EditorTypography: Hashable {
    var font: TypographyFont = .system
    var textSize: CGFloat = EditorTypography.defaultTextSize
    var lineWidth: TypographyLineWidth = .full
    var theme: EditorTheme = .system

    static let defaultTextSize: CGFloat = 14
    static let minTextSize: CGFloat = 10
    static let maxTextSize: CGFloat = 32
    /// Width of the readable column at the default text size; it grows with the text.
    static let readableWidth: CGFloat = 700

    enum Keys {
        static let font = "typographyFont"
        static let textSize = "typographyTextSize"
        static let lineWidth = "typographyLineWidth"
        static let theme = "typographyTheme"
    }

    /// The settings saved in the standard defaults (the app's own; extensions without an app group
    /// see only the defaults).
    static var current: EditorTypography {
        let defaults = UserDefaults.standard
        var typography = EditorTypography()
        if let raw = defaults.string(forKey: Keys.font), let font = TypographyFont(rawValue: raw) { typography.font = font }
        if defaults.object(forKey: Keys.textSize) != nil { typography.textSize = clampedSize(defaults.double(forKey: Keys.textSize)) }
        if let raw = defaults.string(forKey: Keys.lineWidth), let width = TypographyLineWidth(rawValue: raw) { typography.lineWidth = width }
        if let raw = defaults.string(forKey: Keys.theme), let theme = EditorTheme(rawValue: raw) { typography.theme = theme }
        return typography
    }

    /// Bigger / Smaller: steps the saved text size by `delta` points (0 restores the default).
    static func adjustTextSize(by delta: CGFloat) {
        let size = delta == 0 ? defaultTextSize : clampedSize(Double(current.textSize + delta))
        UserDefaults.standard.set(Double(size), forKey: Keys.textSize)
    }

    static func clampedSize(_ size: Double) -> CGFloat {
        min(maxTextSize, max(minTextSize, CGFloat(size.isFinite ? size : Double(defaultTextSize))))
    }

    /// Text size relative to the default.
    var scale: CGFloat { textSize / Self.defaultTextSize }

    /// A size designed for the default text size, scaled to this one (exact at the default).
    func scaled(_ size: CGFloat) -> CGFloat {
        scale == 1 ? size : (size * scale * 2).rounded() / 2
    }

    var readableColumnWidth: CGFloat { (Self.readableWidth * scale).rounded() }

    // MARK: AppKit / UIKit (editor)

    /// Body text font in the chosen family.
    func font(ofSize size: CGFloat, weight: PlatformFont.Weight = .regular) -> PlatformFont {
        switch font {
        case .system:
            return PlatformFont.systemFont(ofSize: size, weight: weight)
        case .serif:
            let base = PlatformFont.systemFont(ofSize: size, weight: weight)
            #if os(macOS)
            if let descriptor = base.fontDescriptor.withDesign(.serif), let serif = NSFont(descriptor: descriptor, size: size) {
                return serif
            }
            #else
            if let descriptor = base.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            #endif
            return base
        case .mono:
            return PlatformFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    /// The plain body font (and the default for text the styler does not touch).
    var bodyFont: PlatformFont { font(ofSize: textSize) }

    /// Source (Edit Markdown) mode stays monospaced; only its size follows the setting.
    var sourceFont: PlatformFont { PlatformFont.monospacedSystemFont(ofSize: scaled(13.5), weight: .regular) }

    var accentColor: PlatformColor { theme.accent ?? .accentTintColor }
    var linkColor: PlatformColor { theme.accent ?? .systemBlue }

    // MARK: SwiftUI (preview)

    var fontDesign: Font.Design {
        switch font {
        case .system: return .default
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }

    private var isDefaultSize: Bool { textSize == Self.defaultTextSize }

    /// The preview's body font (`.body` at the default settings). `design` overrides the family
    /// (block quotes are always serif).
    func previewFont(design: Font.Design? = nil) -> Font {
        let resolved = design ?? fontDesign
        if isDefaultSize {
            return design == nil && font == .system ? .body : .system(.body, design: resolved)
        }
        return .system(size: scaled(13), design: resolved)
    }

    /// A fixed-size preview font scaled with the text size.
    func previewFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design? = nil) -> Font {
        .system(size: scaled(size), weight: weight, design: design ?? .default)
    }

    var previewAccent: Color { theme.accent.map { Color(platformColor: $0) } ?? .accentColor }
    var previewBackground: Color {
        theme.background.map { Color(platformColor: $0) } ?? Color(PlatformColor.windowBackgroundColor).opacity(0.8)
    }
}

// MARK: - View › Bigger / Smaller / Actual Size

struct TypographyCommands: Commands {
    @AppStorage(EditorTypography.Keys.textSize) private var textSize: Double = Double(EditorTypography.defaultTextSize)

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            // ⌘= (the unshifted + key) also makes text bigger in the editor: see SwashNSTextView
            Button("Bigger") { textSize = Double(EditorTypography.clampedSize(textSize + 1)) }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(CGFloat(textSize) >= EditorTypography.maxTextSize)
            Button("Smaller") { textSize = Double(EditorTypography.clampedSize(textSize - 1)) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(CGFloat(textSize) <= EditorTypography.minTextSize)
            Button("Actual Size") { textSize = Double(EditorTypography.defaultTextSize) }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(CGFloat(textSize) == EditorTypography.defaultTextSize)
            Divider()
        }
    }
}

#if os(macOS)
extension SwashTextView.Coordinator {
    /// The theme's page colour (the standard text background unless the theme has its own).
    func applyThemeBackground(_ typography: EditorTypography, in textView: NSTextView) {
        let color = typography.theme.background ?? .textBackgroundColor
        guard textView.backgroundColor != color else { return }
        textView.backgroundColor = color
        textView.enclosingScrollView?.backgroundColor = color
    }
}
#endif
