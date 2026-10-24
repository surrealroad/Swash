//
//  MarkdownPreviewView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import AppKit

/// Keeps the editor and preview scroll positions in step by scrolling the clip views directly.
/// Scroll positions never pass through SwiftUI state, so scrolling doesn't re-evaluate
/// `ContentView` (which would re-parse and re-measure the whole preview on every frame).
/// Held in `@State` like `SwashEditorController`; the stored origin restores the position
/// when the view mode changes.
final class ScrollSync {
    private(set) var originY: CGFloat = 0
    private let scrollViews = NSHashTable<NSScrollView>.weakObjects()
    private var isSyncing = false

    /// Adds a scroll view and moves it to the shared position once it has laid out.
    func register(_ scrollView: NSScrollView) {
        scrollViews.add(scrollView)
        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self = self, let scrollView = scrollView else { return }
            self.isSyncing = true
            ScrollSync.scroll(scrollView, toY: self.originY)
            self.isSyncing = false
        }
    }

    /// Call from a scroll view's bounds-change observer; scrolls every other registered view.
    func scrollViewDidScroll(_ scrollView: NSScrollView) {
        guard !isSyncing else { return }
        let y = scrollView.contentView.bounds.origin.y
        guard abs(y - originY) > 0.5 else { return }
        originY = y
        isSyncing = true
        for other in scrollViews.allObjects where other !== scrollView {
            ScrollSync.scroll(other, toY: y)
        }
        isSyncing = false
    }

    private static func scroll(_ scrollView: NSScrollView, toY y: CGFloat) {
        let clipView = scrollView.contentView
        guard abs(clipView.bounds.origin.y - y) > 0.5 else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clipView)
    }
}

/// Tables and code blocks in the preview sit in horizontal scroll views. AppKit sends a whole
/// scroll gesture to the view under the pointer when it starts, so a vertical swipe that began
/// over a table stalled there. This local monitor sends gestures that start mostly vertical over a
/// nested scroll view to the preview's own scroll view, for the whole gesture including momentum,
/// and leaves mostly horizontal gestures to the nested view.
final class NestedScrollRouter {
    private weak var scrollView: NSScrollView?
    private var monitor: Any?
    /// The decision for the trackpad gesture in progress, made at its `.began` event.
    private var forwardingGesture = false

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self else { return event }
            return self.route(event)
        }
    }

    deinit {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
    }

    func route(_ event: NSEvent) -> NSEvent? {
        guard let scrollView = scrollView, event.window != nil, event.window === scrollView.window,
              shouldForward(phase: event.phase, momentumPhase: event.momentumPhase,
                            deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                            pointInWindow: event.locationInWindow) else { return event }
        scrollView.scrollWheel(with: event)
        return nil
    }

    /// Whether this scroll event should go to the preview's scroll view instead of the view under the pointer.
    func shouldForward(phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, deltaX: CGFloat, deltaY: CGFloat, pointInWindow: NSPoint) -> Bool {
        guard let scrollView = scrollView else { return false }
        let isVertical = abs(deltaY) >= abs(deltaX)

        // Mouse wheels have no phases and aren't latched, so decide per event.
        if phase.isEmpty && momentumPhase.isEmpty {
            return isVertical && isOverNestedScrollView(pointInWindow, in: scrollView)
        }

        if phase.contains(.began) {
            forwardingGesture = isVertical && isOverNestedScrollView(pointInWindow, in: scrollView)
        }
        let forward = forwardingGesture
        if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) {
            forwardingGesture = false
        }
        return forward
    }

    /// True when the pointer is over the preview content and the closest scroll view there is a
    /// nested one rather than the preview's own.
    private func isOverNestedScrollView(_ pointInWindow: NSPoint, in scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView, let contentView = scrollView.window?.contentView else { return false }
        let point = contentView.superview?.convert(pointInWindow, from: nil) ?? pointInWindow
        guard let hit = contentView.hitTest(point), hit.isDescendant(of: documentView) else { return false }
        var view: NSView? = hit
        while let current = view {
            if let nested = current as? NSScrollView { return nested !== scrollView }
            view = current.superview
        }
        return false
    }
}

