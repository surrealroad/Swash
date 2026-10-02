//
//  MarkdownInlineParser.swift
//  Swash
//
//  Inline phase of the Markdown parser: CommonMark 0.31 inlines (code spans, emphasis via the
//  delimiter-stack algorithm, links and images, autolinks, raw HTML, entities, escapes, breaks)
//  plus GFM strikethrough, footnote references and extended autolinks. Every node records its
//  UTF-16 source range and the ranges of its syntax markers.
//

import Foundation

final class MarkdownInlineParser {
    private final class Delimiter {
        let char: UInt16
        var count: Int
        let originalCount: Int
        let node: MarkdownNode
        var previous: Delimiter?
        var next: Delimiter?
        let canOpen: Bool
        let canClose: Bool
        init(char: UInt16, count: Int, node: MarkdownNode, previous: Delimiter?, canOpen: Bool, canClose: Bool) {
            self.char = char
            self.count = count
            self.originalCount = count
            self.node = node
            self.previous = previous
            self.canOpen = canOpen
            self.canClose = canClose
        }
    }

    private final class Bracket {
        let node: MarkdownNode
        let previous: Bracket?
        let previousDelimiter: Delimiter?
        let index: Int
        let isImage: Bool
        var active = true
        var bracketAfter = false
        init(node: MarkdownNode, previous: Bracket?, previousDelimiter: Delimiter?, index: Int, isImage: Bool) {
            self.node = node
            self.previous = previous
            self.previousDelimiter = previousDelimiter
            self.index = index
            self.isImage = isImage
        }
    }

    let options: MarkdownParseOptions
    var refmap: [String: (destination: String, title: String?)] = [:]
    var footnoteLabels: Set<String> = []
    private(set) var footnoteOrder: [String] = []

    private var subject: [UInt16] = []
    private var map: [Int] = []
    private var nsSubject: NSString = ""
    private var pos = 0
    private var delimiters: Delimiter?
    private var brackets: Bracket?
    /// Per text node: source offset of each UTF-16 unit of its literal (used to split text for autolinks).
    private var textMaps: [ObjectIdentifier: (node: MarkdownNode, map: [Int])] = [:]
    
    private func textMap(_ node: MarkdownNode) -> [Int]? { textMaps[ObjectIdentifier(node)]?.map }
    private func setTextMap(_ node: MarkdownNode, _ map: [Int]) { textMaps[ObjectIdentifier(node)] = (node, map) }

    init(options: MarkdownParseOptions) {
        self.options = options
    }

    // MARK: - Source ranges

    private func sourceLocation(_ i: Int) -> Int {
        if i < map.count { return map[i] }
        return map.isEmpty ? 0 : map[map.count - 1] + 1
    }

    private func sourceRange(_ a: Int, _ b: Int) -> NSRange {
        guard b > a, a < map.count else { return NSRange(location: sourceLocation(a), length: 0) }
        let start = map[a]
        let end = map[min(b, map.count) - 1] + 1
        return NSRange(location: start, length: max(0, end - start))
    }

    private func string(_ a: Int, _ b: Int) -> String {
        guard b > a else { return "" }
        return String(utf16CodeUnits: Array(subject[a..<b]), count: b - a)
    }

    private func peek(_ offset: Int = 0) -> UInt16? {
        let i = pos + offset
        return i < subject.count ? subject[i] : nil
    }

    private func match(_ regex: NSRegularExpression) -> NSRange? {
        guard pos <= subject.count else { return nil }
        let m = regex.firstMatch(in: nsSubject as String, options: [.anchored], range: NSRange(location: pos, length: subject.count - pos))
        guard let r = m?.range, r.location == pos else { return nil }
        return r
    }

    // MARK: - Node construction

    @discardableResult
    private func appendText(_ a: Int, _ b: Int, to block: MarkdownNode, literal: String? = nil, literalMap: [Int]? = nil) -> MarkdownNode {
        let node = MarkdownNode(.text, range: sourceRange(a, b))
        node.literal = literal ?? string(a, b)
        setTextMap(node, literalMap ?? Array(map[min(a, map.count)..<min(b, map.count)]))
        block.appendChild(node)
        return node
    }

    // MARK: - Entry points

