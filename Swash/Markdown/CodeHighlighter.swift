//
//  CodeHighlighter.swift
//  Swash
//
//  A small, dependency-free syntax tokenizer for fenced code blocks, shared by Edit Text, the
//  Preview, Quick Look and export. Each block is tokenized in a single forward scan over its UTF-16
//  code units: no regular expressions, no backtracking. Lookahead is bounded or consumed, so time is
//  linear in the length of the block.
//
//  Foundation only: colours live in `CodeHighlightTheme` (AppKit) and in `swash-export.css`.
//

import Foundation

/// What a run of code is, for colouring.
enum CodeTokenKind: String, CaseIterable, Hashable {
    case keyword, literal, type, builtin, function, string, regex, number, comment, meta
    case tag, attribute, property, variable, heading, emphasis, inserted, deleted
}

/// A coloured run, in UTF-16 offsets into the code that was tokenized.
struct CodeToken: Equatable, Hashable {
    let range: NSRange
    let kind: CodeTokenKind
}

/// The languages the tokenizer knows, in the order the language pickers list them.
enum CodeLanguage: String, CaseIterable, Hashable {
    case javascript, typescript, python, swift, go, rust, ruby, java, kotlin, c, cpp, csharp, objectivec
    case php, scala, dart, sql, bash, html, xml, css, json, yaml, toml, markdown, diff

    /// The language for a fence info word (`js`, `py`, `c++`, …), or nil when it isn't known.
    init?(name: String?) {
        guard let raw = name?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        if let language = CodeLanguage(rawValue: raw) { self = language; return }
        guard let language = CodeLanguage.aliases[raw] else { return nil }
        self = language
    }

    var displayName: String {
        switch self {
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .python: return "Python"
        case .swift: return "Swift"
        case .go: return "Go"
        case .rust: return "Rust"
        case .ruby: return "Ruby"
        case .java: return "Java"
        case .kotlin: return "Kotlin"
        case .c: return "C"
        case .cpp: return "C++"
        case .csharp: return "C#"
        case .objectivec: return "Objective-C"
        case .php: return "PHP"
        case .scala: return "Scala"
        case .dart: return "Dart"
        case .sql: return "SQL"
        case .bash: return "Bash"
        case .html: return "HTML"
        case .xml: return "XML"
        case .css: return "CSS"
        case .json: return "JSON"
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .markdown: return "Markdown"
        case .diff: return "Diff"
        }
    }

    /// A short label for the bubble menu's language button.
    var shortLabel: String {
        switch self {
        case .javascript: return "JS"
        case .typescript: return "TS"
        case .objectivec: return "ObjC"
        case .markdown: return "MD"
        default: return displayName
        }
    }

    static let aliases: [String: CodeLanguage] = [
        "js": .javascript, "jsx": .javascript, "mjs": .javascript, "cjs": .javascript, "node": .javascript, "ecmascript": .javascript,
        "ts": .typescript, "tsx": .typescript, "mts": .typescript, "cts": .typescript,
        "py": .python, "py3": .python, "python3": .python, "gyp": .python, "pyi": .python,
        "golang": .go,
        "rs": .rust,
        "rb": .ruby, "gemspec": .ruby, "podfile": .ruby, "rake": .ruby,
        "kt": .kotlin, "kts": .kotlin,
        "h": .c,
        "c++": .cpp, "cc": .cpp, "cxx": .cpp, "hpp": .cpp, "hh": .cpp, "hxx": .cpp, "h++": .cpp,
        "cs": .csharp, "c#": .csharp,
        "objc": .objectivec, "objective-c": .objectivec, "obj-c": .objectivec, "mm": .objectivec,
        "sc": .scala,
        "mysql": .sql, "postgres": .sql, "postgresql": .sql, "psql": .sql, "pgsql": .sql, "plsql": .sql, "sqlite": .sql, "tsql": .sql,
        "sh": .bash, "shell": .bash, "zsh": .bash, "ksh": .bash, "console": .bash, "shellscript": .bash, "shell-session": .bash, "fish": .bash,
        "htm": .html, "xhtml": .html, "vue": .html, "svelte": .html,
        "svg": .xml, "plist": .xml, "xsl": .xml, "xslt": .xml, "rss": .xml, "atom": .xml, "xaml": .xml, "csproj": .xml,
        "scss": .css, "sass": .css, "less": .css,
        "jsonc": .json, "json5": .json, "geojson": .json, "webmanifest": .json,
        "yml": .yaml,
        "ini": .toml, "cfg": .toml, "conf": .toml, "editorconfig": .toml, "properties": .toml,
        "md": .markdown, "mdx": .markdown, "mkd": .markdown, "gfm": .markdown,
        "patch": .diff, "udiff": .diff,
    ]
}

enum CodeHighlighter {
    /// Tokens for `code` in the language named by a fence info word; empty for unknown languages.
    static func tokens(for code: String, language: String?) -> [CodeToken] {
        guard let language = CodeLanguage(name: language) else { return [] }
        return tokens(for: code, language: language)
    }

    /// Tokens in increasing, non-overlapping order.
    static func tokens(for code: String, language: CodeLanguage) -> [CodeToken] {
        var tokenizer = Tokenizer(Array(code.utf16))
        tokenizer.run(language, 0, tokenizer.s.count)
        return tokenizer.out
    }

    /// Tokens split at line breaks, as (line index, column, length, kind) in UTF-16 units, for
    /// callers that place each line of the code somewhere else (the editor's raw Markdown lines).
    static func lineSegments(_ tokens: [CodeToken], in code: NSString) -> [(line: Int, column: Int, length: Int, kind: CodeTokenKind)] {
        var lineStarts = [0]
        let length = code.length
        for i in 0..<length where code.character(at: i) == 0x0A { lineStarts.append(i + 1) }
        var out: [(line: Int, column: Int, length: Int, kind: CodeTokenKind)] = []
        out.reserveCapacity(tokens.count)
        var line = 0
        for token in tokens {
            var start = token.range.location
            let end = NSMaxRange(token.range)
            while line + 1 < lineStarts.count && lineStarts[line + 1] <= start { line += 1 }
            while start < end {
                let lineEnd = line + 1 < lineStarts.count ? lineStarts[line + 1] - 1 : length
                let pieceEnd = min(end, lineEnd)
                if pieceEnd > start { out.append((line, start - lineStarts[line], pieceEnd - start, token.kind)) }
                guard end > lineEnd, line + 1 < lineStarts.count else { break }
                line += 1
                start = lineStarts[line]
            }
        }
        return out
    }
}

// MARK: - Character helpers

@inline(__always) private func A(_ c: Unicode.Scalar) -> UInt16 { UInt16(truncatingIfNeeded: c.value) }
private let NL = A("\n"), CR = A("\r"), SP = A(" "), TAB = A("\t"), BS = A("\\")
private let DQ = A("\""), SQ = A("'"), BT = A("`")

@inline(__always) private func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
@inline(__always) private func isUpper(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }
@inline(__always) private func isLetter(_ c: UInt16) -> Bool { (c | 0x20) >= 97 && (c | 0x20) <= 122 }
@inline(__always) private func isHex(_ c: UInt16) -> Bool { isDigit(c) || ((c | 0x20) >= 97 && (c | 0x20) <= 102) }
@inline(__always) private func isIdentStart(_ c: UInt16) -> Bool { isLetter(c) || c == 95 || c >= 0x80 }
@inline(__always) private func isIdentChar(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }
@inline(__always) private func isBlank(_ c: UInt16) -> Bool { c == SP || c == TAB }
@inline(__always) private func isSpace(_ c: UInt16) -> Bool { c == SP || c == TAB || c == NL || c == CR || c == 0x0C }

private func units(_ s: String) -> [UInt16] { Array(s.utf16) }
private func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }

// MARK: - Language rules for the C-family scanner

/// How a quoted string behaves.
private struct Quote {
    var escapes = true
    var multiline = false
    /// A doubled closing quote is a literal quote (SQL `''`, C# verbatim `""`).
    var doubled = false
    var kind: CodeTokenKind = .string
    /// Embedded code (`${…}`, `\(…)`, `#{…}`): the opener, and the brackets counted to find its end.
    var interpolation: (open: [UInt16], openChar: UInt16, closeChar: UInt16)? = nil
}

