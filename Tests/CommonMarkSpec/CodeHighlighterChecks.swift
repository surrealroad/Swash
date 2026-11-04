//
//  CodeHighlighterChecks.swift
//  Swash
//
//  Token-boundary checks for `CodeHighlighter` in every language, structural invariants under
//  random input, and linear-time checks on large and pathological code blocks.
//

import Foundation

enum CodeHighlighterChecks {
    /// (language, code, tokens that must exist as "kind:text", tokens that must not exist)
    private static let cases: [(String, String, [String], [String])] = [
        ("js", "const x = `a ${b + 1} c`; // done\nlet re = /ab+c/gi; y = a / b / c;\nfunction go() { return null }",
         ["keyword:const", "string:`a ${", "number:1", "string:} c`", "comment:// done", "regex:/ab+c/gi", "function:go", "literal:null", "keyword:return"],
         ["regex:/ b /", "string:b + 1"]),
        ("javascript", "/* block\n comment */ console.log('it\\'s', \"q\")",
         ["comment:/* block\n comment */", "builtin:console", "function:log", "string:'it\\'s'", "string:\"q\""], []),
        ("ts", "interface Point { x: number }\ntype Id = string\n@Component class A implements B {}",
         ["keyword:interface", "type:Point", "type:number", "keyword:type", "type:Id", "type:string", "meta:@Component", "type:A", "type:B"], []),
        ("swift", "/* outer /* nested */ still */ let s = \"v \\(a + 2) end\"\n@MainActor func run() -> Int { #if DEBUG\n return 0x1F }\nlet raw = #\"a \"quoted\" b\"#",
         ["comment:/* outer /* nested */ still */", "keyword:let", "string:\"v \\(", "number:2", "string:) end\"", "meta:@MainActor", "keyword:func", "function:run", "type:Int", "meta:#if", "number:0x1F", "string:#\"a \"quoted\" b\"#"], []),
        ("swift", "let m = \"\"\"\n  line \"one\"\n  \"\"\"\nprint(m)",
         ["string:\"\"\"\n  line \"one\"\n  \"\"\"", "builtin:print"], []),
        ("py", "@decorator\ndef f(x=1.5e3):\n    '''doc\n    string'''\n    return f\"{x}\" + r'\\d' # note\nclass C: pass\nprint(True, None)",
         ["meta:@decorator", "keyword:def", "function:f", "number:1.5e3", "string:'''doc\n    string'''", "string:f\"{x}\"", "string:r'\\d'", "comment:# note", "keyword:class", "type:C", "builtin:print", "literal:True", "literal:None"], []),
        ("go", "package main\nfunc main() {\n\ts := `raw\nstring`\n\tvar r rune = 'x'\n\tfmt.Println(len(s), nil)\n}",
         ["keyword:package", "keyword:func", "function:main", "string:`raw\nstring`", "type:rune", "string:'x'", "function:Println", "builtin:len", "literal:nil"], []),
        ("rs", "#[derive(Debug)]\nfn longest<'a>(x: &'a str) -> Option<u32> {\n    println!(\"{}\", r#\"raw \"q\"\"#);\n    let c = 'c'; /* a /* b */ c */ Some(1_000u32)\n}",
         ["meta:#[derive(Debug)]", "keyword:fn", "function:longest", "type:'a", "type:str", "builtin:Option", "type:u32", "builtin:println!", "string:\"{}\"", "string:r#\"raw \"q\"\"#", "string:'c'", "comment:/* a /* b */ c */", "builtin:Some", "number:1_000u32"], []),
        ("rb", "# comment\nclass Foo < Bar\n  def greet(name)\n    puts \"Hi #{name.upcase}!\" if @ok\n    :sym\n  end\nend\n=begin\nblock\n=end\nx = /re+/",
         ["comment:# comment", "keyword:class", "type:Foo", "type:Bar", "keyword:def", "function:greet", "builtin:puts", "string:\"Hi #{", "string:}!\"", "variable:@ok", "literal::sym", "keyword:end", "comment:=begin\nblock\n=end", "regex:/re+/"], []),
        ("java", "@Override\npublic static void main(String[] args) { int n = 42; String s = \"x\"; char c = 'c'; }",
         ["meta:@Override", "keyword:public", "type:void", "function:main", "type:String", "type:int", "number:42", "string:\"x\"", "string:'c'"], []),
        ("kotlin", "data class User(val name: String)\nfun greet(u: User) = println(\"Hi ${u.name}\")\nval t = \"\"\"raw $x\"\"\"",
         ["keyword:data", "keyword:class", "type:User", "keyword:val", "keyword:fun", "function:greet", "builtin:println", "string:\"Hi ${", "string:}\"", "string:\"\"\"raw $x\"\"\""], []),
        ("c", "#include <stdio.h>\n/* main */\nint main(void) {\n    size_t n = sizeof(int);\n    printf(\"%zu\\n\", n); // print\n    return 0;\n}",
         ["meta:#include <stdio.h>", "comment:/* main */", "type:int", "function:main", "type:void", "type:size_t", "keyword:sizeof", "builtin:printf", "string:\"%zu\\n\"", "comment:// print", "number:0"], []),
        ("c++", "template <typename T>\nclass Box { std::unique_ptr<T> p = nullptr; };\nauto s = R\"(raw \"x\")\";",
         ["keyword:template", "keyword:typename", "keyword:class", "type:Box", "type:std", "type:unique_ptr", "literal:nullptr", "keyword:auto", "string:R\"(raw \"x\")\""], []),
        ("cs", "#region Main\nnamespace App { public record Person(string Name); var p = @\"C:\\dir\"; var q = $\"Hi {name}\"; }",
         ["meta:#region Main", "keyword:namespace", "type:App", "keyword:public", "keyword:record", "type:Person", "type:string", "string:@\"C:\\dir\"", "string:$\"Hi {name}\""], []),
        ("objc", "@interface Foo : NSObject\n@property NSString *name;\n@end\nNSLog(@\"%@\", YES);",
         ["keyword:@interface", "type:Foo", "type:NSObject", "keyword:@property", "keyword:@end", "string:@\"%@\"", "literal:YES"], []),
        ("php", "<?php\n// c\n# also\nfunction add(int $a): int { return $a + 1; }\necho \"x\";\n?>",
         ["meta:<?php", "comment:// c", "comment:# also", "keyword:function", "function:add", "type:int", "variable:$a", "keyword:return", "keyword:echo", "string:\"x\"", "meta:?>"], []),
        ("scala", "object Main extends App { def sq(x: Int): Int = x * x; val s = \"\"\"multi\nline\"\"\" }",
         ["keyword:object", "type:Main", "type:App", "keyword:def", "function:sq", "type:Int", "keyword:val", "string:\"\"\"multi\nline\"\"\""], []),
        ("dart", "void main() { final name = 'Bob'; print('Hi ${name}!'); }",
         ["type:void", "function:main", "keyword:final", "string:'Bob'", "builtin:print", "string:'Hi ${", "string:}!'"], []),
        ("sql", "-- top\nSELECT u.name, COUNT(*) AS n FROM users u WHERE u.note = 'it''s' AND id = @id /* c */ GROUP BY 1;\ncreate table t (id integer primary key, \"Col\" text);",
         ["comment:-- top", "keyword:SELECT", "builtin:COUNT", "keyword:AS", "keyword:FROM", "keyword:WHERE", "string:'it''s'", "keyword:AND", "variable:@id", "comment:/* c */", "keyword:GROUP", "number:1", "keyword:create", "type:integer", "property:\"Col\"", "type:text"], []),
        ("sh", "#!/bin/bash\n# list\nfor f in *.txt; do\n  echo \"File: $f ${HOME}\" | grep -v x 2>&1\ndone\nNAME=value\ncat <<EOF\nbody $x\nEOF\nls -la",
         ["comment:#!/bin/bash", "comment:# list", "keyword:for", "keyword:in", "keyword:do", "builtin:echo", "string:\"File: ", "variable:$f", "variable:${HOME}", "builtin:grep", "attribute:-v", "number:2", "keyword:done", "variable:NAME", "keyword:<<EOF", "string:body $x", "keyword:EOF", "builtin:ls", "attribute:-la"], ["comment:# list\nfor"]),
        ("zsh", "echo ${#arr} a#b", ["variable:${#arr}"], ["comment:#arr} a#b", "comment:#b"]),
        ("html", "<!DOCTYPE html>\n<!-- note -->\n<div class=\"a\" id=main data-x='1'>Hi &amp; bye</div>\n<script>let x = 1;</script>\n<style>p { color: red; }</style>",
         ["meta:<!DOCTYPE html>", "comment:<!-- note -->", "tag:div", "attribute:class", "string:\"a\"", "attribute:id", "string:main", "attribute:data-x", "string:'1'", "literal:&amp;", "tag:script", "keyword:let", "number:1", "tag:style", "tag:p", "property:color"], []),
        ("xml", "<?xml version=\"1.0\"?>\n<root xmlns:a=\"u\"><a:item>text</a:item><![CDATA[ <raw> ]]></root>",
         ["meta:<?xml version=\"1.0\"?>", "tag:root", "attribute:xmlns:a", "string:\"u\"", "tag:a:item", "string:<![CDATA[ <raw> ]]>"], []),
        ("css", "/* theme */\n@media (max-width: 600px) {\n  .card > a:hover, #main { color: #fff; margin: -4px 1.5em; background: url(x.png) !important; --gap: 2px; }\n}",
         ["comment:/* theme */", "keyword:@media", "number:600px", "type:.card", "tag:a", "keyword::hover", "type:#main", "property:color", "number:#fff", "property:margin", "number:-4px", "number:1.5em", "builtin:url", "string:x.png", "keyword:!important", "variable:--gap", "number:2px"], []),
        ("scss", "$base: 4px;\n.btn { padding: $base * 2; &:hover { opacity: 0.5; } }",
         ["variable:$base", "type:.btn", "property:padding", "number:2", "keyword::hover", "property:opacity", "number:0.5"], []),
        ("json", "{\n  \"name\": \"Swash\", // c\n  \"n\": -1.5e2, \"ok\": true, \"none\": null, \"list\": [1, \"two\"]\n}",
         ["property:\"name\"", "string:\"Swash\"", "comment:// c", "property:\"n\"", "number:1.5e2", "literal:true", "literal:null", "number:1", "string:\"two\""], ["property:\"two\"", "property:\"Swash\""]),
        ("yml", "# config\n---\nname: Swash\nversion: 1.2\nenabled: yes\nquoted: \"a: b\" # trailing\nlist:\n  - one\n  - key: 2\nanchor: &base\n  x: 1\nref: *base\ndesc: |\n  block text\n  more: not a key\nafter: ~",
         ["comment:# config", "meta:---", "property:name", "property:version", "number:1.2", "property:enabled", "literal:yes", "property:quoted", "string:\"a: b\"", "comment:# trailing", "property:list", "property:key", "number:2", "variable:&base", "variable:*base", "property:desc", "keyword:|", "string:block text", "string:more: not a key", "property:after", "literal:~"], ["property:more"]),
        ("toml", "# settings\n[package]\nname = \"swash\" # inline\nversion = 3\nbig = \"\"\"\nmulti\n\"\"\"\n[[bin]]\nenabled = true\ndate = 1979-05-27T07:32:00Z",
         ["comment:# settings", "type:[package]", "property:name", "string:\"swash\"", "comment:# inline", "property:version", "number:3", "string:\"\"\"\nmulti\n\"\"\"", "type:[[bin]]", "literal:true", "number:1979-05-27T07:32:00Z"], []),
        ("ini", "; comment\n[section]\nkey = value", ["comment:; comment", "type:[section]", "property:key"], []),
        ("md", "# Title\n\nSome **bold** and *it* with `code` and [link](https://x.y).\n\n> quote\n- item\n1. first\n- [x] done\n\n```swift\nlet x = 1\n```\n---",
         ["heading:# Title", "emphasis:**bold**", "emphasis:*it*", "string:`code`", "property:[link]", "string:(https://x.y)", "keyword:>", "keyword:-", "keyword:1.", "keyword:[x]", "meta:```swift", "string:let x = 1", "meta:```", "meta:---"], ["emphasis:snake_case_name"]),
        ("md", "a snake_case_name here", [], ["emphasis:_case_"]),
        ("diff", "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n context\n-old\n+new\n\\ No newline at end of file",
         ["heading:diff --git a/x b/x", "heading:--- a/x", "heading:+++ b/x", "meta:@@ -1,2 +1,2 @@", "deleted:-old", "inserted:+new", "comment:\\ No newline at end of file"], []),
    ]

