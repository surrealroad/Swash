//
//  ConflictResolution.swift
//  Swash
//
//  iCloud version conflicts: when another Mac saved the same document, offer to choose which
//  version to keep instead of leaving the conflict unresolved.
//

import SwiftUI
import AppKit

enum DocumentConflicts {
    static func unresolved(at url: URL) -> [NSFileVersion] {
        NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
    }

    /// Marks every conflict at `url` resolved and returns the text of `chosen` when it is one of
    /// the conflicting versions (nil keeps the current text). Resolved conflict versions are removed.
    static func resolve(at url: URL, keeping chosen: NSFileVersion?) throws -> String? {
        var replacement: String? = nil
        if let chosen = chosen, chosen != NSFileVersion.currentVersionOfItem(at: url) {
            let data = try Data(contentsOf: chosen.url)
            guard let text = SwashDocument.decode(data) else { throw CocoaError(.fileReadUnknownStringEncoding) }
            replacement = text
        }
        for conflict in unresolved(at: url) {
            conflict.isResolved = true
            try? conflict.remove()
        }
        return replacement
    }

    static func preview(of version: NSFileVersion) -> String {
        guard let data = try? Data(contentsOf: version.url), let text = SwashDocument.decode(data) else { return "" }
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return String(flattened.prefix(160))
    }
}

struct ConflictBanner: View {
    let count: Int
    let onResolve: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.orange)
            Text(count == 1 ? "This document was also changed on another device."
                            : "This document was also changed on \(count) other devices.")
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer()
            Button("Resolve…", action: onResolve)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(NSColor.separatorColor)), alignment: .bottom)
    }
}

/// Lists the current version and each conflicting one; the chosen version is kept.
struct ConflictResolutionSheet: View {
    let url: URL
    let onKeep: (NSFileVersion?) -> Void
    let onCancel: () -> Void

    private struct Row: Identifiable {
        let id: Int
        let version: NSFileVersion?
        let title: String
        let detail: String
        let preview: String
    }

    @State private var selection = 0

    private var rows: [Row] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        func describe(_ version: NSFileVersion?) -> String {
            let date = version?.modificationDate.map { formatter.string(from: $0) } ?? "Unknown date"
            let device = version?.localizedNameOfSavingComputer ?? "this Mac"
            return "\(date) — \(device)"
        }
        let current = NSFileVersion.currentVersionOfItem(at: url)
        var rows = [Row(id: 0, version: current, title: "This Version", detail: describe(current), preview: current.map { DocumentConflicts.preview(of: $0) } ?? "")]
        for (index, conflict) in DocumentConflicts.unresolved(at: url).enumerated() {
            rows.append(Row(id: index + 1, version: conflict, title: "Other Version", detail: describe(conflict), preview: DocumentConflicts.preview(of: conflict)))
        }
        return rows
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: 14) {
            Text("Which version of “\(url.lastPathComponent)” do you want to keep?")
                .font(.headline)
            Text("The other versions are discarded. Keeping another version replaces this document's text, which you can undo.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Version", selection: $selection) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.system(size: 13, weight: .semibold))
                        Text(row.detail).font(.system(size: 11)).foregroundColor(.secondary)
                        if !row.preview.isEmpty {
                            Text(row.preview).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(row.id)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Keep Version") {
                    onKeep(rows.first { $0.id == selection }?.version)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
