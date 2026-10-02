//
//  MarkdownPreviewView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import AppKit

struct PreviewScrollView<Content: View>: NSViewRepresentable {
    @Binding var scrollOriginY: CGFloat
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

        DispatchQueue.main.async { [weak scrollView] in
            guard let scrollView = scrollView else { return }
            let clipView = scrollView.contentView
            let targetPoint = NSPoint(x: clipView.bounds.origin.x, y: context.coordinator.parent.scrollOriginY)
            clipView.scroll(to: targetPoint)
            scrollView.reflectScrolledClipView(clipView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content()
            let currentWidth = nsView.contentSize.width
            if currentWidth > 0 {
                hostingView.frame.size.width = currentWidth
            }
            let targetHeight = hostingView.fittingSize.height
            if hostingView.frame.height != targetHeight || hostingView.frame.width != currentWidth {
                hostingView.frame = NSRect(x: 0, y: 0, width: currentWidth, height: max(targetHeight, nsView.contentSize.height))
            }
        }

        let clipView = nsView.contentView
        if abs(clipView.bounds.origin.y - scrollOriginY) > 1.0 {
            context.coordinator.isProgrammaticScroll = true
            let targetPoint = NSPoint(x: clipView.bounds.origin.x, y: scrollOriginY)
            clipView.scroll(to: targetPoint)
            nsView.reflectScrolledClipView(clipView)
            DispatchQueue.main.async {
                context.coordinator.isProgrammaticScroll = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: PreviewScrollView
        var isProgrammaticScroll = false

        init(_ parent: PreviewScrollView) {
            self.parent = parent
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard !isProgrammaticScroll else { return }
            if let clipView = notification.object as? NSClipView {
                let y = clipView.bounds.origin.y
                if abs(parent.scrollOriginY - y) > 0.5 {
                    DispatchQueue.main.async {
                        self.parent.scrollOriginY = y
                    }
                }
            }
        }
    }
}

struct MarkdownPreviewView: View {
    let text: String
    let flavor: MarkdownFlavor
    let baseURL: URL?
    @Binding var scrollOriginY: CGFloat
    
    init(text: String, flavor: MarkdownFlavor, baseURL: URL? = nil, scrollOriginY: Binding<CGFloat> = .constant(0)) {
        self.text = text
        self.flavor = flavor
        self.baseURL = baseURL
        self._scrollOriginY = scrollOriginY
    }
    
    var body: some View {
        let document = MarkdownPreviewView.parse(text, flavor: flavor)
        let blocks = document.root.children.filter {
            switch $0.kind {
            case .footnoteDefinition, .linkReferenceDefinition: return false
            default: return true
            }
        }
        let context = MarkdownRenderContext(document: document, baseURL: baseURL)
        
        PreviewScrollView(scrollOriginY: $scrollOriginY) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
    }
    
    /// Slack mrkdwn is converted to GFM first; everything else is parsed directly.
    static func parse(_ text: String, flavor: MarkdownFlavor) -> MarkdownDocument {
        let source = flavor == .slack ? MarkdownParser.convertSlackToGithub(text) : text
        return MarkdownDocument.parse(source)
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
            ForEach(Array(MarkdownBlockList.group(nodes).enumerated()), id: \.offset) { _, item in
                switch item {
                case .block(let node):
                    AnyView(MarkdownBlockView(node: node, context: context))
                case .details(let summary, let open, let content):
                    AnyView(MarkdownDetailsView(summary: summary, initiallyOpen: open, content: content, context: context))
                }
            }
        }
    }
    
    enum Item {
        case block(MarkdownNode)
        case details(summary: String, open: Bool, content: [MarkdownNode])
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
    
    func footnoteNumber(_ label: String) -> Int? {
        document.footnoteOrder.firstIndex(of: MarkdownSyntax.normalizeLabel(label)).map { $0 + 1 }
    }
}

/// Renders one block node (recursively for containers).
struct MarkdownBlockView: View {
    let node: MarkdownNode
    let context: MarkdownRenderContext
    
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
                MarkdownInlineView(nodes: node.children, context: context)
                    .font(MarkdownBlockView.headingFont(for: level))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                if level == 1 {
                    Divider().background(Color.secondary.opacity(0.3)).padding(.bottom, 4)
                } else if level == 2 {
                    Divider().background(Color.secondary.opacity(0.15)).padding(.bottom, 2)
                }
            }
            .padding(.top, level == 1 ? 16 : 10)
            
        case .paragraph:
            // Font and colour come from the enclosing context (body, quote, footnote…)
            MarkdownInlineView(nodes: node.children, context: context)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            
        case .blockQuote:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 4)
                children()
                    .font(.system(.body, design: .serif))
                    .italic()
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.04))
            }
            .cornerRadius(4)
            .padding(.vertical, 6)
            
        case .alert(let type):
            let color = MarkdownBlockView.alertColor(type)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4)
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
                            .lineSpacing(3)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.06))
            }
            .cornerRadius(6)
            .padding(.vertical, 6)
            
        case .list(_, _, _, _, let tight):
            VStack(alignment: .leading, spacing: tight ? 4 : 10) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { index, item in
                    MarkdownListItemView(item: item, index: index, context: context)
                }
            }
            
        case .codeBlock(_, let info) where info.lowercased() == "math":
            // $$ display math (or ```math): a readable Unicode rendering, centred
            Text(MarkdownMath.unicode(node.literal.replacingOccurrences(of: "\n", with: " ")))
                .font(.system(size: 17, design: .serif))
                .italic()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            
        case .codeBlock(_, let info):
            let language = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
            CodeBlockView(code: node.literal.hasSuffix("\n") ? String(node.literal.dropLast()) : node.literal, language: language)
            
        case .htmlBlock:
            MarkdownHTMLBlockView(html: node.literal, context: context)
            
        case .thematicBreak:
            Divider()
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
    
    static func tableData(_ table: MarkdownNode, alignments: [TableAlignment], source: String) -> MarkdownTableData {
        let cells = MarkdownTableSource(table, source: source)
        return MarkdownTableData(headers: cells.headers, alignments: alignments, rows: cells.rows)
    }
    
    static func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 26, design: .default)
        case 2: return .system(size: 20, design: .default)
        case 3: return .system(size: 17, design: .default)
        case 4: return .system(size: 15, design: .default)
        default: return .system(size: 14, design: .default)
        }
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