struct PreviewScrollView<Content: View>: NSViewRepresentable {
    var scrollSync: ScrollSync?
    /// Identifies the content: the hosting view is only updated and re-measured when it (or the
    /// width) changes, not on every update of the enclosing view.
    var contentKey: AnyHashable? = nil
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let hostingView = NSHostingView(rootView: content())
        hostingView.autoresizingMask = [.width]
        scrollView.documentView = hostingView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollSync?.register(scrollView)
        context.coordinator.router = NestedScrollRouter(scrollView: scrollView)
        context.coordinator.scrollView = scrollView
        context.coordinator.observeAsynchronousContent()
        // Dragging the split divider or resizing the window doesn't always update SwiftUI; refit
        // when the visible width changes so the content's height follows it
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.scrollSync = scrollSync
        guard let hostingView = nsView.documentView as? NSHostingView<Content> else { return }
        let width = nsView.contentSize.width
        if contentKey == nil || contentKey != coordinator.lastContentKey {
            hostingView.rootView = content()
            coordinator.lastContentKey = contentKey
        } else if width == coordinator.lastWidth {
            return
        }
        coordinator.lastWidth = width
        Self.fit(hostingView, in: nsView)
    }
    
    /// Sizes the hosting view to its content at the scroll view's width (a synchronous layout of
    /// the whole preview, so it only runs when something changed).
    static func fit(_ hostingView: NSView, in scrollView: NSScrollView) {
        let currentWidth = scrollView.contentSize.width
        if currentWidth > 0 {
            hostingView.frame.size.width = currentWidth
        }
        let targetHeight = hostingView.fittingSize.height
        if hostingView.frame.height != targetHeight || hostingView.frame.width != currentWidth {
            hostingView.frame = NSRect(x: 0, y: 0, width: currentWidth, height: max(targetHeight, scrollView.contentSize.height))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollSync: scrollSync)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.router = nil
    }

    class Coordinator: NSObject {
        var scrollSync: ScrollSync?
        var router: NestedScrollRouter?
        weak var scrollView: NSScrollView?
        var lastContentKey: AnyHashable?
        var lastWidth: CGFloat = -1
        private var refitScheduled = false

        init(scrollSync: ScrollSync?) {
            self.scrollSync = scrollSync
        }
        
        /// Formulas, diagrams and images that become readable change the content's height without
        /// a new content key; re-measure when they land.
        func observeAsynchronousContent() {
            NotificationCenter.default.addObserver(self, selector: #selector(contentMayHaveResized), name: RichContentRenderer.didRender, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(contentMayHaveResized), name: NSNotification.Name("SwashFolderAccessGranted"), object: nil)
        }
        
        @objc private func contentMayHaveResized() {
            guard !refitScheduled else { return }
            refitScheduled = true
            // Let SwiftUI apply the new state first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                self.refitScheduled = false
                if let scrollView = self.scrollView, let hostingView = scrollView.documentView {
                    PreviewScrollView.fit(hostingView, in: scrollView)
                }
            }
        }
        
        @objc func clipViewFrameDidChange(_ notification: Notification) {
            guard let scrollView = scrollView, scrollView.contentSize.width != lastWidth else { return }
            lastWidth = scrollView.contentSize.width
            contentMayHaveResized()
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let scrollView = (notification.object as? NSClipView)?.superview as? NSScrollView else { return }
            scrollSync?.scrollViewDidScroll(scrollView)
        }
    }
}

struct MarkdownPreviewView: View {
    let text: String
    let flavor: MarkdownFlavor
    let baseURL: URL?
    var scrollSync: ScrollSync? = nil
    /// Reuses the last parse while the text is unchanged; the view is re-evaluated whenever
    /// `ContentView` updates (selection changes, banners), not only when the text changes.
    @State private var parseCache = ParseCache()
    /// The text being shown. Edits are picked up once typing pauses, so the preview isn't rebuilt
    /// and re-measured on every keystroke; nil until the first render, which shows `text` directly.
    @State private var renderedText: String? = nil
    @State private var revision = 0
    
    static let updateDelay: Duration = .milliseconds(200)
    
    /// `preparsed`: the parse of `text`, made off the main thread by the caller (Quick Look).
    init(text: String, flavor: MarkdownFlavor, baseURL: URL? = nil, scrollSync: ScrollSync? = nil, preparsed: MarkdownDocument? = nil) {
        self.text = text
        self.flavor = flavor
        self.baseURL = baseURL
        self.scrollSync = scrollSync
        if let preparsed = preparsed {
            _parseCache = State(initialValue: ParseCache(text: text, flavor: flavor, document: preparsed))
        }
    }
    
    private struct ContentKey: Hashable {
        let revision: Int
        let flavor: MarkdownFlavor
        let baseURL: URL?
    }
    
    var body: some View {
        let document = parseCache.document(for: renderedText ?? text, flavor: flavor)
        let blocks = document.root.children.filter {
            switch $0.kind {
            case .footnoteDefinition, .linkReferenceDefinition: return false
            default: return true
            }
        }
        let context = MarkdownRenderContext(document: document, baseURL: baseURL)
        
        PreviewScrollView(scrollSync: scrollSync, contentKey: ContentKey(revision: revision, flavor: flavor, baseURL: baseURL)) {
            VStack(alignment: .leading, spacing: 14) {
                if blocks.isEmpty {
                    Text("Nothing to preview yet. Start typing on the left!")
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.top, 24)
                } else {
                    MarkdownBlockList(nodes: blocks, context: context)
                    MarkdownFootnotesView(context: context)
                }
            }
            .font(.body)
            .foregroundColor(.primary)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        .task(id: text) {
            guard let shown = renderedText else {
                renderedText = text
                return
            }
            guard shown != text else { return }
            try? await Task.sleep(for: MarkdownPreviewView.updateDelay)
            guard !Task.isCancelled else { return }
            renderedText = text
            revision += 1
        }
    }
    
    /// Slack mrkdwn is converted to GFM first; everything else is parsed directly.
    static func parse(_ text: String, flavor: MarkdownFlavor) -> MarkdownDocument {
        let source = flavor == .slack ? MarkdownParser.convertSlackToGithub(text) : text
        return MarkdownDocument.parse(source)
    }
    
    final class ParseCache {
        private var key: (text: String, flavor: MarkdownFlavor)? = nil
        private var cached: MarkdownDocument? = nil
        
        init() {}
        
        init(text: String, flavor: MarkdownFlavor, document: MarkdownDocument) {
            key = (text, flavor)
            cached = document
        }
        
        func document(for text: String, flavor: MarkdownFlavor) -> MarkdownDocument {
            if let key = key, let cached = cached, key.flavor == flavor, key.text == text {
                return cached
            }
            let document = MarkdownPreviewView.parse(text, flavor: flavor)
            key = (text, flavor)
            cached = document
            return document
        }
    }
}

