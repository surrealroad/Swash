//
//  SourceTextView.swift
//  Swash
//
//  The iOS and iPadOS Markdown source editor: a UITextView on TextKit 1 (the same text system
//  as the macOS editor) with Markdown-aware Return, Backspace and Tab, a formatting bar above
//  the keyboard and formatting actions in the edit menu.
//

#if os(iOS)
import SwiftUI
import UIKit

/// Lets SwiftUI apply edits to the live text view, so they go through UIKit's undo manager and
/// keep the selection (the iOS counterpart of `SwashEditorController`, GOTCHAS #10).
@MainActor
final class SourceEditorController {
    fileprivate weak var textView: UITextView?
    /// Called by the formatting bar and edit menu; set by the hosting view.
    var onFormatCommand: ((FormatCommand) -> Void)?

    var selection: NSRange {
        textView?.selectedRange ?? NSRange(location: 0, length: 0)
    }

    var isAttached: Bool { textView != nil }

    /// Applies an edit as one undoable change: only the span that differs is replaced.
    func apply(_ edit: MarkdownEdit, actionName: String) {
        guard let textView = textView else { return }
        textView.applyMinimalEdit(edit, actionName: actionName)
    }

    func focus() {
        textView?.becomeFirstResponder()
    }
}

extension UITextView {
    /// Replaces only the changed span with `edit.text`, through `UITextInput` so it is undoable
    /// and the delegate sees it, then selects `edit.selection`.
    func applyMinimalEdit(_ edit: MarkdownEdit, actionName: String) {
        let old = text as NSString? ?? ""
        let new = edit.text as NSString
        var prefix = 0
        let maxPrefix = min(old.length, new.length)
        while prefix < maxPrefix, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        let oldRange = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        if let start = position(from: beginningOfDocument, offset: oldRange.location),
           let end = position(from: start, offset: oldRange.length),
           let range = textRange(from: start, to: end) {
            let source = self as? MarkdownSourceUITextView
            source?.isApplyingEdit = true
            defer { source?.isApplyingEdit = false }
            undoManager?.beginUndoGrouping()
            replace(range, withText: replacement)
            undoManager?.setActionName(actionName)
            undoManager?.endUndoGrouping()
        }
        let length = (text as NSString? ?? "").length
        let location = min(edit.selection.location, length)
        selectedRange = NSRange(location: location, length: min(edit.selection.length, length - location))
        scrollRangeToVisible(selectedRange)
    }
}

struct SourceTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: SourceEditorController
    var scrollSync: ScrollSync?
    var formattingEnabled: Bool = true

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1, matching the AppKit editor's layout manager (see docs/UNIVERSAL_PLAN.md)
        let textView = MarkdownSourceUITextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.text = text
        textView.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 15, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        // Smart punctuation rewrites Markdown syntax (quotes in code, "--" in tables and rules)
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocapitalizationType = .sentences
        textView.dataDetectorTypes = []
        textView.sourceController = controller
        controller.textView = textView
        textView.installFormattingBar(enabled: formattingEnabled)
        scrollSync?.register(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = textView
        if textView.text != text {
            // External change (revert, another window): replace without disturbing undo more than needed
            let selection = textView.selectedRange
            textView.text = text
            let length = (text as NSString).length
            textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        }
        (textView as? MarkdownSourceUITextView)?.installFormattingBar(enabled: formattingEnabled)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SourceTextView

        init(parent: SourceTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard parent.formattingEnabled, (textView as? MarkdownSourceUITextView)?.isApplyingEdit != true, textView.markedTextRange == nil else { return true }
            let current = textView.text ?? ""
            var edit: MarkdownEdit?
            var actionName = ""
            if replacement == "\n", range.length == 0 {
                edit = MarkdownEditingCommands.newline(text: current, selection: range)
                actionName = "Typing"
            } else if replacement.isEmpty, range.length == 1, textView.selectedRange.length == 0 {
                // Backspace at the start of a list item, heading or quote removes its marker
                edit = MarkdownEditingCommands.backspace(text: current, selection: NSRange(location: range.location + 1, length: 0))
                actionName = "Delete"
            }
            guard let edit = edit else { return true }
            textView.applyMinimalEdit(edit, actionName: actionName)
            parent.text = textView.text
            return false
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard parent.formattingEnabled, range.length > 0 else { return nil }
            let controller = parent.controller
            let format = UIMenu(title: "Format", image: UIImage(systemName: "textformat"), children: [
                UIAction(title: "Bold", image: UIImage(systemName: "bold")) { _ in controller.onFormatCommand?(.bold) },
                UIAction(title: "Italic", image: UIImage(systemName: "italic")) { _ in controller.onFormatCommand?(.italic) },
                UIAction(title: "Strikethrough", image: UIImage(systemName: "strikethrough")) { _ in controller.onFormatCommand?(.strikethrough) },
                UIAction(title: "Code", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")) { _ in controller.onFormatCommand?(.code) },
                UIAction(title: "Link…", image: UIImage(systemName: "link")) { _ in controller.onFormatCommand?(.link) },
            ])
            return UIMenu(children: suggestedActions + [format])
        }
    }
}

