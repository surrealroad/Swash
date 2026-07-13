//
//  MarkdownPreviewView.swift
//  Swash
//
//  Created by Jack James on 13/07/2026.
//

import SwiftUI
import AppKit

struct MarkdownPreviewView: View {
    let text: String
    
    var body: some View {
        let blocks = MarkdownParser.parse(text)
        
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if blocks.isEmpty {
                    Text("Nothing to preview yet. Start typing on the left!")
                        .font(.system(.body, design: .serif))
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.top, 24)
                } else {
                    ForEach(blocks) { block in
                        renderBlock(block)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.95))
    }
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block.type {
        case .heading(let level):
            VStack(alignment: .leading, spacing: 6) {
                InlineMarkdownText(text: block.text)
                    .font(headingFont(for: level))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                if level == 1 {
                    Divider()
                        .background(Color.secondary.opacity(0.3))
                        .padding(.bottom, 4)
                } else if level == 2 {
                    Divider()
                        .background(Color.secondary.opacity(0.15))
                        .padding(.bottom, 2)
                }
            }
            .padding(.top, level == 1 ? 16 : 10)
            
        case .blockquote:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 4)
                
                VStack(alignment: .leading) {
                    InlineMarkdownText(text: block.text)
                        .font(.system(.body, design: .serif))
                        .italic()
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.04))
            }
            .cornerRadius(4)
            .padding(.vertical, 6)
            
        case .codeBlock(let code, let language):
            CodeBlockView(code: code, language: language)
            
        case .list(let isOrdered, let indentLevel):
            HStack(alignment: .top, spacing: 8) {
                Spacer()
                    .frame(width: CGFloat(indentLevel * 18))
                
                if isOrdered {
                    Text("1.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("•")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                        .frame(width: 10, height: 16, alignment: .center)
                }
                
                InlineMarkdownText(text: block.text)
                    .font(.body)
                    .lineSpacing(3)
            }
            .padding(.vertical, 1)
            
        case .horizontalRule:
            Divider()
                .padding(.vertical, 12)
            
        case .paragraph:
            InlineMarkdownText(text: block.text)
                .font(.body)
                .lineSpacing(4)
                .foregroundColor(.primary)
        }
    }
    
    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 26, design: .default)
        case 2: return .system(size: 20, design: .default)
        case 3: return .system(size: 17, design: .default)
        case 4: return .system(size: 15, design: .default)
        default: return .system(size: 14, design: .default)
        }
    }
}

// Safely handles inline markdown components via standard AttributedString
struct InlineMarkdownText: View {
    let text: String
    
    var body: some View {
        if let attributedString = try? AttributedString(markdown: text) {
            Text(attributedString)
        } else {
            Text(text)
        }
    }
}

// Copyable, beautifully styled monospaced Code Block component
struct CodeBlockView: View {
    let code: String
    let language: String?
    
    @State private var isHovering = false
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Optional Language header
            HStack {
                Text(language?.uppercased() ?? "CODE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: copyToClipboard) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isCopied ? .green : .accentColor)
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.textColor).opacity(0.04))
            
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(Color(NSColor.textColor).opacity(0.02))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .padding(.vertical, 4)
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isCopied = false
            }
        }
    }
}
