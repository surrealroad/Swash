//
//  SettingsView.swift
//  Swash
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var defaultAppManager = DefaultAppManager.shared
    @AppStorage("markdownFlavor") private var markdownFlavor: MarkdownFlavor = .github
    
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
        }
        .padding(20)
        .frame(width: 460, height: 200)
        .onAppear {
            defaultAppManager.refreshDefaultStatus()
        }
    }
}

#Preview {
    SettingsView()
}
