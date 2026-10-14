//
//  FolderWindowView.swift
//  Swash
//
//  A window for a whole folder: a sidebar lists its Markdown files and the editor shows the
//  selected one. Opened with File › Open Folder… (⇧⌘O).
//

#if os(macOS)
import SwiftUI
import AppKit

struct FolderWindowView: View {
    let folderURL: URL

    @State private var hasAccess: Bool

    init(folderURL: URL) {
        self.folderURL = folderURL
        _hasAccess = State(initialValue: FolderAccessManager.shared.ensureAccess(for: folderURL))
    }

    var body: some View {
        if hasAccess {
            FolderBrowserView(folderURL: folderURL)
        } else {
            // A restored window whose folder bookmark is gone (moved, or access revoked)
            ContentUnavailableView {
                Label("Can’t Open “\(folderURL.lastPathComponent)”", systemImage: "folder.badge.questionmark")
            } description: {
                Text("Swash needs permission to read this folder.")
            } actions: {
                Button("Grant Access…") {
                    FolderAccessManager.shared.promptForAccess(to: folderURL) { granted in
                        hasAccess = granted && FolderAccessManager.shared.hasAccess(to: folderURL)
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .navigationTitle(folderURL.lastPathComponent)
        }
    }

    /// Asks for a folder and opens it in a folder window.
    static func chooseFolder(openWindow: OpenWindowAction) {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.message = "Choose a folder of Markdown files."
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Keeps a bookmark so the window can be restored after a relaunch
        FolderAccessManager.shared.grantAccess(to: url) { _ in
            openWindow(id: Self.windowID, value: url.standardizedFileURL)
        }
    }

    static let windowID = "folder"
}

private struct FolderBrowserView: View {
    @StateObject private var workspace: FolderWorkspace
    @State private var window: NSWindow?

    init(folderURL: URL) {
        _workspace = StateObject(wrappedValue: FolderWorkspace(folderURL: folderURL))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let file = workspace.selectedFile {
                ContentView(document: $workspace.document, fileURL: file)
                    // Fresh editor state (selection, scroll, styling) for each file
                    .id(file)
            } else {
                ContentUnavailableView(
                    "No Markdown Files",
                    systemImage: "doc.text",
                    description: Text("“\(workspace.folderURL.lastPathComponent)” has no Markdown files yet.")
                )
                .frame(minWidth: 600, minHeight: 600)
            }
        }
        .navigationTitle(workspace.folderURL.lastPathComponent)
        .navigationSubtitle(workspace.selectedFile?.lastPathComponent ?? "")
        .background(WindowAccessor(window: $window))
        .onAppear { workspace.open() }
        .onDisappear { workspace.close() }
        .onChange(of: workspace.selectedFile) {
            // Undo actions belong to the previous file's editor
            window?.undoManager?.removeAllActions()
        }
        .onChange(of: workspace.hasUnsavedChanges) { _, unsaved in
            window?.isDocumentEdited = unsaved
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            workspace.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow) === window { workspace.save() }
        }
        .alert("Swash", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(workspace.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { workspace.selectedFile },
            set: { if let url = $0 { workspace.select(url) } }
        )) {
            ForEach(workspace.files, id: \.self) { url in
                Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.text")
                    .help(url.lastPathComponent)
                    .tag(url)
                    .contextMenu {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 400)
        .overlay {
            if workspace.files.isEmpty {
                Text("No Markdown files")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    workspace.createFile()
                } label: {
                    Label("New File", systemImage: "square.and.pencil")
                }
                .help("Create a Markdown file in this folder")
            }
        }
    }
}

/// File › Open Folder…
struct OpenFolderCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
                FolderWindowView.chooseFolder(openWindow: openWindow)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}
#endif
