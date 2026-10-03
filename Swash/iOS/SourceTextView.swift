//
//  SourceTextView.swift
//  Swash
//
//  The iOS and iPadOS Markdown source editor: plain monospaced text with Markdown-aware Return,
//  Backspace and Tab, the formatting bar and formatting in the edit menu.
//

#if os(iOS)
import SwiftUI
import UIKit

struct SourceTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: IOSEditorController
    var scrollSync: ScrollSync?
    var formattingEnabled: Bool = true

    func makeUIView(context: Context) -> MarkdownEditingTextView {
        let textView = MarkdownEditingTextView(usingTextLayoutManager: false)
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
        controller.attach(textView)
        textView.installFormattingBar(enabled: formattingEnabled)
        scrollSync?.register(textView)
        return textView
    }

    func updateUIView(_ textView: MarkdownEditingTextView, context: Context) {
        context.coordinator.parent = self
        controller.attach(textView)
        if textView.text != text {
            // External change (revert, another window)
            let selection = textView.selectedRange
            textView.text = text
            let length = (text as NSString).length
            textView.selectedRange = NSRange(location: min(selection.location, length), length: 0)
        }
        textView.installFormattingBar(enabled: formattingEnabled)
    }

    /// Fill the space offered: a text view's own fitting size is its whole content height, which
    /// would stop it scrolling.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarkdownEditingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
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
            guard parent.formattingEnabled, let textView = textView as? MarkdownEditingTextView,
                  !textView.isApplyingEdit, textView.markedTextRange == nil else { return true }
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
            textView.applyMarkdownEdit(edit, actionName: actionName)
            return false
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            (textView as? MarkdownEditingTextView)?.formattingMenu(for: range, suggestedActions: suggestedActions)
        }
    }
}
#endif
