//
//  MarkdownMath.swift
//  Swash
//
//  A readable Unicode approximation of common TeX math for the Preview (no typesetting engine):
//  Greek letters, operators, relations, arrows, \frac, \sqrt, sub/superscripts and text commands.
//

import Foundation

enum MarkdownMath {
    private static let symbols: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
        "xi": "ξ", "pi": "π", "varpi": "ϖ", "rho": "ρ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ",
        "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ",
        "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators and relations
        "times": "×", "cdot": "·", "pm": "±", "mp": "∓", "div": "÷", "ast": "∗", "star": "⋆", "circ": "∘",
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡",
        "sim": "∼", "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫",
        "infty": "∞", "partial": "∂", "nabla": "∇", "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "oint": "∮",
        "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "supseteq": "⊇",
        "cup": "∪", "cap": "∩", "setminus": "∖", "emptyset": "∅", "varnothing": "∅",
        "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "lnot": "¬", "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨",
        "oplus": "⊕", "otimes": "⊗", "perp": "⊥", "parallel": "∥", "angle": "∠", "triangle": "△",
        // Arrows
        "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←", "leftrightarrow": "↔", "Rightarrow": "⇒",
        "Leftarrow": "⇐", "Leftrightarrow": "⇔", "implies": "⇒", "iff": "⇔", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        // Misc
        "ldots": "…", "cdots": "⋯", "dots": "…", "vdots": "⋮", "ddots": "⋱", "degree": "°", "prime": "′",
        "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ",
        "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉",
        "{": "{", "}": "}", "%": "%", "$": "$", "&": "&", "#": "#", "_": "_", "|": "‖",
        // Spacing
        ",": "\u{2009}", ";": " ", ":": " ", "!": "", "quad": "  ", "qquad": "    ", " ": " ",
        // Functions keep their names
        "sin": "sin", "cos": "cos", "tan": "tan", "log": "log", "ln": "ln", "exp": "exp", "lim": "lim",
        "max": "max", "min": "min", "det": "det", "sup": "sup", "inf": "inf",
    ]
    private static let blackboard: [Character: String] = ["R": "ℝ", "N": "ℕ", "Z": "ℤ", "Q": "ℚ", "C": "ℂ", "P": "ℙ"]
    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "x": "ˣ", "y": "ʸ", "a": "ᵃ", "b": "ᵇ",
        "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "k": "ᵏ", "m": "ᵐ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
        "T": "ᵀ", "′": "′", "*": "*",
    ]
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "n": "ₙ", "m": "ₘ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ",
    ]

    /// Converts TeX source to a readable Unicode string.
    static func unicode(_ tex: String) -> String {
        var parser = Parser(Array(tex))
        // Spaces in math mode are not significant: collapse runs to one
        let collapsed = parser.parseSequence(until: nil).replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        init(_ chars: [Character]) { self.chars = chars }

        mutating func parseSequence(until terminator: Character?) -> String {
            var out = ""
            while i < chars.count {
                let c = chars[i]
                if let t = terminator, c == t { i += 1; return out }
                out += parseAtom()
            }
            return out
        }

        /// One argument: a {group}, a command, or a single character.
        mutating func parseArgument() -> String {
            while i < chars.count, chars[i] == " " { i += 1 }
            guard i < chars.count else { return "" }
            if chars[i] == "{" {
                i += 1
                return parseSequence(until: "}")
            }
            return parseAtom()
        }

        mutating func parseAtom() -> String {
            let c = chars[i]
            switch c {
            case "\\":
                return parseCommand()
            case "{":
                i += 1
                return parseSequence(until: "}")
            case "^", "_":
                i += 1
                let argument = parseArgument()
                let table = c == "^" ? MarkdownMath.superscripts : MarkdownMath.subscripts
                let mapped = argument.map { table[$0] }
                if !argument.isEmpty, mapped.allSatisfy({ $0 != nil }) {
                    return String(mapped.compactMap { $0 })
                }
                return argument.count == 1 ? "\(c)\(argument)" : "\(c)(\(argument))"
            case "~":
                i += 1
                return " "
            default:
                i += 1
                return String(c)
            }
        }

        mutating func parseCommand() -> String {
            i += 1   // backslash
            guard i < chars.count else { return "\\" }
            var name = ""
            if chars[i].isLetter {
                while i < chars.count, chars[i].isLetter { name.append(chars[i]); i += 1 }
            } else {
                name = String(chars[i])
                i += 1
            }
            switch name {
            case "frac", "dfrac", "tfrac":
                let numerator = parseArgument()
                let denominator = parseArgument()
                let wrap: (String) -> String = { $0.count > 1 && !$0.allSatisfy({ $0.isNumber }) ? "(\($0))" : $0 }
                if numerator.count == 1 && denominator.count == 1 { return "\(numerator)⁄\(denominator)" }
                return "\(wrap(numerator))/\(wrap(denominator))"
            case "sqrt":
                let argument = parseArgument()
                return argument.count > 1 ? "√(\(argument))" : "√\(argument)"
            case "text", "mathrm", "mathit", "mathbf", "textbf", "textit", "operatorname", "mathsf", "mathtt", "boldsymbol":
                return parseArgument()
            case "mathbb":
                let argument = parseArgument()
                return argument.map { MarkdownMath.blackboard[$0] ?? String($0) }.joined()
            case "left", "right", "big", "Big", "bigg", "Bigg":
                guard i < chars.count else { return "" }
                if chars[i] == "\\" { return parseCommand() }
                let delimiter = chars[i]
                i += 1
                return delimiter == "." ? "" : String(delimiter)
            case "vec":
                return parseArgument() + "\u{20D7}"
            case "hat":
                return parseArgument() + "\u{0302}"
            case "bar", "overline":
                return parseArgument() + "\u{0305}"
            case "dot":
                return parseArgument() + "\u{0307}"
            default:
                return MarkdownMath.symbols[name] ?? name
            }
        }
    }
}
