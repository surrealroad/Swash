// Checks for Swash/FolderIndex.swift. Run via scripts/run_folder_index_tests.sh.
import Foundation

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    let extra = ok ? "" : detail()
    print("\(ok ? "PASS" : "FAIL") \(name)\(extra.isEmpty ? "" : " — \(extra)")")
    if !ok { failures += 1 }
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/folder-index/fixture")
    .absoluteURL.standardizedFileURL
try? fm.removeItem(at: root)

func write(_ path: String, _ text: String = "") {
    let url = root.appendingPathComponent(path)
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.write(to: url, atomically: true, encoding: .utf8)
}

write("Readme.md", "# Readme\nSee [Plan](Projects/Plan.md#goals) and [[Ideas]].\n")
write("ideas.markdown", "Café ideas\n")
write("notes.txt", "not markdown\n")
write("Projects/Plan.md", "# Plan\n\n    indented Goals here\nsecond goal line\n")
write("Projects/Old/Archive.md", "archived\n")
write("Projects/Empty/picture.png")
write("Projects/My Note.md", "spaces\n")
write(".git/HEAD.md", "hidden\n")
write(".hidden/Secret.md", "hidden\n")
write("node_modules/pkg/README.md", "dependency\n")
write("Deep/1/2/3/Deep.md", "deep\n")

// MARK: Scanning

let scan = FolderScanner.scan(root)
let names = scan.nodes.map(\.displayName)
check("folders come first, then files in Finder order", names == ["Deep", "Projects", "ideas", "Readme"], "\(names)")
check("only Markdown files are listed", !scan.files.contains { $0.pathExtension == "txt" })
check("hidden folders, .git and node_modules are skipped",
      !scan.files.contains { $0.path.contains("/.git/") || $0.path.contains("/.hidden/") || $0.path.contains("node_modules") })
let projects = scan.nodes.first { $0.displayName == "Projects" }
check("folders without Markdown files are left out", projects?.children.map(\.displayName) == ["Old", "My Note", "Plan"],
      "\(projects?.children.map(\.displayName) ?? [])")
check("every Markdown file is in the flat list", scan.files.count == 6, "\(scan.files.count)")
check("a full scan isn't truncated", !scan.isTruncated)

let shallow = FolderScanner.scan(root, maximumDepth: 2)
check("the depth limit stops deep folders", !shallow.files.contains { $0.lastPathComponent == "Deep.md" } && shallow.isTruncated)
let few = FolderScanner.scan(root, maximumFiles: 2)
check("the file limit caps the scan", few.files.count == 2 && few.isTruncated, "\(few.files.count)")
let cancelled = FolderScanner.scan(root, isCancelled: { true })
check("a cancelled scan stops", cancelled.files.isEmpty && cancelled.isTruncated)

// MARK: Filtering

let planOnly = FolderScanner.filter(scan.nodes, query: "plan")
check("filtering keeps matching files and their folders",
      planOnly.count == 1 && planOnly[0].displayName == "Projects" && planOnly[0].children.map(\.displayName) == ["Plan"],
      "\(planOnly.map(\.displayName))")
check("filtering ignores case and accents", FolderScanner.filter(scan.nodes, query: "IDÉAS").map(\.displayName) == ["ideas"])
check("a folder whose name matches keeps its contents",
      FolderScanner.filter(scan.nodes, query: "projects").first?.children.count == 3)
check("an empty filter keeps everything", FolderScanner.filter(scan.nodes, query: "  ") == scan.nodes)
check("no match gives an empty tree", FolderScanner.filter(scan.nodes, query: "zzz").isEmpty)
check("folder URLs are collected for expanding", FolderScanner.folderURLs(in: scan.nodes).count == 6,
      "\(FolderScanner.folderURLs(in: scan.nodes).count)")

// MARK: Paths, renaming

let plan = root.appendingPathComponent("Projects/Plan.md")
check("relative path below the root", FolderScanner.relativePath(of: plan, in: root) == "Projects/Plan.md")
check("relocating a renamed file",
      FolderScanner.relocate(plan, from: plan, to: root.appendingPathComponent("Projects/Roadmap.md"))?.lastPathComponent == "Roadmap.md")
check("relocating a file inside a renamed folder",
      FolderScanner.relocate(plan, from: root.appendingPathComponent("Projects"), to: root.appendingPathComponent("Work"))?.path
        == root.appendingPathComponent("Work/Plan.md").path)
check("relocating an unrelated file gives nil",
      FolderScanner.relocate(plan, from: root.appendingPathComponent("Project"), to: root.appendingPathComponent("Work")) == nil)
check("rename keeps the Markdown extension", FolderScanner.renamedFileName(for: plan, to: "Roadmap", isFolder: false) == "Roadmap.md")
check("rename accepts a typed extension", FolderScanner.renamedFileName(for: plan, to: "Roadmap.markdown", isFolder: false) == "Roadmap.markdown")
check("folders are renamed as typed", FolderScanner.renamedFileName(for: root, to: "v1.2", isFolder: true) == "v1.2")
check("names with slashes are refused", FolderScanner.renameProblem("a/b") != nil)
check("empty and hidden names are refused", FolderScanner.renameProblem(" ") != nil && FolderScanner.renameProblem(".x") != nil)
check("ordinary names are accepted", FolderScanner.renameProblem("Roadmap 2") == nil)

// MARK: Full-text search

let readmeURL = root.appendingPathComponent("Readme.md")

