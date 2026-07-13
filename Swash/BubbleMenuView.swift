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

enum CodeFormat: Hashable, CaseIterable {
    case inline
    case plainBlock
    case javascript
    case swift
    case python
    case html
    case css
    case json
    
    var name: String {
        switch self {
        case .inline: return "Inline Code"
        case .plainBlock: return "Plain Block"
        case .javascript: return "JavaScript"
        case .swift: return "Swift"
        case .python: return "Python"
        case .html: return "HTML"
        case .css: return "CSS"
        case .json: return "JSON"
        }
    }
    
    var label: String {
        switch self {
        case .inline: return "Inline"
        case .plainBlock: return "Plain"
        case .javascript: return "JS"
        case .swift: return "Swift"
        case .python: return "Python"
        case .html: return "HTML"
        case .css: return "CSS"
        case .json: return "JSON"
        }
    }
    
    var languageSignifier: String? {
        switch self {
        case .inline: return nil
        case .plainBlock: return nil
        case .javascript: return "javascript"
        case .swift: return "swift"
        case .python: return "python"
        case .html: return "html"
        case .css: return "css"
        case .json: return "json"
        }
    }
}

struct BubbleMenuView: View {
    let activeFormats: Set<FormatAction>
    let activeCodeFormat: CodeFormat?
    let onAction: (FormatAction) -> Void
    let onSelectCodeFormat: (CodeFormat) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            BubbleButton(systemImage: "bold", textLabel: nil, tooltip: "Bold (⌘B)", isActive: activeFormats.contains(.bold), action: { onAction(.bold) })
            BubbleButton(systemImage: "italic", textLabel: nil, tooltip: "Italic (⌘I)", isActive: activeFormats.contains(.italic), action: { onAction(.italic) })
            BubbleButton(systemImage: "curlybraces", textLabel: nil, tooltip: "Code Formatting", isActive: activeFormats.contains(.code), action: { onAction(.code) })
            
            if activeFormats.contains(.code), let currentFormat = activeCodeFormat {
                Menu {
                    ForEach(CodeFormat.allCases, id: \.self) { format in
                        Button(action: {
                            onSelectCodeFormat(format)
                        }) {
                            HStack {
                                Text(format.name)
                                if format == currentFormat {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(currentFormat.label)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(Color.accentColor)
                    .padding(.horizontal, 6)
                    .frame(height: 28)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 72)
                .help("Select code format or language")
            }
            
            BubbleButton(systemImage: "strikethrough", textLabel: nil, tooltip: "Strikethrough", isActive: activeFormats.contains(.strikethrough), action: { onAction(.strikethrough) })
            
            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)
            
            BubbleButton(systemImage: nil, textLabel: "H1", tooltip: "Heading 1", isActive: activeFormats.contains(.h1), action: { onAction(.h1) })
            BubbleButton(systemImage: nil, textLabel: "H2", tooltip: "Heading 2", isActive: activeFormats.contains(.h2), action: { onAction(.h2) })
            BubbleButton(systemImage: "quote.bubble", textLabel: nil, tooltip: "Blockquote", isActive: activeFormats.contains(.quote), action: { onAction(.quote) })
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
    let isActive: Bool
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
            .foregroundColor(isActive ? Color.accentColor : (isHovered ? .primary : .primary.opacity(0.75)))
            .frame(width: 28, height: 28)
            .background(isActive ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.1) : Color.clear))
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
