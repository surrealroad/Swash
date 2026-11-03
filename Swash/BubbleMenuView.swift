//
//  BubbleMenuView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import Translation

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

extension FormatAction {
    /// The manifest command behind the button (FormatManifest.generated.swift).
    var command: FormatCommand {
        switch self {
        case .bold: return .bold
        case .italic: return .italic
        case .code: return .code
        case .strikethrough: return .strikethrough
        case .heading: return .heading(1)
        case .h1: return .heading(1)
        case .h2: return .heading(2)
        case .h3: return .heading(3)
        case .h4: return .heading(4)
        case .h5: return .heading(5)
        case .h6: return .heading(6)
        case .quote: return .quote
        case .bulletList: return .bulletList
        case .numberedList: return .numberedList
        case .table: return .table
        }
    }

    /// Whether the manifest offers the command in the bubble menu.
    var isInBubbleMenu: Bool { command.definition?.surfaces.contains(.bubble) ?? false }

    /// The button's tooltip: the manifest label, plus its shortcut.
    var tooltip: String {
        let label = self == .heading ? (command.definition?.label ?? "") : (command.label ?? "")
        guard self != .heading, let shortcut = command.shortcut else { return label }
        return "\(label) (\(shortcut.displayString))"
    }
}

/// What the code button's menu applies: inline code, a plain fenced block, or a fenced block
/// in one of the languages `CodeHighlighter` colours.
enum CodeFormat: Hashable, CustomStringConvertible {
    case inline
    case plainBlock
    case language(CodeLanguage)

    /// Inline and plain blocks are Swash's own. The shared manifest's languages come first, in its
    /// order and with its labels; the highlighter's other languages follow.
    static let allCases: [CodeFormat] = {
        let shared = FormatManifest.codeLanguages.compactMap { CodeLanguage(name: $0.id) }
        let rest = CodeLanguage.allCases.filter { !shared.contains($0) }
        return [.inline, .plainBlock] + (shared + rest).map { .language($0) }
    }()

    /// The manifest's entry for a language, when the manifest lists it.
    private static func manifestLanguage(_ language: CodeLanguage) -> ManifestCodeLanguage? {
        FormatManifest.codeLanguages.first { CodeLanguage(name: $0.id) == language }
    }

    var name: String {
        switch self {
        case .inline: return FormatCommand.code.label ?? "Inline Code"
        case .plainBlock: return "Plain Block"
        case .language(let language): return Self.manifestLanguage(language)?.label ?? language.displayName
        }
    }

    var label: String {
        switch self {
        case .inline: return "Inline"
        case .plainBlock: return "Plain"
        case .language(let language): return Self.manifestLanguage(language)?.compactLabel ?? language.shortLabel
        }
    }

    var languageSignifier: String? {
        if case .language(let language) = self { return Self.manifestLanguage(language)?.id ?? language.rawValue }
        return nil
    }

    var description: String {
        switch self {
        case .inline: return "inline"
        case .plainBlock: return "plainBlock"
        case .language: return languageSignifier ?? ""
        }
    }
}

enum BubbleMenuContext: Hashable {
    case codeBlock
    case tableCell
    case heading
    case listItem
    case blockquote
    /// A GitHub-style callout (`> [!NOTE]`).
    case callout(AlertType)
    /// A selected image.
    case image
    case standard

    /// Quotes and callouts share the block buttons.
    var isQuoteLike: Bool {
        switch self {
        case .blockquote, .callout: return true
        default: return false
        }
    }
}

/// What the image bubble menu does to the selected image.
struct ImageMenuActions {
    let setAlt: (String) -> Void
    let setWidth: (Int?) -> Void
    let replace: () -> Void
    /// Nil when the image isn't a local file.
    let reveal: (() -> Void)?
    let copyPath: () -> Void
}

/// The footnote the selection is on, and what the menu can do with it.
struct FootnoteMenuActions {
    let isDefinition: Bool
    let goToCounterpart: () -> Void
    let delete: () -> Void
}

extension AlertType {
    var symbolName: String {
        switch self {
        case .note: return "info.circle"
        case .tip: return "lightbulb"
        case .important: return "exclamationmark.bubble"
        case .warning: return "exclamationmark.triangle"
        case .caution: return "exclamationmark.octagon"
        }
    }
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
    /// Plain text of the selection, offered to Translate (nil hides the button).
    var translatableText: String? = nil
    /// Replaces the selection with a translation chosen in the Translate popover.
    var onReplaceWithTranslation: ((String) -> Void)? = nil
    /// Changes the callout type of the selection; nil makes it a plain quote.
    var onSelectCalloutType: ((AlertType?) -> Void)? = nil
    /// The selected image, when `context` is `.image`.
    var image: MarkdownImageSource? = nil
    var imageActions: ImageMenuActions? = nil
    var onInsertFootnote: (() -> Void)? = nil
    var footnoteActions: FootnoteMenuActions? = nil
    