/// A sequence of sibling blocks. `<details>` … `</details>` HTML blocks and the Markdown between
/// them are grouped into a disclosure; every other block renders on its own.
struct MarkdownBlockList: View {
    let nodes: [MarkdownNode]
    let context: MarkdownRenderContext
    var spacing: CGFloat = 14
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // Blocks are identified by their source, so an edit only re-renders the blocks it changed
            ForEach(MarkdownBlockList.identified(MarkdownBlockList.group(nodes), source: context.document.source), id: \.id) { entry in
                switch entry.item {
                case .block(let node):
                    MarkdownBlockView(node: node, context: context).equatable()
                case .details(let summary, let open, let content):
                    MarkdownDetailsView(summary: summary, initiallyOpen: open, content: content, context: context)
                }
            }
        }
    }
    
    enum Item {
        case block(MarkdownNode)
        case details(summary: String, open: Bool, content: [MarkdownNode])
    }
    
    /// Stable identities: a hash of each item's source plus how many identical items precede it.
    static func identified(_ items: [Item], source: String) -> [(id: String, item: Item)] {
        let ns = source as NSString
        var seen: [Int: Int] = [:]
        return items.map { item in
            let range: NSRange
            switch item {
            case .block(let node): range = node.range
            case .details(_, _, let content):
                range = content.isEmpty ? NSRange(location: 0, length: 0) : NSUnionRange(content[0].range, content[content.count - 1].range)
            }
            let valid = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
            var hasher = Hasher()
            if case .details(let summary, _, _) = item { hasher.combine(summary) }
            hasher.combine(ns.substring(with: valid))
            let hash = hasher.finalize()
            let occurrence = seen[hash, default: 0]
            seen[hash] = occurrence + 1
            return ("\(hash)-\(occurrence)", item)
        }
    }
    
    private static func isDetailsOpen(_ node: MarkdownNode) -> Bool {
        guard case .htmlBlock = node.kind else { return false }
        return node.literal.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("<details")
    }
    
    private static func isDetailsClose(_ node: MarkdownNode) -> Bool {
        guard case .htmlBlock = node.kind else { return false }
        return node.literal.lowercased().contains("</details>")
    }
    
    static func summary(in html: String) -> String? {
        guard let start = html.range(of: "<summary[^>]*>", options: [.regularExpression, .caseInsensitive]),
              let end = html.range(of: "</summary>", options: .caseInsensitive, range: start.upperBound..<html.endIndex) else { return nil }
        let inner = String(html[start.upperBound..<end.lowerBound])
        return inner.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func group(_ nodes: [MarkdownNode]) -> [Item] {
        var items: [Item] = []
        var i = 0
        while i < nodes.count {
            let node = nodes[i]
            if isDetailsOpen(node), !isDetailsClose(node) {
                // Find the matching </details>, allowing nesting
                var depth = 1
                var j = i + 1
                while j < nodes.count {
                    if isDetailsOpen(nodes[j]) && !isDetailsClose(nodes[j]) { depth += 1 }
                    if isDetailsClose(nodes[j]) { depth -= 1; if depth == 0 { break } }
                    j += 1
                }
                if j < nodes.count {
                    var content = Array(nodes[(i + 1)..<j])
                    var summary = summary(in: node.literal)
                    // <summary> may be its own HTML block right after <details>
                    if summary == nil, let first = content.first, case .htmlBlock = first.kind, let s = MarkdownBlockList.summary(in: first.literal) {
                        summary = s
                        content.removeFirst()
                    }
                    let open = node.literal.range(of: "<details[^>]*\\bopen\\b", options: [.regularExpression, .caseInsensitive]) != nil
                    items.append(.details(summary: summary ?? "Details", open: open, content: content))
                    i = j + 1
                    continue
                }
            }
            items.append(.block(node))
            i += 1
        }
        return items
    }
}

struct MarkdownDetailsView: View {
    let summary: String
    let content: [MarkdownNode]
    let context: MarkdownRenderContext
    @State private var isExpanded: Bool
    
    init(summary: String, initiallyOpen: Bool, content: [MarkdownNode], context: MarkdownRenderContext) {
        self.summary = summary
        self.content = content
        self.context = context
        _isExpanded = State(initialValue: initiallyOpen)
    }
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            MarkdownBlockList(nodes: content, context: context, spacing: 10)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(summary).fontWeight(.semibold)
        }
    }
}

/// Raw HTML blocks: images (with their width) render directly; other HTML is converted to Markdown
/// and rendered as blocks. Fragments with no content (an opening <div>, a comment) render nothing.
struct MarkdownHTMLBlockView: View {
    let html: String
    let context: MarkdownRenderContext
    
    private static let imageTagRegex = try! NSRegularExpression(pattern: "<img\\b[^>]*>", options: [.caseInsensitive])
    
    var body: some View {
        let images = MarkdownHTMLBlockView.images(in: html)
        let markdown = HTMLToMarkdown.convert(html)
        let document = markdown.map { MarkdownDocument.parse($0) }
        let textContent = document.map { doc -> String in
            var text = ""
            doc.root.walk { if case .text = $0.kind { text += $0.literal } }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        if !images.isEmpty && textContent.isEmpty {
            MarkdownFlowLayout(spacing: 6) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    MarkdownImageView(alt: image.alt, urlString: image.src, baseURL: context.baseURL, maxWidth: image.width)
                }
            }
        } else if let document = document {
            MarkdownBlockList(nodes: document.root.children, context: MarkdownRenderContext(document: document, baseURL: context.baseURL), spacing: 10)
        }
    }
    
    static func images(in html: String) -> [(src: String, alt: String, width: CGFloat?)] {
        let ns = html as NSString
        return imageTagRegex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length)).compactMap { match in
            if case .image(let src, let alt, let width) = InlineHTMLTag(ns.substring(with: match.range)).kind {
                return (src, alt, width.map { CGFloat($0) })
            }
            return nil
        }
    }
}