/// Rules for languages with C-like lexical structure (and Python, Ruby, PHP, SQL and JSON, which
/// differ only in the details).
private struct CLikeRules {
    var lineComments: [[UInt16]] = [units("//")]
    var blockComment: (open: [UInt16], close: [UInt16])? = (units("/*"), units("*/"))
    var nestedComments = false
    /// Ruby's `=begin`/`=end` only count at the start of a line.
    var blockCommentAtLineStart = false
    var keywords: Set<String> = []
    var literals: Set<String> = []
    var types: Set<String> = []
    var builtins: Set<String> = []
    var caseInsensitive = false
    /// The word after one of these is a function or type name.
    var functionDefiners: Set<String> = []
    var typeDefiners: Set<String> = []
    var capitalizedTypes = true
    var callsAreFunctions = true
    var doubleQuote: Quote? = Quote()
    var singleQuote: Quote? = Quote()
    var backtick: Quote? = nil
    /// `"""` / `'''` strings (Python, Swift, Kotlin, Scala, Dart).
    var tripleQuote: Quote? = nil
    /// Words that prefix a string (`r"…"`, `f'…'`, `b"…"`); a prefix containing `r` disables escapes.
    var stringPrefixes: Set<String> = []
    var rustCharsAndLifetimes = false
    var rustRawStrings = false
    var rustAttributes = false
    var macroBang = false
    var swiftRawStrings = false
    var hashDirectives = false
    var cppRawStrings = false
    var csharpStrings = false
    var preprocessor = false
    var annotations = false
    var atKeywords = false
    var dollarVariables = false
    var sigilVariables = false
    var sqlVariables = false
    var regexLiterals = false
    var rubySymbols = false
    var phpTags = false
    var jsonKeys = false
    var maxWord = 0

    mutating func finish() {
        maxWord = (keywords.union(literals).union(types).union(builtins).union(stringPrefixes)).map { $0.utf16.count }.max() ?? 0
        if caseInsensitive {
            keywords = Set(keywords.map { $0.lowercased() }); literals = Set(literals.map { $0.lowercased() })
            types = Set(types.map { $0.lowercased() }); builtins = Set(builtins.map { $0.lowercased() })
        }
    }

    static let regexKeywords: Set<String> = words("return typeof instanceof in of new delete void throw case do else yield await when unless if and or not")

    static func make(_ language: CodeLanguage) -> CLikeRules? {
        var r = CLikeRules()
        let cKeywords = "auto break case const continue default do else enum extern for goto if inline register restrict return signed sizeof static struct switch typedef union unsigned volatile while _Alignas _Alignof _Atomic _Bool _Complex _Generic _Noreturn _Static_assert _Thread_local"
        let cTypes = "char double float int long short void bool size_t ssize_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t intptr_t uintptr_t ptrdiff_t wchar_t FILE va_list"
        let cBuiltins = "printf fprintf sprintf snprintf scanf malloc calloc realloc free memcpy memmove memset memcmp strlen strcmp strncmp strcpy strncpy strcat fopen fclose fread fwrite puts putchar getchar exit abort assert"
        let jsKeywords = "break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new of return super switch this throw try typeof var void while with yield async await static get set from as"
        let jsBuiltins = "console window document globalThis require module exports process parseInt parseFloat isNaN isFinite setTimeout setInterval clearTimeout clearInterval fetch alert structuredClone queueMicrotask"
        switch language {
        case .javascript, .typescript:
            r.keywords = words(jsKeywords)
            r.literals = words("true false null undefined NaN Infinity")
            r.builtins = words(jsBuiltins)
            r.functionDefiners = ["function"]
            r.typeDefiners = ["class", "extends", "new"]
            r.backtick = Quote(escapes: true, multiline: true, interpolation: (units("${"), A("{"), A("}")))
            r.regexLiterals = true
            r.annotations = true
            if language == .typescript {
                r.keywords.formUnion(words("interface type enum implements declare namespace abstract readonly keyof private protected public satisfies infer is asserts override unique module accessor"))
                r.types = words("string number boolean any unknown never object symbol bigint")
                r.typeDefiners.formUnion(["interface", "type", "enum", "implements", "namespace"])
            }
        case .swift:
            r.keywords = words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as is try throws await async actor some any self Self super nonisolated isolated mutating nonmutating override required convenience final lazy weak unowned dynamic indirect get set willSet didSet consume borrowing consuming package macro each")
            r.literals = words("true false nil")
            r.builtins = words("print debugPrint fatalError precondition preconditionFailure assert assertionFailure min max abs zip stride type withAnimation")
            r.functionDefiners = ["func"]
            r.typeDefiners = words("class struct enum protocol extension typealias actor associatedtype")
            r.nestedComments = true
            r.singleQuote = nil
            r.tripleQuote = Quote(escapes: true, multiline: true, interpolation: (units("\\("), A("("), A(")")))
            r.doubleQuote = Quote(escapes: true, multiline: false, interpolation: (units("\\("), A("("), A(")")))
            r.swiftRawStrings = true
            r.hashDirectives = true
            r.annotations = true
        case .python:
            r.lineComments = [units("#")]
            r.blockComment = nil
            r.keywords = words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case")
            r.literals = words("True False None")
            r.builtins = words("print len range int str float list dict set tuple bool bytes open super isinstance issubclass enumerate zip map filter sorted reversed sum min max abs any all iter next type object self cls repr hasattr getattr setattr delattr input format id hash vars dir callable staticmethod classmethod property round divmod pow ord chr hex bin oct frozenset bytearray memoryview slice globals locals exec eval compile breakpoint")
            r.functionDefiners = ["def"]
            r.typeDefiners = ["class"]
            r.tripleQuote = Quote(escapes: true, multiline: true)
            r.stringPrefixes = words("r u b f rb br fr rf R U B F Rb bR Br BR Fr fR FR RF rB Rf")
            r.annotations = true
        case .go:
            r.keywords = words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var")
            r.types = words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable")
            r.builtins = words("append cap clear close complex copy delete imag len make max min new panic print println real recover")
            r.literals = words("true false nil iota")
            r.functionDefiners = ["func"]
            r.typeDefiners = ["type"]
            r.backtick = Quote(escapes: false, multiline: true)
            r.capitalizedTypes = false
        case .rust:
            r.keywords = words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while union macro_rules yield")
            r.types = words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str")
            r.literals = words("true false")
            r.builtins = words("Some None Ok Err Box Vec String Option Result drop")
            r.functionDefiners = ["fn"]
            r.typeDefiners = words("struct enum trait type union impl")
            r.nestedComments = true
            r.doubleQuote = Quote(escapes: true, multiline: true)
            r.singleQuote = nil
            r.rustCharsAndLifetimes = true
            r.rustRawStrings = true
            r.rustAttributes = true
            r.macroBang = true
            r.stringPrefixes = ["b", "r", "br", "c", "cr"]
        case .ruby:
            r.lineComments = [units("#")]
            r.blockComment = (units("=begin"), units("=end"))
            r.blockCommentAtLineStart = true
            r.keywords = words("BEGIN END alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield __method__ private protected public")
            r.literals = words("true false nil")
            r.builtins = words("puts print p pp require require_relative include extend prepend attr_accessor attr_reader attr_writer raise lambda proc loop catch throw format sprintf gets")
            r.functionDefiners = ["def"]
            r.typeDefiners = ["class", "module"]
            r.doubleQuote = Quote(escapes: true, multiline: true, interpolation: (units("#{"), A("{"), A("}")))
            r.singleQuote = Quote(escapes: true, multiline: true)
            r.backtick = Quote(escapes: true, multiline: true, interpolation: (units("#{"), A("{"), A("}")))
            r.sigilVariables = true
            r.regexLiterals = true
            r.rubySymbols = true
        case .java, .kotlin, .scala, .dart:
            r.annotations = true
            r.literals = words("true false null")
            switch language {
            case .java:
                r.keywords = words("abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while var record sealed permits yield")
                r.types = words("boolean byte char double float int long short void")
                r.typeDefiners = words("class interface enum record extends implements new")
                r.tripleQuote = Quote(escapes: true, multiline: true)
            case .kotlin:
                r.keywords = words("as break class continue do else for fun if in interface is object package return super this throw try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam where actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg value")
                r.builtins = words("println print listOf mapOf setOf mutableListOf mutableMapOf mutableSetOf arrayOf emptyList lazy require check error repeat run let apply also with takeIf")
                r.functionDefiners = ["fun"]
                r.typeDefiners = words("class interface object typealias")
                r.doubleQuote = Quote(escapes: true, multiline: false, interpolation: (units("${"), A("{"), A("}")))
                r.tripleQuote = Quote(escapes: false, multiline: true, interpolation: (units("${"), A("{"), A("}")))
            case .scala:
                r.keywords = words("abstract case catch class def do else extends final finally for forSome if implicit import lazy match new object override package private protected return sealed super this throw trait try type val var while with yield given using enum then export extension end")
                r.builtins = words("println print require assert Some None List Map Set Seq Vector Option")
                r.functionDefiners = ["def"]
                r.typeDefiners = words("class trait object type extends with new")
                r.tripleQuote = Quote(escapes: false, multiline: true)
            default:
                r.keywords = words("abstract as assert async await base break case catch class const continue covariant default deferred do else enum export extends extension external factory final finally for get hide if implements import in interface is late library mixin new of on operator part required rethrow return sealed set show static super switch sync this throw try typedef var when while with yield")
                r.types = words("int double num bool dynamic void")
                r.builtins = words("print")
                r.typeDefiners = words("class mixin enum extends implements with typedef new")
                r.doubleQuote = Quote(escapes: true, multiline: false, interpolation: (units("${"), A("{"), A("}")))
                r.singleQuote = Quote(escapes: true, multiline: false, interpolation: (units("${"), A("{"), A("}")))
                r.tripleQuote = Quote(escapes: true, multiline: true, interpolation: (units("${"), A("{"), A("}")))
                r.stringPrefixes = ["r"]
            }
        case .c, .cpp, .objectivec:
            r.keywords = words(cKeywords)
            r.types = words(cTypes)
            r.builtins = words(cBuiltins)
            r.literals = words("NULL true false")
            r.typeDefiners = words("struct enum union")
            r.preprocessor = true
            r.capitalizedTypes = false
            r.stringPrefixes = ["L", "u", "U", "u8"]
            if language == .cpp {
                r.keywords.formUnion(words("alignas alignof and and_eq asm catch class concept consteval constexpr constinit const_cast co_await co_return co_yield decltype delete dynamic_cast explicit export friend mutable namespace new noexcept not not_eq operator or or_eq private protected public reinterpret_cast requires static_assert static_cast template this thread_local throw try typeid typename using virtual xor override final"))
                r.types.formUnion(words("char8_t char16_t char32_t string string_view vector array map unordered_map set unordered_set pair tuple optional variant unique_ptr shared_ptr weak_ptr std"))
                r.builtins.formUnion(words("cout cin cerr endl make_unique make_shared move forward swap"))
                r.literals.insert("nullptr")
                r.typeDefiners.formUnion(["class", "namespace", "concept", "typename"])
                r.cppRawStrings = true
                r.capitalizedTypes = true
            } else if language == .objectivec {
                r.types.formUnion(words("id instancetype BOOL SEL Class IMP NSInteger NSUInteger CGFloat"))
                r.literals.formUnion(words("YES NO nil Nil self super"))
                r.atKeywords = true
                r.capitalizedTypes = true
            }
        case .csharp:
            r.keywords = words("abstract as base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected public readonly ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using virtual volatile while add alias async await by descending dynamic equals from get global group init into join let nameof on orderby partial record remove required select set value var when where with yield file scoped")
            r.types = words("bool byte char decimal double float int long object sbyte short string uint ulong ushort void nint nuint")
            r.literals = words("true false null")
            r.typeDefiners = words("class struct interface enum record namespace new")
            r.preprocessor = true
            r.csharpStrings = true
            r.tripleQuote = Quote(escapes: false, multiline: true)
        case .php:
            r.lineComments = [units("//"), units("#")]
            r.keywords = words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield")
            r.literals = words("true false null")
            r.types = words("int float string bool object mixed void never iterable self parent")
            r.builtins = words("count strlen str_replace explode implode array_map array_filter array_keys array_values in_array isset json_encode json_decode var_dump print_r sprintf printf die exit")
            r.caseInsensitive = true
            r.functionDefiners = ["function", "fn"]
            r.typeDefiners = words("class interface trait enum extends implements new")
            r.doubleQuote = Quote(escapes: true, multiline: true)
            r.singleQuote = Quote(escapes: true, multiline: true)
            r.dollarVariables = true
            r.phpTags = true
            r.annotations = false
        case .sql:
            r.lineComments = [units("--")]
            r.keywords = words("select from where and or not insert into values update set delete create alter drop table view index trigger procedure function database schema if exists primary key foreign references unique default check constraint join inner left right full outer cross on as group by order having limit offset union all distinct case when then else end is like ilike in between asc desc with recursive returning begin commit rollback transaction grant revoke declare cascade natural using except intersect over partition window replace truncate exec execute return returns language add column rename to fetch next rows only top")
            r.literals = words("true false null")
            r.types = words("int integer bigint smallint tinyint decimal numeric float real double precision char varchar nvarchar text date time timestamp timestamptz datetime boolean bool blob bytea serial bigserial uuid json jsonb interval money")
            r.builtins = words("count sum avg min max coalesce nullif cast now concat substring lower upper length trim round abs date_trunc row_number rank dense_rank extract current_date current_timestamp ifnull isnull greatest least string_agg array_agg")
            r.caseInsensitive = true
            r.capitalizedTypes = false
            r.singleQuote = Quote(escapes: false, multiline: true, doubled: true)
            r.doubleQuote = Quote(escapes: false, multiline: false, doubled: true, kind: .property)
            r.backtick = Quote(escapes: false, multiline: false, kind: .property)
            r.sqlVariables = true
        case .json:
            r.literals = words("true false null")
            r.capitalizedTypes = false
            r.callsAreFunctions = false
            r.singleQuote = nil
            r.jsonKeys = true
        default:
            return nil
        }
        r.finish()
        return r
    }
}