struct MarkdownListItemView: View {
    let item: MarkdownNode
    let index: Int
    let context: MarkdownRenderContext
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker
            VStack(alignment: .leading, spacing: isTight ? 4 : 10) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                    AnyView(MarkdownBlockView(node: child, context: context))
                }
                if item.firstChild == nil {
                    Text(" ")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
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
                .background(Color.secondary.opacity(0.3))
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
                                AnyView(MarkdownBlockView(node: child, context: context))
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
    
    var body: some View {
        let segments = MarkdownInlineAttributes.segments(nodes, context: context)
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
struct InlineMarkdownText: View {
    let text: String
    let flavor: MarkdownFlavor
    var baseURL: URL? = nil
    
    var body: some View {
        let document = MarkdownPreviewView.parse(text, flavor: flavor)
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
    
    static func segments(_ nodes: [MarkdownNode], context: MarkdownRenderContext) -> [MarkdownInlineSegment] {
        var segments: [MarkdownInlineSegment] = []
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
                if style.link == nil && !style.keyboard { run = run.foregroundColor(Color(nsColor: .systemPurple)) }
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
                style.math = true
                append(MarkdownMath.unicode(node.literal), style)
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
                        Divider()
                    }
                }
            }
            .background(Color.secondary.opacity(0.12))
            
            Divider()
            
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
                            Divider()
                        }
                    }
                }
                .background(rowIndex % 2 == 1 ? Color.secondary.opacity(0.04) : Color.clear)
                
                if rowIndex < rows.count - 1 {
                    Divider()
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