    @State private var isPresentingLinkPopover = false
    @State private var isPresentingTranslation = false
    @State private var isPresentingAltPopover = false
    
    var body: some View {
        HStack(spacing: 4) {
            if context == .image, let image = image, let actions = imageActions {
                imageControls(image, actions: actions)
            } else if context == .codeBlock || activeFormats.contains(.code) {
                bubbleButton(.code, systemImage: "curlybraces", isActive: true)
                
                if let currentFormat = activeCodeFormat {
                    codeFormatDropdown(currentFormat: currentFormat)
                }
                
                if context == .tableCell || activeFormats.contains(.table) {
                    bubbleButton(.table, systemImage: "tablecells", isActive: true)
                }
            } else {
                bubbleButton(.bold, systemImage: "bold")
                bubbleButton(.italic, systemImage: "italic")
                bubbleButton(.code, systemImage: "curlybraces")
                
                if activeFormats.contains(.code), let currentFormat = activeCodeFormat {
                    codeFormatDropdown(currentFormat: currentFormat)
                }
                
                bubbleButton(.strikethrough, systemImage: "strikethrough")
                
                if FormatCommand.link.definition?.surfaces.contains(.bubble) == true {
                    BubbleButton(
                        systemImage: "link",
                        textLabel: nil,
                        tooltip: Self.linkTooltip,
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
                }
                
                if let footnote = footnoteActions {
                    BubbleButton(
                        systemImage: footnote.isDefinition ? "arrow.up.to.line" : "arrow.down.to.line",
                        textLabel: nil,
                        tooltip: footnote.isDefinition ? "Go to Footnote Reference" : "Go to Footnote",
                        isActive: false,
                        action: footnote.goToCounterpart
                    )
                    BubbleButton(systemImage: "trash", textLabel: nil, tooltip: "Delete Footnote", isActive: false, action: footnote.delete)
                } else if let insertFootnote = onInsertFootnote, context != .tableCell {
                    BubbleButton(systemImage: "textformat.superscript", textLabel: nil, tooltip: "Insert Footnote", isActive: false, action: insertFootnote)
                }
                
                if context == .standard || context == .heading || context.isQuoteLike {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    bubbleButton(.heading, textLabel: "H", isActive: activeHeadingLevel != nil)
                    
                    if let currentLevel = activeHeadingLevel {
                        headingLevelDropdown(currentLevel: currentLevel)
                    }
                    
                    if case .callout(let type) = context {
                        calloutDropdown(current: type)
                    } else if context != .heading {
                        bubbleButton(.quote, systemImage: "quote.bubble")
                        if context == .blockquote, onSelectCalloutType != nil {
                            calloutDropdown(current: nil)
                        }
                    }
                } else if context == .listItem {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    bubbleButton(.quote, systemImage: "quote.bubble")
                }
                
                if context == .standard || context == .listItem || context.isQuoteLike {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    bubbleButton(.bulletList, systemImage: "list.bullet")
                    bubbleButton(.numberedList, systemImage: "list.number")
                    
                    if context == .standard {
                        bubbleButton(.table, systemImage: "tablecells")
                    }
                } else if context == .tableCell || activeFormats.contains(.table) {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    bubbleButton(.table, systemImage: "tablecells", isActive: true)
                }
                
                if let text = translatableText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)
                    
                    BubbleButton(systemImage: "translate", textLabel: nil, tooltip: "Translate", isActive: false, action: {
                        isPresentingTranslation = true
                    })
                    .modifier(TranslationPopover(isPresented: $isPresentingTranslation, text: text, onReplace: onReplaceWithTranslation))
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
        // The menu floats over the text view, whose I-beam would otherwise show through
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.arrow.set() }
        }
    }
    
    /// The link button's tooltip, from the manifest.
    private static var linkTooltip: String {
        let label = FormatCommand.link.label ?? ""
        return FormatCommand.link.shortcut.map { "\(label) (\($0.displayString))" } ?? label
    }

    /// A button for a manifest command, hidden when the manifest doesn't offer it in the bubble menu.
    @ViewBuilder
    private func bubbleButton(_ action: FormatAction, systemImage: String? = nil, textLabel: String? = nil, isActive: Bool? = nil) -> some View {
        if action.isInBubbleMenu {
            BubbleButton(systemImage: systemImage, textLabel: textLabel, tooltip: action.tooltip,
                         isActive: isActive ?? activeFormats.contains(action), action: { onAction(action) })
        }
    }

