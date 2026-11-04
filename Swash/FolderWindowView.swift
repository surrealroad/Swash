//
//  FolderWindowView.swift
//  Swash
//
//  A window for a whole folder: a sidebar lists its Markdown files and subfolders as a tree,
//  filters them by name and searches their text, and the editor shows the selected file. Links to
//  other notes in the folder open in the same window. Opened with File › Open Folder… (⇧⌘O).
//

#if os(macOS)
import SwiftUI
import MacAppKitExtras
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

    /// What the sidebar shows: the file tree (filtered by name), full-text search results or the
    /// open file's heading outline.
    enum SidebarMode: Hashable { case files, search, outline }
    @State private var mode: SidebarMode = .files
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var outline = DocumentOutlineState()
    @State private var query = ""
    @FocusState private var queryFocused: Bool
    @State private var expanded: Set<URL> = []
    @State private var selectedResult: String?

    @State private var renameTarget: FolderNode?
    @State private var renameText = ""
    @State private var trashTarget: FolderNode?

    init(folderURL: URL) {
        _workspace = StateObject(wrappedValue: FolderWorkspace(folderURL: folderURL))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle(workspace.folderURL.lastPathComponent)
        .navigationSubtitle(workspace.selectedFile.map { workspace.relativePath(of: $0) } ?? "")
        .background(WindowAccessor(window: $window))
        .onAppear { workspace.open() }
        .onDisappear { workspace.close() }
        .focusedSceneValue(\.outlineVisibility, Binding(
            get: { mode == .outline },
            set: { shown in
                mode = shown ? .outline : .files
                if shown { columnVisibility = .all }
            }
        ))
        .onChange(of: workspace.selectedFile) { _, file in
            // Undo actions belong to the previous file's editor
            window?.undoManager?.removeAllActions()
            if let file { expandAncestors(of: file) } else { outline.outline = MarkdownOutline(text: "") }
        }
        .onChange(of: workspace.hasUnsavedChanges) { _, unsaved in
            window?.isDocumentEdited = unsaved
        }
        .onChange(of: query) { _, newQuery in
            if mode == .search { workspace.search(newQuery) }
        }
        .onChange(of: mode) { _, newMode in
            workspace.search(newMode == .search ? query : "")
            selectedResult = nil
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
        .modifier(FileActionDialogs(workspace: workspace, renameTarget: $renameTarget, renameText: $renameText, trashTarget: $trashTarget))
    }

    @ViewBuilder
    private var detail: some View {
        if let file = workspace.selectedFile {
            // Not `.id(file)`: rebuilding ContentView also rebuilds its customizable toolbar,
            // and AppKit throws while removing the old items. `documentID` resets only the editor.
            ContentView(document: $workspace.document, fileURL: file, documentID: file, hostedOutline: outline)
                .environment(\.noteLinkHandler, { [weak workspace] url in workspace?.openLink(url) ?? false })
                .environment(\.textRevealRequest, workspace.revealRequest)
                // Links in the split view's preview
                .environment(\.openURL, OpenURLAction { [weak workspace] url in
                    workspace?.openLink(url) == true ? .handled : .systemAction
                })
        } else if workspace.isLoading {
            ProgressView()
                .frame(minWidth: 600, minHeight: 600)
        } else {
            ContentUnavailableView(
                "No Markdown Files",
                systemImage: "doc.text",
                description: Text("“\(workspace.folderURL.lastPathComponent)” has no Markdown files yet.")
            )
            .frame(minWidth: 600, minHeight: 600)
        }
    }

    // MARK: Sidebar

    private var isQueryEmpty: Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sidebar: some View {
        Group {
            if mode == .outline {
                DocumentOutlineView(state: outline)
            } else if mode == .search && !isQueryEmpty {
                searchResultsList
            } else {
                fileTree
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 420)
        .safeAreaInset(edge: .top, spacing: 0) { sidebarHeader }
        .toolbar {
            ToolbarItem {
                Button {
                    mode = .search
                    queryFocused = true
                } label: {
                    Label("Search in Folder", systemImage: "magnifyingglass")
                }
                .help("Search the text of every note in this folder (⇧⌘F)")
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
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

    private var sidebarHeader: some View {
        VStack(spacing: 6) {
            Picker("Sidebar", selection: $mode) {
                Text("Files").tag(SidebarMode.files)
                Text("Search").tag(SidebarMode.search)
                Text("Outline").tag(SidebarMode.outline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if mode != .outline {
                HStack(spacing: 4) {
                    Image(systemName: mode == .files ? "line.3.horizontal.decrease" : "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(mode == .files ? "Filter by Name" : "Search in Notes", text: $query)
                        .textFieldStyle(.plain)
                        .focused($queryFocused)
                        .onSubmit {
                            if mode == .search, let first = workspace.searchResults.first { open(first) }
                        }
                        .onExitCommand { query = "" }
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var isFiltering: Bool {
        mode == .files && !isQueryEmpty
    }

    private var fileTree: some View {
        let nodes = isFiltering ? FolderScanner.filter(workspace.tree, query: query) : workspace.tree
        return List(selection: Binding(
            get: { workspace.selectedFile },
            set: { if let url = $0 { workspace.select(url) } }
        )) {
            FolderTreeRows(nodes: nodes, expanded: $expanded, showsAll: isFiltering, actions: rowActions)
        }
        .contextMenu {
            Button("New File") { workspace.createFile() }
        }
        .overlay {
            if workspace.isLoading {
                ProgressView().controlSize(.small)
            } else if nodes.isEmpty {
                Text(isFiltering ? "No Matching Files" : "No Markdown Files")
                    .foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if workspace.isTruncated {
                Text("This folder is too large to list completely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(6)
            }
        }
    }

    private var rowActions: FolderRowActions {
        FolderRowActions(
            newFile: { folder in workspace.createFile(in: folder) },
            rename: { node in
                renameText = node.isFolder ? node.url.lastPathComponent : node.displayName
                renameTarget = node
            },
            trash: { node in trashTarget = node },
            reveal: { node in NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        )
    }

    private var searchResultsList: some View {
        let results = workspace.searchResults
        let groups = Dictionary(grouping: results, by: \.file)
        // Files in the order their results came in
        let order = results.map(\.file).reduce(into: [URL]()) { if $0.last != $1 { $0.append($1) } }
        return List(selection: $selectedResult) {
            ForEach(order, id: \.self) { file in
                Section {
                    ForEach(groups[file] ?? []) { match in
                        SearchResultRow(match: match).tag(match.id)
                    }
                } header: {
                    Text(workspace.relativePath(of: file))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .onChange(of: selectedResult) { _, id in
            if let id, let match = workspace.searchResults.first(where: { $0.id == id }) { open(match) }
        }
        .overlay {
            if results.isEmpty {
                if workspace.isSearching {
                    ProgressView().controlSize(.small)
                } else {
                    Text("No Results").foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !results.isEmpty {
                let count = results.count >= FolderSearch.maximumResults ? "\(results.count)+" : "\(results.count)"
                Text("\(count) \(results.count == 1 ? "result" : "results") in \(order.count) \(order.count == 1 ? "note" : "notes")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(6)
            }
        }
    }

    private func open(_ match: FolderSearchMatch) {
        workspace.select(match.file, revealing: match.range)
    }

    /// Shows the folders holding `file`, so a file opened from a link or search is visible in the tree.
    private func expandAncestors(of file: URL) {
        var folder = file.deletingLastPathComponent().standardizedFileURL
        var ancestors: Set<URL> = []
        while folder != workspace.folderURL, FolderScanner.contains(workspace.folderURL, folder) {
            ancestors.insert(folder)
            folder = folder.deletingLastPathComponent().standardizedFileURL
        }
        if !ancestors.isSubset(of: expanded) { expanded.formUnion(ancestors) }
    }
}

/// What a sidebar row's context menu can do.
private struct FolderRowActions {
    let newFile: (URL) -> Void
    let rename: (FolderNode) -> Void
    let trash: (FolderNode) -> Void
    let reveal: (FolderNode) -> Void
}

/// The rows of a folder tree: folders as disclosure groups, files as selectable rows.
private struct FolderTreeRows: View {
    let nodes: [FolderNode]
    @Binding var expanded: Set<URL>
    /// While filtering, every folder is open so the matches are visible.
    let showsAll: Bool
    let actions: FolderRowActions

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                DisclosureGroup(isExpanded: isExpanded(node.url)) {
                    FolderTreeRows(nodes: node.children, expanded: $expanded, showsAll: showsAll, actions: actions)
                } label: {
                    Label(node.displayName, systemImage: "folder")
                        .contextMenu { menu(for: node) }
                }
            } else {
                Label(node.displayName, systemImage: "doc.text")
                    .help(node.url.lastPathComponent)
                    .tag(node.url)
                    .contextMenu { menu(for: node) }
            }
        }
    }

    private func isExpanded(_ url: URL) -> Binding<Bool> {
        Binding(
            get: { showsAll || expanded.contains(url) },
            set: { open in
                if open { expanded.insert(url) } else { expanded.remove(url) }
            }
        )
    }

    @ViewBuilder
    private func menu(for node: FolderNode) -> some View {
        if node.isFolder {
            Button("New File") { actions.newFile(node.url) }
            Divider()
        }
        Button("Rename…") { actions.rename(node) }
        Button("Show in Finder") { actions.reveal(node) }
        Divider()
        Button("Move to Trash…") { actions.trash(node) }
    }
}

/// A search result: the matching line with the match in bold, and its line number.
private struct SearchResultRow: View {
    let match: FolderSearchMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(highlighted)
                .lineLimit(2)
            Text("Line \(match.line)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var highlighted: AttributedString {
        let snippet = match.snippet as NSString
        let range = match.snippetRange
        guard NSMaxRange(range) <= snippet.length else { return AttributedString(match.snippet) }
        var text = AttributedString(snippet.substring(to: range.location))
        var found = AttributedString(snippet.substring(with: range))
        found.inlinePresentationIntent = .stronglyEmphasized
        text.append(found)
        text.append(AttributedString(snippet.substring(from: NSMaxRange(range))))
        return text
    }
}

/// The rename and move-to-Trash dialogs, kept out of the browser's long modifier chain.
private struct FileActionDialogs: ViewModifier {
    @ObservedObject var workspace: FolderWorkspace
    @Binding var renameTarget: FolderNode?
    @Binding var renameText: String
    @Binding var trashTarget: FolderNode?

    func body(content: Content) -> some View {
        content
            .alert(
                renameTarget.map { "Rename “\($0.url.lastPathComponent)”" } ?? "Rename",
                isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }),
                presenting: renameTarget
            ) { node in
                TextField("Name", text: $renameText)
                Button("Rename") { workspace.rename(node.url, to: renameText) }
                Button("Cancel", role: .cancel) {}
            } message: { node in
                Text(node.isFolder
                     ? "Enter a new name for the folder."
                     : "Enter a new name for the note. Links to it from other notes aren’t updated.")
            }
            .alert(
                trashTarget.map { "Move “\($0.url.lastPathComponent)” to the Trash?" } ?? "Move to the Trash?",
                isPresented: Binding(get: { trashTarget != nil }, set: { if !$0 { trashTarget = nil } }),
                presenting: trashTarget
            ) { node in
                Button("Move to Trash", role: .destructive) { workspace.moveToTrash(node.url) }
                Button("Cancel", role: .cancel) {}
            } message: { node in
                Text(node.isFolder
                     ? "The folder and everything in it are moved to the Trash. You can put them back from the Trash in the Finder."
                     : "You can put it back from the Trash in the Finder.")
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
