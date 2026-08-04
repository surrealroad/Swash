//
//  BubbleMenuView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import AppKit

enum FormatAction: Hashable {
    case bold
    case italic
    case code
    case strikethrough
    case heading
    case h1
    case h2
    case h3
    case h4
    case h5
    case h6
    case quote
    case bulletList
    case numberedList
    case table
}

enum CodeFormat: Hashable, CaseIterable {
    case inline
    case plainBlock
    case javascript
    case swift
    case python
    case html
    case css
    case json
    case bash
    
    var name: String {
        switch self {
        case .inline: return "Inline Code"
        case .plainBlock: return "Plain Block"
        case .javascript: return "JavaScript"
        case .swift: return "Swift"
        case .python: return "Python"
        case .html: return "HTML"
        case .css: return "CSS"
        case .json: return "JSON"
        case .bash: return "Bash"
        }
    }
    
    var label: String {
        switch self {
        case .inline: return "Inline"
        case .plainBlock: return "Plain"
        case .javascript: return "JS"
        case .swift: return "Swift"
        case .python: return "Python"
        case .html: return "HTML"
        case .css: return "CSS"
        case .json: return "JSON"
        case .bash: return "Bash"
        }
    }
    
    var languageSignifier: String? {
        switch self {
        case .inline: return nil
        case .plainBlock: return nil
        case .javascript: return "javascript"
        case .swift: return "swift"
        case .python: return "python"
        case .html: return "html"
        case .css: return "css"
        case .json: return "json"
        case .bash: return "bash"
        }
    }
}

enum BubbleMenuContext: Hashable {
    case codeBlock
    case tableCell
    case heading
    case listItem
    case blockquote
    case standard
}

struct BubbleMenuView: View {
    let activeFormats: Set<FormatAction>
    let activeCodeFormat: CodeFormat?
    let activeHeadingLevel: Int?
    let activeLink: DetectedLink?
    let context: BubbleMenuContext
    let onAction: (FormatAction) -> Void
    let onSelectCodeFormat: (CodeFormat) -> Void
    let onSelectHeadingLevel: (Int) -> Void
    let onApplyLink: (String) -> Void
    let onRemoveLink: () -> Void
    
    @State private var isPresentingLinkPopover = false
    