/// Lays children out left to right, wrapping onto new rows (badge rows, image galleries).
struct MarkdownFlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Shared state for rendering one document: footnote numbering and the base URL for images.
struct MarkdownRenderContext {
    let document: MarkdownDocument
    let baseURL: URL?
    /// Changes when anything outside a block can change how it renders: link reference
    /// definitions and footnote numbering.
    let signature: Int
    
    init(document: MarkdownDocument, baseURL: URL?) {
        self.document = document
        self.baseURL = baseURL
        var hasher = Hasher()
        hasher.combine(document.footnoteOrder)
        for label in document.linkReferences.keys.sorted() {
            hasher.combine(label)
            hasher.combine(document.linkReferences[label]?.destination)
            hasher.combine(document.linkReferences[label]?.title)
        }
        self.signature = hasher.finalize()
    }
    
    func footnoteNumber(_ label: String) -> Int? {
        document.footnoteOrder.firstIndex(of: MarkdownSyntax.normalizeLabel(label)).map { $0 + 1 }
    }
}

/// Renders one block node (recursively for containers).
struct MarkdownBlockView: View, Equatable {
    let node: MarkdownNode
    let context: MarkdownRenderContext
    
    /// Same source, base URL and document-wide definitions render the same, even from a new parse.
    static func == (lhs: MarkdownBlockView, rhs: MarkdownBlockView) -> Bool {
        if lhs.node === rhs.node { return lhs.context.signature == rhs.context.signature && lhs.context.baseURL == rhs.context.baseURL }
        guard lhs.context.signature == rhs.context.signature, lhs.context.baseURL == rhs.context.baseURL,
              lhs.node.range.length == rhs.node.range.length else { return false }
        return lhs.source == rhs.source
    }
    
    private var source: String {
        let ns = context.document.source as NSString
        return ns.substring(with: NSIntersectionRange(node.range, NSRange(location: 0, length: ns.length)))
    }
    
    var body: some View {
        content
    }
    
    private func children(spacing: CGFloat = 10) -> some View {
        MarkdownBlockList(nodes: node.children, context: context, spacing: spacing)
    }
    
    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .heading(let level, _):
            VStack(alignment: .leading, spacing: 6) {
                MarkdownInlineView(nodes: node.children, context: context, mathFontSize: MarkdownBlockView.headingSize(for: level))
                    .font(MarkdownBlockView.headingFont(for: level))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                if level == 1 {
                    Divider().opacity(0.35).padding(.bottom, 4)
                } else if level == 2 {
                    Divider().opacity(0.2).padding(.bottom, 2)
                }
            }
            .padding(.top, level == 1 ? 16 : 10)
            
        case .paragraph:
            // Font and colour come from the enclosing context (body, quote, footnote…)
            MarkdownInlineView(nodes: node.children, context: context)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            
        case .blockQuote:
            children()
                .font(.system(.body, design: .serif))
                .italic()
                .foregroundColor(.secondary)
                .lineSpacing(6)
                .padding(.vertical, 8)
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(QuoteBox(color: .accentColor, fillOpacity: 0.04, cornerRadius: 4))
                .padding(.vertical, 6)
            
        case .alert(let type):
            let color = MarkdownBlockView.alertColor(type)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: MarkdownBlockView.alertIcon(type))
                        .foregroundColor(color)
                        .font(.system(size: 13, weight: .bold))
                    Text(type.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(color)
                }
                if node.firstChild != nil {
                    children(spacing: 8)
                        .font(.body)
                        .lineSpacing(5)
                        .foregroundColor(.primary)
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(QuoteBox(color: color, fillOpacity: 0.06, cornerRadius: 6))
            .padding(.vertical, 6)
            
        case .list(_, _, _, _, let tight):
            VStack(alignment: .leading, spacing: tight ? 6 : 12) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { index, item in
                    MarkdownListItemView(item: item, index: index, context: context)
                }
            }
            
        case .codeBlock(_, let info) where info.lowercased() == "math":
            // $$ display math (or ```math): typeset with KaTeX, centred
            MarkdownDisplayMathView(tex: node.literal)
            
        case .codeBlock(_, let info) where MarkdownBlockView.isMermaid(info):
            MarkdownMermaidView(source: node.literal)
            
        case .codeBlock(_, let info):
            let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
            CodeBlockView(code: node.literal.hasSuffix("\n") ? String(node.literal.dropLast()) : node.literal, language: language)
            
        case .htmlBlock:
            MarkdownHTMLBlockView(html: node.literal, context: context)
            
        case .thematicBreak:
            Divider()
                .opacity(0.3)
                .padding(.vertical, 12)
            
        case .table(let alignments):
            InteractiveTableView(
                tableData: MarkdownBlockView.tableData(node, alignments: alignments, source: context.document.source),
                flavor: .github,
                isEditable: false
            )
            .padding(.vertical, 6)
            
        case .frontMatter:
            Text(node.literal.trimmingCharacters(in: .newlines))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            
        case .footnoteDefinition, .linkReferenceDefinition:
            EmptyView()
            
        default:
            children()
        }
    }
    
    static func isMermaid(_ info: String) -> Bool {
        info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first?.lowercased() == "mermaid"
    }
    
    static func tableData(_ table: MarkdownNode, alignments: [TableAlignment], source: String) -> MarkdownTableData {
        let cells = MarkdownTableSource(table, source: source)
        return MarkdownTableData(headers: cells.headers, alignments: alignments, rows: cells.rows)
    }
    
    static func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 26
        case 2: return 20
        case 3: return 17
        case 4: return 15
        default: return 14
        }
    }
    
    static func headingFont(for level: Int) -> Font {
        .system(size: headingSize(for: level), design: .default)
    }
    
    static func alertColor(_ type: AlertType) -> Color {
        switch type {
        case .note: return .blue
        case .tip: return .green
        case .important: return .purple
        case .warning: return .orange
        case .caution: return .red
        }
    }
    
    static func alertIcon(_ type: AlertType) -> String {
        switch type {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "octagon.fill"
        }
    }
}