/// UITextView with hardware-keyboard Tab / Shift-Tab for list indentation and the formatting bar.
final class MarkdownSourceUITextView: UITextView {
    fileprivate weak var sourceController: SourceEditorController?
    private var formattingBarEnabled: Bool?
    /// Set while a Markdown edit replaces text, so the delegate doesn't intercept the replacement.
    fileprivate var isApplyingEdit = false

    override var keyCommands: [UIKeyCommand]? {
        let indent = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentLine))
        let outdent = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentLine))
        indent.wantsPriorityOverSystemBehavior = true
        outdent.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [indent, outdent]
    }

    @objc private func indentLine() {
        if let edit = MarkdownEditingCommands.indent(text: text, selection: selectedRange) {
            applyMinimalEdit(edit, actionName: "Indent")
            delegate?.textViewDidChange?(self)
        } else {
            insertText("\t")
        }
    }

    @objc private func outdentLine() {
        guard let edit = MarkdownEditingCommands.outdent(text: text, selection: selectedRange) else { return }
        applyMinimalEdit(edit, actionName: "Outdent")
        delegate?.textViewDidChange?(self)
    }

    /// Shows the formatting bar above the software keyboard (hidden when Slack mrkdwn is
    /// selected, whose delimiters the AST engine does not write yet).
    func installFormattingBar(enabled: Bool) {
        guard formattingBarEnabled != enabled else { return }
        formattingBarEnabled = enabled
        inputAccessoryView = enabled ? makeFormattingBar() : nil
        reloadInputViews()
    }

    private func makeFormattingBar() -> UIView {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.autoresizingMask = .flexibleWidth
        func item(_ symbol: String, _ label: String, _ command: FormatCommand) -> UIBarButtonItem {
            let item = UIBarButtonItem(image: UIImage(systemName: symbol), primaryAction: UIAction(title: label) { [weak self] _ in
                self?.sourceController?.onFormatCommand?(command)
            })
            item.accessibilityLabel = label
            return item
        }
        func action(_ title: String, _ symbol: String, _ command: FormatCommand) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in
                self?.sourceController?.onFormatCommand?(command)
            }
        }
        let headings = UIBarButtonItem(image: UIImage(systemName: "textformat.size"), menu: UIMenu(title: "Text Style", children: [
            action("Heading 1", "1.square", .heading(1)),
            action("Heading 2", "2.square", .heading(2)),
            action("Heading 3", "3.square", .heading(3)),
            action("Paragraph", "text.alignleft", .paragraph),
        ]))
        headings.accessibilityLabel = "Text Style"
        let blocks = UIBarButtonItem(image: UIImage(systemName: "list.bullet"), menu: UIMenu(title: "Blocks", children: [
            action("Bullet List", "list.bullet", .bulletList),
            action("Numbered List", "list.number", .numberedList),
            action("To-do List", "checklist", .taskList),
            action("Quote", "text.quote", .quote),
            action("Code Block", "curlybraces", .codeBlock),
        ]))
        blocks.accessibilityLabel = "Blocks"
        let dismiss = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), primaryAction: UIAction(title: "Hide Keyboard") { [weak self] _ in
            self?.resignFirstResponder()
        })
        dismiss.accessibilityLabel = "Hide Keyboard"
        bar.items = [
            headings,
            item("bold", "Bold", .bold),
            item("italic", "Italic", .italic),
            item("strikethrough", "Strikethrough", .strikethrough),
            item("chevron.left.forwardslash.chevron.right", "Code", .code),
            item("link", "Link", .link),
            blocks,
            .flexibleSpace(),
            dismiss,
        ]
        bar.sizeToFit()
        return bar
    }
}

#endif
