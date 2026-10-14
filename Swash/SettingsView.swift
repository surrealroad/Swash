//
//  SettingsView.swift
//  Swash
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var defaultAppManager = DefaultAppManager.shared
    @ObservedObject private var sparkleUpdater = SparkleUpdater.shared
    @AppStorage("markdownFlavor") private var markdownFlavor: MarkdownFlavor = .github
    @AppStorage(QuickCaptureShortcut.defaultsKey) private var quickCaptureShortcut: QuickCaptureShortcut = QuickCaptureShortcut.defaultValue
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = false
    @State private var opensAtLogin = LoginItem.isEnabled
    
    var body: some View {
        Form {
            Section {
                Picker("Markdown Scheme:", selection: $markdownFlavor) {
                    ForEach(MarkdownFlavor.allCases) { flavor in
                        Text(flavor.rawValue).tag(flavor)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("General Settings")
                    .font(.headline)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default App for Markdown (.md)")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        if defaultAppManager.isDefaultAppStatus {
                            Label("Swash is currently your default Markdown application.", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else {
                            Label("Swash is not your default Markdown application.", systemImage: "info.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if !defaultAppManager.isDefaultAppStatus {
                        Button("Make Default") {
                            defaultAppManager.makeSwashDefaultApp()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } header: {
                Text("File Associations")
                    .font(.headline)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Software Updates")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        Toggle("Automatically check for updates", isOn: $sparkleUpdater.automaticallyChecksForUpdates)
                            .font(.subheadline)
                    }
                    
                    Spacer()
                    
                    Button("Check Now...") {
                        sparkleUpdater.checkForUpdates()
                    }
                    .disabled(!sparkleUpdater.canCheckForUpdates)
                }
            } header: {
                Text("Updates")
                    .font(.headline)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Section {
                Picker("Quick Note shortcut:", selection: $quickCaptureShortcut) {
                    ForEach(QuickCaptureShortcut.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }
                .pickerStyle(.menu)
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
                    .font(.headline)
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
        .onAppear {
            defaultAppManager.refreshDefaultStatus()
        }
    }
}

#Preview {
    SettingsView()
}