/// A KaTeX formula or Mermaid diagram rendered to an image. `fallback` is shown while it renders,
/// when the bundled renderer is unavailable, and on failure (with the error message).
struct RichContentImage<Fallback: View>: View {
    let kind: RichContentRenderer.Kind
    let source: String
    var fontSize: CGFloat = 13
    @ViewBuilder let fallback: (_ error: String?) -> Fallback
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var result: (request: RichContentRenderer.Request, outcome: RichContentRenderer.Outcome)?
    
    var body: some View {
        let request = RichContentRenderer.Request(kind: kind, source: source, dark: colorScheme == .dark, fontSize: fontSize)
        let outcome = result?.request == request ? result?.outcome : RichContentRenderer.shared.cached(request)
        Group {
            switch outcome {
            case .rendered(let rendered)?:
                Image(nsImage: rendered.image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: rendered.image.size.width)
                    // Its full height for the width: stacks would otherwise squeeze a flexible image
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(source))
                    .help(source)
            case .failed(let message)?:
                fallback(RichContentRenderer.isAvailable ? message : nil)
            case nil:
                fallback(nil)
            }
        }
        .task(id: request) {
            let outcome = await RichContentRenderer.shared.render(request)
            result = (request, outcome)
        }
    }
}

/// `$$` display math: KaTeX, with the Unicode approximation as the fallback.
struct MarkdownDisplayMathView: View {
    let tex: String
    