// MARK: - Tokenizer

private struct Tokenizer {
    let s: [UInt16]
    var out: [CodeToken] = []
    /// Interpolation and embedded-language nesting, capped so hostile input can't recurse deeply.
    var depth = 0
    private static let rules: [CodeLanguage: CLikeRules] = {
        var table: [CodeLanguage: CLikeRules] = [:]
        for language in CodeLanguage.allCases { table[language] = CLikeRules.make(language) }
        return table
    }()

    init(_ s: [UInt16]) {
        self.s = s
        out.reserveCapacity(s.count / 6)
    }

    @inline(__always) mutating func add(_ a: Int, _ b: Int, _ kind: CodeTokenKind) {
        guard b > a else { return }
        if let last = out.last, last.kind == kind, NSMaxRange(last.range) == a {
            out[out.count - 1] = CodeToken(range: NSRange(location: last.range.location, length: b - last.range.location), kind: kind)
        } else {
            out.append(CodeToken(range: NSRange(location: a, length: b - a), kind: kind))
        }
    }

    @inline(__always) func matches(_ pattern: [UInt16], at i: Int, _ hi: Int) -> Bool {
        guard i + pattern.count <= hi else { return false }
        for k in 0..<pattern.count where s[i + k] != pattern[k] { return false }
        return true
    }

    /// Case-insensitive ASCII match.
    func matchesFolded(_ pattern: [UInt16], at i: Int, _ hi: Int) -> Bool {
        guard i + pattern.count <= hi else { return false }
        for k in 0..<pattern.count where (s[i + k] | 0x20) != (pattern[k] | 0x20) { return false }
        return true
    }

    func word(_ a: Int, _ b: Int, folded: Bool = false) -> String {
        let w = String(decoding: s[a..<b], as: UTF16.self)
        return folded ? w.lowercased() : w
    }

    func lineEnd(_ i: Int, _ hi: Int) -> Int {
        var j = i
        while j < hi && s[j] != NL { j += 1 }
        return j
    }

    @inline(__always) func identEnd(_ i: Int, _ hi: Int, extra: UInt16 = 0) -> Int {
        var j = i
        while j < hi && (isIdentChar(s[j]) || (extra != 0 && s[j] == extra)) { j += 1 }
        return j
    }

    /// The end of a number starting at `i`: digits, one fraction, an exponent, and a suffix
    /// (`10f`, `1u32`, `100px`, `2n`).
    func numberEnd(_ i: Int, _ hi: Int) -> Int {
        var j = i
        if s[j] == A("0"), j + 1 < hi, "xXbBoO".utf16.contains(s[j + 1]) {
            j += 2
            while j < hi && (isHex(s[j]) || s[j] == A("_")) { j += 1 }
        } else {
            while j < hi && (isDigit(s[j]) || s[j] == A("_")) { j += 1 }
            if j + 1 < hi && s[j] == A(".") && isDigit(s[j + 1]) {
                j += 1
                while j < hi && (isDigit(s[j]) || s[j] == A("_")) { j += 1 }
            }
            if j < hi && (s[j] | 0x20) == A("e") {
                var k = j + 1
                if k < hi && (s[k] == A("+") || s[k] == A("-")) { k += 1 }
                if k < hi && isDigit(s[k]) {
                    j = k
                    while j < hi && isDigit(s[j]) { j += 1 }
                }
            }
        }
        while j < hi && isIdentChar(s[j]) { j += 1 }
        return j
    }

