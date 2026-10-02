//
//  GFMSpecRunner.swift
//  Swash
//
//  Automated GFM Spec Compliance and Headless Snapshot Test Harness
//

import Foundation
import SwiftUI
import AppKit

// MARK: - Fixture Models

struct TableTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
    let expectedHeaders: [String]
    let expectedAlignments: [String]
    let expectedRowCount: Int
    let expectedRows: [[String]]
}

struct TableTestSuite: Decodable {
    let section: String
    let cases: [TableTestCase]
}

struct TaskItemExpectation: Decodable {
    let isChecked: Bool
    let indentLevel: Int
    let text: String
}

struct TaskListTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
    let expectedItems: [TaskItemExpectation]
}

struct TaskListTestSuite: Decodable {
    let section: String
    let cases: [TaskListTestCase]
}

struct ThematicBreakTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
    let expectedCount: Int
}

struct ThematicBreakTestSuite: Decodable {
    let section: String
    let cases: [ThematicBreakTestCase]
}

struct HeadingExpectation: Decodable {
    let level: Int
    let text: String
}

struct HeadingTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
    let expectedHeadings: [HeadingExpectation]
}

struct HeadingTestSuite: Decodable {
    let section: String
    let cases: [HeadingTestCase]
}

struct FencedCodeTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
    let expectedCode: String
    let expectedLanguage: String?
}

struct FencedCodeTestSuite: Decodable {
    let section: String
    let cases: [FencedCodeTestCase]
}

struct BlockquoteAlertTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
    let expectedType: String
    let expectedAlertType: String?
    let expectedText: String
}

struct BlockquoteAlertTestSuite: Decodable {
    let section: String
    let cases: [BlockquoteAlertTestCase]
}

struct InlineTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
}

struct InlineTestSuite: Decodable {
    let section: String
    let cases: [InlineTestCase]
}

struct FootnoteTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
}

struct FootnoteTestSuite: Decodable {
    let section: String
    let cases: [FootnoteTestCase]
}

struct ImageTestCase: Decodable {
    let id: String
    let example: Int
    let description: String
    let markdown: String
}

struct ImageTestSuite: Decodable {
    let section: String
    let cases: [ImageTestCase]
}

// MARK: - Snapshot Renderer

final class HeadlessSnapshotRenderer {
    static let shared = HeadlessSnapshotRenderer()
    
    private init() {
        // Ensure NSApplication is initialized for AppKit text rendering
        _ = NSApplication.shared
    }
    
    func renderViewToPNG<V: View>(_ view: V, width: CGFloat = 650, minHeight: CGFloat = 80, targetURL: URL) -> Bool {
        let hostingView = NSHostingView(rootView: view.frame(width: width))
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: minHeight)
        hostingView.layoutSubtreeIfNeeded()
        
        // Pump main run loop to allow SwiftUI/AppKit coordinator updates and async dispatches
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        
        var finalHeight = max(minHeight, ceil(hostingView.fittingSize.height))
        func findScrollView(in v: NSView) -> NSScrollView? {
            if let sv = v as? NSScrollView { return sv }
            for sub in v.subviews {
                if let found = findScrollView(in: sub) { return found }
            }
            return nil
        }
        if let sv = findScrollView(in: hostingView), let doc = sv.documentView {
            var docH = doc.fittingSize.height
            if let tv = doc as? NSTextView, let lm = tv.layoutManager, let tc = tv.textContainer {
                lm.ensureLayout(for: tc)
                docH = max(docH, lm.usedRect(for: tc).height + tv.textContainerInset.height * 2 + 10)
            }
            if docH > finalHeight {
                finalHeight = max(finalHeight, ceil(docH))
            }
        }
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: finalHeight)
        hostingView.layoutSubtreeIfNeeded()
        
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return false
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pngData.write(to: targetURL)
            return true
        } catch {
            print("  ❌ Failed to write PNG to \(targetURL.path): \(error)")
            return false
        }
    }
}

// MARK: - Main Test Runner