    /// Callout type menu: the five GitHub alert types, plus turning the callout back into a quote.
    @ViewBuilder
    private func calloutDropdown(current: AlertType?) -> some View {
        Menu {
            ForEach(AlertType.allCases, id: \.self) { type in
                Button(action: { onSelectCalloutType?(type) }) {
                    Label(type.title, systemImage: type == current ? "checkmark" : type.symbolName)
                }
            }
            if current != nil {
                Divider()
                Button("Plain Quote") { onSelectCalloutType?(nil) }
                Button("Remove Callout") { onAction(.quote) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: current?.symbolName ?? "exclamationmark.bubble")
                    .font(.system(size: 11, weight: .semibold))
                if let current = current {
                    Text(current.title)
                        .font(.system(size: 10, weight: .bold))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(current != nil ? Color.accentColor : .primary.opacity(0.75))
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(current != nil ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(current != nil ? "Change callout type" : "Make this quote a callout")
    }
    
    /// Image controls: alt text, display size, and the image file.
    @ViewBuilder
    private func imageControls(_ image: MarkdownImageSource, actions: ImageMenuActions) -> some View {
        BubbleButton(systemImage: "text.below.photo", textLabel: nil, tooltip: "Edit Alt Text", isActive: !image.alt.isEmpty, action: {
            isPresentingAltPopover.toggle()
        })
        .popover(isPresented: $isPresentingAltPopover, arrowEdge: .bottom) {
            ImageAltTextPopoverView(initialText: image.alt, onApply: { alt in
                isPresentingAltPopover = false
                actions.setAlt(alt)
            }, onCancel: { isPresentingAltPopover = false })
        }
        
        Menu {
            ForEach(ImageSizePreset.allCases, id: \.self) { preset in
                Button(action: { actions.setWidth(preset.width) }) {
                    if preset.width == image.width {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                Text(ImageSizePreset.label(for: image.width))
                    .font(.system(size: 10, weight: .bold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(.primary.opacity(0.75))
            .padding(.horizontal, 6)
            .frame(height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Image size")
        
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 2)
        
        BubbleButton(systemImage: "photo.on.rectangle.angled", textLabel: nil, tooltip: "Replace Image…", isActive: false, action: actions.replace)
        if let reveal = actions.reveal {
            BubbleButton(systemImage: "folder", textLabel: nil, tooltip: "Show in Finder", isActive: false, action: reveal)
        }
        BubbleButton(systemImage: "doc.on.doc", textLabel: nil, tooltip: "Copy Image Path", isActive: false, action: actions.copyPath)
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
        .menuIndicator(.hidden)
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
                        Text(FormatCommand.heading(level).label ?? "H\(level)")
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
        .menuIndicator(.hidden)
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
                    .help("Remove link and keep text")
                }
                
                Spacer()
                
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
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

/// Display widths offered by the image bubble menu. The editor caps images at 550 points.
enum ImageSizePreset: CaseIterable {
    case small, medium, large, original
    
    var width: Int? {
        switch self {
        case .small: return 200
        case .medium: return 360
        case .large: return 550
        case .original: return nil
        }
    }
    
    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .original: return "Original Size"
        }
    }
    
    static func label(for width: Int?) -> String {
        guard let width = width else { return "Original" }
        return allCases.first { $0.width == width }?.title ?? "\(width) pt"
    }
}

struct ImageAltTextPopoverView: View {
    let onApply: (String) -> Void
    let onCancel: () -> Void
    @State private var text: String
    @FocusState private var isFocused: Bool
    
    init(initialText: String, onApply: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alt Text")
                .font(.system(size: 12, weight: .bold))
            TextField("Describe the image", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit { onApply(text) }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Update") { onApply(text) }
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isFocused = true }
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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help(tooltip)
    }
}

/// The system Translate popover (macOS 14.4 and later), with "Replace" writing the translation
/// back into the document.
private struct TranslationPopover: ViewModifier {
    @Binding var isPresented: Bool
    let text: String
    let onReplace: ((String) -> Void)?
    
    func body(content: Content) -> some View {
        if #available(macOS 14.4, *) {
            if let onReplace = onReplace {
                content.translationPresentation(isPresented: $isPresented, text: text, arrowEdge: .bottom) { translated in
                    onReplace(translated)
                }
            } else {
                content.translationPresentation(isPresented: $isPresented, text: text, arrowEdge: .bottom)
            }
        } else {
            content
        }
    }
}