    mutating func blockComment(_ i: Int, open: [UInt16], close: [UInt16], nested: Bool, _ hi: Int) -> Int {
        var level = 1
        var j = i + open.count
        while j < hi {
            if matches(close, at: j, hi) {
                level -= 1
                j += close.count
                if level == 0 { break }
                continue
            }
            if nested && matches(open, at: j, hi) {
                level += 1
                j += open.count
                continue
            }
            j += 1
        }
        add(i, j, .comment)
        return j
    }

    /// Scans a quoted string whose contents start at `contentStart` (the token starts at `start`)
    /// and returns the index after it. Interpolated code is tokenized with `language`.
    mutating func quoted(_ start: Int, contentStart: Int, close: [UInt16], _ q: Quote, _ hi: Int, language: CodeLanguage) -> Int {
        var i = contentStart
        var pieceStart = start
        while i < hi {
            let c = s[i]
            if let interp = q.interpolation, depth < 6, matches(interp.open, at: i, hi) {
                let inner = i + interp.open.count
                add(pieceStart, inner, q.kind)
                var level = 1
                var j = inner
                while j < hi {
                    let d = s[j]
                    if d == interp.openChar { level += 1 } else if d == interp.closeChar { level -= 1; if level == 0 { break } }
                    else if d == NL && !q.multiline { break }
                    j += 1
                }
                depth += 1
                run(language, inner, j)
                depth -= 1
                if j >= hi || s[j] != interp.closeChar { return j }
                pieceStart = j
                i = j + 1
                continue
            }
            if q.escapes && c == BS {
                i += 2
                continue
            }
            if matches(close, at: i, hi) {
                if q.doubled && matches(close, at: i + close.count, hi) {
                    i += close.count * 2
                    continue
                }
                i += close.count
                add(pieceStart, i, q.kind)
                return i
            }
            if c == NL && !q.multiline {
                add(pieceStart, i, q.kind)
                return i
            }
            i += 1
        }
        add(pieceStart, hi, q.kind)
        return hi
    }

    // MARK: Dispatch

    mutating func run(_ language: CodeLanguage, _ lo: Int, _ hi: Int) {
        guard lo < hi else { return }
        switch language {
        case .html: markup(lo, hi, html: true)
        case .xml: markup(lo, hi, html: false)
        case .css: css(lo, hi)
        case .bash: bash(lo, hi)
        case .yaml: yaml(lo, hi)
        case .toml: toml(lo, hi)
        case .markdown: markdown(lo, hi)
        case .diff: diff(lo, hi)
        default:
            if let rules = Tokenizer.rules[language] { clike(rules, language, lo, hi) }
        }
    }

    // MARK: C family (and Python, Ruby, PHP, SQL, JSON)

