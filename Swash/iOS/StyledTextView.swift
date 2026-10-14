//
//  StyledTextView.swift
//  Swash
//
//  The iOS and iPadOS Edit Text editor: Markdown edited in place with its syntax hidden, styled by
//  the shared MarkdownEditorStyler. It mirrors the AST path of the macOS SwashTextView: the text
//  storage holds the raw Markdown except that tables and images are collapsed into attachments
//  (GOTCHAS #9), and edits restyle only the blocks they touch (GOTCHAS #20).
//

#if os(iOS)
import SwiftUI
import UIKit

struct StyledTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: IOSEditorController
    var flavor: MarkdownFlavor
    var baseURL: URL?

    func makeUIView(context: Context) -> StyledUITextView {
        let storage = NSTextStorage()
        let layoutManager = StyledLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = StyledUITextView(frame: .zero, textContainer: container)
        textView.coordinator = context.coordinator
        textView.delegate = context.coordinator
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 14, bottom: 20, right: 14)
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.dataDetectorTypes = []
        textView.typingAttributes = Coordinator.baseAttributes
        textView.text = text
        textView.typingAttributes = Coordinator.baseAttributes
        controller.attach(textView)
        textView.installFormattingBar(enabled: true)
        context.coordinator.textView = textView
        context.coordinator.scheduleFullRestyle()
        return textView
    }

    func updateUIView(_ textView: StyledUITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        controller.attach(textView)
        coordinator.isUpdatingFromSwiftUI = true
        defer { coordinator.isUpdatingFromSwiftUI = false }

        let current = swashRawMarkdown(from: textView.textStorage)
        if coordinator.lastStyledText != text, current != text {
            // External change (revert, another window, flavour conversion)
            let offset = textView.contentOffset
            textView.textStorage.setAttributedString(NSAttributedString(string: text, attributes: Coordinator.baseAttributes))
            coordinator.invalidateOffsetMap()
            textView.contentOffset = offset
            coordinator.scheduleFullRestyle()
        } else if coordinator.lastFlavor != flavor || coordinator.lastBaseURL != baseURL {
            coordinator.scheduleFullRestyle()
        }
    }

    /// Fill the space offered: a text view's own fitting size is its whole content height, which
    /// would stop it scrolling.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: StyledUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: StyledTextView
        weak var textView: StyledUITextView?
        var isUpdatingFromSwiftUI = false
        private var isHighlighting = false

        var lastStyledText: String?
        var lastFlavor: MarkdownFlavor?
        var lastBaseURL: URL?

        private var cachedOffsetMap: AttachmentOffsetMap?
        /// Raw-markdown selection to restore after the next styling pass.
        private var pendingRawSelection: NSRange?
        private var editGeneration = 0
        private var highlightedGeneration = -1
        /// Caret position before the latest selection change, to tell arrow steps from jumps.
        private var lastSelection = NSRange(location: 0, length: 0)

        static var baseFont: UIFont { .systemFont(ofSize: MarkdownEditorStyler.baseFontSize * MarkdownEditorStyler.fontScale, weight: .regular) }
        static var baseAttributes: [NSAttributedString.Key: Any] { [.font: baseFont, .foregroundColor: UIColor.label] }

        init(_ parent: StyledTextView) {
            self.parent = parent
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        // MARK: Storage ↔ raw offsets

        func invalidateOffsetMap() {
            cachedOffsetMap = nil
        }

        func offsetMap(for textView: UITextView) -> AttachmentOffsetMap {
            if let map = cachedOffsetMap { return map }
            let map = AttachmentOffsetMap(storage: textView.textStorage)
            cachedOffsetMap = map
            return map
        }

        func rawRange(forStorage range: NSRange, in textView: UITextView) -> NSRange {
            offsetMap(for: textView).rawRange(forStorage: range)
        }

        func storageRange(forRaw range: NSRange, in textView: UITextView) -> NSRange {
            let length = textView.textStorage.length
            let mapped = offsetMap(for: textView).storageRange(forRaw: range)
            let start = min(max(0, mapped.location), length)
            return NSRange(location: start, length: min(mapped.length, length - start))
        }

        // MARK: Edits

        /// Applies a whole-document rewrite as the smallest equivalent storage edit (one undo step),
        /// then restyles and selects `rawSelection`.
        func applyEdit(in textView: StyledUITextView, newRawText: String, rawSelection: NSRange?, actionName: String) {
            let storage = textView.textStorage
            let oldRaw = swashRawMarkdown(from: storage) as NSString
            let newRaw = newRawText as NSString
            guard oldRaw != newRaw else {
                if let selection = rawSelection { textView.selectedRange = storageRange(forRaw: selection, in: textView) }
                return
            }
            // Common prefix / suffix in UTF-16 units, never splitting a surrogate pair
            let minLength = min(oldRaw.length, newRaw.length)
            var prefix = 0
            while prefix < minLength && oldRaw.character(at: prefix) == newRaw.character(at: prefix) { prefix += 1 }
            if prefix > 0 && CFStringIsSurrogateHighCharacter(oldRaw.character(at: prefix - 1)) { prefix -= 1 }
            var suffix = 0
            while suffix < minLength - prefix &&
                  oldRaw.character(at: oldRaw.length - 1 - suffix) == newRaw.character(at: newRaw.length - 1 - suffix) { suffix += 1 }
            if suffix > 0 && CFStringIsSurrogateLowCharacter(oldRaw.character(at: oldRaw.length - suffix)) { suffix -= 1 }

            let changedRaw = NSRange(location: prefix, length: oldRaw.length - prefix - suffix)
            let map = offsetMap(for: textView)
            // Attachments touched by the edit are replaced whole, by their (new) raw source
            let storageTarget = map.storageRange(forRaw: changedRaw)
            let expandedRaw = map.rawRange(forStorage: storageTarget)
            let delta = newRaw.length - oldRaw.length
            let replacement = newRaw.substring(with: NSRange(location: expandedRaw.location, length: expandedRaw.length + delta))

            textView.replaceUndoably(storageTarget, with: replacement, actionName: actionName)
            cachedOffsetMap = nil
            parent.text = swashRawMarkdown(from: storage)
            editGeneration += 1
            pendingRawSelection = rawSelection
            highlight(in: textView)
        }

        /// Runs a structural editing command on the raw Markdown; false falls back to the default key behaviour.
        private func applyStructuralEdit(in textView: StyledUITextView, actionName: String, _ command: (String, NSRange) -> MarkdownEdit?) -> Bool {
            let raw = swashRawMarkdown(from: textView.textStorage)
            let selection = rawRange(forStorage: textView.selectedRange, in: textView)
            guard let edit = command(raw, selection) else { return false }
            applyEdit(in: textView, newRawText: edit.text, rawSelection: edit.selection, actionName: actionName)
            return true
        }

        /// Toggles `[ ]` ↔ `[x]` for the task marker at `markerRange` (storage offsets).
        func toggleTask(markerRange: NSRange, in textView: StyledUITextView) {
            let raw = swashRawMarkdown(from: textView.textStorage) as NSString
            let rawMarker = rawRange(forStorage: markerRange, in: textView)
            guard NSMaxRange(rawMarker) <= raw.length else { return }
            let markerText = raw.substring(with: rawMarker) as NSString
            let box = markerText.range(of: "\\[[ xX]\\]", options: .regularExpression)
            guard box.location != NSNotFound else { return }
            let checked = markerText.substring(with: NSRange(location: box.location + 1, length: 1)) != " "
            let absolute = NSRange(location: rawMarker.location + box.location + 1, length: 1)
            let updated = raw.replacingCharacters(in: absolute, with: checked ? " " : "x")
            let selection = rawRange(forStorage: textView.selectedRange, in: textView)
            applyEdit(in: textView, newRawText: updated, rawSelection: selection, actionName: checked ? "Uncheck To-do" : "Check To-do")
        }

        /// Replaces the "/" typed at `slashLocation` (raw) with the chosen block.
        func insertBlock(_ kind: MarkdownEditingCommands.BlockInsert, slashLocation: Int, in textView: StyledUITextView) {
            let raw = swashRawMarkdown(from: textView.textStorage)
            guard let edit = MarkdownEditingCommands.insertBlock(kind, text: raw, slashLocation: slashLocation) else { return }
            applyEdit(in: textView, newRawText: edit.text, rawSelection: edit.selection, actionName: kind.title)
        }

        /// Sets (or clears) the language of the fenced code block whose badge is at `location` (storage).
        func setCodeLanguage(_ language: String?, atStorageLocation location: Int, in textView: StyledUITextView) {
            let raw = swashRawMarkdown(from: textView.textStorage)
            let rawLocation = rawRange(forStorage: NSRange(location: location, length: 0), in: textView).location
            guard let edit = MarkdownEditingCommands.setCodeLanguage(language, text: raw, location: rawLocation) else { return }
            let selection = rawRange(forStorage: textView.selectedRange, in: textView)
            let delta = (edit.text as NSString).length - (raw as NSString).length
            let kept = selection.location > rawLocation ? NSRange(location: selection.location + delta, length: selection.length) : selection
            applyEdit(in: textView, newRawText: edit.text, rawSelection: kept, actionName: "Code Language")
        }

        /// Replaces the selection with `markdown` (one undoable edit) and puts the caret after it.
        func replaceSelection(with markdown: String, in textView: StyledUITextView, actionName: String) {
            let raw = swashRawMarkdown(from: textView.textStorage) as NSString
            let selection = rawRange(forStorage: textView.selectedRange, in: textView)
            guard NSMaxRange(selection) <= raw.length else { return }
            let updated = raw.replacingCharacters(in: selection, with: markdown)
            let caret = NSRange(location: selection.location + (markdown as NSString).length, length: 0)
            applyEdit(in: textView, newRawText: updated, rawSelection: caret, actionName: actionName)
        }

        // MARK: UITextViewDelegate

        func textViewDidChange(_ textView: UITextView) {
            guard let textView = textView as? StyledUITextView else { return }
            cachedOffsetMap = nil
            textView.setNeedsOverlayLayout()
            guard !isUpdatingFromSwiftUI, !isHighlighting else { return }
            parent.text = swashRawMarkdown(from: textView.textStorage)
            editGeneration += 1
            let generation = editGeneration
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self = self, let textView = textView else { return }
                // Skip if a synchronous pass (a formatting edit) already styled this revision
                guard self.highlightedGeneration < generation else { return }
                self.highlight(in: textView)
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard let textView = textView as? StyledUITextView, !textView.isApplyingEdit, !isHighlighting,
                  textView.markedTextRange == nil else { return true }
            textView.dismissBlockMenu()
            if replacement == "/", range.length == 0 {
                let raw = swashRawMarkdown(from: textView.textStorage)
                let rawLocation = rawRange(forStorage: range, in: textView).location
                if MarkdownEditingCommands.isBlockMenuTrigger(text: raw, location: rawLocation) {
                    DispatchQueue.main.async { [weak self, weak textView] in
                        guard let self = self, let textView = textView else { return }
                        textView.presentBlockMenu { [weak self, weak textView] kind in
                            guard let self = self, let textView = textView else { return }
                            self.insertBlock(kind, slashLocation: rawLocation, in: textView)
                        }
                    }
                }
                return true
            }
            if replacement == "\n", range.length == 0 {
                return !applyStructuralEdit(in: textView, actionName: "New Line") { MarkdownEditingCommands.newline(text: $0, selection: $1) }
            }
            if replacement.isEmpty, range.length == 1, textView.selectedRange.length == 0 {
                return !applyStructuralEdit(in: textView, actionName: "Delete") {
                    MarkdownEditingCommands.backspace(text: $0, selection: $1, markersHidden: true)
                }
            }
            return true
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isHighlighting, !isUpdatingFromSwiftUI else {
                lastSelection = textView.selectedRange
                return
            }
            let snapped = snappedSelection(from: lastSelection, to: textView.selectedRange, in: textView.textStorage)
            if snapped != lastSelection, snapped.location != lastSelection.location + 1 {
                (textView as? StyledUITextView)?.dismissBlockMenu()
            }
            lastSelection = snapped
            if snapped != textView.selectedRange {
                textView.selectedRange = snapped
            }
            sanitizeTypingAttributes(textView)
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            (textView as? MarkdownEditingTextView)?.formattingMenu(for: range, suggestedActions: suggestedActions)
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            // Links are edited here, not followed; the edit menu offers them instead
            textView.isFirstResponder ? nil : defaultAction
        }

        // MARK: Caret atomicity

        /// True when the character at `index` is a hidden syntax marker (collapsed font or clear colour).
        private func isHiddenCharacter(_ index: Int, in storage: NSTextStorage) -> Bool {
            guard index >= 0, index < storage.length else { return false }
            if storage.attribute(.attachment, at: index, effectiveRange: nil) != nil { return false }
            if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? UIFont, font.pointSize < 1 { return true }
            if let color = storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor, color == .clear { return true }
            return false
        }

        /// Keeps the caret off hidden markers, as the macOS editor does: arrow steps skip a hidden run
        /// plus one visible character, and a caret placed in a line's hidden prefix moves to the content.
        private func snappedSelection(from oldRange: NSRange, to newRange: NSRange, in storage: NSTextStorage) -> NSRange {
            guard newRange.length == 0, oldRange.length == 0 else { return newRange }
            let length = storage.length
            let ns = storage.string as NSString
            let old = oldRange.location
            let proposed = newRange.location

            func snapForward(_ position: Int) -> Int {
                var i = position
                while i < length && isHiddenCharacter(i, in: storage) &&
                      (i == 0 || ns.character(at: i - 1) == 0x0A || isHiddenCharacter(i - 1, in: storage)) {
                    i += 1
                }
                return i
            }

            if proposed == old + 1 {
                var i = old
                if isHiddenCharacter(old, in: storage) {
                    while i < length && isHiddenCharacter(i, in: storage) { i += 1 }
                    if i < length { i += 1 }
                } else {
                    i = proposed
                }
                return NSRange(location: snapForward(min(i, length)), length: 0)
            }
            if proposed == old - 1, old > 0, isHiddenCharacter(old - 1, in: storage) {
                var i = old
                while i > 0 && isHiddenCharacter(i - 1, in: storage) { i -= 1 }
                if i > 0 { i -= 1 }
                return NSRange(location: max(0, i), length: 0)
            }
            if proposed != old - 1 {
                return NSRange(location: snapForward(proposed), length: 0)
            }
            return newRange
        }

        /// Typing next to a hidden marker must not inherit its collapsed font or clear colour.
        private func sanitizeTypingAttributes(_ textView: UITextView) {
            var attributes = textView.typingAttributes
            var changed = false
            if let font = attributes[.font] as? UIFont, font.pointSize < 1 {
                attributes[.font] = Self.baseFont
                changed = true
            }
            if let color = attributes[.foregroundColor] as? UIColor, color == .clear {
                attributes[.foregroundColor] = UIColor.label
                changed = true
            }
            if changed { textView.typingAttributes = attributes }
        }

        // MARK: Styling

        /// Requests a full pass on the next run loop (after SwiftUI finishes updating).
        func scheduleFullRestyle() {
            forceFullRestyle = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let textView = self.textView else { return }
                self.highlight(in: textView)
            }
        }

        /// Top-level blocks of the last styling pass, for incremental restyling.
        private var lastBlocks: [(source: String, range: NSRange, isDefinition: Bool)]?
        private var lastRawLength = 0
        /// Set whenever the storage was replaced or styling inputs changed; the next pass is a full one.
        var forceFullRestyle = true

        private static func blockSummaries(_ document: MarkdownDocument, raw: NSString) -> [(source: String, range: NSRange, isDefinition: Bool)] {
            document.root.children.map { block in
                let isDefinition: Bool
                switch block.kind {
                case .linkReferenceDefinition, .footnoteDefinition: isDefinition = true
                default: isDefinition = false
                }
                return (raw.substring(with: block.range), block.range, isDefinition)
            }
        }

        func highlight(in textView: StyledUITextView) {
            guard !isHighlighting else { return }
            let storage = textView.textStorage
            if highlightIncrementally(in: textView, storage: storage) {
                pendingRawSelection = nil
                return
            }
            forceFullRestyle = false
            isHighlighting = true
            let savedOffset = textView.contentOffset
            let savedRawSelection = pendingRawSelection ?? rawRange(forStorage: textView.selectedRange, in: textView)
            pendingRawSelection = nil

            let rawText = swashRawMarkdown(from: storage)
            textView.removeAllTableViews()
            storage.beginEditing()
            if storage.string != rawText {
                storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: rawText)
            }
            cachedOffsetMap = nil
            storage.setAttributes(Self.baseAttributes, range: NSRange(location: 0, length: storage.length))

            let document = MarkdownDocument.parse(rawText)
            let styler = MarkdownEditorStyler(storage: storage, document: document)
            configureRichPreviews(styler, for: textView)
            styler.style()
            collectRichPreviews(from: styler, fullPass: true)
            collapseAttachments(styler.attachments, shift: 0, in: textView)
            storage.endEditing()
            isHighlighting = false

            lastBlocks = Self.blockSummaries(document, raw: rawText as NSString)
            lastRawLength = (rawText as NSString).length
            finishStyling(in: textView, rawText: rawText, savedRawSelection: savedRawSelection, savedOffset: savedOffset)
        }

        /// Restyles only the top-level blocks that changed since the last pass. Returns false when a
        /// full pass is required (first pass, definitions changed, or the change cannot be localised).
        private func highlightIncrementally(in textView: StyledUITextView, storage: NSTextStorage) -> Bool {
            guard !forceFullRestyle, let previous = lastBlocks else { return false }
            let savedOffset = textView.contentOffset
            let savedRawSelection = pendingRawSelection ?? rawRange(forStorage: textView.selectedRange, in: textView)

            let rawText = swashRawMarkdown(from: storage)
            let raw = rawText as NSString
            let document = MarkdownDocument.parse(rawText)
            let blocks = document.root.children
            let current = Self.blockSummaries(document, raw: raw)

            var prefix = 0
            while prefix < min(previous.count, current.count),
                  previous[prefix].source == current[prefix].source, previous[prefix].range == current[prefix].range { prefix += 1 }
            var suffix = 0
            while suffix < min(previous.count, current.count) - prefix {
                let old = previous[previous.count - 1 - suffix]
                let new = current[current.count - 1 - suffix]
                guard old.source == new.source, lastRawLength - old.range.location == raw.length - new.range.location else { break }
                suffix += 1
            }
            let changedOld = previous[prefix..<(previous.count - suffix)]
            let changedNew = current[prefix..<(current.count - suffix)]
            if changedOld.contains(where: { $0.isDefinition }) || changedNew.contains(where: { $0.isDefinition }) { return false }

            // The last unchanged leading block is restyled too (its trailing line break may have been
            // retyped); the region starts at the beginning of that block's line.
            let firstStyled = max(0, prefix - 1)
            let start = prefix > 0 ? raw.lineRange(for: NSRange(location: current[firstStyled].range.location, length: 0)).location : 0
            let end = suffix > 0 ? current[current.count - suffix].range.location : raw.length
            guard end >= start else { return false }

            let map = offsetMap(for: textView)
            let storageStart = map.storageLocation(forRaw: start, roundUp: false)
            let storageEnd = map.storageLocation(forRaw: end, roundUp: true)
            guard storageEnd >= storageStart, storageEnd <= storage.length else { return false }
            let storageRegion = NSRange(location: storageStart, length: storageEnd - storageStart)
            let shift = start - storageStart

            isHighlighting = true
            storage.beginEditing()
            storage.enumerateAttribute(.attachment, in: storageRegion, options: []) { value, _, _ in
                (value as? TableTextAttachment)?.host?.view.removeFromSuperview()
            }
            storage.replaceCharacters(in: storageRegion, with: raw.substring(with: NSRange(location: start, length: end - start)))
            let region = NSRange(location: storageStart, length: end - start)
            storage.setAttributes(Self.baseAttributes, range: region)

            let styler = MarkdownEditorStyler(storage: storage, document: document, storageShift: shift)
            configureRichPreviews(styler, for: textView)
            styler.style(blocks: Array(blocks[firstStyled..<(blocks.count - suffix)]))
            collectRichPreviews(from: styler, fullPass: false)
            collapseAttachments(styler.attachments, shift: shift, in: textView)
            storage.endEditing()
            isHighlighting = false

            lastBlocks = current
            lastRawLength = raw.length
            finishStyling(in: textView, rawText: rawText, savedRawSelection: savedRawSelection, savedOffset: savedOffset)
            return true
        }

        /// Replaces table and image source (raw ranges, shifted to storage) with attachments, last first.
        private func collapseAttachments(_ requests: [EditorAttachmentRequest], shift: Int, in textView: StyledUITextView) {
            let storage = textView.textStorage
            for request in requests.sorted(by: { $0.range.location > $1.range.location }) {
                let range = NSIntersectionRange(NSRange(location: request.range.location - shift, length: request.range.length),
                                                NSRange(location: 0, length: storage.length))
                guard range.length > 0 else { continue }
                let attachment: NSTextAttachment
                switch request.kind {
                case .table(let source, let headers, let alignments, let rows):
                    let data = MarkdownTableData(headers: headers, alignments: alignments, rows: rows)
                    let table = TableTextAttachment(tableData: data, flavor: parent.flavor, originalMarkdown: source, onUpdate: nil)
                    table.onUpdate = { [weak self, weak table, weak textView] updated in
                        guard let self = self, let table = table, let textView = textView else { return }
                        table.tableData = updated
                        // The table's raw length may have changed; restyle fully next time
                        self.cachedOffsetMap = nil
                        self.forceFullRestyle = true
                        self.parent.text = swashRawMarkdown(from: textView.textStorage)
                    }
                    attachment = table
                case .image(let alt, let urlString, let rawMarkdown, let width):
                    let cleaned = MarkdownParser.cleanImageURLAndTitle(urlString)
                    let image: UIImage
                    if let resolved = MarkdownParser.resolveImage(urlString: cleaned.url, baseURL: parent.baseURL) {
                        let available = max(120, textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right - 24)
                        image = MarkdownParser.scaleImageForEditor(resolved, maxWidth: min(available, width ?? available))
                    } else {
                        image = MarkdownParser.placeholderImage(alt: alt)
                    }
                    attachment = ImageTextAttachment(image: image, alt: alt, urlString: urlString, rawMarkdown: rawMarkdown)
                }
                let replacement = NSMutableAttributedString(attachment: attachment)
                replacement.addAttributes(Self.baseAttributes, range: NSRange(location: 0, length: replacement.length))
                storage.replaceCharacters(in: range, with: replacement)
            }
        }

        /// Bookkeeping after a styling pass: selection, scroll position, state.
        private func finishStyling(in textView: StyledUITextView, rawText: String, savedRawSelection: NSRange, savedOffset: CGPoint) {
            cachedOffsetMap = nil
            highlightedGeneration = editGeneration
            let restored = storageRange(forRaw: savedRawSelection, in: textView)
            isHighlighting = true
            if textView.selectedRange != restored {
                textView.selectedRange = restored
            }
            lastSelection = restored
            isHighlighting = false
            textView.typingAttributes = Self.baseAttributes
            if textView.contentOffset != savedOffset, !textView.isFirstResponder || textView.isDragging || textView.isDecelerating {
                textView.contentOffset = savedOffset
            }
            textView.setNeedsOverlayLayout()
            lastStyledText = rawText
            lastFlavor = parent.flavor
            lastBaseURL = parent.baseURL
        }

        // MARK: Rendered math and Mermaid

        private var richPreviewMemory: [Int: RichContentRenderer.Rendered] = [:]
        private var pendingRichPreviews: [(location: Int, request: RichContentRenderer.Request)] = []
        private var richPreviewsDark = false
        private var richPreviewRefreshScheduled = false
        private var observesRichRenders = false

        private func configureRichPreviews(_ styler: MarkdownEditorStyler, for textView: UITextView) {
            guard RichContentRenderer.isAvailable else { return }
            if !observesRichRenders {
                observesRichRenders = true
                NotificationCenter.default.addObserver(self, selector: #selector(handleRichContentRendered(_:)), name: RichContentRenderer.didRender, object: nil)
            }
            styler.richPreviewDark = textView.traitCollection.userInterfaceStyle == .dark
            let width = textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right
                - textView.textContainer.lineFragmentPadding * 2
            // Leave room for the code block's padding and border
            styler.richPreviewMaxWidth = max(120, min(900, width - 48))
            styler.richPreviewMemory = richPreviewMemory
        }

        private func collectRichPreviews(from styler: MarkdownEditorStyler, fullPass: Bool) {
            guard RichContentRenderer.isAvailable else { return }
            richPreviewMemory = styler.richPreviewMemory
            richPreviewsDark = styler.richPreviewDark
            if fullPass {
                pendingRichPreviews = styler.pendingRichPreviews
            } else {
                pendingRichPreviews += styler.pendingRichPreviews
            }
        }

        @objc private func handleRichContentRendered(_ notification: Notification) {
            guard !pendingRichPreviews.isEmpty, !richPreviewRefreshScheduled else { return }
            richPreviewRefreshScheduled = true
            DispatchQueue.main.async { [weak self] in self?.refreshRichPreviews() }
        }

        /// Restyles just the blocks whose renders have landed.
        private func refreshRichPreviews() {
            richPreviewRefreshScheduled = false
            guard let textView = textView, lastStyledText != nil, !isHighlighting else { return }
            let ready = pendingRichPreviews.filter { RichContentRenderer.cachedOutcome($0.request) != nil }
            guard !ready.isEmpty else { return }
            pendingRichPreviews.removeAll { pending in ready.contains { $0.request == pending.request } }
            if var blocks = lastBlocks {
                for item in ready {
                    if let index = blocks.firstIndex(where: { NSLocationInRange(item.location, $0.range) }) {
                        blocks[index].source = "\u{0}" + blocks[index].source
                    }
                }
                lastBlocks = blocks
            } else {
                forceFullRestyle = true
            }
            highlight(in: textView)
        }

        /// Rendered previews are drawn for one appearance; switching re-renders them.
        func appearanceChanged(in textView: StyledUITextView) {
            guard lastStyledText != nil, RichContentRenderer.isAvailable, !richPreviewMemory.isEmpty || !pendingRichPreviews.isEmpty else { return }
            guard (textView.traitCollection.userInterfaceStyle == .dark) != richPreviewsDark else { return }
            forceFullRestyle = true
            highlight(in: textView)
        }

        /// The editor width changed: rendered previews and images are sized to it.
        func widthChanged(in textView: StyledUITextView) {
            guard lastStyledText != nil else { return }
            forceFullRestyle = true
            highlight(in: textView)
        }
    }
}

