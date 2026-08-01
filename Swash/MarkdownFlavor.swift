//
//  MarkdownFlavor.swift
//  Swash
//
//  Created by Jack James on 01/08/2026.
//

import Foundation

enum MarkdownFlavor: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case commonMark = "CommonMark"
    case original = "Original"
    case slack = "Slack"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .github: return "GitHub Markdown"
        case .commonMark: return "CommonMark"
        case .original: return "Original Markdown"
        case .slack: return "Slack mrkdwn"
        }
    }
}