    mutating func clike(_ r: CLikeRules, _ language: CodeLanguage, _ lo: Int, _ hi: Int) {
        var i = lo
        var atLineStart = true
        var previous: UInt16 = 0            // last significant character
        var previousWord: String? = nil     // last keyword, for regex detection
        var pending: CodeTokenKind? = nil   // name expected after `func`, `class`, …

        func regexAllowed() -> Bool {
            if let w = previousWord { return CLikeRules.regexKeywords.contains(w) }
            return previous == 0 || "(,=:[!&|?{};+-*%<>~^".utf16.contains(previous)
        }

        while i < hi {
            let c = s[i]
            if c == NL { atLineStart = true; i += 1; continue }
            if isSpace(c) { i += 1; continue }
            let lineStart = atLineStart
            atLineStart = false

            // Comments
            var isComment = false
            for marker in r.lineComments where matches(marker, at: i, hi) {
                let e = lineEnd(i, hi)
                add(i, e, .comment)
                i = e
                isComment = true
                break
            }
            if isComment { continue }
            if let bc = r.blockComment, (!r.blockCommentAtLineStart || lineStart), matches(bc.open, at: i, hi) {
                i = blockComment(i, open: bc.open, close: bc.close, nested: r.nestedComments, hi)
                continue
            }

            // Preprocessor lines and directives
            if c == A("#") {
                if r.preprocessor && lineStart {
                    var j = i
                    while j < hi && s[j] != NL {
                        if s[j] == BS && j + 1 < hi && s[j + 1] == NL { j += 2; continue }
                        if s[j] == A("/") && j + 1 < hi && (s[j + 1] == A("/") || s[j + 1] == A("*")) { break }
                        j += 1
                    }
                    add(i, j, .meta)
                    i = j
                    continue
                }
                if r.rustAttributes, i + 1 < hi, s[i + 1] == A("[") || (s[i + 1] == A("!") && i + 2 < hi && s[i + 2] == A("[")) {
                    var level = 0
                    var j = i + 1
                    while j < hi {
                        if s[j] == A("[") { level += 1 } else if s[j] == A("]") { level -= 1; if level == 0 { j += 1; break } }
                        j += 1
                    }
                    add(i, j, .meta)
                    i = j
                    previous = A("]")
                    continue
                }
                if r.swiftRawStrings {
                    var j = i
                    while j < hi && s[j] == A("#") { j += 1 }
                    let hashes = Array(s[i..<j])
                    if j < hi && s[j] == DQ {
                        let triple = matches(units("\"\"\""), at: j, hi)
                        let close = (triple ? units("\"\"\"") : [DQ]) + hashes
                        i = quoted(i, contentStart: j + (triple ? 3 : 1), close: close, Quote(escapes: false, multiline: triple), hi, language: language)
                        previous = DQ; previousWord = nil
                        continue
                    }
                }
                if r.hashDirectives, i + 1 < hi, isIdentStart(s[i + 1]) {
                    let e = identEnd(i + 1, hi)
                    add(i, e, .meta)
                    i = e
                    previous = A("a"); previousWord = nil
                    continue
                }
            }

            // PHP open/close tags
            if r.phpTags {
                if c == A("<"), matches(units("<?php"), at: i, hi) || matches(units("<?="), at: i, hi) {
                    let e = i + (s[i + 2] == A("=") ? 3 : 5)
                    add(i, e, .meta); i = e; continue
                }
                if c == A("?"), i + 1 < hi, s[i + 1] == A(">") { add(i, i + 2, .meta); i += 2; continue }
            }

            // Strings
            if let tq = r.tripleQuote, c == DQ || c == SQ, matches([c, c, c], at: i, hi), (c == DQ || r.singleQuote != nil) {
                i = quoted(i, contentStart: i + 3, close: [c, c, c], tq, hi, language: language)
                previous = DQ; previousWord = nil
                continue
            }
            if r.csharpStrings, c == A("@") || c == A("$") {
                var j = i
                var verbatim = false
                while j < hi && j < i + 3 && (s[j] == A("@") || s[j] == A("$")) { if s[j] == A("@") { verbatim = true }; j += 1 }
                if j < hi && s[j] == DQ {
                    let q = verbatim ? Quote(escapes: false, multiline: true, doubled: true) : Quote()
                    i = quoted(i, contentStart: j + 1, close: [DQ], q, hi, language: language)
                    previous = DQ; previousWord = nil
                    continue
                }
            }
            if c == DQ, let q = r.doubleQuote {
                let e = quoted(i, contentStart: i + 1, close: [DQ], q, hi, language: language)
                if r.jsonKeys {
                    var k = e
                    while k < hi && isBlank(s[k]) { k += 1 }
                    if k < hi && s[k] == A(":"), let last = out.last, last.range.location == i {
                        out[out.count - 1] = CodeToken(range: last.range, kind: .property)
                    }
                }
                i = e
                previous = DQ; previousWord = nil
                continue
            }
            if c == SQ {
                if r.rustCharsAndLifetimes {
                    // 'a' or '\n' is a character; 'a without a closing quote is a lifetime
                    var j = i + 1
                    if j < hi && s[j] == BS { j += 2; while j < hi && j < i + 12 && s[j] != SQ && s[j] != NL { j += 1 } }
                    else if j < hi { j += (j + 1 < hi && s[j] >= 0xD800 && s[j] < 0xDC00) ? 2 : 1 }
                    if j < hi && s[j] == SQ {
                        add(i, j + 1, .string); i = j + 1
                    } else {
                        let e = identEnd(i + 1, hi)
                        add(i, max(e, i + 1), .type); i = max(e, i + 1)
                    }
                    previous = SQ; previousWord = nil
                    continue
                }
                if let q = r.singleQuote {
                    i = quoted(i, contentStart: i + 1, close: [SQ], q, hi, language: language)
                    previous = DQ; previousWord = nil
                    continue
                }
            }
            if c == BT, let q = r.backtick {
                i = quoted(i, contentStart: i + 1, close: [BT], q, hi, language: language)
                previous = DQ; previousWord = nil
                continue
            }

            // Regular expression literals
            if c == A("/"), r.regexLiterals, i + 1 < hi, s[i + 1] != A("/"), s[i + 1] != A("*"), regexAllowed() {
                var j = i + 1
                var inClass = false
                var found = false
                let limit = min(hi, i + 512)
                while j < limit {
                    let d = s[j]
                    if d == NL { break }
                    if d == BS { j += 2; continue }
                    if d == A("[") { inClass = true } else if d == A("]") { inClass = false }
                    else if d == A("/") && !inClass { found = true; break }
                    j += 1
                }
                if found {
                    j = identEnd(j + 1, hi)
                    add(i, j, .regex)
                    i = j
                    previous = DQ; previousWord = nil
                    continue
                }
            }

            // Numbers
            if isDigit(c) || (c == A(".") && i + 1 < hi && isDigit(s[i + 1]) && !(i > lo && isIdentChar(s[i - 1]))) {
                let e = numberEnd(i, hi)
                add(i, e, .number)
                i = e
                previous = A("0"); previousWord = nil; pending = nil
                continue
            }

            // Sigils
            if (c == A("@") && (r.annotations || r.atKeywords || r.sigilVariables || r.sqlVariables)) || (c == A("$") && (r.dollarVariables || r.sigilVariables)) {
                var j = i + 1
                if c == A("@") && r.sigilVariables && j < hi && s[j] == A("@") { j += 1 }
                if r.atKeywords && c == A("@") && j < hi && s[j] == DQ {
                    i = quoted(i, contentStart: j + 1, close: [DQ], Quote(), hi, language: language)
                    previous = DQ; previousWord = nil
                    continue
                }
                if j < hi && isIdentStart(s[j]) {
                    var e = identEnd(j, hi)
                    if c == A("@") && r.annotations { while e + 1 < hi && s[e] == A(".") && isIdentStart(s[e + 1]) { e = identEnd(e + 1, hi) } }
                    let kind: CodeTokenKind = c == A("$") || r.sigilVariables || r.sqlVariables ? .variable : (r.atKeywords ? .keyword : .meta)
                    add(i, e, kind)
                    i = e
                    previous = A("a"); previousWord = nil
                    continue
                }
            }

            // Ruby symbols (:name, but not a::b or a ? b : c)
            if r.rubySymbols, c == A(":"), i + 1 < hi, isIdentStart(s[i + 1]), !(i > lo && (isIdentChar(s[i - 1]) || s[i - 1] == A(":"))) {
                let e = identEnd(i + 1, hi)
                add(i, e, .literal)
                i = e
                previous = A("a"); previousWord = nil
                continue
            }

            // Words
            if isIdentStart(c) {
                let start = i
                var e = identEnd(i, hi, extra: language == .javascript || language == .typescript ? A("$") : 0)
                if language == .ruby, e < hi, s[e] == A("?") || s[e] == A("!"), !(e + 1 < hi && s[e + 1] == A("=")) { e += 1 }
                let length = e - start
                var w: String? = nil
                if length <= r.maxWord { w = word(start, e, folded: r.caseInsensitive) }

                // String prefixes: r"…", f'…', b"…", u8"…"
                if let w, e < hi, r.stringPrefixes.contains(w) {
                    let q0 = s[e]
                    if r.rustRawStrings && w.hasSuffix("r") && (q0 == A("#") || q0 == DQ) {
                        var j = e
                        while j < hi && s[j] == A("#") { j += 1 }
                        if j < hi && s[j] == DQ {
                            i = quoted(start, contentStart: j + 1, close: [DQ] + Array(s[e..<j]), Quote(escapes: false, multiline: true), hi, language: language)
                            previous = DQ; previousWord = nil; pending = nil
                            continue
                        }
                    } else if q0 == DQ || (q0 == SQ && r.singleQuote != nil) {
                        var q = q0 == DQ ? (r.doubleQuote ?? Quote()) : (r.singleQuote ?? Quote())
                        q.interpolation = nil
                        if w.lowercased().contains("r") { q.escapes = false }
                        if let tq = r.tripleQuote, matches([q0, q0, q0], at: e, hi) {
                            var t = tq
                            t.interpolation = nil
                            if w.lowercased().contains("r") { t.escapes = false }
                            i = quoted(start, contentStart: e + 3, close: [q0, q0, q0], t, hi, language: language)
                        } else {
                            i = quoted(start, contentStart: e + 1, close: [q0], q, hi, language: language)
                        }
                        previous = DQ; previousWord = nil; pending = nil
                        continue
                    }
                }
                // C++ raw strings: R"delim(…)delim"
                if r.cppRawStrings, let w, w.hasSuffix("R"), ["R", "u8R", "uR", "UR", "LR"].contains(w), e < hi, s[e] == DQ {
                    var j = e + 1
                    while j < hi && j < e + 18 && s[j] != A("(") && s[j] != NL { j += 1 }
                    if j < hi && s[j] == A("(") {
                        let close = [A(")")] + Array(s[(e + 1)..<j]) + [DQ]
                        var k = j + 1
                        while k < hi && !matches(close, at: k, hi) { k += 1 }
                        k = min(hi, k + close.count)
                        add(start, k, .string)
                        i = k
                        previous = DQ; previousWord = nil; pending = nil
                        continue
                    }
                }

                var kind: CodeTokenKind? = nil
                if let w {
                    if r.literals.contains(w) { kind = .literal }
                    else if r.keywords.contains(w) { kind = .keyword }
                    else if r.types.contains(w) { kind = .type }
                    else if r.builtins.contains(w) { kind = .builtin }
                }
                if r.macroBang, e < hi, s[e] == A("!"), !(e + 1 < hi && s[e + 1] == A("=")), kind == nil || kind == .builtin {
                    e += 1
                    kind = .builtin
                }
                if kind == nil || (kind == .builtin && pending != nil) {
                    if let p = pending { kind = p }
                    else if r.callsAreFunctions {
                        var k = e
                        while k < hi && isBlank(s[k]) { k += 1 }
                        if k < hi && s[k] == A("(") { kind = .function }
                    }
                    if kind == nil, r.capitalizedTypes, isUpper(s[start]) { kind = .type }
                }
                if let kind { add(start, e, kind) }
                pending = nil
                previousWord = nil
                if kind == .keyword, let w {
                    if r.functionDefiners.contains(w) { pending = .function }
                    else if r.typeDefiners.contains(w) { pending = .type }
                    previousWord = w
                }
                previous = A("a")
                i = e
                continue
            }

            // Anything else: punctuation and operators
            if c != A("*") { pending = nil }
            previous = c
            previousWord = nil
            i += 1
        }
    }

    // MARK: Shell

