//
//  MarkdownMathEditing.swift
//  Swash
//
//  Editing help inside TeX math: knowing when the caret is in math, pairing braces, and the
//  commands offered by completion (Esc / ⌥Esc) after a backslash.
//

import Foundation

extension MarkdownMath {
    /// KaTeX commands offered for completion, most common first within each group.
    static let completionCommands: [String] = [
        // Structures
        "frac", "dfrac", "tfrac", "sqrt", "sum", "prod", "int", "iint", "oint", "lim", "binom",
        "left", "right", "begin", "end", "text", "operatorname", "displaystyle",
        "mathrm", "mathbf", "mathit", "mathbb", "mathcal", "mathfrak", "mathsf", "mathtt",
        "vec", "hat", "bar", "dot", "ddot", "tilde", "overline", "underline", "overbrace", "underbrace",
        // Greek
        "alpha", "beta", "gamma", "delta", "epsilon", "varepsilon", "zeta", "eta", "theta", "vartheta",
        "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "varpi", "rho", "sigma", "tau", "upsilon",
        "phi", "varphi", "chi", "psi", "omega",
        "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega",
        // Operators and relations
        "times", "cdot", "pm", "mp", "div", "circ", "leq", "geq", "neq", "approx", "equiv", "sim",
        "simeq", "cong", "propto", "ll", "gg", "infty", "partial", "nabla",
        "in", "notin", "subset", "subseteq", "supset", "supseteq", "cup", "cap", "setminus", "emptyset",
        "forall", "exists", "neg", "land", "lor", "oplus", "otimes", "perp", "parallel",
        // Arrows
        "to", "rightarrow", "leftarrow", "leftrightarrow", "Rightarrow", "Leftarrow", "Leftrightarrow",
        "implies", "iff", "mapsto", "uparrow", "downarrow",
        // Dots, delimiters, spacing
        "ldots", "cdots", "vdots", "ddots", "langle", "rangle", "lfloor", "rfloor", "lceil", "rceil",
        "quad", "qquad",
        // Functions
        "sin", "cos", "tan", "sec", "csc", "cot", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
        "log", "ln", "exp", "max", "min", "sup", "inf", "det", "gcd",
    ]

    /// Commands starting with `partial` (case-sensitive first, then case-insensitive matches).
    static func completions(for partial: String) -> [String] {
        guard !partial.isEmpty else { return completionCommands }
        let exact = completionCommands.filter { $0.hasPrefix(partial) }
        let loose = completionCommands.filter { !$0.hasPrefix(partial) && $0.lowercased().hasPrefix(partial.lowercased()) }
        return exact + loose
    }

    /// Whether a caret at `location` is inside math: inline `$…$` (closed, or opened earlier on the
    /// line and not yet closed while it is being typed) or a `$$` / ```` ```math ```` block. Code
    /// spans and other code blocks never count.
    static func isEditingMath(in document: MarkdownDocument, at location: Int) -> Bool {
        let path = document.nodePath(containing: NSRange(location: location, length: 0))
        for node in path.reversed() {
            switch node.kind {
            case .math:
                return location > node.range.location && location < NSMaxRange(node.range)
            case .codeBlock(_, let info):
                guard info.lowercased() == "math" else { return false }
                // Not on the fence lines themselves
                return !node.markers.contains { NSLocationInRange(location, $0) || location == NSMaxRange($0) }
            case .code, .htmlBlock, .htmlInline, .frontMatter:
                return false
            default:
                continue
            }
        }
        // An inline formula still being typed is not parsed as math until it is closed: count the
        // `$` openers on the line before the caret (a `$` followed by a space or another `$` doesn't open)
        let text = document.source as NSString
        guard location <= text.length else { return false }
        let lineStart = text.lineRange(for: NSRange(location: location, length: 0)).location
        var open = false
        var i = lineStart
        while i < location {
            let c = text.character(at: i)
            if c == 0x5C { i += 2; continue }   // escaped character
            if c == 0x24 {
                let next: UInt16 = i + 1 < text.length ? text.character(at: i + 1) : 0
                if next == 0x24 { i += 2; continue }
                if open {
                    open = false
                } else if next != 0x20 && next != 0x09 && next != 0x0A && next != 0 {
                    open = true
                }
            }
            i += 1
        }
        return open
    }
}

extension MarkdownEditingCommands {
    /// Typing `{` in math inserts a pair (wrapping any selection) with the caret inside; typing `}`
    /// just before a `}` steps over it. Nil outside math or for other input.
    static func mathBrace(_ typed: String, text: String, selection: NSRange, document: MarkdownDocument? = nil) -> MarkdownEdit? {
        guard typed == "{" || typed == "}" else { return nil }
        let ns = text as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        let parsed = document.flatMap { $0.source == text ? $0 : nil } ?? MarkdownDocument.parse(text)
        guard MarkdownMath.isEditingMath(in: parsed, at: selection.location) else { return nil }
        if typed == "{" {
            let inner = ns.substring(with: selection)
            let edited = ns.replacingCharacters(in: selection, with: "{" + inner + "}")
            let caret = selection.length > 0
                ? NSRange(location: selection.location + 1, length: selection.length)
                : NSRange(location: selection.location + 1, length: 0)
            return MarkdownEdit(text: edited, selection: caret)
        }
        guard selection.length == 0, selection.location < ns.length, ns.character(at: selection.location) == 0x7D else { return nil }
        return MarkdownEdit(text: text, selection: NSRange(location: selection.location + 1, length: 0))
    }
}
