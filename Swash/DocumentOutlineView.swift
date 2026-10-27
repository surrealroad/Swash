//
//  DocumentOutlineView.swift
//  Swash
//
//  The heading outline sidebar and the status bar's statistics menu.
//

import SwiftUI

/// Sidebar listing the document's headings; the heading around the caret is highlighted and
/// choosing one moves the editor there.
struct DocumentOutlineView: View {
    let outline: MarkdownOutline
    let currentIndex: Int?
    let onSelect: (MarkdownOutline.Heading) -> Void

    /// The sidebar's fixed width; ContentView resizes the window by it when the outline is toggled.
    static let width: CGFloat = 220

    var body: some View {
        Group {
            if outline.headings.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                    Text("No Headings")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Lines starting with # appear here.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let minLevel = outline.headings.map(\.level).min() ?? 1
                ScrollViewReader { proxy in
                    List(selection: Binding<Int?>(
                        get: { currentIndex },
                        set: { index in
                            if let index = index, outline.headings.indices.contains(index) {
                                onSelect(outline.headings[index])
                            }
                        }
                    )) {
                        ForEach(Array(outline.headings.enumerated()), id: \.offset) { index, heading in
                            Text(heading.title.isEmpty ? "Untitled" : heading.title)
                                .font(.system(size: 12, weight: heading.level == minLevel ? .semibold : .regular))
                                .foregroundColor(heading.title.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.leading, CGFloat(min(heading.level - minLevel, 5)) * 12)
                                .help(heading.title)
                                .tag(index)
                                .id(index)
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: currentIndex) { _, index in
                        if let index = index { proxy.scrollTo(index) }
                    }
                }
            }
        }
        .frame(width: Self.width)
        .accessibilityLabel("Outline")
    }
}

/// Which statistic the status bar shows; the choice is remembered across documents.
enum StatusStatistic: String, CaseIterable, Identifiable {
    case words, characters, charactersExcludingSpaces, paragraphs, readingTime

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .words: return "Words"
        case .characters: return "Characters"
        case .charactersExcludingSpaces: return "Characters (No Spaces)"
        case .paragraphs: return "Paragraphs"
        case .readingTime: return "Reading Time"
        }
    }

    func value(_ statistics: MarkdownStatistics) -> Int {
        switch self {
        case .words: return statistics.words
        case .characters: return statistics.characters
        case .charactersExcludingSpaces: return statistics.charactersExcludingSpaces
        case .paragraphs: return statistics.paragraphs
        case .readingTime: return statistics.readingMinutes
        }
    }

    func unit(_ count: Int) -> String {
        switch self {
        case .words: return count == 1 ? "word" : "words"
        case .characters, .charactersExcludingSpaces: return count == 1 ? "character" : "characters"
        case .paragraphs: return count == 1 ? "paragraph" : "paragraphs"
        case .readingTime: return "min read"
        }
    }

    /// "340 words", or "12 of 340 words" when part of the document is selected.
    func label(document: MarkdownStatistics, selection: MarkdownStatistics?) -> String {
        let total = value(document)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let format = { (n: Int) in formatter.string(from: NSNumber(value: n)) ?? "\(n)" }
        if let selection = selection {
            return "\(format(value(selection))) of \(format(total)) \(unit(total))"
        }
        return "\(format(total)) \(unit(total))"
    }
}

/// The status bar's statistic: a menu showing every count, which picks the one displayed.
struct StatisticsMenu: View {
    let document: MarkdownStatistics
    let selection: MarkdownStatistics?
    @AppStorage("statusStatistic") private var statistic: StatusStatistic = .words

    var body: some View {
        Menu {
            Picker("Show", selection: $statistic) {
                ForEach(StatusStatistic.allCases) { item in
                    Text("\(item.menuTitle): \(item.label(document: document, selection: selection))").tag(item)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(statistic.label(document: document, selection: selection))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose the statistic shown here")
    }
}