    mutating func bash(_ lo: Int, _ hi: Int) {
        let keywords = words("if then else elif fi case esac for select while until do done in function time return break continue exit local export readonly declare typeset unset shift trap source alias unalias eval exec let coproc")
        let builtins = words("echo printf read cd pwd pushd popd test set kill wait jobs bg fg sudo grep egrep sed awk cat ls cp mv rm mkdir rmdir touch chmod chown find xargs curl wget git ssh scp tar gzip unzip make npm npx yarn pnpm brew apt apt-get yum dnf pip pip3 python python3 node docker kubectl swift xcodebuild xcrun open head tail sort uniq wc tr cut tee diff env exec basename dirname which type command builtin true false getopts mapfile readarray")
        var i = lo
        var commandStart = true
        var heredoc: (delimiter: [UInt16], stripTabs: Bool)? = nil

        while i < hi {
            let c = s[i]
            if c == NL {
                i += 1
                commandStart = true
                if let doc = heredoc {
                    heredoc = nil
                    // Body: up to the line that holds just the delimiter
                    let bodyStart = i
                    var j = i
                    var closing = hi
                    while j < hi {
                        var k = j
                        if doc.stripTabs { while k < hi && s[k] == TAB { k += 1 } }
                        let e = lineEnd(j, hi)
                        if e - k == doc.delimiter.count && matches(doc.delimiter, at: k, hi) { closing = j; break }
                        j = e + 1
                    }
                    add(bodyStart, closing < hi ? max(bodyStart, closing - 1) : hi, .string)
                    if closing < hi {
                        let e = lineEnd(closing, hi)
                        add(closing, e, .keyword)
                        i = e
                    } else {
                        i = hi
                    }
                }
                continue
            }
            if isSpace(c) { i += 1; continue }
            if c == A("#") && (i == lo || isSpace(s[i - 1]) || ";|&(".utf16.contains(s[i - 1])) {
                let e = lineEnd(i, hi); add(i, e, .comment); i = e; continue
            }
            if c == A(";") || c == A("|") || c == A("&") || c == A("(") || c == A("{") {
                commandStart = true; i += 1; continue
            }
            if c == SQ {
                var j = i + 1
                while j < hi && s[j] != SQ { j += 1 }
                j = min(hi, j + 1)
                add(i, j, .string); i = j; commandStart = false; continue
            }
            if c == DQ || c == BT {
                // Double quotes: variables inside are coloured as variables
                var j = i + 1
                var pieceStart = i
                while j < hi {
                    let d = s[j]
                    if d == BS { j += 2; continue }
                    if d == c { j += 1; break }
                    if d == A("$"), c == DQ, j + 1 < hi, isIdentStart(s[j + 1]) || s[j + 1] == A("{") {
                        add(pieceStart, j, .string)
                        let e = variableEnd(j, hi)
                        add(j, e, .variable)
                        pieceStart = e
                        j = e
                        continue
                    }
                    j += 1
                }
                j = min(j, hi)
                add(pieceStart, j, .string)
                i = j; commandStart = false; continue
            }
            if c == A("$") {
                let e = variableEnd(i, hi)
                if e > i + 1 { add(i, e, .variable); i = e } else { i += 1 }
                commandStart = false
                continue
            }
            if c == A("<"), i + 2 < hi, s[i + 1] == A("<"), s[i + 2] != A("<") {
                var j = i + 2
                var strip = false
                if j < hi && s[j] == A("-") { strip = true; j += 1 }
                while j < hi && isBlank(s[j]) { j += 1 }
                var quote: UInt16 = 0
                if j < hi && (s[j] == SQ || s[j] == DQ) { quote = s[j]; j += 1 }
                let w = j
                while j < hi && (isIdentChar(s[j]) || s[j] == A("-")) { j += 1 }
                if j > w {
                    heredoc = (Array(s[w..<j]), strip)
                    if quote != 0 && j < hi && s[j] == quote { j += 1 }
                    add(i, j, .keyword)
                    i = j
                    continue
                }
            }
            if c == A("-"), i + 1 < hi, isLetter(s[i + 1]) || (s[i + 1] == A("-") && i + 2 < hi && isLetter(s[i + 2])), i == lo || isSpace(s[i - 1]) {
                var j = i + 1
                while j < hi && (isIdentChar(s[j]) || s[j] == A("-")) { j += 1 }
                add(i, j, .attribute); i = j; continue
            }
            if isDigit(c), i == lo || !isIdentChar(s[i - 1]) {
                var j = i
                while j < hi && isDigit(s[j]) { j += 1 }
                if j >= hi || !isIdentChar(s[j]) { add(i, j, .number); i = j; commandStart = false; continue }
            }
            if isIdentStart(c) {
                var e = i
                while e < hi && (isIdentChar(s[e]) || s[e] == A("-") || s[e] == A(".")) { e += 1 }
                let w = word(i, e)
                if e < hi && s[e] == A("="), commandStart { add(i, e, .variable) }
                else if keywords.contains(w) { add(i, e, .keyword); commandStart = true; i = e; continue }
                else if builtins.contains(w) && commandStart { add(i, e, .builtin) }
                else if e < hi, s[e] == A("("), e + 1 < hi, s[e + 1] == A(")") { add(i, e, .function) }
                commandStart = false
                i = e
                continue
            }
            commandStart = false
            i += 1
        }
    }

    /// `$name`, `${…}`, `$1`, `$@`, `$?` … starting at the `$`.
    func variableEnd(_ i: Int, _ hi: Int) -> Int {
        let j = i + 1
        guard j < hi else { return j }
        if s[j] == A("{") {
            var k = j + 1
            while k < hi && s[k] != A("}") && s[k] != NL { k += 1 }
            return min(hi, k + 1)
        }
        if isIdentStart(s[j]) { return identEnd(j, hi) }
        if isDigit(s[j]) || "@*#?$!-".utf16.contains(s[j]) { return j + 1 }
        return j
    }

    // MARK: HTML and XML

    mutating func markup(_ lo: Int, _ hi: Int, html: Bool) {
        var i = lo
        while i < hi {
            let c = s[i]
            if c == A("<") {
                if matches(units("<!--"), at: i, hi) {
                    var j = i + 4
                    while j < hi && !matches(units("-->"), at: j, hi) { j += 1 }
                    j = min(hi, j + 3)
                    add(i, j, .comment); i = j; continue
                }
                if matches(units("<![CDATA["), at: i, hi) {
                    var j = i + 9
                    while j < hi && !matches(units("]]>"), at: j, hi) { j += 1 }
                    j = min(hi, j + 3)
                    add(i, j, .string); i = j; continue
                }
                if i + 1 < hi, s[i + 1] == A("!") || s[i + 1] == A("?") {
                    var j = i + 2
                    while j < hi && s[j] != A(">") { j += 1 }
                    j = min(hi, j + 1)
                    add(i, j, .meta); i = j; continue
                }
                var j = i + 1
                let closing = j < hi && s[j] == A("/")
                if closing { j += 1 }
                if j < hi && isIdentStart(s[j]) {
                    let nameStart = j
                    while j < hi && (isIdentChar(s[j]) || s[j] == A("-") || s[j] == A(":") || s[j] == A(".")) { j += 1 }
                    add(nameStart, j, .tag)
                    let name = j - nameStart <= 6 ? word(nameStart, j, folded: true) : ""
                    var selfClosing = false
                    while j < hi && s[j] != A(">") {
                        let d = s[j]
                        if d == A("/") && j + 1 < hi && s[j + 1] == A(">") { selfClosing = true; j += 1; break }
                        if d == DQ || d == SQ {
                            var k = j + 1
                            while k < hi && s[k] != d { k += 1 }
                            k = min(hi, k + 1)
                            add(j, k, .string); j = k; continue
                        }
                        if d == A("<") { break }
                        if !isSpace(d) && d != A("=") {
                            let a = j
                            while j < hi && !isSpace(s[j]) && s[j] != A("=") && s[j] != A(">") && s[j] != A("/") && s[j] != DQ && s[j] != SQ && s[j] != A("<") { j += 1 }
                            if a > i, s[a - 1] == A("=") { add(a, j, .string) } else { add(a, j, .attribute) }
                            if j == a { j += 1 }
                            continue
                        }
                        j += 1
                    }
                    if j < hi && s[j] == A(">") { j += 1 }
                    i = j
                    if html && !closing && !selfClosing && (name == "script" || name == "style") {
                        let end = units("</" + name)
                        var k = i
                        while k < hi && !matchesFolded(end, at: k, hi) { k += 1 }
                        if depth < 4 {
                            depth += 1
                            run(name == "script" ? .javascript : .css, i, k)
                            depth -= 1
                        }
                        i = k
                    }
                    continue
                }
                i += 1
                continue
            }
            if c == A("&") {
                var j = i + 1
                while j < hi && j < i + 32 && (isIdentChar(s[j]) || s[j] == A("#")) { j += 1 }
                if j < hi && j > i + 1 && s[j] == A(";") { add(i, j + 1, .literal); i = j + 1; continue }
            }
            i += 1
        }
    }

    // MARK: CSS (and SCSS / Less)