/// The Edit Text text view: maps selections and edits to raw Markdown, toggles task checkboxes on
/// tap, and hosts table attachments' SwiftUI views over the space they reserve.
final class StyledUITextView: MarkdownEditingTextView {
    weak var coordinator: StyledTextView.Coordinator?
    private var lastLayoutWidth: CGFloat = 0
    private var placedTables: [ObjectIdentifier: TableTextAttachment] = [:]
    /// The checkbox tap's delegate. Not the text view itself: a scroll view is already the delegate
    /// of its own pan and text gestures, and overriding those callbacks would filter them too.
    private let taskTapFilter = TaskTapFilter()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTaskTap(_:)))
        taskTapFilter.textView = self
        tap.delegate = taskTapFilter
        addGestureRecognizer(tap)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.coordinator?.appearanceChanged(in: self)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var markdownSelection: NSRange {
        coordinator?.rawRange(forStorage: selectedRange, in: self) ?? selectedRange
    }

    override var markdownText: String {
        swashRawMarkdown(from: textStorage)
    }

    override func applyMarkdownEdit(_ edit: MarkdownEdit, actionName: String) {
        guard let coordinator = coordinator else { return super.applyMarkdownEdit(edit, actionName: actionName) }
        coordinator.applyEdit(in: self, newRawText: edit.text, rawSelection: edit.selection, actionName: actionName)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastLayoutWidth) > 1 {
            needsOverlayLayout = true
            let isFirstLayout = lastLayoutWidth == 0
            lastLayoutWidth = bounds.width
            if !isFirstLayout { coordinator?.widthChanged(in: self) }
        }
        // Tables and badge buttons are content subviews: they scroll with the text, so they only
        // move after a restyle or a size change, not on every scroll frame
        if needsOverlayLayout {
            needsOverlayLayout = false
            layoutTableViews()
            layoutCodeBadgeButtons()
        }
    }

    /// Set when the text or its layout changed, so the next layout pass repositions the overlays.
    private var needsOverlayLayout = true

    func setNeedsOverlayLayout() {
        needsOverlayLayout = true
        setNeedsLayout()
    }

    // MARK: Clipboard

    override func copy(_ sender: Any?) {
        EditorClipboard.copy(selectedRange, from: textStorage)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        EditorClipboard.copy(selectedRange, from: textStorage)
        coordinator?.replaceSelection(with: "", in: self, actionName: "Cut")
    }

    /// Rich text (HTML, RTF) is converted to Markdown and Swash's own copies paste their raw
    /// Markdown; anything else pastes as plain text.
    override func paste(_ sender: Any?) {
        if let markdown = EditorClipboard.markdownForPaste(from: .general), let coordinator = coordinator {
            coordinator.replaceSelection(with: markdown, in: self, actionName: "Paste")
            return
        }
        super.paste(sender)
    }

    // MARK: Code language

    private var badgeButtons: [UIButton] = []

    /// An invisible button over each code block's language badge; tapping it opens the language menu.
    private func layoutCodeBadgeButtons() {
        guard let layoutManager = layoutManager as? StyledLayoutManager else { return }
        let badges = layoutManager.codeBadgeRects()
        while badgeButtons.count < badges.count {
            let button = UIButton(type: .custom)
            button.showsMenuAsPrimaryAction = true
            addSubview(button)
            badgeButtons.append(button)
        }
        for (index, button) in badgeButtons.enumerated() {
            guard index < badges.count else {
                button.isHidden = true
                continue
            }
            let badge = badges[index]
            button.isHidden = false
            button.frame = badge.rect.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top).insetBy(dx: -8, dy: -6)
            button.accessibilityLabel = "Code language: \(badge.info.title.capitalized)"
            button.menu = languageMenu(current: badge.info.language, location: badge.location)
        }
    }

    private func languageMenu(current: String?, location: Int) -> UIMenu {
        let selected = (current ?? "").lowercased()
        func action(_ title: String, _ value: String?) -> UIAction {
            UIAction(title: title, state: (value ?? "") == selected ? .on : .off) { [weak self] _ in
                guard let self = self else { return }
                self.coordinator?.setCodeLanguage(value, atStorageLocation: location, in: self)
            }
        }
        var languages = MarkdownEditingCommands.commonLanguages.map { action($0.capitalized, $0) }
        if !selected.isEmpty, !MarkdownEditingCommands.commonLanguages.contains(selected) {
            languages.insert(action(current ?? selected, current), at: 0)
        }
        return UIMenu(title: "Language", children: [
            UIMenu(options: .displayInline, children: [action("Plain Text", nil)]),
            UIMenu(options: .displayInline, children: languages),
        ])
    }

    // MARK: "/" block menu

    private var blockMenuChoice: ((MarkdownEditingCommands.BlockInsert) -> Void)?
    private weak var blockMenuPopover: UIViewController?

    /// Offers the block types: a popover at the caret where there is room (iPad), otherwise a bar
    /// above the keyboard (iPhone).
    func presentBlockMenu(_ choose: @escaping (MarkdownEditingCommands.BlockInsert) -> Void) {
        dismissBlockMenu()
        blockMenuChoice = choose
        if traitCollection.horizontalSizeClass == .regular, let presenter = topViewController(), let caret = selectedTextRange?.end {
            let menu = BlockMenuViewController { [weak self] kind in self?.chooseBlock(kind) }
            menu.modalPresentationStyle = .popover
            if let popover = menu.popoverPresentationController {
                popover.sourceView = self
                popover.sourceRect = caretRect(for: caret)
                popover.permittedArrowDirections = [.up, .down]
                popover.delegate = menu
            }
            presenter.present(menu, animated: true)
            blockMenuPopover = menu
        } else {
            inputAccessoryView = BlockMenuBar(choose: { [weak self] kind in self?.chooseBlock(kind) },
                                              close: { [weak self] in self?.dismissBlockMenu() })
            reloadInputViews()
        }
    }

    private func chooseBlock(_ kind: MarkdownEditingCommands.BlockInsert) {
        let choose = blockMenuChoice
        dismissBlockMenu()
        choose?(kind)
    }

    /// Closes the block menu (leaving the typed "/" in place) and restores the formatting bar.
    func dismissBlockMenu() {
        guard blockMenuChoice != nil else { return }
        blockMenuChoice = nil
        if let popover = blockMenuPopover {
            popover.dismiss(animated: true)
            blockMenuPopover = nil
        }
        if inputAccessoryView is BlockMenuBar {
            restoreFormattingBar()
        }
    }

    private func topViewController() -> UIViewController? {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    // MARK: Task checkboxes

    @objc private func handleTaskTap(_ recognizer: UITapGestureRecognizer) {
        guard let marker = taskMarkerRange(at: recognizer.location(in: self)) else { return }
        coordinator?.toggleTask(markerRange: marker, in: self)
    }

    /// Storage range of the task checkbox marker under `point` (view coordinates), if any.
    func taskMarkerRange(at point: CGPoint) -> NSRange? {
        guard layoutManager.numberOfGlyphs > 0 else { return nil }
        let containerPoint = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        var lineGlyphs = NSRange()
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineGlyphs)
        guard containerPoint.y >= lineRect.minY, containerPoint.y <= lineRect.maxY else { return nil }
        let lineCharacters = layoutManager.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
        var hit: NSRange?
        textStorage.enumerateAttribute(.listMarker, in: lineCharacters, options: []) { value, range, stop in
            guard let info = value as? ListMarkerInfo, info.text == "☐" || info.text == "☑" else { return }
            let contentGlyph = layoutManager.glyphIndexForCharacter(at: min(NSMaxRange(range), max(0, textStorage.length - 1)))
            let contentX = lineRect.minX + layoutManager.location(forGlyphAt: contentGlyph).x
            // The checkbox is drawn just left of the item's text; a finger needs a generous target
            if containerPoint.x >= contentX - 40 && containerPoint.x <= contentX + 4 {
                hit = range
                stop.pointee = true
            }
        }
        return hit
    }

    // MARK: Tables

    /// Removes every hosted table (before the storage is rebuilt).
    func removeAllTableViews() {
        for table in placedTables.values { table.host?.view.removeFromSuperview() }
        placedTables.removeAll()
    }

    /// Places each table attachment's SwiftUI view over the space its glyph reserves, measuring
    /// it so the reservation matches the table's real height.
    private func layoutTableViews() {
        var current: [ObjectIdentifier: TableTextAttachment] = [:]
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length), options: []) { value, range, _ in
            guard let table = value as? TableTextAttachment else { return }
            current[ObjectIdentifier(table)] = table
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var frame = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            frame.origin.x += textContainerInset.left
            frame.origin.y += textContainerInset.top
            let host: UIHostingController<InteractiveTableView>
            if let existing = table.host {
                host = existing
            } else {
                host = UIHostingController(rootView: InteractiveTableView(
                    tableData: table.tableData, flavor: table.flavor, isEditable: true,
                    onChange: { [weak table] data in table?.onUpdate?(data) }))
                host.view.backgroundColor = .clear
                host.sizingOptions = []
                table.host = host
            }
            if host.view.superview !== self { addSubview(host.view) }
            let fitted = host.sizeThatFits(in: CGSize(width: frame.width, height: .greatestFiniteMagnitude)).height
            if fitted > 0, abs(fitted - (table.measuredHeight ?? 0)) > 1 {
                table.measuredHeight = fitted
                layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                needsOverlayLayout = true
                setNeedsLayout()
            }
            frame.size.height = table.measuredHeight ?? frame.height
            if host.view.frame != frame { host.view.frame = frame }
        }
        for (id, table) in placedTables where current[id] == nil {
            table.host?.view.removeFromSuperview()
        }
        placedTables = current
    }
}
/// Lets the checkbox tap see only touches on a task checkbox.
private final class TaskTapFilter: NSObject, UIGestureRecognizerDelegate {
    weak var textView: StyledUITextView?

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let textView = textView else { return false }
        return textView.taskMarkerRange(at: touch.location(in: textView)) != nil
    }
}
/// The "/" menu's block types in a popover (iPad).
private final class BlockMenuViewController: UITableViewController, UIPopoverPresentationControllerDelegate {
    private let choose: (MarkdownEditingCommands.BlockInsert) -> Void
    private let kinds = MarkdownEditingCommands.BlockInsert.allCases

