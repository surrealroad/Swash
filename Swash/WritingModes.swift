//
//  WritingModes.swift
//  Swash
//
//  Focus mode (dims all but the current paragraph or sentence), typewriter scrolling (keeps the
//  caret line centred) and distraction-free writing (full screen, no toolbar, a readable column).
//  Focus and typewriter are app-wide settings in the View menu; distraction-free is per window.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum FocusUnit: String, CaseIterable, Identifiable {
    case paragraph
    case sentence

    var id: String { rawValue }
    var title: String { self == .paragraph ? "Paragraph" : "Sentence" }
}

/// What the editor applies on top of the document's styling.
struct WritingOptions: Equatable {
    var focus: FocusUnit? = nil
    var typewriter = false
    /// Centres the text in a column of `readableWidth` points.
    var readableColumn = false

    static let readableWidth: CGFloat = 700
}

enum WritingDefaults {
    static let focusMode = "focusMode"
    static let focusUnit = "focusUnit"
    static let typewriterScrolling = "typewriterScrolling"
}

extension FocusUnit {
    /// The part of `text` that stays at full strength around `selection`.
    static func range(_ unit: FocusUnit, around selection: NSRange, in text: NSString) -> NSRange {
        let paragraph = text.paragraphRange(for: selection)
        guard unit == .sentence, paragraph.length > 0 else { return paragraph }
        var sentences: [NSRange] = []
        text.enumerateSubstrings(in: paragraph, options: [.bySentences, .substringNotRequired]) { _, _, enclosing, _ in
            sentences.append(enclosing)
        }
        guard let last = sentences.last else { return paragraph }
        func sentence(at location: Int) -> NSRange {
            sentences.first { location >= $0.location && location < NSMaxRange($0) } ?? last
        }
        let first = sentence(at: selection.location)
        let end = sentence(at: max(selection.location, NSMaxRange(selection) - 1))
        return NSUnionRange(first, end)
    }
}

extension Notification.Name {
    /// Posted with the window as object and `isOn` in userInfo, so a folder window can hide its sidebar.
    static let distractionFreeWritingDidChange = Notification.Name("SwashDistractionFreeWritingDidChange")
}

struct DistractionFreeToggle {
    let isOn: Bool
    let toggle: () -> Void
}

struct DistractionFreeToggleKey: FocusedValueKey {
    typealias Value = DistractionFreeToggle
}

extension FocusedValues {
    var distractionFreeToggle: DistractionFreeToggle? {
        get { self[DistractionFreeToggleKey.self] }
        set { self[DistractionFreeToggleKey.self] = newValue }
    }
}

#if os(macOS)
/// View › Focus Mode, Typewriter Scrolling and Distraction-Free Writing.
struct WritingModeCommands: Commands {
    @AppStorage(WritingDefaults.focusMode) private var focusMode = false
    @AppStorage(WritingDefaults.focusUnit) private var focusUnit: FocusUnit = .paragraph
    @AppStorage(WritingDefaults.typewriterScrolling) private var typewriterScrolling = false
    @FocusedValue(\.distractionFreeToggle) private var distractionFree

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Toggle("Focus Mode", isOn: $focusMode)
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Picker("Focus On", selection: $focusUnit) {
                ForEach(FocusUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            Toggle("Typewriter Scrolling", isOn: $typewriterScrolling)
                .keyboardShortcut("t", modifiers: [.command, .control])
            Button(distractionFree?.isOn == true ? "Exit Distraction-Free Writing" : "Distraction-Free Writing") {
                distractionFree?.toggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .control, .shift])
            .disabled(distractionFree == nil)
            Divider()
        }
    }
}

extension SwashTextView.Coordinator {
    /// Applies changed writing options to the text view.
    func applyWritingOptions(_ options: WritingOptions, in textView: NSTextView) {
        guard options != lastWritingOptions else { return }
        lastWritingOptions = options
        updateWritingInsets(in: textView)
        applyFocus(in: textView)
        centerCaret(in: textView)
    }

    /// Typewriter scrolling needs half a screen of space above and below the text so the first and
    /// last lines can be centred; the readable column insets the sides.
    func updateWritingInsets(in textView: NSTextView) {
        guard let clip = textView.enclosingScrollView?.contentView else { return }
        let options = parent.writingOptions
        let width = options.readableColumn ? max(20, ((clip.bounds.width - WritingOptions.readableWidth) / 2).rounded()) : 20
        let height = options.typewriter ? max(20, (clip.bounds.height / 2).rounded()) : 20
        let inset = NSSize(width: width, height: height)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
            centerCaret(in: textView)
        }
    }

    /// Dims everything outside the focused paragraph or sentence. Temporary attributes leave the
    /// document's styling alone; markers hidden with a clear colour stay hidden.
    func applyFocus(in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        guard let unit = parent.writingOptions.focus, storage.length > 0 else { return }
        let focus = FocusUnit.range(unit, around: textView.selectedRange(), in: storage.string as NSString)
        let dimmed = [NSRange(location: 0, length: focus.location),
                      NSRange(location: NSMaxRange(focus), length: storage.length - NSMaxRange(focus))]
        let color = NSColor.tertiaryLabelColor
        for range in dimmed where range.length > 0 {
            storage.enumerateAttribute(.foregroundColor, in: range, options: []) { value, run, _ in
                if (value as? NSColor) == .clear { return }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: run)
            }
        }
    }

    /// Scrolls so the caret's line sits in the middle of the view (not while the mouse is selecting).
    func centerCaret(in textView: NSTextView) {
        guard parent.writingOptions.typewriter, NSEvent.pressedMouseButtons & 1 == 0,
              let layoutManager = textView.layoutManager, let storage = textView.textStorage,
              let scrollView = textView.enclosingScrollView else { return }
        let location = textView.selectedRange().location
        var line: NSRect
        if location >= storage.length, !layoutManager.extraLineFragmentRect.isEmpty {
            line = layoutManager.extraLineFragmentRect
        } else if layoutManager.numberOfGlyphs > 0 {
            let glyph = layoutManager.glyphIndexForCharacter(at: min(location, storage.length - 1))
            line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        } else {
            return
        }
        line.origin.y += textView.textContainerOrigin.y
        let clip = scrollView.contentView
        let maxY = max(0, textView.frame.height - clip.bounds.height)
        let y = min(max(0, (line.midY - clip.bounds.height / 2).rounded()), maxY)
        guard abs(clip.bounds.origin.y - y) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }
}
#endif