    private static func describe(_ tokens: [CodeToken], _ code: String) -> Set<String> {
        let ns = code as NSString
        return Set(tokens.map { "\($0.kind.rawValue):\(ns.substring(with: $0.range))" })
    }

    /// Tokens must be in order, non-empty, non-overlapping and inside the code.
    private static func structureProblem(_ tokens: [CodeToken], length: Int) -> String? {
        var last = 0
        for token in tokens {
            if token.range.length <= 0 { return "empty token at \(token.range.location)" }
            if token.range.location < last { return "token at \(token.range.location) overlaps or is out of order" }
            if NSMaxRange(token.range) > length { return "token \(token.range) past the end (\(length))" }
            last = NSMaxRange(token.range)
        }
        return nil
    }

    static func run() -> Int {
        var failures = 0
        print("Code highlighter")
        // 1. Token boundaries per language
        var covered = Set<CodeLanguage>()
        for (language, code, expected, absent) in cases {
            guard let lang = CodeLanguage(name: language) else {
                failures += 1; print("  ❌ unknown language \(language)"); continue
            }
            covered.insert(lang)
            let tokens = CodeHighlighter.tokens(for: code, language: language)
            let found = describe(tokens, code)
            let missing = expected.filter { !found.contains($0) }
            let unexpected = absent.filter { found.contains($0) }
            let structure = structureProblem(tokens, length: (code as NSString).length)
            if !missing.isEmpty || !unexpected.isEmpty || structure != nil {
                failures += 1
                print("  ❌ \(language): missing \(missing.map(\.debugDescription)) unexpected \(unexpected.map(\.debugDescription)) \(structure ?? "")")
                print("     got \(found.sorted().map(\.debugDescription))")
            }
        }
        let uncovered = CodeLanguage.allCases.filter { !covered.contains($0) }
        if !uncovered.isEmpty { failures += 1; print("  ❌ languages without boundary checks: \(uncovered)") }

        // 2. Aliases
        let aliases: [(String, CodeLanguage)] = [("JS", .javascript), ("tsx", .typescript), ("py", .python), ("sh", .bash), ("zsh", .bash),
                                                 ("yml", .yaml), ("c++", .cpp), ("cs", .csharp), ("C#", .csharp), ("golang", .go), ("rs", .rust),
                                                 ("kt", .kotlin), ("rb", .ruby), ("md", .markdown), ("patch", .diff), ("svg", .xml), ("scss", .css)]
        for (alias, language) in aliases where CodeLanguage(name: alias) != language {
            failures += 1; print("  ❌ alias \(alias) is not \(language)")
        }
        if CodeLanguage(name: "mermaid") != nil || CodeLanguage(name: "math") != nil || !CodeHighlighter.tokens(for: "graph TD; A-->B", language: "mermaid").isEmpty {
            failures += 1; print("  ❌ mermaid and math must not be highlighted")
        }

        // 3. Line segments map multi-line tokens onto each line
        let segmentCode = "a /* one\ntwo\nthree */ b"
        let segments = CodeHighlighter.lineSegments(CodeHighlighter.tokens(for: segmentCode, language: .c), in: segmentCode as NSString)
        let segmentText = segments.map { "\($0.line):\($0.column):\($0.length)" }
        if segmentText != ["0:2:6", "1:0:3", "2:0:8"] { failures += 1; print("  ❌ line segments \(segmentText)") }

        // 4. Random input keeps the structure valid in every language
        var rng = SplitMix64(seed: 38)
        let alphabet = Array("abcXYZ_09 \t\n\"'`/*#-+<>{}()[]$@!:;=.,\\|&%~^?r".utf16)
        var randomProblems = 0
        for language in CodeLanguage.allCases {
            for _ in 0..<60 {
                let length = Int(rng.next() % 200)
                let units = (0..<length).map { _ in alphabet[Int(rng.next() % UInt64(alphabet.count))] }
                let code = String(decoding: units, as: UTF16.self)
                let tokens = CodeHighlighter.tokens(for: code, language: language)
                if let problem = structureProblem(tokens, length: (code as NSString).length) {
                    randomProblems += 1
                    if randomProblems <= 3 { print("  ❌ random \(language): \(problem) in \(code.debugDescription)") }
                }
            }
        }
        failures += randomProblems

        // 5. Linear time: a large block, and pathological input that would backtrack a regex
        func ms(_ language: CodeLanguage, _ code: String) -> Double {
            let start = Date()
            _ = CodeHighlighter.tokens(for: code, language: language)
            return Date().timeIntervalSince(start) * 1000
        }
        let jsLine = "export async function load(id) { const r = await fetch(`/api/${id}?q=1`); /* c */ return r.ok ? /a+b/.test(s) : \"no\" } // end\n"
        let large = String(repeating: jsLine, count: 10_000)
        let largeMs = ms(.javascript, large)
        let largeOK = largeMs < 400
        if !largeOK { failures += 1 }
        print(String(format: "  %@ large block: %d lines, %.1f MB in %.1f ms", largeOK ? "✓" : "❌", 10_000, Double(large.utf16.count) / 1_000_000, largeMs))

        let pathological: [(String, CodeLanguage, (Int) -> String)] = [
            ("unclosed strings", .javascript, { String(repeating: "\"a ", count: $0) }),
            ("unclosed block comment", .c, { "/*" + String(repeating: "x ", count: $0) }),
            ("slashes", .javascript, { String(repeating: "(/ ", count: $0) }),
            ("interpolation", .javascript, { String(repeating: "`${", count: $0) }),
            ("swift interpolation", .swift, { String(repeating: "\"\\(", count: $0) }),
            ("nested comments", .rust, { String(repeating: "/*", count: $0) }),
            ("markdown brackets", .markdown, { String(repeating: "[a *b _c `d ", count: $0) }),
            ("css lookahead", .css, { "a {" + String(repeating: "b: c; ", count: $0) + "}" }),
            ("yaml colons", .yaml, { String(repeating: "a:b:c ", count: $0) }),
            ("html attributes", .html, { "<a " + String(repeating: "b='c' ", count: $0) }),
            ("shell variables", .bash, { String(repeating: "\"$a ${b", count: $0) }),
            ("toml keys", .toml, { String(repeating: "a = \"b\"\n", count: $0) }),
        ]
        for (name, language, make) in pathological {
            let small = ms(language, make(5_000))
            let big = ms(language, make(20_000))
            let ratio = big / max(small, 0.01)
            let ok = big < 5 || ratio < 8
            if !ok { failures += 1 }
            print(String(format: "  %@ growth %-24@ 5k %6.1f ms  20k %6.1f ms  ×%.1f", ok ? "✓" : "❌", name as NSString, small, big, ratio))
        }
        print("  \(cases.count) boundary cases, \(CodeLanguage.allCases.count) languages: \(failures == 0 ? "all passed" : "\(failures) failures")")
        return failures
    }
}
