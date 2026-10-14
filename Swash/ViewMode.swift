//
//  ViewMode.swift
//  Swash
//

import Foundation

enum ViewMode: String, CaseIterable, Identifiable {
    case edit = "Source"
    case preview = "Formatted"
    case split = "Split"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .edit: return "text.alignleft"
        case .preview: return "character.cursor.ibeam"
        case .split: return "square.split.2x1"
        }
    }
    
    var tooltip: String {
        switch self {
        case .edit: return "Show source"
        case .preview: return "Edit text"
        case .split: return "Side-by-side view"
        }
    }
}