    mutating func css(_ lo: Int, _ hi: Int) {
        var i = lo
        var level = 0
        var statementStart = true
        var declaration = false
        var inValue = false
        while i < hi {
            let c = s[i]
            if c == A("/") && i + 1 < hi && s[i + 1] == A("*") {
                i = blockComment(i, open: units("/*"), close: units("*/"), nested: false, hi); continue
            }
            if c == A("/") && i + 1 < hi && s[i + 1] == A("/") && (i == lo || isSpace(s[i - 1])) {
                let e = lineEnd(i, hi); add(i, e, .comment); i = e; continue
            }
            if isSpace(c) { i += 1; continue }
            if statementStart {
                // A declaration ends at `;` or `}` before any `{`; a selector reaches `{` first
                statementStart = false
                inValue = false
                var j = i
                var stop: UInt16 = 0
                while j < hi {
                    let d = s[j]
                    if d == A(";") || d == A("{") || d == A("}") { stop = d; break }
                    if d == DQ || d == SQ { let q = d; j += 1; while j < hi && s[j] != q && s[j] != NL { j += 1 } }
                    j += 1
                }
                declaration = level > 0 && stop != A("{")
                if c == A("@") { declaration = false }
            }
            switch c {
            case A("{"): level += 1; statementStart = true; i += 1; continue
            case A("}"): level = max(0, level - 1); statementStart = true; i += 1; continue
            case A(";"): statementStart = true; i += 1; continue
            case DQ, SQ:
                i = quoted(i, contentStart: i + 1, close: [c], Quote(), hi, language: .css); continue
            default: break
            }
            if c == A("@") || c == A("$") {
                let e = identEnd(i + 1, hi, extra: A("-"))
                if e > i + 1 {
                    add(i, e, c == A("$") || inValue ? .variable : .keyword)
                    i = e; continue
                }
            }
            if c == A("!"), i + 1 < hi, isLetter(s[i + 1]) {
                let e = identEnd(i + 1, hi); add(i, e, .keyword); i = e; continue
            }
            if inValue || declaration {
                if c == A(":") && declaration && !inValue { inValue = true; i += 1; continue }
                if c == A("#"), i + 1 < hi, isHex(s[i + 1]) {
                    let e = identEnd(i + 1, hi); add(i, e, .number); i = e; continue
                }
                if isDigit(c) || ((c == A(".") || c == A("-") || c == A("+")) && i + 1 < hi && isDigit(s[i + 1]) && !(i > lo && isIdentChar(s[i - 1]))) {
                    var e = numberEnd(c == A("-") || c == A("+") ? i + 1 : i, hi)
                    if e < hi && s[e] == A("%") { e += 1 }
                    add(i, e, .number); i = e; continue
                }
                if isIdentStart(c) || (c == A("-") && i + 1 < hi && (isIdentStart(s[i + 1]) || s[i + 1] == A("-"))) {
                    let e = identEnd(i + 1, hi, extra: A("-"))
                    let isCustom = c == A("-") && i + 1 < hi && s[i + 1] == A("-")
                    if !inValue {
                        add(i, e, isCustom ? .variable : .property)
                    } else if e < hi && s[e] == A("(") {
                        add(i, e, .builtin)
                        if e - i == 3 && matchesFolded(units("url"), at: i, hi) {
                            var k = e + 1
                            while k < hi && s[k] != A(")") && s[k] != NL { k += 1 }
                            add(e + 1, k, .string)
                            i = k; continue
                        }
                    } else if isCustom {
                        add(i, e, .variable)
                    }
                    i = e; continue
                }
                i += 1; continue
            }
            // Selectors
            if (c == A(".") || c == A("#")) && i + 1 < hi && (isIdentStart(s[i + 1]) || s[i + 1] == A("-")) {
                let e = identEnd(i + 1, hi, extra: A("-")); add(i, e, .type); i = e; continue
            }
            if c == A(":") {
                var j = i + 1
                if j < hi && s[j] == A(":") { j += 1 }
                let e = identEnd(j, hi, extra: A("-"))
                if e > j { add(i, e, .keyword); i = e; continue }
            }
            if c == A("[") {
                var j = i + 1
                while j < hi && s[j] != A("]") && s[j] != NL { j += 1 }
                j = min(hi, j + 1)
                add(i, j, .attribute); i = j; continue
            }
            if isIdentStart(c) || c == A("*") || c == A("&") {
                let e = c == A("*") || c == A("&") ? i + 1 : identEnd(i, hi, extra: A("-"))
                add(i, e, .tag); i = e; continue
            }
            if isDigit(c) {
                var e = numberEnd(i, hi)
                if e < hi && s[e] == A("%") { e += 1 }
                add(i, e, .number); i = e; continue
            }
            i += 1
        }
    }

    // MARK: YAML

    mutating func yaml(_ lo: Int, _ hi: Int) {
        var lineStart = lo
        var blockIndent: Int? = nil
        while lineStart < hi {
            let e = lineEnd(lineStart, hi)
            var p = lineStart
            while p < e && s[p] == SP { p += 1 }
            let indent = p - lineStart
            defer { lineStart = e + 1 }
            if p == e || (s[p] == CR && p + 1 == e) { continue }
            if let bi = blockIndent {
                if indent > bi { add(p, e, .string); continue }
                blockIndent = nil
            }
            if s[p] == A("#") { add(p, e, .comment); continue }
            if indent == 0, matches(units("---"), at: p, e) || matches(units("..."), at: p, e), p + 3 == e || isSpace(s[p + 3]) {
                add(p, p + 3, .meta)
                p += 3
            }
            // List markers
            while p < e && s[p] == A("-") && (p + 1 == e || isBlank(s[p + 1])) {
                p += 1
                while p < e && isBlank(s[p]) { p += 1 }
            }
            // A key ends at the first ": " (or ":" at the end of the line) outside quotes
            if p < e {
                if s[p] == DQ || s[p] == SQ {
                    var k = p + 1
                    while k < e && s[k] != s[p] { if s[k] == BS && s[p] == DQ { k += 1 }; k += 1 }
                    k = min(e, k + 1)
                    var m = k
                    while m < e && isBlank(s[m]) { m += 1 }
                    if m < e && s[m] == A(":") && (m + 1 == e || isSpace(s[m + 1])) {
                        add(p, k, .property)
                        p = m + 1
                    }
                } else if s[p] != A("{") && s[p] != A("[") && s[p] != A("&") && s[p] != A("*") && s[p] != A("!") && s[p] != A("|") && s[p] != A(">") {
                    var q = p
                    while q < e {
                        if s[q] == A(":") && (q + 1 == e || isSpace(s[q + 1])) { break }
                        if s[q] == A("#") && q > p && isBlank(s[q - 1]) { q = e; break }
                        q += 1
                    }
                    if q < e {
                        var k = q
                        while k > p && isBlank(s[k - 1]) { k -= 1 }
                        add(p, k, .property)
                        p = q + 1
                    }
                }
            }
            // Value
            while p < e && isBlank(s[p]) { p += 1 }
            if p < e && (s[p] == A("|") || s[p] == A(">")) {
                var k = p + 1
                while k < e && (isDigit(s[k]) || s[k] == A("+") || s[k] == A("-")) { k += 1 }
                var m = k
                while m < e && isBlank(s[m]) { m += 1 }
                if m == e || s[m] == A("#") || s[m] == CR {
                    add(p, k, .keyword)
                    if m < e && s[m] == A("#") { add(m, e, .comment) }
                    blockIndent = indent
                    continue
                }
            }
            yamlValue(p, e)
        }
    }

    mutating func yamlValue(_ lo: Int, _ hi: Int) {
        var i = lo
        while i < hi {
            let c = s[i]
            if isSpace(c) || c == A(",") || c == A("[") || c == A("]") || c == A("{") || c == A("}") || c == A(":") || c == A("-") && i + 1 < hi && isBlank(s[i + 1]) { i += 1; continue }
            if c == A("#") && (i == lo || isBlank(s[i - 1])) { add(i, hi, .comment); return }
            if c == DQ || c == SQ {
                var k = i + 1
                while k < hi && s[k] != c { if s[k] == BS && c == DQ { k += 1 }; k += 1 }
                k = min(hi, k + 1)
                add(i, k, .string); i = k; continue
            }
            if c == A("&") || c == A("*") || c == A("!") {
                var k = i + 1
                while k < hi && !isSpace(s[k]) && s[k] != A(",") && s[k] != A("]") && s[k] != A("}") { k += 1 }
                add(i, k, c == A("!") ? .meta : .variable); i = k; continue
            }
            // A plain scalar runs to a flow indicator or a comment
            var k = i
            while k < hi && s[k] != A(",") && s[k] != A("]") && s[k] != A("}") && !(s[k] == A("#") && isBlank(s[k - 1])) {
                if s[k] == A(":") && (k + 1 == hi || isSpace(s[k + 1])) { break }
                k += 1
            }
            var end = k
            while end > i && isSpace(s[end - 1]) { end -= 1 }
            if end - i <= 5, ["true", "false", "yes", "no", "on", "off", "null", "~"].contains(word(i, end, folded: true)) {
                add(i, end, .literal)
            } else if isNumberLiteral(i, end) {
                add(i, end, .number)
            }
            i = max(k, i + 1)
        }
    }

