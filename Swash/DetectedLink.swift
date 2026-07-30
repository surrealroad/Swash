//
//  DetectedLink.swift
//  Swash
//
//  Created by Jack James on 30/07/2026.
//

import Foundation

struct DetectedLink: Equatable, Hashable {
    let fullRange: NSRange      // Entire link syntax range in text
    let textRange: NSRange      // Range of display text
    let urlRange: NSRange       // Range of URL string
    let text: String            // Display text
    let url: String            // URL string
    let isBareURL: Bool
}

struct LinkDetector {
    static func findLinks(in fullText: String, flavor: MarkdownFlavor) -> [DetectedLink] {
        var links: [DetectedLink] = []
        let nsText = fullText as NSString
        let length = nsText.length
        if length == 0 { return [] }
        
        // Helper to check if range is in code block or inline code
        func isInCode(_ range: NSRange) -> Bool {
            // Find code blocks ```...```
            if let regex = try? NSRegularExpression(pattern: "```[\\s\\S]*?```", options: []) {
                let matches = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: length))
                if matches.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) {
                    return true
                }
            }
            // Find inline code `...`
            if let regex = try? NSRegularExpression(pattern: "`[^`\\n]+`", options: []) {
                let matches = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: length))
                if matches.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) {
                    return true
                }
            }
            return false
        }
        
        if flavor == .slack {
            // 1. Slack link with pipe: <url|text>
            if let regex = try? NSRegularExpression(pattern: "<(https?://[^>|\\n]+)\\|([^>|\\n]+)>", options: []) {
                let matches = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: length))
                for m in matches {
                    let fullR = m.range(at: 0)
                    if isInCode(fullR) { continue }
                    let urlR = m.range(at: 1)
                    let textR = m.range(at: 2)
                    let urlStr = nsText.substring(with: urlR)
                    let textStr = nsText.substring(with: textR)
                    links.append(DetectedLink(fullRange: fullR, textRange: textR, urlRange: urlR, text: textStr, url: urlStr, isBareURL: false))
                }
            }
            
            // 2. Slack link without pipe: <url>
            if let regex = try? NSRegularExpression(pattern: "<(https?://[^>|\\n]+)>", options: []) {
                let matches = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: length))
                for m in matches {
                    let fullR = m.range(at: 0)
                    if isInCode(fullR) { continue }
                    if links.contains(where: { NSIntersectionRange($0.fullRange, fullR).length > 0 }) { continue }
                    let urlR = m.range(at: 1)
                    let urlStr = nsText.substring(with: urlR)
                    links.append(DetectedLink(fullRange: fullR, textRange: urlR, urlRange: urlR, text: urlStr, url: urlStr, isBareURL: false))
                }
            }
        } else {
            // GitHub / Standard Markdown: [text](url)
            if let regex = try? NSRegularExpression(pattern: "\\[([^\\]\\n]*)\\]\\(([^\\)\\n]*)\\)", options: []) {
                let matches = regex.matches(in: fullText, options: [], range: NSRange(location: 0, length: length))
                for m in matches {
                    let fullR = m.range(at: 0)
                    if isInCode(fullR) { continue }
                    let textR = m.range(at: 1)
                    let urlR = m.range(at: 2)
                    let textStr = nsText.substring(with: textR)
                    let urlStr = nsText.substring(with: urlR)
                    links.append(DetectedLink(fullRange: fullR, textRange: textR, urlRange: urlR, text: textStr, url: urlStr, isBareURL: false))
                }
            }
        }
        
        // Bare URLs: https?://...
        if let bareRegex = try? NSRegularExpression(pattern: "https?://[^\\s<>\"'\\)]+", options: []) {
            let matches = bareRegex.matches(in: fullText, options: [], range: NSRange(location: 0, length: length))
            for m in matches {
                var rawR = m.range(at: 0)
                if isInCode(rawR) { continue }
                
                var str = nsText.substring(with: rawR)
                while let last = str.last, [".", ",", ";", ":", "!", "?", ")", "]", "\"", "'"].contains(last) {
                    str.removeLast()
                    rawR.length -= 1
                }
                if rawR.length == 0 { continue }
                
                if links.contains(where: { NSIntersectionRange($0.fullRange, rawR).length > 0 }) {
                    continue
                }
                
                links.append(DetectedLink(fullRange: rawR, textRange: rawR, urlRange: rawR, text: str, url: str, isBareURL: true))
            }
        }
        
        return links
    }
    
    static func findLink(at range: NSRange?, in fullText: String, flavor: MarkdownFlavor) -> DetectedLink? {
        guard let range = range else { return nil }
        let allLinks = findLinks(in: fullText, flavor: flavor)
        
        for link in allLinks {
            if range.length > 0 {
                if NSIntersectionRange(range, link.fullRange).length > 0 {
                    return link
                }
            } else {
                let loc = range.location
                if loc >= link.fullRange.location && loc <= (link.fullRange.location + link.fullRange.length) {
                    return link
                }
            }
        }
        return nil
    }
}
