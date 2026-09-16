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
        
        let fitting = hostingView.fittingSize
        let finalHeight = max(minHeight, ceil(fitting.height))
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
            let blocks = MarkdownParser.parse(testCase.markdown)
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
            let blocks = MarkdownParser.parse(testCase.markdown)
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
}
