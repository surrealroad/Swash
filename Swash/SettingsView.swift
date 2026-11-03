//
//  SettingsView.swift
//  Swash
//

import SwiftUI

struct SettingsView: View {
    private enum Tab: Hashable {
        case general, appearance, updates
    }

    @State private var selection: Tab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)

            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "textformat.size") }
                .tag(Tab.appearance)

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
    @AppStorage(QuickCaptureShortcut.defaultsKey) private var quickCaptureShortcut: QuickCaptureShortcut = QuickCaptureShortcut.defaultValue
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false
    @AppStorage(ImageInsertion.folderDefaultsKey) private var imageFolder = ImageInsertion.defaultFolderName
    @State private var opensAtLogin = LoginItem.isEnabled

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

            Section {
                TextField("Images folder", text: $imageFolder, prompt: Text("Same folder as the document"))
            } header: {
                Text("Images")
            } footer: {
                Text("Images you drag or paste into a document are copied into this folder beside it and linked with a relative path. Leave it empty to put them next to the document.")
                    .settingsFooterStyle()
            }

            Section {
                Picker("Quick Note shortcut", selection: $quickCaptureShortcut) {
                    ForEach(QuickCaptureShortcut.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }
                .onChange(of: quickCaptureShortcut) { _, shortcut in
                    GlobalHotKey.shared.register(shortcut)
                }
                Toggle("Show Swash in the menu bar", isOn: $showMenuBarExtra)
                Toggle("Open Swash at login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { LoginItem.setEnabled($0); opensAtLogin = LoginItem.isEnabled }
                ))
            } header: {
                Text("Quick Note")
            } footer: {
                Text("The shortcut opens a floating note from any app. Save it as a new document or add it to the last document you used.")
                    .settingsFooterStyle()
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

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @AppStorage(EditorTypography.Keys.font) private var font: TypographyFont = .system
    @AppStorage(EditorTypography.Keys.textSize) private var textSize: Double = Double(EditorTypography.defaultTextSize)
    @AppStorage(EditorTypography.Keys.lineWidth) private var lineWidth: TypographyLineWidth = .full
    @AppStorage(EditorTypography.Keys.theme) private var theme: EditorTheme = .system

    private var typography: EditorTypography {
        EditorTypography(font: font, textSize: EditorTypography.clampedSize(textSize), lineWidth: lineWidth, theme: theme)
    }

    var body: some View {
        Form {
            Section {
                Picker("Font", selection: $font) {
                    ForEach(TypographyFont.allCases) { font in
                        Text(font.title).tag(font)
                    }
                }
                LabeledContent("Text size") {
                    HStack(spacing: 8) {
                        Slider(value: $textSize,
                               in: Double(EditorTypography.minTextSize)...Double(EditorTypography.maxTextSize),
                               step: 1)
                            .frame(width: 180)
                        Text("\(Int(textSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Line width", selection: $lineWidth) {
                    ForEach(TypographyLineWidth.allCases) { width in
                        Text(width.title).tag(width)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Typography")
            } footer: {
                Text("Applies to Edit Text, Edit Markdown and the Preview. Use View › Bigger (⌘+), Smaller (⌘−) and Actual Size (⌘0) to change the text size from any document.")
                    .settingsFooterStyle()
            }

            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(EditorTheme.allCases) { theme in
                        Label {
                            Text(theme.title)
                        } icon: {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(theme.accent.map { Color(nsColor: $0) } ?? Color.accentColor)
                        }
                        .tag(theme)
                    }
                }
                LabeledContent("Sample") {
                    sample
                }
            } header: {
                Text("Colours")
            } footer: {
                Text("Themes colour code, links, quotes and tasks, and follow Light and Dark Mode. Quick Look previews use the standard look.")
                    .settingsFooterStyle()
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        font = .system
                        textSize = Double(EditorTypography.defaultTextSize)
                        lineWidth = .full
                        theme = .system
                    }
                    .disabled(typography == EditorTypography())
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sample: some View {
        let accent = typography.previewAccent
        return (Text("Swash ").bold()
            + Text("writes ")
            + Text("code").monospaced().foregroundColor(accent)
            + Text(" and ")
            + Text("links").foregroundColor(accent).underline())
            .font(typography.previewFont())
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(typography.theme.background.map { Color(nsColor: $0) } ?? Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
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
