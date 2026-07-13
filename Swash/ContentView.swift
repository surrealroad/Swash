//
//  ContentView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case edit = "Editor"
    case split = "Split"
    case preview = "Preview"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .edit: return "text.alignleft"
        case .split: return "square.split.2x1"
        case .preview: return "eye"
        }
    }
}

struct ContentView: View {
    @Binding var document: SwashDocument
    
    @State private var viewMode: ViewMode = .preview
    @State private var selectedRange: NSRange? = nil
    @State private var selectionRect: NSRect? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if viewMode == .preview {
                    SwashTextView(
                        text: $document.text,
                        selectedRange: $selectedRange,
                        selectionRect: $selectionRect,
                        isStyled: true
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(bubbleMenuOverlay)
                } else if viewMode == .edit {
                    SwashTextView(
                        text: $document.text,
                        selectedRange: $selectedRange,
                        selectionRect: $selectionRect,
                        isStyled: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(bubbleMenuOverlay)
                } else if viewMode == .split {
                    HSplitView {
                        SwashTextView(
                            text: $document.text,
                            selectedRange: $selectedRange,
                            selectionRect: $selectionRect,
                            isStyled: false
                        )
                        .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(bubbleMenuOverlay)
                        
                        MarkdownPreviewView(text: document.text)
                            .frame(minWidth: 250, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Premium Bottom Status Bar
            statusView
        }
        .frame(minWidth: 600, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Layout", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Toggle layout modes: Editor only, Split, or Preview only")
            }
        }
    }
    
    // Bubble menu overlay positioned relatively in local coordinates
    @ViewBuilder
    private var bubbleMenuOverlay: some View {
        GeometryReader { _ in
            if let rect = selectionRect {
                BubbleMenuView { action in
                    applyFormatting(action)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .position(
                    x: rect.midX,
                    y: max(22, rect.minY - 28) // Shipped above selection rect with top bounds safety
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.72), value: selectionRect)
            }
        }
    }
    
    // Status panel rendering word/character count stats
    private var statusView: some View {
        HStack {
            Text(viewMode.rawValue)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            
            Spacer()
            
            let stats = calculateStats()
            Text("\(stats.words) words   •   \(stats.chars) characters")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        .overlay(
            Divider(), alignment: .top
        )
    }
    
    // Apply formatting to selected text
    private func applyFormatting(_ action: FormatAction) {
        guard let range = selectedRange,
              let textRange = Range(range, in: document.text) else { return }
        
        let selectedText = String(document.text[textRange])
        var formatted = ""
        
        switch action {
        case .bold:
            formatted = "**\(selectedText)**"
        case .italic:
            formatted = "*\(selectedText)*"
        case .code:
            formatted = "`\(selectedText)`"
        case .strikethrough:
            formatted = "~~\(selectedText)~~"
        case .h1:
            formatted = "\n# \(selectedText)\n"
        case .h2:
            formatted = "\n## \(selectedText)\n"
        case .quote:
            formatted = "\n> \(selectedText)\n"
        }
        
        // Apply modification & notify SwiftUI
        document.text = document.text.replacingCharacters(in: textRange, with: formatted)
        
        // Reset selection variables to dismiss bubble menu
        selectedRange = nil
        selectionRect = nil
    }
    
    private func calculateStats() -> (words: Int, chars: Int) {
        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (0, 0) }
        
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
        let chars = document.text.count
        
        return (words, chars)
    }
}

#Preview {
    ContentView(document: .constant(SwashDocument()))
}
