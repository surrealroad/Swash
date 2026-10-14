//
//  ShareViewController.swift
//  SwashShareExtension
//

#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: NSViewController {

    private var sharedText: String = ""
    private var sharedTitle: String = "Shared Note"

    override func loadView() {
        let hostingView = NSHostingView(rootView: ShareView(
            initialText: sharedText,
            initialTitle: sharedTitle,
            onCancel: { [weak self] in
                self?.cancel()
            },
            onPost: { [weak self] title, text in
                self?.post(title: title, text: text)
            }
        ))
        hostingView.frame = NSRect(x: 0, y: 0, width: 450, height: 320)
        self.view = hostingView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedContent()
    }

    private func cancel() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        extensionContext?.cancelRequest(withError: error)
    }

    private func post(title: String, text: String) {
        if let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "swash://new?text=\(encodedText)&title=\(encodedTitle)") {
            NSWorkspace.shared.open(url)
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func extractSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (data, error) in
                        if let text = data as? String {
                            DispatchQueue.main.async {
                                self?.sharedText = text
                                self?.reloadHostingView()
                            }
                        }
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (data, error) in
                        if let url = data as? URL {
                            let markdownLink = "[\(url.lastPathComponent)](\(url.absoluteString))"
                            DispatchQueue.main.async {
                                self?.sharedText = markdownLink
                                self?.reloadHostingView()
                            }
                        }
                    }
                }
            }
        }
    }

    private func reloadHostingView() {
        let hostingView = NSHostingView(rootView: ShareView(
            initialText: sharedText,
            initialTitle: sharedTitle,
            onCancel: { [weak self] in
                self?.cancel()
            },
            onPost: { [weak self] title, text in
                self?.post(title: title, text: text)
            }
        ))
        hostingView.frame = view.frame
        self.view = hostingView
    }
}

struct ShareView: View {
    @State private var text: String
    @State private var title: String
    var onCancel: () -> Void
    var onPost: (String, String) -> Void

    init(initialText: String, initialTitle: String, onCancel: @escaping () -> Void, onPost: @escaping (String, String) -> Void) {
        _text = State(initialValue: initialText)
        _title = State(initialValue: initialTitle)
        self.onCancel = onCancel
        self.onPost = onPost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Save to Swash")
                    .font(.headline)
                Spacer()
            }

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $text)
                .font(.body)
                .padding(4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create Note in Swash") {
                    onPost(title, text)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 320)
    }
}
#else
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// iOS share extension. Extensions can't open the app, so the note is saved to the App Group
/// inbox; Swash moves it into its documents and opens it when it next comes to the front.
class ShareViewController: UIViewController {
    /// Must match `DocumentOpener.appGroupIdentifier` in the app.
    private static let appGroupIdentifier = "group.com.surrealroad.Swash"

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { [weak self] in
            guard let self = self else { return }
            let text = await self.loadSharedText()
            let host = UIHostingController(rootView: ShareNoteView(
                text: text,
                onCancel: { [weak self] in self?.cancel() },
                onSave: { [weak self] title, text in self?.save(title: title, text: text) ?? "Swash isn't available." }))
            self.addChild(host)
            host.view.frame = self.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    /// Saves the note to the inbox and closes the sheet; returns an error message on failure.
    private func save(title: String, text: String) -> String? {
        guard let inbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
            .appendingPathComponent("Inbox", isDirectory: true) else {
            return "Swash can't receive notes from this build (its App Group isn't set up)."
        }
        do {
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let base = title.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
            var file = inbox.appendingPathComponent(base.isEmpty ? "Shared Note" : base).appendingPathExtension("md")
            var counter = 2
            while FileManager.default.fileExists(atPath: file.path) {
                file = inbox.appendingPathComponent("\(base.isEmpty ? "Shared Note" : base) \(counter)").appendingPathExtension("md")
                counter += 1
            }
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return error.localizedDescription
        }
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        return nil
    }

    /// Shared text as-is, or a shared web page as a Markdown link.
    private func loadSharedText() async -> String {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return text
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                let title = url.host() ?? url.lastPathComponent
                return "[\(title)](\(url.absoluteString))"
            }
        }
        return ""
    }
}

struct ShareNoteView: View {
    @State private var title = "Shared Note"
    @State private var text: String
    @State private var errorMessage: String?
    var onCancel: () -> Void
    var onSave: (String, String) -> String?

    init(text: String, onCancel: @escaping () -> Void, onSave: @escaping (String, String) -> String?) {
        _text = State(initialValue: text)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Markdown") {
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .frame(minHeight: 180)
                }
                if let errorMessage = errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Save to Swash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { errorMessage = onSave(title, text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
#endif
