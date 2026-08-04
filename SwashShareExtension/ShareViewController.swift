//
//  ShareViewController.swift
//  SwashShareExtension
//

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