    func isNumberLiteral(_ a: Int, _ b: Int) -> Bool {
        guard b > a else { return false }
        var i = a
        if s[i] == A("-") || s[i] == A("+") { i += 1 }
        guard i < b else { return false }
        if s[i] == A(".") && b - i == 4 { let w = word(i, b, folded: true); return w == ".inf" || w == ".nan" }
        if s[i] == A("0"), i + 2 < b, (s[i + 1] | 0x20) == A("x") {
            var j = i + 2
            while j < b && isHex(s[j]) { j += 1 }
            return j == b
        }
        var j = i
        var digits = 0
        while j < b && (isDigit(s[j]) || s[j] == A("_")) { j += 1; digits += 1 }
        if j < b && s[j] == A(".") {
            j += 1
            while j < b && isDigit(s[j]) { j += 1; digits += 1 }
        }
        guard digits > 0 else { return false }
        if j < b && (s[j] | 0x20) == A("e") {
            j += 1
            if j < b && (s[j] == A("+") || s[j] == A("-")) { j += 1 }
            let exponent = j
            while j < b && isDigit(s[j]) { j += 1 }
            if j == exponent { return false }
        }
        return j == b
    }

    // MARK: TOML and INI

    mutating func toml(_ lo: Int, _ hi: Int) {
        var i = lo
        var lineStart = true
        while i < hi {
            let c = s[i]
            if c == NL { lineStart = true; i += 1; continue }
            if isSpace(c) { i += 1; continue }
            if c == A("#") || (c == A(";") && lineStart) { let e = lineEnd(i, hi); add(i, e, .comment); i = e; continue }
            if lineStart {
                lineStart = false
                let e = lineEnd(i, hi)
                if c == A("[") {
                    var k = i
                    var close = -1
                    while k < e && s[k] != A("#") { if s[k] == A("]") { close = k }; k += 1 }
                    if close > i { add(i, close + 1, .type); i = close + 1; continue }
                }
                // key = value (or key: value in .properties-style files)
                var k = i
                var quote: UInt16 = 0
                while k < e {
                    let d = s[k]
                    if quote != 0 { if d == quote { quote = 0 } }
                    else if d == DQ || d == SQ { quote = d }
                    else if d == A("=") || d == A("#") { break }
                    k += 1
                }
                if k < e && s[k] == A("=") {
                    var m = k
                    while m > i && isBlank(s[m - 1]) { m -= 1 }
                    add(i, m, .property)
                    i = k + 1
                    continue
                }
            }
            if c == DQ || c == SQ {
                if matches([c, c, c], at: i, hi) {
                    i = quoted(i, contentStart: i + 3, close: [c, c, c], Quote(escapes: c == DQ, multiline: true), hi, language: .toml)
                } else {
                    i = quoted(i, contentStart: i + 1, close: [c], Quote(escapes: c == DQ, multiline: false), hi, language: .toml)
                }
                continue
            }
            if isDigit(c) || ((c == A("+") || c == A("-")) && i + 1 < hi && isDigit(s[i + 1])) {
                var e = i + 1
                while e < hi && (isIdentChar(s[e]) || ".:+-".utf16.contains(s[e])) { e += 1 }
                add(i, e, .number); i = e; continue
            }
            if isIdentStart(c) {
                let e = identEnd(i, hi)
                let w = e - i <= 5 ? word(i, e) : ""
                if w == "true" || w == "false" { add(i, e, .literal) } else if w == "inf" || w == "nan" { add(i, e, .number) }
                i = e; continue
            }
            i += 1
        }
    }

    // MARK: Markdown

    mutating func markdown(_ lo: Int, _ hi: Int) {
        var lineStart = lo
        var fence: (char: UInt16, count: Int)? = nil
        while lineStart < hi {
            let e = lineEnd(lineStart, hi)
            defer { lineStart = e + 1 }
            var p = lineStart
            while p < e && isBlank(s[p]) { p += 1 }
            let fenceRun: (UInt16, Int)? = {
                guard p < e, s[p] == BT || s[p] == A("~") else { return nil }
                var k = p
                while k < e && s[k] == s[p] { k += 1 }
                return k - p >= 3 ? (s[p], k - p) : nil
            }()
            if let open = fence {
                if let run = fenceRun, run.0 == open.char, run.1 >= open.count { add(lineStart, e, .meta); fence = nil }
                else { add(lineStart, e, .string) }
                continue
            }
            if let run = fenceRun { add(p, e, .meta); fence = (run.0, run.1); continue }
            if p < e && s[p] == A("#") {
                var k = p
                while k < e && s[k] == A("#") { k += 1 }
                if k - p <= 6 && (k == e || isBlank(s[k])) { add(p, e, .heading); continue }
            }
            // Thematic breaks and setext underlines
            if p < e, s[p] == A("-") || s[p] == A("*") || s[p] == A("_") || s[p] == A("=") {
                var k = p
                var count = 0
                while k < e && (s[k] == s[p] || isBlank(s[k])) { if s[k] == s[p] { count += 1 }; k += 1 }
                if k == e && count >= 3 { add(p, e, .meta); continue }
            }
            while p < e && s[p] == A(">") {
                add(p, p + 1, .keyword)
                p += 1
                while p < e && isBlank(s[p]) { p += 1 }
            }
            if p + 1 < e, s[p] == A("-") || s[p] == A("*") || s[p] == A("+"), isBlank(s[p + 1]) {
                add(p, p + 1, .keyword); p += 2
            } else if p < e, isDigit(s[p]) {
                var k = p
                while k < e && k < p + 9 && isDigit(s[k]) { k += 1 }
                if k + 1 < e, s[k] == A(".") || s[k] == A(")"), isBlank(s[k + 1]) { add(p, k + 1, .keyword); p = k + 2 }
            }
            if p + 3 <= e, s[p] == A("["), s[p + 2] == A("]"), s[p + 1] == SP || (s[p + 1] | 0x20) == A("x") {
                add(p, p + 3, .keyword); p += 3
            }
            markdownInline(p, e)
        }
    }

    mutating func markdownInline(_ lo: Int, _ hi: Int) {
        var i = lo
        var noBracketClose = false
        var noParenClose = false
        var exhausted: Set<UInt16> = []
        while i < hi {
            let c = s[i]
            if c == BS { i += 2; continue }
            if c == BT || c == A("*") || c == A("_") || c == A("~") {
                var k = i
                while k < hi && s[k] == c { k += 1 }
                let run = k - i
                if exhausted.contains(c) || (c == A("_") && i > lo && isIdentChar(s[i - 1])) || (c == A("~") && run < 2) { i = k; continue }
                // Next run of the same character on the line
                var m = k
                while m < hi && s[m] != c { if c != BT && s[m] == BS { m += 1 }; m += 1 }
                if m >= hi { exhausted.insert(c); i = k; continue }
                var n = m
                while n < hi && s[n] == c && (c != BT || n - m < run) { n += 1 }
                add(i, n, c == BT ? .string : .emphasis)
                i = n
                continue
            }
            if c == A("[") || (c == A("!") && i + 1 < hi && s[i + 1] == A("[")) {
                let open = c == A("!") ? i + 1 : i
                if noBracketClose { i = open + 1; continue }
                var k = open + 1
                while k < hi && s[k] != A("]") { k += 1 }
                if k >= hi { noBracketClose = true; i = open + 1; continue }
                if k + 1 < hi && s[k + 1] == A("(") && !noParenClose {
                    var m = k + 2
                    while m < hi && s[m] != A(")") { m += 1 }
                    if m >= hi { noParenClose = true; i = k + 1; continue }
                    add(i, k + 1, .property)
                    add(k + 1, m + 1, .string)
                    i = m + 1
                    continue
                }
                i = k + 1
                continue
            }
            if c == A("<"), i + 1 < hi, isLetter(s[i + 1]) || s[i + 1] == A("/") {
                var k = i + 1
                while k < hi && k < i + 256 && s[k] != A(">") && s[k] != A("<") { k += 1 }
                if k < hi && s[k] == A(">") { add(i, k + 1, .tag); i = k + 1; continue }
            }
            i += 1
        }
    }

    // MARK: Diff

    mutating func diff(_ lo: Int, _ hi: Int) {
        var lineStart = lo
        while lineStart < hi {
            let e = lineEnd(lineStart, hi)
            let c = s[lineStart]
            if matches(units("+++"), at: lineStart, e) || matches(units("---"), at: lineStart, e) {
                add(lineStart, e, .heading)
            } else if matches(units("@@"), at: lineStart, e) {
                add(lineStart, e, .meta)
            } else if c == A("+") || c == A(">") {
                add(lineStart, e, .inserted)
            } else if c == A("-") || c == A("<") {
                add(lineStart, e, .deleted)
            } else if matches(units("diff "), at: lineStart, e) || matches(units("index "), at: lineStart, e) || matches(units("*** "), at: lineStart, e) {
                add(lineStart, e, .heading)
            } else if c == BS {
                add(lineStart, e, .comment)
            }
            lineStart = e + 1
        }
    }
}
