//
//  BubbleMenuView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI

enum FormatAction {
    case bold
    case italic
    case code
    case strikethrough
    case h1
    case h2
    case quote
}

struct BubbleMenuView: View {
    let onAction: (FormatAction) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            BubbleButton(systemImage: "bold", textLabel: nil, tooltip: "Bold (⌘B)", action: { onAction(.bold) })
            BubbleButton(systemImage: "italic", textLabel: nil, tooltip: "Italic (⌘I)", action: { onAction(.italic) })
            BubbleButton(systemImage: "curlybraces", textLabel: nil, tooltip: "Inline Code", action: { onAction(.code) })
            BubbleButton(systemImage: "strikethrough", textLabel: nil, tooltip: "Strikethrough", action: { onAction(.strikethrough) })
            
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)
            
            BubbleButton(systemImage: nil, textLabel: "H1", tooltip: "Heading 1", action: { onAction(.h1) })
            BubbleButton(systemImage: nil, textLabel: "H2", tooltip: "Heading 2", action: { onAction(.h2) })
            BubbleButton(systemImage: "quote.bubble", textLabel: nil, tooltip: "Blockquote", action: { onAction(.quote) })
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct BubbleButton: View {
    let systemImage: String?
    let textLabel: String?
    let tooltip: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12.5, weight: .semibold))
                } else if let textLabel = textLabel {
                    Text(textLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
            .foregroundColor(isHovered ? .primary : .primary.opacity(0.75))
            .frame(width: 28, height: 28)
            .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
        .help(tooltip)
    }
}