@main
struct GFMSpecRunner {
    static func main() {
        print("==================================================")
        print("  Swash GFM Spec Compliance & Snapshot Runner    ")
        print("==================================================")
        
        let fileManager = FileManager.default
        let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let fixturesDir = currentDir.appendingPathComponent("Tests/GFMSpec/fixtures")
        let snapshotsBaseDir = currentDir.appendingPathComponent("Tests/GFMSpec/snapshots")
        
        var totalPassed = 0
        var totalFailed = 0
        
        // 1. Run Table Tests
        let tablesFixtureURL = fixturesDir.appendingPathComponent("tables.json")
        if fileManager.fileExists(atPath: tablesFixtureURL.path) {
            let (passed, failed) = runTableTests(from: tablesFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // 2. Run Task List Tests
        let taskListsFixtureURL = fixturesDir.appendingPathComponent("tasklists.json")
        if fileManager.fileExists(atPath: taskListsFixtureURL.path) {
            let (passed, failed) = runTaskListTests(from: taskListsFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // 3. Run Thematic Break Tests
        let breaksFixtureURL = fixturesDir.appendingPathComponent("thematic_breaks.json")
        if fileManager.fileExists(atPath: breaksFixtureURL.path) {
            let (passed, failed) = runThematicBreakTests(from: breaksFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // 4. Run Heading Tests
        let headingsFixtureURL = fixturesDir.appendingPathComponent("headings.json")
        if fileManager.fileExists(atPath: headingsFixtureURL.path) {
            let (passed, failed) = runHeadingTests(from: headingsFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // 5. Run Fenced Code Tests
        let fencedCodeFixtureURL = fixturesDir.appendingPathComponent("fenced_code.json")
        if fileManager.fileExists(atPath: fencedCodeFixtureURL.path) {
            let (passed, failed) = runFencedCodeTests(from: fencedCodeFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // 6. Run Blockquote & Alert Tests
        let quotesFixtureURL = fixturesDir.appendingPathComponent("blockquotes_alerts.json")
        if fileManager.fileExists(atPath: quotesFixtureURL.path) {
            let (passed, failed) = runBlockquoteAlertTests(from: quotesFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // 7. Run Inline Tests
        let inlinesFixtureURL = fixturesDir.appendingPathComponent("inlines.json")
        if fileManager.fileExists(atPath: inlinesFixtureURL.path) {
            let (passed, failed) = runInlineTests(from: inlinesFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // 8. Run Footnote Tests
        let footnotesFixtureURL = fixturesDir.appendingPathComponent("footnotes.json")
        if fileManager.fileExists(atPath: footnotesFixtureURL.path) {
            let (passed, failed) = runFootnoteTests(from: footnotesFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // 9. Run Image Tests
        let imagesFixtureURL = fixturesDir.appendingPathComponent("images.json")
        if fileManager.fileExists(atPath: imagesFixtureURL.path) {
            let (passed, failed) = runImageTests(from: imagesFixtureURL, snapshotsDir: snapshotsBaseDir)
            totalPassed += passed
            totalFailed += failed
        }
        
        // Summary
        print("\n--------------------------------------------------")
        print("Summary: \(totalPassed) Passed, \(totalFailed) Failed")
        print("Snapshots written to: \(snapshotsBaseDir.path)")
        print("--------------------------------------------------")
        
        if totalFailed > 0 {
            exit(1)
        } else {
            exit(0)
        }
    }
    
    // MARK: - Table Test Execution
    
    static func runTableTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(TableTestSuite.self, from: data) else {
            print("❌ Failed to decode tables fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            // 1. Parse AST
            let blocks = ASTBlocks.parse(testCase.markdown)
            let tableBlock = blocks.first(where: {
                if case .table = $0.type { return true }
                return false
            })
            
            var astSuccess = false
            var astFailureReason = ""
            
            if let tableBlock = tableBlock, case let .table(headers, alignments, rows) = tableBlock.type {
                let actualAlignments = alignments.map { "\($0)" }
                
                if headers != testCase.expectedHeaders {
                    astFailureReason = "Headers mismatch. Expected: \(testCase.expectedHeaders), got: \(headers)"
                } else if actualAlignments != testCase.expectedAlignments {
                    astFailureReason = "Alignments mismatch. Expected: \(testCase.expectedAlignments), got: \(actualAlignments)"
                } else if rows.count != testCase.expectedRowCount {
                    astFailureReason = "Row count mismatch. Expected: \(testCase.expectedRowCount), got: \(rows.count)"
                } else {
                    astSuccess = true
                }
            } else {
                astFailureReason = "No .table block produced. Blocks: \(blocks.map { "\($0.type)" })"
            }
            
            // 2. Render Snapshots
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
    
    // MARK: - Task List Test Execution
    
    static func runTaskListTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(TaskListTestSuite.self, from: data) else {
            print("❌ Failed to decode task lists fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            // 1. Parse AST
            let blocks = ASTBlocks.parse(testCase.markdown)
            let taskListBlocks = blocks.filter {
                if case .taskList = $0.type { return true }
                return false
            }
            
            var astSuccess = false
            var astFailureReason = ""
            
            if taskListBlocks.count != testCase.expectedItems.count {
                astFailureReason = "Task item count mismatch. Expected: \(testCase.expectedItems.count), got: \(taskListBlocks.count). Blocks: \(blocks.map { "\($0.type)" })"
            } else {
                var allMatch = true
                for (index, expected) in testCase.expectedItems.enumerated() {
                    let block = taskListBlocks[index]
                    if case let .taskList(isChecked, indentLevel) = block.type {
                        if isChecked != expected.isChecked {
                            astFailureReason = "Item [\(index)] isChecked mismatch: expected \(expected.isChecked), got \(isChecked)"
                            allMatch = false
                            break
                        }
                        if indentLevel != expected.indentLevel {
                            astFailureReason = "Item [\(index)] indentLevel mismatch: expected \(expected.indentLevel), got \(indentLevel)"
                            allMatch = false
                            break
                        }
                        if block.text != expected.text {
                            astFailureReason = "Item [\(index)] text mismatch: expected '\(expected.text)', got '\(block.text)'"
                            allMatch = false
                            break
                        }
                    }
                }
                astSuccess = allMatch
            }
            
            // 2. Render Snapshots
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
    
    // MARK: - Thematic Break Test Execution
    
    static func runThematicBreakTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(ThematicBreakTestSuite.self, from: data) else {
            print("❌ Failed to decode thematic breaks fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            let blocks = ASTBlocks.parse(testCase.markdown)
            let breaks = blocks.filter {
                if case .horizontalRule = $0.type { return true }
                return false
            }
            
            let astSuccess = breaks.count == testCase.expectedCount
            let astFailureReason = astSuccess ? "" : "Expected \(testCase.expectedCount) thematic breaks, got \(breaks.count). Blocks: \(blocks.map { "\($0.type)" })"
            
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
    
    // MARK: - Heading Test Execution
    
    static func runHeadingTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(HeadingTestSuite.self, from: data) else {
            print("❌ Failed to decode headings fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            let blocks = ASTBlocks.parse(testCase.markdown)
            let parsedHeadings: [(Int, String)] = blocks.compactMap { block in
                if case .heading(let level) = block.type {
                    return (level, block.text)
                }
                return nil
            }
            
            var astSuccess = false
            var astFailureReason = ""
            
            if parsedHeadings.count != testCase.expectedHeadings.count {
                astFailureReason = "Expected \(testCase.expectedHeadings.count) headings, got \(parsedHeadings.count). Parsed: \(parsedHeadings)"
            } else {
                var allMatch = true
                for (idx, expected) in testCase.expectedHeadings.enumerated() {
                    let (lvl, txt) = parsedHeadings[idx]
                    if lvl != expected.level || txt != expected.text {
                        astFailureReason = "Heading [\(idx)] mismatch: expected (level: \(expected.level), text: '\(expected.text)'), got (level: \(lvl), text: '\(txt)')"
                        allMatch = false
                        break
                    }
                }
                astSuccess = allMatch
            }
            
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
    
    // MARK: - Fenced Code Test Execution
    
    static func runFencedCodeTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(FencedCodeTestSuite.self, from: data) else {
            print("❌ Failed to decode fenced code fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            let blocks = ASTBlocks.parse(testCase.markdown)
            let codeBlocks: [(String, String?)] = blocks.compactMap { block in
                if case let .codeBlock(code, lang) = block.type {
                    return (code, lang)
                }
                return nil
            }
            
            var astSuccess = false
            var astFailureReason = ""
            
            if let firstCode = codeBlocks.first {
                if firstCode.0 != testCase.expectedCode {
                    astFailureReason = "Code mismatch. Expected:\n'\(testCase.expectedCode)'\nGot:\n'\(firstCode.0)'"
                } else if firstCode.1 != testCase.expectedLanguage {
                    astFailureReason = "Language mismatch. Expected: \(String(describing: testCase.expectedLanguage)), got: \(String(describing: firstCode.1))"
                } else {
                    astSuccess = true
                }
            } else {
                astFailureReason = "No code blocks found. Blocks: \(blocks.map { "\($0.type)" })"
            }
            
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
    
    // MARK: - Blockquote & Alert Test Execution
    
    static func runBlockquoteAlertTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(BlockquoteAlertTestSuite.self, from: data) else {
            print("❌ Failed to decode blockquotes & alerts fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            let blocks = ASTBlocks.parse(testCase.markdown)
            var astSuccess = false
            var astFailureReason = ""
            
            if testCase.expectedType == "alertCallout" {
                if let block = blocks.first(where: { if case .alertCallout = $0.type { return true }; return false }) {
                    if case let .alertCallout(alertType, text) = block.type {
                        if alertType.rawValue != testCase.expectedAlertType {
                            astFailureReason = "Alert type mismatch: expected \(testCase.expectedAlertType ?? ""), got \(alertType.rawValue)"
                        } else if text != testCase.expectedText {
                            astFailureReason = "Alert text mismatch: expected '\(testCase.expectedText)', got '\(text)'"
                        } else {
                            astSuccess = true
                        }
                    }
                } else {
                    astFailureReason = "No alert callout block found in: \(blocks.map { "\($0.type)" })"
                }
            } else if testCase.expectedType == "blockquote" {
                if let block = blocks.first(where: { if case .blockquote = $0.type { return true }; return false }) {
                    if block.text != testCase.expectedText {
                        astFailureReason = "Blockquote text mismatch: expected '\(testCase.expectedText)', got '\(block.text)'"
                    } else {
                        astSuccess = true
                    }
                } else {
                    astFailureReason = "No blockquote found in: \(blocks.map { "\($0.type)" })"
                }
            }
            
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
    
    // MARK: - Inline Test Execution
    
    static func runInlineTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(InlineTestSuite.self, from: data) else {
            print("❌ Failed to decode inlines fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            let blocks = ASTBlocks.parse(testCase.markdown)
            let astSuccess = !blocks.isEmpty
            let astFailureReason = astSuccess ? "" : "Parser produced no blocks"
            
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
    
    // MARK: - Footnote Test Execution
    
    static func runFootnoteTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(FootnoteTestSuite.self, from: data) else {
            print("❌ Failed to decode footnotes fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            let blocks = ASTBlocks.parse(testCase.markdown)
            let footnoteDef = blocks.first(where: {
                if case .footnoteDefinition = $0.type { return true }
                return false
            })
            
            let astSuccess = footnoteDef != nil
            let astFailureReason = astSuccess ? "" : "No .footnoteDefinition block found in AST: \(blocks.map { "\($0.type)" })"
            
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
    
    // MARK: - Image Test Execution
    
    static func runImageTests(from fixtureURL: URL, snapshotsDir: URL) -> (Int, Int) {
        guard let data = try? Data(contentsOf: fixtureURL),
              let suite = try? JSONDecoder().decode(ImageTestSuite.self, from: data) else {
            print("❌ Failed to decode images fixture: \(fixtureURL.path)")
            return (0, 1)
        }
        
        print("\n▶ Running Section: \(suite.section)")
        var passed = 0
        var failed = 0
        
        for testCase in suite.cases {
            print("  Case [\(testCase.id)] (GFM #\(testCase.example)): \(testCase.description)")
            
            let blocks = ASTBlocks.parse(testCase.markdown)
            let astSuccess = !blocks.isEmpty
            let astFailureReason = astSuccess ? "" : "Parser produced no blocks"
            
            let previewPNG = snapshotsDir.appendingPathComponent("preview/\(testCase.id).png")
            let editorPNG = snapshotsDir.appendingPathComponent("editor/\(testCase.id).png")
            let baseScriptsURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts")
            
            let previewView = MarkdownPreviewView(text: testCase.markdown, flavor: .github, baseURL: baseScriptsURL)
            let editorView = SwashTextView(
                text: .constant(testCase.markdown),
                selectedRange: .constant(nil),
                selectionRect: .constant(nil),
                scrollOriginY: .constant(0),
                isStyled: true,
                flavor: .github,
                baseURL: baseScriptsURL
            )
            
            let previewSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(previewView, targetURL: previewPNG)
            let editorSaved = HeadlessSnapshotRenderer.shared.renderViewToPNG(editorView, targetURL: editorPNG)
            
            if astSuccess {
                print("    ✓ AST: PASS | Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                passed += 1
            } else {
                print("    ❌ AST: FAIL - \(astFailureReason)")
                print("       Preview Snapshot: \(previewSaved ? "✓" : "❌") | Editor Snapshot: \(editorSaved ? "✓" : "❌")")
                failed += 1
            }
        }
        
        return (passed, failed)
    }
}

// MARK: - AST adapter
//
// The GFM fixtures were written against Swash's original flat block parser. These types map
// the shared Markdown AST (Swash/Markdown) onto that flat shape so the same assertions now
// exercise the parser the app actually uses.

enum BlockType: Equatable {
    case heading(level: Int)
    case blockquote
    case alertCallout(type: AlertType, text: String)
    case codeBlock(code: String, language: String?)
    case list(isOrdered: Bool, indentLevel: Int, itemNumber: Int)
    case taskList(isChecked: Bool, indentLevel: Int)
    case table(headers: [String], alignments: [TableAlignment], rows: [[String]])
    case horizontalRule
    case footnoteDefinition(label: String, text: String)
    case linkReference(label: String, url: String)
    case paragraph
}

struct MarkdownBlock {
    let type: BlockType
    let text: String
}

enum ASTBlocks {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let document = MarkdownDocument.parse(text)
        let ns = text as NSString
        var blocks: [MarkdownBlock] = []
        
        func source(_ r: NSRange) -> String { ns.substring(with: r) }
        /// Source of `range` with the given marker ranges removed, per line, trimmed.
        func stripped(_ range: NSRange, markers: [NSRange]) -> String {
            let inside = markers.filter { NSIntersectionRange($0, range).length > 0 }.sorted { $0.location > $1.location }
            let result = NSMutableString(string: source(range))
            for m in inside {
                let local = NSIntersectionRange(m, range)
                result.deleteCharacters(in: NSRange(location: local.location - range.location, length: local.length))
            }
            return (result as String).components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        }
        func quoteMarkers(_ node: MarkdownNode) -> [NSRange] {
            var markers: [NSRange] = []
            node.walk { n in
                switch n.kind {
                case .blockQuote, .alert: markers += n.markers
                default: break
                }
            }
            return markers
        }
        func depth(_ node: MarkdownNode) -> Int {
            node.ancestors.filter { if case .listItem = $0.kind { return true }; return false }.count
        }
        func visit(_ node: MarkdownNode) {
            switch node.kind {
            case .heading(let level, let setext):
                let text = setext
                    ? stripped(node.range, markers: node.markers).components(separatedBy: "\n").filter { !$0.isEmpty }.joined(separator: " ")
                    : stripped(node.range, markers: node.markers)
                blocks.append(MarkdownBlock(type: .heading(level: level), text: text.trimmingCharacters(in: .whitespaces)))
            case .paragraph:
                blocks.append(MarkdownBlock(type: .paragraph, text: source(node.range)))
            case .blockQuote:
                blocks.append(MarkdownBlock(type: .blockquote, text: stripped(node.range, markers: quoteMarkers(node))))
            case .alert(let type):
                let body = node.children.map { stripped($0.range, markers: quoteMarkers(node)) }.joined(separator: "\n")
                blocks.append(MarkdownBlock(type: .alertCallout(type: type, text: body), text: ""))
            case .codeBlock(_, let info):
                let code = node.literal.hasSuffix("\n") ? String(node.literal.dropLast()) : node.literal
                let language = info.split(separator: " ").first.map(String.init)
                blocks.append(MarkdownBlock(type: .codeBlock(code: code, language: language), text: ""))
            case .listItem(let task):
                let firstText = node.firstChild.map { source($0.range) } ?? ""
                if let task = task {
                    blocks.append(MarkdownBlock(type: .taskList(isChecked: task == .checked, indentLevel: depth(node)), text: firstText))
                } else if let list = node.parent, case .list(let ordered, let start, _, _, _) = list.kind {
                    let index = list.children.firstIndex { $0 === node } ?? 0
                    blocks.append(MarkdownBlock(type: .list(isOrdered: ordered, indentLevel: depth(node), itemNumber: start + index), text: firstText))
                }
                for child in node.children.dropFirst() { visit(child) }
                return
            case .table(let alignments):
                var headers: [String] = []
                var rows: [[String]] = []
                for section in node.children {
                    if case .tableHead = section.kind {
                        headers = section.firstChild?.children.map { source($0.range).replacingOccurrences(of: "\\|", with: "|") } ?? []
                    } else if case .tableRow = section.kind {
                        rows.append(section.children.map { source($0.range) })
                    }
                }
                blocks.append(MarkdownBlock(type: .table(headers: headers, alignments: alignments, rows: rows), text: ""))
                return
            case .thematicBreak:
                blocks.append(MarkdownBlock(type: .horizontalRule, text: ""))
            case .footnoteDefinition(let label):
                let body = node.children.map { source($0.range) }.joined(separator: " ")
                blocks.append(MarkdownBlock(type: .footnoteDefinition(label: label, text: body), text: ""))
                return
            case .linkReferenceDefinition(let label, let destination, _):
                blocks.append(MarkdownBlock(type: .linkReference(label: label, url: destination), text: ""))
            default:
                break
            }
            switch node.kind {
            case .blockQuote, .alert, .heading, .paragraph:
                return
            default:
                for child in node.children { visit(child) }
            }
        }
        visit(document.root)
        return blocks
    }
}
