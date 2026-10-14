//
//  SettingsView.swift
//  Swash
//

import SwiftUI

struct SettingsView: View {
    private enum Tab: Hashable {
        case general, updates
    }

    @State private var selection: Tab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)

            UpdatesSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
                .tag(Tab.updates)
        }
        .frame(width: 500)
        .scenePadding(.minimum, edges: .vertical)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @ObservedObject private var defaultAppManager = DefaultAppManager.shared
    @AppStorage("markdownFlavor") private var markdownFlavor: MarkdownFlavor = .github

    var body: some View {
        Form {
            Section {
                Picker("Markdown flavor", selection: $markdownFlavor) {
                    ForEach(MarkdownFlavor.allCases) { flavor in
                        Text(flavor.displayName).tag(flavor)
                    }
                }
            } header: {
                Text("Editor")
            } footer: {
                Text("Controls which Markdown syntax extensions are recognised when editing and previewing documents.")
                    .settingsFooterStyle()
            }

            Section {
                LabeledContent {
                    if defaultAppManager.isDefaultAppStatus {
                        Label("Default", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.green)
                    } else {
                        Button("Make Default") {
                            defaultAppManager.makeSwashDefaultApp()
                        }
                    }
                } label: {
                    Text("Default Markdown editor")
                    Text(defaultAppManager.isDefaultAppStatus
                         ? "Markdown files open in Swash."
                         : "Markdown files open in another app.")
                }
            } header: {
                Text("File Associations")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            defaultAppManager.refreshDefaultStatus()
        }
    }
}

// MARK: - Updates

private struct UpdatesSettingsView: View {
    @ObservedObject private var sparkleUpdater = SparkleUpdater.shared

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Automatically check for updates", isOn: $sparkleUpdater.automaticallyChecksForUpdates)

                LabeledContent("Current version") {
                    Text(versionString)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Check for Updates…") {
                        sparkleUpdater.checkForUpdates()
                    }
                    .disabled(!sparkleUpdater.canCheckForUpdates)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private extension View {
    func settingsFooterStyle() -> some View {
        font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    SettingsView()
}
