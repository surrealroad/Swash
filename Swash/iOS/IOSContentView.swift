//
//  IOSContentView.swift
//  Swash
//
//  The document screen on iPhone and iPad. It offers the same modes as the Mac window:
//  Source, Formatted, and Split side by side when the width is regular (iPad).
//

#if os(iOS)
import SwiftUI
import UIKit

struct IOSContentView: View {
    @Binding var document: SwashDocument
    let fileURL: URL?

    @SceneStorage("viewMode") private var viewMode: ViewMode = .preview
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var editor = IOSEditorController()
    @State private var scrollSync = ScrollSync()
    @State private var showingSettings = false
    @State private var linkPrompt: LinkPrompt?
    @State private var dismissedFolderBanner: URL?
    @ObservedObject private var folderAccessManager = FolderAccessManager.shared

    /// Split needs room for two columns; in compact width it falls back to Source.
    private var effectiveMode: ViewMode {
        viewMode == .split && horizontalSizeClass == .compact ? .edit : viewMode
    }

    private var availableModes: [ViewMode] {
        horizontalSizeClass == .compact ? [.edit, .preview] : ViewMode.allCases
    }

    private var unreadableFolderURL: URL? {
        guard let folder = MarkdownParser.unreadableRelativeFolder(in: document.text, baseURL: fileURL),
              folder != dismissedFolderBanner else { return nil }
        return folder
    }

    var body: some View {
        VStack(spacing: 0) {
            if let folderURL = unreadableFolderURL {
                folderAccessBanner(for: folderURL)
            }
            content
        }
        .toolbar { toolbar }
        .toolbarRole(.editor)
        .sheet(isPresented: $showingSettings) {
            IOSSettingsView()
        }
        .alert(linkPrompt?.isEditing == true ? "Edit Link" : "Add Link", isPresented: Binding(
            get: { linkPrompt != nil },
            set: { if !$0 { linkPrompt = nil } }
        ), presenting: linkPrompt) { prompt in
            TextField("https://example.com", text: Binding(
                get: { linkPrompt?.url ?? "" },
                set: { linkPrompt?.url = $0 }
            ))
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
            Button(prompt.isEditing ? "Update" : "Add") { applyLink(linkPrompt?.url ?? "", selection: prompt.selection) }
            if prompt.isEditing {
                Button("Remove Link", role: .destructive) { applyLink(nil, selection: prompt.selection) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .focusedSceneValue(\.formatCommandHandler, canFormat ? { handleFormatCommand($0) } : nil)
        .onAppear {
            editor.onFormatCommand = { handleFormatCommand($0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch effectiveMode {
        case .edit:
            sourceEditor
        case .preview:
            if usesStyledEditor {
                StyledTextView(text: $document.text, controller: editor, flavor: document.flavor, baseURL: fileURL)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .id(folderAccessManager.accessGrantedTrigger)
            } else {
                preview
            }
        case .split:
            HStack(spacing: 0) {
                sourceEditor
                Divider()
                preview
            }
        }
    }

    private var sourceEditor: some View {
        SourceTextView(
            text: $document.text,
            controller: editor,
            scrollSync: effectiveMode == .split ? scrollSync : nil,
            formattingEnabled: document.flavor != .slack
        )
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var preview: some View {
        MarkdownPreviewView(
            text: document.text,
            flavor: document.flavor,
            baseURL: fileURL,
            scrollSync: effectiveMode == .split ? scrollSync : nil
        )
        .id(folderAccessManager.accessGrantedTrigger)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("View", selection: $viewMode) {
                ForEach(availableModes) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("View Mode")
        }
        ToolbarItem(placement: .secondaryAction) {
            Picker(selection: flavorBinding) {
                ForEach(MarkdownFlavor.allCases) { flavor in
                    Text(flavor.rawValue).tag(flavor)
                }
            } label: {
                Label("Markdown Flavor", systemImage: "textformat")
            }
            .pickerStyle(.menu)
        }
        ToolbarItem(placement: .secondaryAction) {
            ShareLink(item: document.text, subject: Text(documentTitle), preview: SharePreview(Text(documentTitle))) {
                Label("Share Markdown", systemImage: "square.and.arrow.up")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    /// Changing flavour converts the text in place, as on the Mac.
    private var flavorBinding: Binding<MarkdownFlavor> {
        Binding(
            get: { document.flavor },
            set: { newFlavor in
                guard newFlavor != document.flavor else { return }
                var updated = document
                updated.text = MarkdownParser.convert(document.text, from: document.flavor, to: newFlavor)
                updated.flavor = newFlavor
                document = updated
            }
        )
    }

    private var documentTitle: String {
        if let name = fileURL?.deletingPathExtension().lastPathComponent, !name.isEmpty {
            return name
        }
        return "Untitled"
    }

    private func folderAccessBanner(for folderURL: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(Color.accentColor)
            Text("Allow access to **\(folderURL.lastPathComponent)** to show linked images.")
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Allow…") {
                FolderAccessManager.shared.promptForAccess(to: folderURL) { success in
                    if success { dismissedFolderBanner = nil }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("GrantFolderAccessButton")
            Button {
                dismissedFolderBanner = folderURL
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("DismissFolderAccessButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(PlatformColor.controlBackgroundColor))
    }

    // MARK: - Formatting

    /// Formatted mode edits in place (Edit Text) for CommonMark and GFM; Slack mrkdwn, which the
    /// AST styler does not handle, shows the read-only preview there.
    private var usesStyledEditor: Bool {
        document.flavor != .slack
    }

    /// Formatting needs an editor on screen, and isn't offered for Slack mrkdwn.
    private var canFormat: Bool {
        document.flavor != .slack
    }

    private func handleFormatCommand(_ command: FormatCommand) {
        guard canFormat else { return }
        let selection = editor.isAttached ? editor.selection : NSRange(location: (document.text as NSString).length, length: 0)
        if command == .link {
            let current = FormatCommandEdits.activeLink(text: document.text, selection: selection)
            let clipboard = PlatformPasteboard.string.flatMap { URL(string: $0)?.scheme != nil ? $0 : nil }
            linkPrompt = LinkPrompt(url: current ?? clipboard ?? "", isEditing: current != nil, selection: selection)
            return
        }
        guard let edit = FormatCommandEdits.edit(for: command, text: document.text, selection: selection) else { return }
        commit(edit, actionName: command.actionName)
    }

    private func applyLink(_ url: String?, selection: NSRange) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed = trimmed, trimmed.isEmpty { return }
        guard let edit = FormatCommandEdits.link(trimmed, text: document.text, selection: selection) else { return }
        commit(edit, actionName: trimmed == nil ? "Remove Link" : "Link")
    }

    /// Edits go through the live text view so they can be undone (GOTCHAS #10).
    private func commit(_ edit: MarkdownEdit, actionName: String) {
        if editor.isAttached {
            editor.apply(edit, actionName: actionName)
            document.text = edit.text
            editor.focus()
        } else {
            document.text = edit.text
        }
    }

    private struct LinkPrompt {
        var url: String
        let isEditing: Bool
        let selection: NSRange
    }
}

private extension FormatCommand {
    var actionName: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .strikethrough: return "Strikethrough"
        case .code: return "Code"
        case .link: return "Link"
        case .heading(let level): return "Heading \(level)"
        case .paragraph: return "Paragraph"
        case .bulletList: return "Bullet List"
        case .numberedList: return "Numbered List"
        case .taskList: return "To-do List"
        case .quote: return "Quote"
        case .codeBlock: return "Code Block"
        }
    }
}
#endif
