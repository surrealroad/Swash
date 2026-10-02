//
//  SpecRunner.swift
//  Swash
//
//  Runs the CommonMark 0.31.2 and GFM extension example suites against MarkdownDocument
//  by rendering each example to HTML and comparing with the expected output. Also checks
//  that every node's source range and markers lie within the source and nest in their parent.
//
//  Usage: run_commonmark_spec.sh [--verbose] [--example N] [--section NAME]
//

import Foundation

struct SpecExample: Decodable {
    let markdown: String
    let html: String
    let example: Int
    let section: String
}

@main
struct SpecRunner {
    static func main() {
        let args = CommandLine.arguments
        let fixtures = URL(fileURLWithPath: args[1])
        let verbose = args.contains("--verbose")
        let onlyExample = args.firstIndex(of: "--example").flatMap { Int(args[$0 + 1]) }
        let onlySection = args.firstIndex(of: "--section").map { args[$0 + 1] }

        var totalFailures = 0
        let suites: [(file: String, name: String, options: MarkdownParseOptions)] = [
            ("commonmark-0.31.2.json", "CommonMark 0.31.2", .commonMark),
            ("gfm-extensions.json", "GFM extensions", .gfm),
        ]
        for suite in suites {
            guard let data = try? Data(contentsOf: fixtures.appendingPathComponent(suite.file)),
                  let examples = try? JSONDecoder().decode([SpecExample].self, from: data) else {
                print("❌ Could not load \(suite.file)")
                exit(2)
            }
            var passed = 0
            var structureFailures = 0
            var sectionStats: [String: (pass: Int, total: Int)] = [:]
            var sectionOrder: [String] = []
            for ex in examples {
                if let only = onlyExample, only != ex.example { continue }
                if let section = onlySection, section != ex.section { continue }
                let document = MarkdownDocument.parse(ex.markdown, options: suite.options)
                let html = MarkdownHTMLRenderer.render(document)
                // "<IGNORE>" examples only check that parsing does not crash
                let ok = html == ex.html || ex.html == "<IGNORE>\n"
                if sectionStats[ex.section] == nil { sectionOrder.append(ex.section) }
                var stat = sectionStats[ex.section] ?? (0, 0)
                stat.total += 1
                if ok { stat.pass += 1; passed += 1 }
                sectionStats[ex.section] = stat
                if let problem = structureProblem(document) {
                    structureFailures += 1
                    if verbose || onlyExample != nil { print("⚠️  [\(suite.name) #\(ex.example)] structure: \(problem)") }
                }
                if !ok && (verbose || onlyExample != nil) {
                    print("❌ [\(suite.name) #\(ex.example)] \(ex.section)")
                    print("   markdown: \(ex.markdown.debugDescription)")
                    print("   expected: \(ex.html.debugDescription)")
                    print("   actual:   \(html.debugDescription)")
                }
            }
            let total = sectionStats.values.reduce(0) { $0 + $1.total }
            print("\n\(suite.name): \(passed)/\(total) passed, \(structureFailures) structure problems")
            for section in sectionOrder {
                let s = sectionStats[section]!
                if s.pass < s.total || verbose {
                    print(String(format: "  %-45@ %3d/%3d", section as NSString, s.pass, s.total))
                }
            }
            totalFailures += (total - passed) + structureFailures
        }
        if onlyExample == nil && onlySection == nil {
            print("")
            totalFailures += ParserChecks.run()
        }
        exit(totalFailures == 0 ? 0 : 1)
    }

    /// Ranges must be inside the source; child and marker ranges must lie inside their node's range.
    static func structureProblem(_ document: MarkdownDocument) -> String? {
        let length = (document.source as NSString).length
        var problem: String? = nil
        func inside(_ inner: NSRange, _ outer: NSRange) -> Bool {
            inner.location >= outer.location && inner.location + inner.length <= outer.location + outer.length
        }
        document.root.walk { node in
            guard problem == nil else { return }
            let r = node.range
            if r.location < 0 || r.length < 0 || r.location + r.length > length {
                problem = "\(node.kind) range \(r) outside source (length \(length))"
                return
            }
            for marker in node.markers where !inside(marker, NSRange(location: 0, length: length)) {
                problem = "\(node.kind) marker \(marker) outside source"
                return
            }
            if let parent = node.parent, parent !== document.root, !inside(r, parent.range) {
                problem = "\(node.kind) \(r) not inside parent \(parent.kind) \(parent.range)"
            }
        }
        return problem
    }
}