    /// Parses inline content into `block` (a paragraph, heading or table cell).
    func parse(_ source: MarkdownInlineSource, into block: MarkdownNode) {
        // Trim leading and trailing whitespace of the whole content
        var lo = 0, hi = source.chars.count
        while lo < hi, isTrimmable(source.chars[lo]) { lo += 1 }
        while hi > lo, isTrimmable(source.chars[hi - 1]) { hi -= 1 }
        subject = Array(source.chars[lo..<hi])
        map = Array(source.map[lo..<hi])
        nsSubject = String(utf16CodeUnits: subject, count: subject.count) as NSString
        pos = 0
        delimiters = nil
        brackets = nil
        textMaps.removeAll(keepingCapacity: true)
        while parseInline(block) {}
        processEmphasis(stackBottom: nil)
        mergeText(in: block)
        if options.contains(.extendedAutolinks) {
            applyExtendedAutolinks(in: block)
        }
        recordFootnoteOrder(block)
    }

    private func isTrimmable(_ c: UInt16) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C
    }

    /// Parses a link reference definition at the start of `source`.
    func parseReference(_ source: MarkdownInlineSource, refmap: inout [String: (destination: String, title: String?)]) -> (consumed: Int, label: String, destination: String, title: String?)? {
        subject = source.chars
        map = source.map
        nsSubject = String(utf16CodeUnits: subject, count: subject.count) as NSString
        pos = 0
        let start = pos
        let labelLength = parseLinkLabel()
        guard labelLength > 0 else { return nil }
        let rawLabel = string(start + 1, start + labelLength - 1)
        guard peek() == 0x3A else { pos = start; return nil }
        pos += 1
        spnl()
        guard let destination = parseLinkDestination() else { pos = start; return nil }
        let beforeTitle = pos
        spnl()
        var title: String? = nil
        if pos != beforeTitle {
            title = parseLinkTitle()
        }
        if title == nil { pos = beforeTitle }
        var atLineEnd = true
        if match(Self.spaceAtEndOfLine) == nil {
            if title == nil {
                atLineEnd = false
            } else {
                title = nil
                pos = beforeTitle
                atLineEnd = match(Self.spaceAtEndOfLine) != nil
            }
        }
        if let m = match(Self.spaceAtEndOfLine) { pos = m.location + m.length }
        guard atLineEnd else { pos = start; return nil }
        let normalized = MarkdownSyntax.normalizeLabel(rawLabel)
        guard !normalized.isEmpty else { pos = start; return nil }
        if refmap[normalized] == nil {
            refmap[normalized] = (destination, title)
        }
        return (pos - start, rawLabel, destination, title)
    }

    // MARK: - Regexes

    private static func regex(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: o)
    }
    private static let spaceAtEndOfLine = regex("^ *(?:\\n|$)")
    private static let spnlRegex = regex("^ *(?:\\n *)?")
    private static let entityHere = regex("^&(?:#[xX][a-fA-F0-9]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});")
    private static let emailAutolink = regex("^<([a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)>")
    private static let autolink = regex("^<[A-Za-z][A-Za-z0-9.+-]{1,31}:[^<>\\x00-\\x20]*>")
    private static let linkTitle = regex("^(?:\"(\\\\[!\"#$%&'()*+,./:;<=>?@\\[\\\\\\]^_`{|}~-]|\\\\[^\\\\]|[^\\\\\"\\x00])*\"|'(\\\\[!\"#$%&'()*+,./:;<=>?@\\[\\\\\\]^_`{|}~-]|\\\\[^\\\\]|[^\\\\'\\x00])*'|\\((\\\\[!\"#$%&'()*+,./:;<=>?@\\[\\\\\\]^_`{|}~-]|\\\\[^\\\\]|[^\\\\()\\x00])*\\))")
    private static let linkDestinationBraces = regex("^(?:<(?:[^<>\\n\\\\\\x00]|\\\\.)*>)")
    private static let linkLabel = regex("^\\[(?:[^\\\\\\[\\]]|\\\\.){0,1000}\\]", [.dotMatchesLineSeparators])

    // MARK: - Main dispatch

    private func parseInline(_ block: MarkdownNode) -> Bool {
        guard let c = peek() else { return false }
        var handled = false
        switch c {
        case 0x0A: handled = parseNewline(block)
        case 0x5C: handled = parseBackslash(block)
        case 0x60: handled = parseBackticks(block)
        case 0x2A, 0x5F: handled = handleDelimiter(c, block)
        case 0x7E where options.contains(.strikethrough): handled = handleDelimiter(c, block)
        case 0x5B: handled = parseOpenBracket(block)
        case 0x21: handled = parseBang(block)
        case 0x5D: handled = parseCloseBracket(block)
        case 0x3C: handled = parseAutolink(block) || parseHTMLTag(block)
        case 0x26: handled = parseEntity(block)
        default: handled = parseString(block)
        }
        if !handled {
            appendText(pos, pos + 1, to: block)
            pos += 1
        }
        return true
    }

    private func isSpecial(_ c: UInt16) -> Bool {
        switch c {
        case 0x0A, 0x60, 0x5B, 0x5D, 0x5C, 0x21, 0x3C, 0x26, 0x2A, 0x5F: return true
        case 0x7E: return options.contains(.strikethrough)
        default: return false
        }
    }

    private func parseString(_ block: MarkdownNode) -> Bool {
        let start = pos
        while pos < subject.count && !isSpecial(subject[pos]) { pos += 1 }
        guard pos > start else { return false }
        appendText(start, pos, to: block)
        return true
    }

    private func parseNewline(_ block: MarkdownNode) -> Bool {
        let newlinePos = pos
        pos += 1
        var breakStart = newlinePos
        var hard = false
        if let last = block.lastChild, case .text = last.kind, last.literal.hasSuffix(" ") {
            let literal = last.literal
            var trimmed = literal
            while trimmed.hasSuffix(" ") { trimmed.removeLast() }
            let removed = literal.utf16.count - trimmed.utf16.count
            hard = removed >= 2
            last.literal = trimmed
            last.range.length = max(0, last.range.length - removed)
            if var m = textMap(last) { m.removeLast(min(removed, m.count)); setTextMap(last, m) }
            breakStart = newlinePos - removed
            if trimmed.isEmpty { last.unlink() }
        }
        let node = MarkdownNode(hard ? .hardBreak : .softBreak, range: sourceRange(breakStart, newlinePos + 1))
        if hard { node.markers = [node.range] }
        block.appendChild(node)
        // Gobble leading spaces on the next line
        while peek() == 0x20 { pos += 1 }
        return true
    }

    private func parseBackslash(_ block: MarkdownNode) -> Bool {
        let start = pos
        pos += 1
        if peek() == 0x0A {
            pos += 1
            let node = MarkdownNode(.hardBreak, range: sourceRange(start, pos))
            node.markers = [sourceRange(start, start + 1)]
            block.appendChild(node)
        } else if let c = peek(), MarkdownSyntax.isASCIIPunctuation(c) {
            pos += 1
            let node = appendText(start, pos, to: block, literal: string(start + 1, pos), literalMap: [sourceLocation(start + 1)])
            node.markers = [sourceRange(start, start + 1)]
        } else {
            appendText(start, start + 1, to: block)
        }
        return true
    }

    private func parseBackticks(_ block: MarkdownNode) -> Bool {
        let start = pos
        while peek() == 0x60 { pos += 1 }
        let tickCount = pos - start
        let afterOpen = pos
        while pos < subject.count {
            if subject[pos] == 0x60 {
                let runStart = pos
                while peek() == 0x60 { pos += 1 }
                if pos - runStart == tickCount {
                    var contentStart = afterOpen
                    var contentEnd = runStart
                    var content = string(contentStart, contentEnd).replacingOccurrences(of: "\n", with: " ")
                    if content.utf16.count >= 2, content.hasPrefix(" "), content.hasSuffix(" "), content.contains(where: { $0 != " " }) {
                        content = String(content.dropFirst().dropLast())
                        contentStart += 1
                        contentEnd -= 1
                    }
                    let node = MarkdownNode(.code, range: sourceRange(start, pos))
                    node.literal = content
                    node.markers = [sourceRange(start, contentStart), sourceRange(contentEnd, pos)]
                    block.appendChild(node)
                    return true
                }
            } else {
                pos += 1
            }
        }
        pos = afterOpen
        appendText(start, afterOpen, to: block)
        return true
    }

    private func parseEntity(_ block: MarkdownNode) -> Bool {
        guard let m = match(Self.entityHere), let decoded = MarkdownSyntax.decodeEntity(nsSubject.substring(with: m)) else { return false }
        let start = pos
        pos = m.location + m.length
        let location = sourceLocation(start)
        appendText(start, pos, to: block, literal: decoded, literalMap: Array(repeating: location, count: decoded.utf16.count))
        return true
    }

    private func parseAutolink(_ block: MarkdownNode) -> Bool {
        let start = pos
        if let m = match(Self.emailAutolink) {
            let address = nsSubject.substring(with: NSRange(location: m.location + 1, length: m.length - 2))
            pos = m.location + m.length
            addAutolink(start: start, end: pos, destination: "mailto:" + address, text: address, block: block)
            return true
        }
        if let m = match(Self.autolink) {
            let url = nsSubject.substring(with: NSRange(location: m.location + 1, length: m.length - 2))
            pos = m.location + m.length
            addAutolink(start: start, end: pos, destination: url, text: url, block: block)
            return true
        }
        return false
    }

    private func addAutolink(start: Int, end: Int, destination: String, text: String, block: MarkdownNode) {
        let link = MarkdownNode(.link(destination: destination, title: nil, kind: .autolink), range: sourceRange(start, end))
        link.markers = [sourceRange(start, start + 1), sourceRange(end - 1, end)]
        block.appendChild(link)
        appendText(start + 1, end - 1, to: link, literal: text)
    }

    private func parseHTMLTag(_ block: MarkdownNode) -> Bool {
        guard let m = match(MarkdownSyntax.htmlTagRegex) else { return false }
        let start = pos
        pos = m.location + m.length
        let node = MarkdownNode(.htmlInline, range: sourceRange(start, pos))
        node.literal = nsSubject.substring(with: m)
        node.markers = [node.range]
        block.appendChild(node)
        return true
    }

    // MARK: - Emphasis delimiters

    private func scalar(before index: Int) -> Unicode.Scalar? {
        guard index > 0 else { return nil }
        let c = subject[index - 1]
        if UTF16.isTrailSurrogate(c), index >= 2, UTF16.isLeadSurrogate(subject[index - 2]) {
            return Unicode.Scalar(0x10000 + ((UInt32(subject[index - 2]) - 0xD800) << 10) + (UInt32(c) - 0xDC00))
        }
        return Unicode.Scalar(c)
    }

    private func scalar(at index: Int) -> Unicode.Scalar? {
        guard index < subject.count else { return nil }
        let c = subject[index]
        if UTF16.isLeadSurrogate(c), index + 1 < subject.count, UTF16.isTrailSurrogate(subject[index + 1]) {
            return Unicode.Scalar(0x10000 + ((UInt32(c) - 0xD800) << 10) + (UInt32(subject[index + 1]) - 0xDC00))
        }
        return Unicode.Scalar(c)
    }

    private func scanDelimiters(_ c: UInt16) -> (count: Int, canOpen: Bool, canClose: Bool)? {
        let start = pos
        var count = 0
        while pos + count < subject.count && subject[pos + count] == c { count += 1 }
        guard count > 0 else { return nil }
        let before = scalar(before: start) ?? "\n"
        let after = scalar(at: start + count) ?? "\n"
        let afterWhitespace = MarkdownSyntax.isUnicodeWhitespace(after)
        let afterPunctuation = MarkdownSyntax.isUnicodePunctuation(after)
        let beforeWhitespace = MarkdownSyntax.isUnicodeWhitespace(before)
        let beforePunctuation = MarkdownSyntax.isUnicodePunctuation(before)
        let leftFlanking = !afterWhitespace && (!afterPunctuation || beforeWhitespace || beforePunctuation)
        let rightFlanking = !beforeWhitespace && (!beforePunctuation || afterWhitespace || afterPunctuation)
        if c == 0x5F {
            return (count, leftFlanking && (!rightFlanking || beforePunctuation), rightFlanking && (!leftFlanking || afterPunctuation))
        }
        return (count, leftFlanking, rightFlanking)
    }

    private func handleDelimiter(_ c: UInt16, _ block: MarkdownNode) -> Bool {
        guard let scan = scanDelimiters(c) else { return false }
        let start = pos
        pos += scan.count
        let node = appendText(start, pos, to: block)
        // GFM strikethrough: only runs of one or two tildes delimit
        if c == 0x7E && scan.count > 2 { return true }
        if scan.canOpen || scan.canClose {
            let d = Delimiter(char: c, count: scan.count, node: node, previous: delimiters, canOpen: scan.canOpen, canClose: scan.canClose)
            delimiters?.next = d
            delimiters = d
        }
        return true
    }

    private func removeDelimiter(_ d: Delimiter) {
        d.previous?.next = d.next
        if let next = d.next {
            next.previous = d.previous
        } else {
            delimiters = d.previous
        }
    }

    private func processEmphasis(stackBottom: Delimiter?) {
        var openersBottom = [Delimiter?](repeating: stackBottom, count: 16)
        var closer = delimiters
        // Start from the first delimiter above stackBottom
        while let c = closer, c.previous !== stackBottom { closer = c.previous }

        while let currentCloser = closer {
            guard currentCloser.canClose else { closer = currentCloser.next; continue }
            let cc = currentCloser.char
            let bottomIndex: Int
            switch cc {
            case 0x5F: bottomIndex = 2 + (currentCloser.canOpen ? 3 : 0) + currentCloser.originalCount % 3
            case 0x2A: bottomIndex = 8 + (currentCloser.canOpen ? 3 : 0) + currentCloser.originalCount % 3
            default: bottomIndex = 14 + min(currentCloser.originalCount, 2) - 1
            }
            var opener = currentCloser.previous
            var openerFound = false
            while let o = opener, o !== stackBottom, o !== openersBottom[bottomIndex] {
                if cc == 0x7E {
                    if o.char == cc && o.canOpen && o.count == currentCloser.count { openerFound = true; break }
                } else {
                    let oddMatch = (currentCloser.canOpen || o.canClose) && currentCloser.originalCount % 3 != 0 &&
                        (o.originalCount + currentCloser.originalCount) % 3 == 0
                    if o.char == cc && o.canOpen && !oddMatch { openerFound = true; break }
                }
                opener = o.previous
            }
            let oldCloser = currentCloser
            if openerFound, let o = opener {
                let used: Int
                let kind: MarkdownNode.Kind
                if cc == 0x7E {
                    used = currentCloser.count
                    kind = .strikethrough
                } else {
                    used = (currentCloser.count >= 2 && o.count >= 2) ? 2 : 1
                    kind = used == 1 ? .emphasis : .strong
                }
                let openerNode = o.node
                let closerNode = currentCloser.node
                o.count -= used
                currentCloser.count -= used
                // Delimiters used: the end of the opener run, the start of the closer run
                let openMarker = NSRange(location: openerNode.range.location + openerNode.range.length - used, length: used)
                let closeMarker = NSRange(location: closerNode.range.location, length: used)
                openerNode.literal = String(openerNode.literal.dropLast(used))
                openerNode.range.length -= used
                closerNode.literal = String(closerNode.literal.dropFirst(used))
                closerNode.range.location += used
                closerNode.range.length -= used
                if let m = textMap(openerNode) { setTextMap(openerNode, Array(m.dropLast(used))) }
                if let m = textMap(closerNode) { setTextMap(closerNode, Array(m.dropFirst(used))) }

                let emphasis = MarkdownNode(kind, range: NSRange(location: openMarker.location, length: closeMarker.location + used - openMarker.location))
                emphasis.markers = [openMarker, closeMarker]
                var node = openerNode.nextSibling
                while let n = node, n !== closerNode {
                    let next = n.nextSibling
                    emphasis.appendChild(n)
                    node = next
                }
                openerNode.insertAfter(emphasis)

                // Remove delimiters between opener and closer
                var between = currentCloser.previous
                while let b = between, b !== o {
                    let prev = b.previous
                    removeDelimiter(b)
                    between = prev
                }
                if o.count == 0 {
                    openerNode.unlink()
                    removeDelimiter(o)
                }
                if currentCloser.count == 0 {
                    closerNode.unlink()
                    let next = currentCloser.next
                    removeDelimiter(currentCloser)
                    closer = next
                }
            } else {
                closer = currentCloser.next
                openersBottom[bottomIndex] = oldCloser.previous
                if !oldCloser.canOpen {
                    removeDelimiter(oldCloser)
                }
            }
        }
        while let d = delimiters, d !== stackBottom {
            removeDelimiter(d)
        }
    }

    // MARK: - Links and images

    private func parseOpenBracket(_ block: MarkdownNode) -> Bool {
        let start = pos
        pos += 1
        let node = appendText(start, pos, to: block)
        addBracket(node, index: start, isImage: false)
        return true
    }

    private func parseBang(_ block: MarkdownNode) -> Bool {
        let start = pos
        pos += 1
        if peek() == 0x5B {
            pos += 1
            let node = appendText(start, pos, to: block)
            addBracket(node, index: start + 1, isImage: true)
        } else {
            appendText(start, pos, to: block)
        }
        return true
    }

    private func addBracket(_ node: MarkdownNode, index: Int, isImage: Bool) {
        brackets?.bracketAfter = true
        brackets = Bracket(node: node, previous: brackets, previousDelimiter: delimiters, index: index, isImage: isImage)
    }

    private func removeBracket() {
        brackets = brackets?.previous
    }

    @discardableResult
    private func spnl() -> Bool {
        if let m = match(Self.spnlRegex) { pos = m.location + m.length }
        return true
    }

    private func parseLinkLabel() -> Int {
        guard let m = match(Self.linkLabel), m.length <= 1001 else { return 0 }
        pos = m.location + m.length
        return m.length
    }

    private func parseLinkTitle() -> String? {
        guard let m = match(Self.linkTitle) else { return nil }
        pos = m.location + m.length
        let raw = nsSubject.substring(with: NSRange(location: m.location + 1, length: m.length - 2))
        return MarkdownSyntax.unescape(raw)
    }

    private func parseLinkDestination() -> String? {
        if let m = match(Self.linkDestinationBraces) {
            pos = m.location + m.length
            return MarkdownSyntax.unescape(nsSubject.substring(with: NSRange(location: m.location + 1, length: m.length - 2)))
        }
        if peek() == 0x3C { return nil }
        let start = pos
        var openParens = 0
        while let c = peek() {
            if c == 0x5C, let n = peek(1), MarkdownSyntax.isASCIIPunctuation(n) {
                pos += 2
            } else if c == 0x28 {
                pos += 1
                openParens += 1
            } else if c == 0x29 {
                if openParens < 1 { break }
                pos += 1
                openParens -= 1
            } else if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0B || c == 0x0C || c == 0x0D || c < 0x20 || c == 0x7F {
                break
            } else {
                pos += 1
            }
        }
        if pos == start && peek() != 0x29 { return nil }
        if openParens != 0 { return nil }
        return MarkdownSyntax.unescape(string(start, pos))
    }

    private func parseCloseBracket(_ block: MarkdownNode) -> Bool {
        let closeStart = pos
        pos += 1
        let startpos = pos
        guard let opener = brackets else {
            appendText(closeStart, pos, to: block)
            return true
        }
        guard opener.active else {
            appendText(closeStart, pos, to: block)
            removeBracket()
            return true
        }
        let isImage = opener.isImage
        let savepos = pos
        var destination: String? = nil
        var title: String? = nil
        var matched = false
        var linkKind: LinkKind = .inline

        if peek() == 0x28 {
            pos += 1
            spnl()
            if let dest = parseLinkDestination() {
                let beforeTitle = pos
                spnl()
                var t: String? = nil
                if pos > beforeTitle, let previous = subject[safe: pos - 1], previous == 0x20 || previous == 0x0A || previous == 0x09 {
                    t = parseLinkTitle()
                }
                spnl()
                if peek() == 0x29 {
                    pos += 1
                    matched = true
                    destination = dest
                    title = t
                }
            }
            if !matched { pos = savepos }
        }

        var footnoteLabel: String? = nil
        if !matched {
            let beforeLabel = pos
            let n = parseLinkLabel()
            var refLabel: String? = nil
            if n > 2 {
                refLabel = string(beforeLabel + 1, beforeLabel + n - 1)
            } else if !opener.bracketAfter {
                refLabel = string(opener.index + 1, closeStart)
            }
            if n == 0 { pos = savepos }
            if let label = refLabel {
                // GFM footnote reference: [^label] with a matching definition
                if options.contains(.footnotes), n == 0, label.hasPrefix("^"),
                   footnoteLabels.contains(MarkdownSyntax.normalizeLabel(String(label.dropFirst()))) {
                    footnoteLabel = String(label.dropFirst())
                } else if let ref = refmap[MarkdownSyntax.normalizeLabel(label)] {
                    destination = ref.destination
                    title = ref.title
                    matched = true
                    linkKind = .reference
                }
            }
        }

        if let label = footnoteLabel {
            let node = MarkdownNode(.footnoteReference(label: label), range: sourceRange(opener.index, pos))
            node.markers = [node.range]
            node.literal = label
            var child = opener.node.nextSibling
            while let c = child { let next = c.nextSibling; c.unlink(); child = next }
            if isImage {
                // `![^1]` is a literal "!" followed by the footnote reference
                opener.node.literal = "!"
                opener.node.range.length = 1
                setTextMap(opener.node, [opener.node.range.location])
            } else {
                opener.node.unlink()
            }
            block.appendChild(node)
            processEmphasis(stackBottom: opener.previousDelimiter)
            removeBracket()
            return true
        }

        guard matched, let dest = destination else {
            removeBracket()
            pos = startpos
            appendText(closeStart, startpos, to: block)
            return true
        }

        let start = isImage ? opener.index - 1 : opener.index
        let kind: MarkdownNode.Kind = isImage ? .image(destination: dest, title: title) : .link(destination: dest, title: title, kind: linkKind)
        let node = MarkdownNode(kind, range: sourceRange(start, pos))
        node.markers = [sourceRange(start, opener.index + 1), sourceRange(closeStart, pos)]
        var child = opener.node.nextSibling
        while let c = child {
            let next = c.nextSibling
            node.appendChild(c)
            child = next
        }
        block.appendChild(node)
        processEmphasis(stackBottom: opener.previousDelimiter)
        removeBracket()
        opener.node.unlink()
        if !isImage {
            var o = brackets
            while let b = o {
                if !b.isImage { b.active = false }
                o = b.previous
            }
        }
        return true
    }

    // MARK: - Post passes

    /// Merges adjacent text nodes (and their source maps) throughout the inline tree.
    private func mergeText(in node: MarkdownNode) {
        var child = node.firstChild
        while let c = child {
            if case .text = c.kind {
                while let next = c.nextSibling, case .text = next.kind {
                    c.literal += next.literal
                    let end = next.range.location + next.range.length
                    c.range = NSRange(location: c.range.location, length: max(c.range.length, end - c.range.location))
                    c.markers += next.markers
                    setTextMap(c, (textMap(c) ?? []) + (textMap(next) ?? []))
                    next.unlink()
                }
            } else {
                mergeText(in: c)
            }
            child = c.nextSibling
        }
    }

    private func recordFootnoteOrder(_ node: MarkdownNode) {
        node.walk { n in
            if case .footnoteReference(let label) = n.kind {
                let normalized = MarkdownSyntax.normalizeLabel(label)
                if !footnoteOrder.contains(normalized) { footnoteOrder.append(normalized) }
            }
        }
    }

    // MARK: GFM extended autolinks

    private func applyExtendedAutolinks(in node: MarkdownNode) {
        var child = node.firstChild
        while let c = child {
            let next = c.nextSibling
            switch c.kind {
            case .text:
                splitAutolinks(c)
            case .link, .image, .code, .htmlInline:
                break
            default:
                applyExtendedAutolinks(in: c)
            }
            child = next
        }
    }

    private func splitAutolinks(_ textNode: MarkdownNode) {
        let literal = Array(textNode.literal.utf16)
        let literalMap = textMap(textNode) ?? []
        guard literal.count == literalMap.count,
              literal.contains(where: { $0 == 0x3A || $0 == 0x40 || $0 == 0x2E }) else { return }
        var segments: [(start: Int, end: Int, destination: String?)] = []
        var i = 0
        var segmentStart = 0
        while i < literal.count {
            if let link = matchExtendedAutolink(literal, at: i) {
                if i > segmentStart { segments.append((segmentStart, i, nil)) }
                segments.append((i, link.end, link.destination))
                i = link.end
                segmentStart = i
            } else {
                i += 1
            }
        }
        guard segments.contains(where: { $0.destination != nil }) else { return }
        if segmentStart < literal.count { segments.append((segmentStart, literal.count, nil)) }

        func range(_ a: Int, _ b: Int) -> NSRange {
            NSRange(location: literalMap[a], length: literalMap[b - 1] + 1 - literalMap[a])
        }
        var anchor = textNode
        for segment in segments {
            let text = String(utf16CodeUnits: Array(literal[segment.start..<segment.end]), count: segment.end - segment.start)
            let piece: MarkdownNode
            if let destination = segment.destination {
                piece = MarkdownNode(.link(destination: destination, title: nil, kind: .extendedAutolink), range: range(segment.start, segment.end))
                let inner = MarkdownNode(.text, range: piece.range)
                inner.literal = text
                piece.appendChild(inner)
            } else {
                piece = MarkdownNode(.text, range: range(segment.start, segment.end))
                piece.literal = text
            }
            anchor.insertAfter(piece)
            anchor = piece
        }
        textNode.unlink()
    }

    private func isAlnum(_ c: UInt16) -> Bool {
        (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }

    /// Recognises a GFM extended autolink starting at `i` (www., http(s)://, mailto:/xmpp: or bare email).
    private func matchExtendedAutolink(_ s: [UInt16], at i: Int) -> (end: Int, destination: String)? {
        // www. must follow the start, whitespace, or one of * _ ~ (; a scheme must not be preceded by a letter
        let previous: UInt16? = i > 0 ? s[i - 1] : nil
        let wwwBoundary = previous.map { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x2A || $0 == 0x5F || $0 == 0x7E || $0 == 0x28 } ?? true
        let schemeBoundary = previous.map { !(($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)) } ?? true
        func hasPrefix(_ prefix: String) -> Bool {
            let p = Array(prefix.utf16)
            guard i + p.count <= s.count else { return false }
            for (k, ch) in p.enumerated() {
                var c = s[i + k]
                if c >= 0x41 && c <= 0x5A { c += 0x20 }
                if c != ch { return false }
            }
            return true
        }
        var schemeEnd: Int? = nil
        var prefixText = ""
        if wwwBoundary && hasPrefix("www.") {
            schemeEnd = i
            prefixText = "http://"
        } else if schemeBoundary && hasPrefix("https://") {
            schemeEnd = i + 8
        } else if schemeBoundary && hasPrefix("http://") {
            schemeEnd = i + 7
        } else if schemeBoundary && hasPrefix("ftp://") {
            schemeEnd = i + 6
        }
        if let domainStart = schemeEnd {
            // Scheme URLs may use single-label hosts (e.g. http://localhost); www. needs a period
            guard let domainEnd = validDomain(s, from: domainStart, requirePeriod: prefixText == "http://"), domainEnd > domainStart else { return nil }
            var end = domainEnd
            while end < s.count && s[end] != 0x20 && s[end] != 0x09 && s[end] != 0x0A && s[end] != 0x3C { end += 1 }
            end = trimAutolinkEnd(s, start: i, end: end)
            guard end > domainStart else { return nil }
            let text = String(utf16CodeUnits: Array(s[i..<end]), count: end - i)
            return (end, prefixText + text)
        }
        if schemeBoundary && (hasPrefix("mailto:") || hasPrefix("xmpp:")) {
            let schemeLength = hasPrefix("mailto:") ? 7 : 5
            if let email = matchEmail(s, at: i + schemeLength) {
                var end = email.end
                if schemeLength == 5, end < s.count, s[end] == 0x2F {
                    // xmpp resource
                    var k = end + 1
                    while k < s.count && (isAlnum(s[k]) || s[k] == 0x40 || s[k] == 0x2E) { k += 1 }
                    end = k
                    while end > email.end && s[end - 1] == 0x2E { end -= 1 }
                }
                let text = String(utf16CodeUnits: Array(s[i..<end]), count: end - i)
                return (end, text)
            }
            return nil
        }
        return matchEmail(s, at: i)
    }

    /// A valid GFM domain: alnum/_/- segments separated by periods, at least one period,
    /// no underscores in the last two segments. Returns the end index.
    private func validDomain(_ s: [UInt16], from start: Int, requirePeriod: Bool) -> Int? {
        var i = start
        var segments: [(hasUnderscore: Bool, length: Int)] = []
        var current = (hasUnderscore: false, length: 0)
        while i < s.count {
            let c = s[i]
            if isAlnum(c) || c == 0x2D || c >= 0x80 {
                current.length += 1
            } else if c == 0x5F {
                current.hasUnderscore = true
                current.length += 1
            } else if c == 0x2E, i + 1 < s.count, isAlnum(s[i + 1]) || s[i + 1] == 0x2D || s[i + 1] == 0x5F || s[i + 1] >= 0x80 {
                segments.append(current)
                current = (false, 0)
            } else {
                break
            }
            i += 1
        }
        segments.append(current)
        guard segments.count >= (requirePeriod ? 2 : 1), segments.allSatisfy({ $0.length > 0 }) else { return nil }
        if segments[segments.count - 1].hasUnderscore || (segments.count >= 2 && segments[segments.count - 2].hasUnderscore) { return nil }
        return i
    }

    private func trimAutolinkEnd(_ s: [UInt16], start: Int, end: Int) -> Int {
        var end = end
        while end > start {
            let c = s[end - 1]
            if c == 0x3F || c == 0x21 || c == 0x2E || c == 0x2C || c == 0x3A || c == 0x2A || c == 0x5F || c == 0x7E || c == 0x27 || c == 0x22 {
                end -= 1
            } else if c == 0x29 {
                var opens = 0, closes = 0
                for k in start..<end {
                    if s[k] == 0x28 { opens += 1 } else if s[k] == 0x29 { closes += 1 }
                }
                if closes > opens { end -= 1 } else { break }
            } else if c == 0x3B {
                // Trailing entity-like reference `&name;` is excluded
                var k = end - 2
                while k > start && isAlnum(s[k]) { k -= 1 }
                if k >= start && s[k] == 0x26 && k < end - 2 { end = k } else { break }
            } else {
                break
            }
        }
        return end
    }

    /// GFM extended email autolink: local part, `@`, domain with at least one period.
    private func matchEmail(_ s: [UInt16], at i: Int) -> (end: Int, destination: String)? {
        func isLocal(_ c: UInt16) -> Bool { isAlnum(c) || c == 0x2E || c == 0x2D || c == 0x5F || c == 0x2B }
        // Start only at the beginning of a run of local-part characters
        guard i < s.count, isLocal(s[i]), i == 0 || !isLocal(s[i - 1]) else { return nil }
        var j = i
        while j < s.count && isLocal(s[j]) { j += 1 }
        guard j < s.count, s[j] == 0x40, j > i else { return nil }
        var k = j + 1
        var periods = 0
        let domainStart = k
        while k < s.count {
            let c = s[k]
            if isAlnum(c) || c == 0x2D || c == 0x5F { k += 1 }
            else if c == 0x2E, k + 1 < s.count, isAlnum(s[k + 1]) || s[k + 1] == 0x2D || s[k + 1] == 0x5F { periods += 1; k += 1 }
            else { break }
        }
        guard periods >= 1, k > domainStart else { return nil }
        let last = s[k - 1]
        guard last != 0x2D && last != 0x5F else { return nil }
        let text = String(utf16CodeUnits: Array(s[i..<k]), count: k - i)
        return (k, "mailto:" + text)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        index >= 0 && index < count ? self[index] : nil
    }
}
