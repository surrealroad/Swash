// Checks for what Swash adds to the engine's HTML → Markdown paste conversion
// (Swash/PixerateMarkdownExtensions.swift). Run via scripts/run_paste_tests.sh.
import Foundation
import PixerateMarkdown

var failures = 0
func check(_ name: String, _ actual: String?, _ expected: String) {
    let ok = actual == expected
    print("\(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " — expected \(expected.debugDescription), got \((actual ?? "nil").debugDescription)")")
    if !ok { failures += 1 }
}

// Confluence copies images as media placeholders; they link to the attachment on the source page's site
let media = "<p>Before</p><div data-node-type=\"mediaSingle\"><div data-node-type=\"media\" data-type=\"file\" data-context-id=\"42\" data-alt=\"shot 1.png\" data-file-name=\"shot 1.png\"></div></div>"
check("Confluence media links to the attachment",
      HTMLToMarkdown.convert(media, sourceURL: URL(string: "https://example.atlassian.net/wiki/spaces/X/pages/42")),
      "Before\n\n![shot 1.png](https://example.atlassian.net/wiki/download/attachments/42/shot%201.png)")
check("media without a source keeps the file name",
      HTMLToMarkdown.convert(media, sourceURL: nil),
      "Before\n\n![shot 1.png](shot%201.png)")

// Jira names the page in data-collection, and attribute values are entity-encoded
let jira = "<div data-node-type='media' data-collection='contentId-7' data-file-name='a&amp;b.png'></div>"
check("Jira media reads the page from data-collection",
      HTMLToMarkdown.convert(jira, sourceURL: URL(string: "https://jira.example.com:8443/browse/X-1")),
      "![a&b.png](https://jira.example.com:8443/download/attachments/7/a&b.png)")

let external = "<div data-node-type=\"media\" data-type=\"external\" data-url=\"https://img.example.com/x.png\" data-alt=\"Logo\"></div>"
check("external media uses its URL",
      HTMLToMarkdown.convert(external, sourceURL: nil),
      "![Logo](https://img.example.com/x.png)")

check("HTML without media is unchanged",
      HTMLToMarkdown.convert("<p><b>Bold</b> text</p>", sourceURL: nil),
      HTMLToMarkdown.convert("<p><b>Bold</b> text</p>") ?? "nil")

print(failures == 0 ? "PASTE: all checks passed" : "PASTE: \(failures) failed")
exit(failures == 0 ? 0 : 1)
