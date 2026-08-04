//
//  QuickNoteWidget.swift
//  SwashWidgetExtension
//

import WidgetKit
import SwiftUI

struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entries = [SimpleEntry(date: Date())]
        let timeline = Timeline(entries: entries, policy: .never)
        completion(timeline)
    }
}

struct QuickNoteWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Swash")
                    .font(.headline)
            }
            
            Spacer()
            
            Link(destination: URL(string: "swash://new")!) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Note")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

struct QuickNoteWidget: Widget {
    let kind: String = "QuickNoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            QuickNoteWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("New Note Launcher")
        .description("Quickly open Swash to create a new Markdown note.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
