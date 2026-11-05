//
//  IOSSettingsView.swift
//  Swash
//
//  Settings sheet for iPhone and iPad. Updates come from the App Store and file associations
//  from the document types, so only the Mac's general settings apply here.
//

#if os(iOS)
import SwiftUI

struct IOSSettingsView: View {
    @AppStorage("markdownFlavor") private var markdownFlavor: MarkdownFlavor = .github
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Picker("Markdown Scheme", selection: $markdownFlavor) {
                        ForEach(MarkdownFlavor.allCases) { flavor in
                            Text(flavor.rawValue).tag(flavor)
                        }
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