    var body: some View {
        HStack(spacing: 4) {
            if context == .codeBlock || activeFormats.contains(.code) {
                BubbleButton(
                    systemImage: "curlybraces",
                    textLabel: nil,
                    tooltip: "Toggle Code Off",
                    isActive: true,
                    action: { onAction(.code) }
                )
                
                if let currentFormat = activeCodeFormat {
                    codeFormatDropdown(currentFormat: currentFormat)
                }
                
                if context == .tableCell || activeFormats.contains(.table) {
                    BubbleButton(
                        systemImage: "tablecells",
                        textLabel: nil,
                        tooltip: "Remove Table",
                        isActive: true,
                        action: { onAction(.table) }
                    )
                }
            } else {
                BubbleButton(systemImage: "bold", textLabel: nil, tooltip: "Bold (⌘B)", isActive: activeFormats.contains(.bold), action: { onAction(.bold) })
                BubbleButton(systemImage: "italic", textLabel: nil, tooltip: "Italic (⌘I)", isActive: activeFormats.contains(.italic), action: { onAction(.italic) })
                BubbleButton(systemImage: "curlybraces", textLabel: nil, tooltip: "Code Formatting", isActive: activeFormats.contains(.code), action: { onAction(.code) })
                
                if activeFormats.contains(.code), let currentFormat = activeCodeFormat {
                    codeFormatDropdown(currentFormat: currentFormat)
                }
                
                BubbleButton(systemImage: "strikethrough", textLabel: nil, tooltip: "Strikethrough", isActive: activeFormats.contains(.strikethrough), action: { onAction(.strikethrough) })
                
                BubbleButton(
                    systemImage: "link",
                    textLabel: nil,
                    tooltip: activeLink != nil ? "Edit Link" : "Add Link",
                    isActive: activeLink != nil,
                    action: {
                        isPresentingLinkPopover.toggle()
                    }
                )
                .popover(isPresented: $isPresentingLinkPopover, arrowEdge: .bottom) {
                    LinkEditorPopoverView(
                        initialURL: activeLink?.url ?? "",
                        isEditing: activeLink != nil,
                        onApply: { url in
                            isPresentingLinkPopover = false
                            onApplyLink(url)
                        },
                        onRemove: {
                            isPresentingLinkPopover = false
                            onRemoveLink()
                        },
                        onCancel: {
                            isPresentingLinkPopover = false
                        }
                    )
                }
                
                if context == .standard || context == .heading || context == .blockquote {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    BubbleButton(
                        systemImage: nil,
                        textLabel: "H",
                        tooltip: activeHeadingLevel != nil ? "Toggle Heading Off" : "Toggle Heading On",
                        isActive: activeHeadingLevel != nil,
                        action: { onAction(.heading) }
                    )
                    
                    if let currentLevel = activeHeadingLevel {
                        headingLevelDropdown(currentLevel: currentLevel)
                    }
                    
                    if context != .heading {
                        BubbleButton(systemImage: "quote.bubble", textLabel: nil, tooltip: "Blockquote", isActive: activeFormats.contains(.quote), action: { onAction(.quote) })
                    }
                } else if context == .listItem {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    BubbleButton(systemImage: "quote.bubble", textLabel: nil, tooltip: "Blockquote", isActive: activeFormats.contains(.quote), action: { onAction(.quote) })
                }
                
                if context == .standard || context == .listItem || context == .blockquote {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    BubbleButton(systemImage: "list.bullet", textLabel: nil, tooltip: "Bullet List", isActive: activeFormats.contains(.bulletList), action: { onAction(.bulletList) })
                    BubbleButton(systemImage: "list.number", textLabel: nil, tooltip: "Numbered List", isActive: activeFormats.contains(.numberedList), action: { onAction(.numberedList) })
                    
                    if context == .standard {
                        BubbleButton(systemImage: "tablecells", textLabel: nil, tooltip: "Table", isActive: activeFormats.contains(.table), action: { onAction(.table) })
                    }
                } else if context == .tableCell || activeFormats.contains(.table) {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    BubbleButton(systemImage: "tablecells", textLabel: nil, tooltip: "Remove Table", isActive: true, action: { onAction(.table) })
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: activeFormats)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: activeCodeFormat)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: activeHeadingLevel)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: context)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cursor(.arrow)
    }
    
    @ViewBuilder
    private func codeFormatDropdown(currentFormat: CodeFormat) -> some View {
        Menu {
            ForEach(CodeFormat.allCases, id: \.self) { format in
                Button(action: {
                    onSelectCodeFormat(format)
                }) {
                    HStack {
                        Text(format.name)
                        if format == currentFormat {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(currentFormat.label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(Color.accentColor)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .cursor(.arrow)
        .frame(width: 72)
        .help("Select code format or language")
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 0.8, anchor: .center).combined(with: .opacity)
        ))
    }
    
    @ViewBuilder
    private func headingLevelDropdown(currentLevel: Int) -> some View {
        Menu {
            ForEach(1...6, id: \.self) { level in
                Button(action: {
                    onSelectHeadingLevel(level)
                }) {
                    HStack {
                        Text("Heading \(level) (H\(level))")
                        if level == currentLevel {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text("H\(currentLevel)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(Color.accentColor)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(Color.accentColor.opacity(0.12))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .cursor(.arrow)
        .frame(width: 48)
        .help("Select heading level")
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 0.8, anchor: .center).combined(with: .opacity)
        ))
    }
}

struct LinkEditorPopoverView: View {
    let initialURL: String
    let isEditing: Bool
    let onApply: (String) -> Void
    let onRemove: () -> Void
    let onCancel: () -> Void
    
    @State private var urlText: String
    @FocusState private var isTextFieldFocused: Bool
    
    init(initialURL: String, isEditing: Bool, onApply: @escaping (String) -> Void, onRemove: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.initialURL = initialURL
        self.isEditing = isEditing
        self.onApply = onApply
        self.onRemove = onRemove
        self.onCancel = onCancel
        _urlText = State(initialValue: initialURL)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isEditing ? "Edit Link" : "Add Link")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                TextField("https://example.com", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($isTextFieldFocused)
                    .cursor(.iBeam)
                    .onSubmit {
                        submit()
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            
            HStack(spacing: 8) {
                if isEditing {
                    Button(action: {
                        onRemove()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "link.badge.minus")
                                .font(.system(size: 11))
                            Text("Remove Link")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .cursor(.arrow)
                    .help("Remove link and keep text")
                }
                
                Spacer()
                
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .cursor(.arrow)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Button(action: submit) {
                    Text(isEditing ? "Update" : "Add")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .cursor(.arrow)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func submit() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onApply(trimmed)
        }
    }
}

struct BubbleButton: View {
    let systemImage: String?
    let textLabel: String?
    let tooltip: String
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12.5, weight: .semibold))
                } else if let textLabel = textLabel {
                    Text(textLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
            .foregroundColor(isActive ? Color.accentColor : (isHovered ? .primary : .primary.opacity(0.75)))
            .frame(width: 28, height: 28)
            .background(isActive ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.1) : Color.clear))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .cursor(.arrow)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help(tooltip)
    }
}

// MARK: - NSCursor Helpers

struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content
            .background(CursorView(cursor: cursor))
    }
}

struct CursorView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> NSCursorTrackingView {
        return NSCursorTrackingView(cursor: cursor)
    }

    func updateNSView(_ nsView: NSCursorTrackingView, context: Context) {
        nsView.cursor = cursor
    }
}

final class NSCursorTrackingView: NSView {
    var cursor: NSCursor {
        didSet {
            if oldValue != cursor {
                updateTrackingAreas()
            }
        }
    }

    private var trackingArea: NSTrackingArea?

    init(cursor: NSCursor) {
        self.cursor = cursor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [
            .cursorUpdate,
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeInKeyWindow,
            .activeInActiveApp,
            .inVisibleRect
        ]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    override func mouseEntered(with event: NSEvent) {
        cursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        cursor.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.modifier(CursorModifier(cursor: cursor))
    }
}