let sample = "First line\n  Second GOAL here\nno match\ngoal and goal\n"
let found = FolderSearch.matches(of: "goal", in: sample, file: plan)
check("search finds every occurrence, ignoring case", found.count == 3, "\(found.count)")
check("matches carry one-based line numbers", found.map(\.line) == [2, 4, 4], "\(found.map(\.line))")
check("the match range is in the file's text", (sample as NSString).substring(with: found[0].range) == "GOAL")
check("snippets are the trimmed line", found[0].snippet == "Second GOAL here", found[0].snippet)
check("the snippet range points at the match", (found[0].snippet as NSString).substring(with: found[0].snippetRange) == "GOAL")
check("accents are ignored", FolderSearch.matches(of: "cafe", in: "Un café noir", file: plan).count == 1)
check("an empty query finds nothing", FolderSearch.matches(of: " ", in: sample, file: plan).isEmpty)
check("the per-file limit applies", FolderSearch.matches(of: "goal", in: sample, file: plan, limit: 1).count == 1)

let long = String(repeating: "word ", count: 60) + "needle" + String(repeating: " tail", count: 60)
let longMatch = FolderSearch.matches(of: "needle", in: long, file: plan)[0]
check("long lines are shortened around the match",
      longMatch.snippet.hasPrefix("…") && longMatch.snippet.hasSuffix("…") && longMatch.snippet.count < 140, longMatch.snippet)
check("the shortened snippet still points at the match", (longMatch.snippet as NSString).substring(with: longMatch.snippetRange) == "needle")
let emoji = "😀😀 find me"
let emojiMatch = FolderSearch.matches(of: "find", in: emoji, file: plan)[0]
check("ranges are UTF-16 offsets", emojiMatch.range.location == 5, "\(emojiMatch.range)")

let everywhere = FolderSearch.search("goal", in: scan.files)
check("searching the folder reads files from disk", everywhere.count == 3 && Set(everywhere.map(\.file)) == [readmeURL, plan], "\(everywhere.count)")
let edited = FolderSearch.search("second goal", in: scan.files, texts: [plan: "no longer"])
check("unsaved text is searched instead of the file on disk", edited.isEmpty)
check("the total limit applies", FolderSearch.search("e", in: scan.files, limit: 3).count == 3)

// MARK: Relative links

let readme = root.appendingPathComponent("Readme.md")
check("a relative link resolves", NoteLinkResolver.resolve("Projects/Plan.md", from: readme, root: root) == plan)
check("anchors and queries are ignored", NoteLinkResolver.resolve("Projects/Plan.md#goals", from: readme, root: root) == plan)
check("percent-encoded names resolve",
      NoteLinkResolver.resolve("Projects/My%20Note.md", from: readme, root: root)?.lastPathComponent == "My Note.md")
check("angle-bracket destinations resolve",
      NoteLinkResolver.resolve("<Projects/My Note.md>", from: readme, root: root)?.lastPathComponent == "My Note.md")
check("parent folders resolve", NoteLinkResolver.resolve("../Readme.md", from: plan, root: root) == readme)
check("links from the folder's top resolve", NoteLinkResolver.resolve("/Projects/Plan.md", from: readme, root: root) == plan)
check("a missing extension tries .md", NoteLinkResolver.resolve("Projects/Plan", from: readme, root: root) == plan)
check("file URLs inside the folder resolve", NoteLinkResolver.resolve(plan.absoluteString, from: readme, root: root) == plan)
check("links leaving the folder are refused", NoteLinkResolver.resolve("../../Outside.md", from: plan, root: root, exists: { _ in true }) == nil)
check("web links are not notes", NoteLinkResolver.resolve("https://example.com/a.md", from: readme, root: root, exists: { _ in true }) == nil)
check("mailto links are not notes", NoteLinkResolver.resolve("mailto:a@b.c", from: readme, root: root, exists: { _ in true }) == nil)
check("in-page anchors are not notes", NoteLinkResolver.resolve("#goals", from: readme, root: root) == nil)
check("other file types are not notes", NoteLinkResolver.resolve("notes.txt", from: readme, root: root) == nil)
check("missing files give nil", NoteLinkResolver.resolve("Missing.md", from: readme, root: root) == nil)

// MARK: Wiki links

let wiki = NoteLinkResolver.wikiLinks(in: "See [[Ideas]], [[Projects/Plan|the plan]] and [[Plan#Goals]]. Not [[ ]] or [[a\nb]].")
check("wiki links are found with their targets", wiki.map(\.target) == ["Ideas", "Projects/Plan", "Plan"], "\(wiki.map(\.target))")
check("wiki link ranges cover the brackets", wiki.first?.range == NSRange(location: 4, length: 9), "\(String(describing: wiki.first?.range))")
check("wiki names ignore case and extension",
      NoteLinkResolver.resolveWiki("IDEAS", from: readme, root: root, files: scan.files)?.lastPathComponent == "ideas.markdown")
check("wiki paths resolve", NoteLinkResolver.resolveWiki("Projects/Plan", from: readme, root: root, files: scan.files) == plan)
check("wiki labels and headings are ignored", NoteLinkResolver.resolveWiki("Plan#Goals|x", from: readme, root: root, files: scan.files) == plan)
let twins = [root.appendingPathComponent("A/Deeper/Note.md"), root.appendingPathComponent("B/Note.md"), root.appendingPathComponent("C/Note.md")]
check("a note beside the current file wins",
      NoteLinkResolver.resolveWiki("Note", from: root.appendingPathComponent("C/Other.md"), root: root, files: twins) == twins[2])
check("otherwise the shortest path wins",
      NoteLinkResolver.resolveWiki("Note", from: readme, root: root, files: twins) == twins[1])
check("unknown wiki names give nil", NoteLinkResolver.resolveWiki("Nope", from: readme, root: root, files: scan.files) == nil)

try? fm.removeItem(at: root)
print(failures == 0 ? "FOLDER INDEX: all checks passed" : "FOLDER INDEX: \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