    init(choose: @escaping (MarkdownEditingCommands.BlockInsert) -> Void) {
        self.choose = choose
        super.init(style: .plain)
        preferredContentSize = CGSize(width: 240, height: CGFloat(kinds.count) * 44)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "block")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        kinds.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "block", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = kinds[indexPath.row].title
        content.image = UIImage(systemName: kinds[indexPath.row].symbolName)
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        choose(kinds[indexPath.row])
    }

    /// Stay a popover on every size class.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}

/// The "/" menu's block types as a scrolling bar above the keyboard (iPhone).
private final class BlockMenuBar: UIInputView {
    init(choose: @escaping (MarkdownEditingCommands.BlockInsert) -> Void, close: @escaping () -> Void) {
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 52), inputViewStyle: .keyboard)
        autoresizingMask = .flexibleWidth
        allowsSelfSizing = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        for kind in MarkdownEditingCommands.BlockInsert.allCases {
            var configuration = UIButton.Configuration.gray()
            configuration.title = kind.title
            configuration.image = UIImage(systemName: kind.symbolName)
            configuration.imagePadding = 6
            configuration.cornerStyle = .capsule
            configuration.buttonSize = .small
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12)
            stack.addArrangedSubview(UIButton(configuration: configuration, primaryAction: UIAction { _ in choose(kind) }))
        }
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        var closeConfiguration = UIButton.Configuration.plain()
        closeConfiguration.image = UIImage(systemName: "xmark")
        let closeButton = UIButton(configuration: closeConfiguration, primaryAction: UIAction { _ in close() })
        closeButton.accessibilityLabel = "Close Block Menu"
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scroll)
        addSubview(closeButton)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
            heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