    var body: some View {
        RichContentImage(kind: .displayMath, source: tex, fontSize: 15) { error in
            VStack(spacing: 4) {
                Text(MarkdownMath.unicode(tex.replacingOccurrences(of: "\n", with: " ")))
                    .font(.system(size: 17, design: .serif))
                    .italic()
                    .textSelection(.enabled)
                if let error = error {
                    RichContentErrorLabel(title: "TeX", message: error)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
}

/// ```mermaid code blocks: the diagram, or the code itself until it renders (and on errors).
struct MarkdownMermaidView: View {
    let source: String
    
    var body: some View {
        RichContentImage(kind: .mermaid, source: source) { error in
            VStack(alignment: .leading, spacing: 4) {
                if let error = error {
                    RichContentErrorLabel(title: "Mermaid", message: error)
                }
                CodeBlockView(code: source.hasSuffix("\n") ? String(source.dropLast()) : source, language: "mermaid")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 6)
    }
}

struct RichContentErrorLabel: View {
    let title: String
    let message: String
    
    var body: some View {
        Label("\(title): \(message.components(separatedBy: .newlines).first ?? message)", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundColor(.orange)
            .lineLimit(2)
            .help(message)
    }
}

/// Cell markdown of a table node, taken verbatim from the source (escapes intact).
struct MarkdownTableSource {
    var headers: [String] = []
    var rows: [[String]] = []
    
    init(_ table: MarkdownNode, source: String) {
        let text = source as NSString
        func cell(_ node: MarkdownNode) -> String {
            NSMaxRange(node.range) <= text.length ? text.substring(with: node.range) : node.plainText
        }
        for section in table.children {
            switch section.kind {
            case .tableHead:
                headers = section.firstChild?.children.map(cell) ?? []
            case .tableRow:
                rows.append(section.children.map(cell))
            default:
                break
            }
        }
    }
}

/// The tinted box and leading bar behind quotes and callouts. The bar is an overlay, so it always
/// spans the content's full height, and the box keeps its natural height when the preview offers
/// it more (a short document in a tall pane).
struct QuoteBox: ViewModifier {
    let color: Color
    let fillOpacity: Double
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(color.opacity(fillOpacity))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MarkdownListItemView: View {
    let item: MarkdownNode
    let index: Int
    let context: MarkdownRenderContext
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker
            VStack(alignment: .leading, spacing: isTight ? 4 : 8) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    MarkdownBlockView(node: child, context: context).equatable()
                }
                if item.firstChild == nil {
                    Text(" ")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
    
    private var isTight: Bool {
        if let list = item.parent, case .list(_, _, _, _, let tight) = list.kind { return tight }
        return true
    }
    
    private var depth: Int {
        item.ancestors.filter { if case .listItem = $0.kind { return true }; return false }.count
    }
    
    @ViewBuilder
    private var marker: some View {
        if case .listItem(let task) = item.kind, let task = task {
            Image(systemName: task == .checked ? "checkmark.square.fill" : "square")
                .foregroundColor(task == .checked ? .accentColor : .secondary)
                .font(.system(size: 14))
                .frame(width: 16, alignment: .center)
        } else if let list = item.parent, case .list(let ordered, let start, let delimiter, _, _) = list.kind, ordered {
            Text("\(start + index)\(String(delimiter))")
                .font(.body)
                .foregroundColor(.secondary)
                .monospacedDigit()
        } else {
            Text(["•", "◦", "▪"][depth % 3])
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 10, alignment: .center)
        }
    }
}

struct MarkdownFootnotesView: View {
    let context: MarkdownRenderContext
    
    var body: some View {
        let definitions = footnoteDefinitions
        if !definitions.isEmpty {
            Divider()
                .opacity(0.3)
                .padding(.top, 16)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(definitions.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(entry.number).")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(entry.node.children.enumerated()), id: \.offset) { _, child in
                                MarkdownBlockView(node: child, context: context).equatable()
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    /// Referenced definitions in order of first reference (GFM numbering).
    private var footnoteDefinitions: [(number: Int, node: MarkdownNode)] {
        var byLabel: [String: MarkdownNode] = [:]
        context.document.root.walk { node in
            if case .footnoteDefinition(let label) = node.kind {
                let key = MarkdownSyntax.normalizeLabel(label)
                if byLabel[key] == nil { byLabel[key] = node }
            }
        }
        return context.document.footnoteOrder.enumerated().compactMap { index, label in
            byLabel[label].map { (index + 1, $0) }
        }
    }
}

struct MarkdownImageView: View {
    let alt: String
    let urlString: String
    var baseURL: URL? = nil
    /// Width from an HTML <img width="…"> attribute.
    var maxWidth: CGFloat? = nil
    @ObservedObject private var folderAccessManager = FolderAccessManager.shared
    
    private var cleanedData: (url: String, title: String?) {
        MarkdownParser.cleanImageURLAndTitle(urlString)
    }
    
    private var resolvedNSImage: NSImage? {
        MarkdownParser.resolveImage(urlString: cleanedData.url, baseURL: baseURL)
    }
    
    var body: some View {
        let (cleanURL, title) = cleanedData
        let tooltip = title ?? alt
        
        if let url = URL(string: cleanURL), (url.scheme == "http" || url.scheme == "https") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(alt.isEmpty ? "Loading image..." : alt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: maxWidth)
                        .cornerRadius(6)
                        .help(tooltip)
                case .failure:
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .foregroundColor(.secondary)
                        Text(alt.isEmpty ? cleanURL : alt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
                @unknown default:
                    EmptyView()
                }
            }
            .padding(.vertical, 6)
        } else if let nsImage = resolvedNSImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxWidth ?? nsImage.size.width)
                .cornerRadius(6)
                .help(tooltip)
                .padding(.vertical, 6)
        } else {
            let isRelativeLocal = !cleanURL.isEmpty && !cleanURL.contains("://") && !cleanURL.hasPrefix("/")
            let folderURL = baseURL.map { $0.hasDirectoryPath ? $0 : $0.deletingLastPathComponent() }
            let needsPermission = isRelativeLocal && (folderURL != nil && !FolderAccessManager.shared.hasAccess(to: folderURL!))
            
            Button(action: {
                if let folder = folderURL {
                    FolderAccessManager.shared.promptForAccess(to: folder, window: nil) { _ in }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: needsPermission ? "folder.badge.questionmark" : "photo")
                        .foregroundColor(needsPermission ? .accentColor : .secondary)
                    Text(alt.isEmpty ? cleanURL : alt)
                        .font(.caption)
                        .foregroundColor(needsPermission ? .accentColor : .secondary)
                    if needsPermission {
                        Text("(Click to grant access)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help(needsPermission ? "Click to grant Swash permission to access this folder" : tooltip)
            .padding(.vertical, 6)
        }
    }
}

/// Inline Markdown in a view: text runs concatenated into one Text (so emphasis, code and
/// strikethrough compose with the surrounding font), with images split out as image views.
struct MarkdownInlineView: View {
    let nodes: [MarkdownNode]
    let context: MarkdownRenderContext
    /// Point size of the surrounding text, so rendered inline math matches it (headings are larger).
    var mathFontSize: CGFloat = MarkdownInlineAttributes.bodyMathFontSize
    
    @Environment(\.colorScheme) private var colorScheme
    /// Bumped when a formula this view is waiting on finishes rendering.
    @State private var renderGeneration = 0
    
    var body: some View {
        var pendingMath = false
        let segments = MarkdownInlineAttributes.segments(nodes, context: context, dark: colorScheme == .dark, mathFontSize: mathFontSize, pendingMath: &pendingMath)
        let _ = renderGeneration
        content(segments)
            .onReceive(NotificationCenter.default.publisher(for: RichContentRenderer.didRender)) { _ in
                if pendingMath { renderGeneration += 1 }
            }
    }
    
    @ViewBuilder
    private func content(_ segments: [MarkdownInlineSegment]) -> some View {
        if segments.count == 1, case .text(let text) = segments[0] {
            text.fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        text.fixedSize(horizontal: false, vertical: true)
                    case .image(let alt, let url, let width):
                        MarkdownImageView(alt: alt, urlString: url, baseURL: context.baseURL, maxWidth: width)
                    }
                }
            }
        }
    }
}

/// Inline Markdown from a raw string (table cells and other inline-only contexts).
struct InlineMarkdownText: View, Equatable {
    let text: String
    let flavor: MarkdownFlavor
    var baseURL: URL? = nil
    
    /// Recent cell parses. Table cells are re-evaluated whenever the table's hover or editing
    /// state changes; re-parsing every cell then made clicking into a cell slow.
    @MainActor private static var parses: [String: MarkdownDocument] = [:]
    
    @MainActor private static func document(for text: String, flavor: MarkdownFlavor) -> MarkdownDocument {
        let key = "\(flavor.rawValue)\u{0}\(text)"
        if let cached = parses[key] { return cached }
        if parses.count > 1024 { parses.removeAll(keepingCapacity: true) }
        let document = MarkdownPreviewView.parse(text, flavor: flavor)
        parses[key] = document
        return document
    }
    
    var body: some View {
        let document = Self.document(for: text, flavor: flavor)
        // Inline-only: use the inline content of every leaf block
        var inlines: [MarkdownNode] = []
        document.root.walk { node in
            switch node.kind {
            case .paragraph, .heading:
                if !inlines.isEmpty { inlines.append(MarkdownNode(.softBreak, range: node.range)) }
                inlines.append(contentsOf: node.children)
            default:
                break
            }
        }
        return MarkdownInlineView(nodes: inlines, context: MarkdownRenderContext(document: document, baseURL: baseURL))
    }
}

enum MarkdownInlineSegment {
    case text(Text)
    case image(alt: String, url: String, width: CGFloat?)
}

/// Builds SwiftUI Text from inline AST nodes.
enum MarkdownInlineAttributes {
    private struct Style {
        var bold = false
        var italic = false
        var mono = false
        var strike = false
        var link: URL? = nil
        var superscript = false
        var lowered = false
        var math = false
        var underline = false
        var highlight = false
        var keyboard = false
        var small = false
        
        mutating func apply(_ html: InlineHTMLStyle) {
            switch html {
            case .keyboard: keyboard = true; mono = true
            case .lowered: lowered = true
            case .raised: superscript = true
            case .highlight: highlight = true
            case .underline: underline = true
            case .strikethrough: strike = true
            case .bold: bold = true
            case .italic: italic = true
            case .small: small = true
            case .code: mono = true
            }
        }
    }
    
    /// Inline math uses its KaTeX rendering once cached; until then (or if it fails) the Unicode
    /// approximation, with `pendingMath` set so the caller can refresh when the render lands.
    /// The Preview's body text size (`.body`).
    static let bodyMathFontSize: CGFloat = 13
    
    static func segments(_ nodes: [MarkdownNode], context: MarkdownRenderContext, dark: Bool = false, mathFontSize: CGFloat = bodyMathFontSize) -> [MarkdownInlineSegment] {
        var pending = false
        return segments(nodes, context: context, dark: dark, mathFontSize: mathFontSize, pendingMath: &pending)
    }
    
    static func segments(_ nodes: [MarkdownNode], context: MarkdownRenderContext, dark: Bool, mathFontSize: CGFloat = bodyMathFontSize, pendingMath: inout Bool) -> [MarkdownInlineSegment] {
        var segments: [MarkdownInlineSegment] = []
        var pending = false
        var current: Text? = nil
        func flush() {
            if let text = current {
                segments.append(.text(text))
                current = nil
            }
        }
        func append(_ string: String, _ style: Style) {
            guard !string.isEmpty else { return }
            var attributed = AttributedString(string)
            if let url = style.link {
                attributed.link = url
                attributed.underlineStyle = .single
                attributed.foregroundColor = .accentColor
            }
            if style.highlight { attributed.backgroundColor = Color.yellow.opacity(0.4) }
            if style.keyboard { attributed.backgroundColor = Color.secondary.opacity(0.15) }
            var run = Text(attributed)
            if style.bold { run = run.bold() }
            if style.italic { run = run.italic() }
            if style.strike { run = run.strikethrough() }
            if style.underline { run = run.underline() }
            if style.math { run = run.fontDesign(.serif).italic() }
            if style.mono {
                run = run.monospaced()
                if style.link == nil && !style.keyboard { run = run.foregroundColor(.accentColor) }
            }
            if style.small { run = run.font(.callout) }
            if style.lowered { run = run.font(.system(size: 10)).baselineOffset(-3) }
            if style.superscript {
                // Footnote references (links) are accent-coloured; <sup> text keeps its colour
                run = run.font(.system(size: 10, weight: .semibold)).baselineOffset(4)
                if style.link != nil { run = run.foregroundColor(.accentColor) }
            }
            current = current.map { $0 + run } ?? run
        }
        /// Visits siblings, applying paired inline HTML tags (<kbd>…</kbd>) to the nodes between them.
        func visitChildren(_ children: [MarkdownNode], _ style: Style) {
            let pairing = MarkdownInlineHTML.pairing(of: children)
            for (index, child) in children.enumerated() where !pairing.pairedTags.contains(index) {
                var childStyle = style
                for html in pairing.styles[index] ?? [] { childStyle.apply(html) }
                visit(child, childStyle)
            }
        }
        func visit(_ node: MarkdownNode, _ style: Style) {
            var style = style
            switch node.kind {
            case .text:
                append(node.literal, style)
            case .softBreak:
                append(" ", style)
            case .hardBreak:
                append("\n", style)
            case .code:
                style.mono = true
                append(node.literal, style)
            case .emphasis:
                style.italic = true
                visitChildren(node.children, style)
            case .strong:
                style.bold = true
                visitChildren(node.children, style)
            case .strikethrough:
                style.strike = true
                visitChildren(node.children, style)
            case .link(let destination, _, _):
                style.link = MarkdownEditorStyler.url(destination)
                visitChildren(node.children, style)
            case .image(let destination, _):
                flush()
                segments.append(.image(alt: node.plainText, url: destination, width: nil))
            case .htmlInline:
                // Raw HTML tags are not shown; <br> becomes a line break and <img> an image
                switch InlineHTMLTag(node.literal).kind {
                case .lineBreak: append("\n", style)
                case .image(let src, let alt, let width):
                    flush()
                    segments.append(.image(alt: alt, url: src, width: width.map { CGFloat($0) }))
                default: break
                }
            case .math:
                let request = RichContentRenderer.Request(kind: .inlineMath, source: node.literal, dark: dark, fontSize: mathFontSize)
                switch RichContentRenderer.cachedOrRequest(request) {
                case .rendered(let rendered)?:
                    let run = Text(Image(nsImage: rendered.image)).baselineOffset(-rendered.descent)
                    current = current.map { $0 + run } ?? run
                case .failed?:
                    style.math = true
                    append(MarkdownMath.unicode(node.literal), style)
                case nil:
                    pending = RichContentRenderer.isAvailable
                    style.math = true
                    append(MarkdownMath.unicode(node.literal), style)
                }
            case .footnoteReference(let label):
                style.superscript = true
                style.link = URL(string: "#fn-\(MarkdownSyntax.normalizeURI(label))")
                append(context.footnoteNumber(label).map(String.init) ?? label, style)
            default:
                visitChildren(node.children, style)
            }
        }
        visitChildren(nodes, Style())
        flush()
        if segments.isEmpty { segments.append(.text(Text(""))) }
        pendingMath = pending
        return segments
    }
}

// Clean Github-style Table renderer
struct TableView: View {
    let headers: [String]
    let rows: [[String]]
    let flavor: MarkdownFlavor
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(0..<headers.count, id: \.self) { colIndex in
                    InlineMarkdownText(text: headers[colIndex], flavor: flavor)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if colIndex < headers.count - 1 {
                        Divider().opacity(0.3)
                    }
                }
            }
            .background(Color.secondary.opacity(0.12))
            
            Divider().opacity(0.35)
            
            // Rows
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    let row = rows[rowIndex]
                    ForEach(0..<headers.count, id: \.self) { colIndex in
                        let cellText = colIndex < row.count ? row[colIndex] : ""
                        InlineMarkdownText(text: cellText, flavor: flavor)
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        if colIndex < headers.count - 1 {
                            Divider().opacity(0.2)
                        }
                    }
                }
                .background(rowIndex % 2 == 1 ? Color.secondary.opacity(0.04) : Color.clear)
                
                if rowIndex < rows.count - 1 {
                    Divider().opacity(0.2)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(6)
        .padding(.vertical, 6)
    }
}

// Copyable, beautifully styled monospaced Code Block component
struct CodeBlockView: View {
    let code: String
    let language: String?
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isHovering = false
    @State private var isCopied = false
    
    private var highlightedCode: AttributedString {
        let mutableAttrString = NSMutableAttributedString(string: code)
        let fullRange = NSRange(location: 0, length: mutableAttrString.length)
        
        let defaultColor = colorScheme == .dark ? NSColor(white: 0.9, alpha: 1.0) : NSColor.textColor.withAlphaComponent(0.9)
        let commentColor = colorScheme == .dark ? NSColor(white: 0.55, alpha: 1.0) : NSColor.secondaryLabelColor
        
        // Use monospaced font by default for syntax highlighting
        mutableAttrString.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: fullRange)
        mutableAttrString.addAttribute(.foregroundColor, value: defaultColor, range: fullRange)
        
        guard let lang = language else {
            return AttributedString(mutableAttrString)
        }
        let lowerLang = lang.lowercased()
        
        let lines = code.components(separatedBy: .newlines)
        var offset = 0
        for line in lines {
            let lineLength = line.utf16.count
            let lineRange = NSRange(location: offset, length: lineLength)
            
            // Common Comments
            var isCommentLine = false
            if ["python", "bash", "sh"].contains(lowerLang) {
                if let commentIdx = line.firstIndex(of: "#") {
                    let nsCommentStart = line.distance(from: line.startIndex, to: commentIdx)
                    let commentRange = NSRange(location: offset + nsCommentStart, length: lineLength - nsCommentStart)
                    mutableAttrString.addAttribute(.foregroundColor, value: commentColor, range: commentRange)
                    isCommentLine = true
                }
            } else if ["javascript", "swift", "html", "css", "json"].contains(lowerLang) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") {
                    mutableAttrString.addAttribute(.foregroundColor, value: commentColor, range: lineRange)
                    isCommentLine = true
                }
            }
            
            if !isCommentLine {
                // Highlight keywords
                var keywords: [String] = []
                if ["javascript", "swift"].contains(lowerLang) {
                    keywords = ["func", "function", "let", "var", "const", "return", "class", "import", "if", "else", "for", "while", "in", "switch", "case", "break", "continue", "struct", "enum"]
                } else if lowerLang == "python" {
                    keywords = ["def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "in", "as", "try", "except", "lambda", "pass"]
                } else if lowerLang == "css" {
                    keywords = ["body", "html", "div", "span", "p", "a", "img", "button", "input", "label", "form", "section", "header", "footer", "h1", "h2", "h3"]
                } else if ["bash", "sh"].contains(lowerLang) {
                    keywords = ["if", "then", "else", "elif", "fi", "for", "while", "in", "do", "done", "case", "esac", "function", "return", "local", "echo", "exit"]
                }
                
                if !keywords.isEmpty {
                    let wordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
                    if let regex = try? NSRegularExpression(pattern: wordPattern, options: []) {
                        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: lineLength))
                        for match in matches {
                            let matchRange = NSRange(location: offset + match.range.location, length: match.range.length)
                            mutableAttrString.addAttribute(.foregroundColor, value: NSColor.systemPink, range: matchRange)
                        }
                    }
                }
                
                // Highlight strings
                let stringPattern = "\"[^\"]*\"|'[^']*'"
                if let stringRegex = try? NSRegularExpression(pattern: stringPattern, options: []) {
                    let matches = stringRegex.matches(in: line, options: [], range: NSRange(location: 0, length: lineLength))
                    for match in matches {
                        let matchRange = NSRange(location: offset + match.range.location, length: match.range.length)
                        mutableAttrString.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: matchRange)
                    }
                }
                
                // Highlight numbers
                let numberPattern = "\\b\\d+\\b"
                if let numberRegex = try? NSRegularExpression(pattern: numberPattern, options: []) {
                    let matches = numberRegex.matches(in: line, options: [], range: NSRange(location: 0, length: lineLength))
                    for match in matches {
                        let matchRange = NSRange(location: offset + match.range.location, length: match.range.length)
                        mutableAttrString.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: matchRange)
                    }
                }
            }
            
            offset += lineLength + 1
        }
        
        return AttributedString(mutableAttrString)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Optional Language header
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.textColor).opacity(0.04))
            
            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlightedCode)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(Color(NSColor.textColor).opacity(0.02))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .padding(.vertical, 4)
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isCopied = false
            }
        }
    }
}
