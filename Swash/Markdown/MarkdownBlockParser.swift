//
//  MarkdownBlockParser.swift
//  Swash
//
//  Block-structure phase of the Markdown parser. Follows the CommonMark 0.31 reference
//  algorithm (as implemented by commonmark.js), extended with GFM tables, footnote
//  definitions and task list items, plus Swash's GitHub alerts and YAML front matter.
//  All positions are UTF-16 offsets into the source.
//

import Foundation

/// Inline source for a paragraph, heading or table cell: the content characters with the
/// source offset of each one (container prefixes and stripped whitespace are not included).
struct MarkdownInlineSource {
    var chars: [UInt16] = []
    var map: [Int] = []
}

final class MarkdownBlockParser {
    private enum BlockType {
        case document, frontMatter, blockQuote, list, item, heading, thematicBreak
        case codeBlock, htmlBlock, paragraph, table, footnoteDefinition, other
    }

    private struct ListData {
        var isOrdered: Bool
        var bulletChar: UInt16
        var start: Int
        var delimiter: UInt16
        var padding: Int
        var markerOffset: Int
    }

    private final class BlockState {
        /// Strong reference: keeps discarded nodes alive so their ObjectIdentifier is never reused mid-parse
        let node: MarkdownNode
        init(node: MarkdownNode) { self.node = node }
        var open = true
        var content = MarkdownInlineSource()
        var startLine = 0
        var endLine = -1
        var endOffset = 0
        var listData: ListData?
        var isFenced = false
        var fenceChar: UInt16 = 0
        var fenceLength = 0
        var fenceOffset = 0
        var htmlBlockType = 0
        var headingLevel = 0
        var setext = false
        var alignments: [TableAlignment] = []
        var columnCount = 0
    }

    let source: String
    let options: MarkdownParseOptions
    private let chars: [UInt16]
    private var states: [ObjectIdentifier: BlockState] = [:]
    private var inlineSources: [ObjectIdentifier: (cell: MarkdownNode, source: MarkdownInlineSource)] = [:]
    private let root: MarkdownNode
    private var tip: MarkdownNode
    private var oldtip: MarkdownNode
    private var lastMatchedContainer: MarkdownNode
    private var allClosed = true

    private var lineNumber = -1
    private var lineStart = 0
    private var lineLength = 0
    private var offset = 0
    private var column = 0
    private var nextNonspace = 0
    private var nextNonspaceColumn = 0
    private var indent = 0
    private var indented = false
    private var blank = false
    private var partiallyConsumedTab = false

    private(set) var refmap: [String: (destination: String, title: String?)] = [:]
    private var footnoteLabels: Set<String> = []
    private lazy var inlineParser = MarkdownInlineParser(options: options)

    init(source: String, options: MarkdownParseOptions) {
        self.source = source
        self.options = options
        var units = Array(source.utf16)
        // CommonMark: U+0000 is replaced by U+FFFD
        for i in units.indices where units[i] == 0 { units[i] = 0xFFFD }
        self.chars = units
        root = MarkdownNode(.document, range: NSRange(location: 0, length: units.count))
        tip = root
        oldtip = root
        lastMatchedContainer = root
        states[ObjectIdentifier(root)] = BlockState(node: root)
    }

    // MARK: - Entry point

    func parse() -> MarkdownDocument {
        var position = 0
        if options.contains(.frontMatter) {
            position = parseFrontMatter()
        }
        while position <= chars.count {
            var end = position
            while end < chars.count && chars[end] != 0x0A && chars[end] != 0x0D { end += 1 }
            lineStart = position
            lineLength = end - position
            incorporateLine()
            if end >= chars.count { break }
            position = end + ((chars[end] == 0x0D && end + 1 < chars.count && chars[end + 1] == 0x0A) ? 2 : 1)
            if position == chars.count { break }   // trailing newline: no extra empty line
        }
        while true {
            let current = tip
            finalize(current)
            if current === root { break }
        }
        postProcess(root)
        processInlines(root)
        return MarkdownDocument(source: source, root: root, linkReferences: refmap, footnoteOrder: inlineParser.footnoteOrder)
    }

    // MARK: - Helpers

    private func state(_ node: MarkdownNode) -> BlockState {
        let id = ObjectIdentifier(node)
        if let s = states[id] { return s }
        let s = BlockState(node: node)
        states[id] = s
        return s
    }

    private func type(_ node: MarkdownNode) -> BlockType {
        switch node.kind {
        case .document: return .document
        case .frontMatter: return .frontMatter
        case .blockQuote, .alert: return .blockQuote
        case .list: return .list
        case .listItem: return .item
        case .heading: return .heading
        case .thematicBreak: return .thematicBreak
        case .codeBlock: return .codeBlock
        case .htmlBlock: return .htmlBlock
        case .paragraph: return .paragraph
        case .table: return .table
        case .footnoteDefinition: return .footnoteDefinition
        default: return .other
        }
    }

    /// Character at `i` in the current line, or nil past its end.
    private func peek(_ i: Int) -> UInt16? {
        i >= 0 && i < lineLength ? chars[lineStart + i] : nil
    }

    private func isSpaceOrTab(_ c: UInt16?) -> Bool { c == 0x20 || c == 0x09 }

    private func lineSlice(from i: Int) -> String {
        guard i < lineLength else { return "" }
        return String(utf16CodeUnits: Array(chars[(lineStart + i)..<(lineStart + lineLength)]), count: lineLength - i)
    }

    private func findNextNonspace() {
        var i = offset
        var cols = column
        while let c = peek(i) {
            if c == 0x20 { i += 1; cols += 1 }
            else if c == 0x09 { i += 1; cols += 4 - (cols % 4) }
            else { break }
        }
        blank = peek(i) == nil
        nextNonspace = i
        nextNonspaceColumn = cols
        indent = nextNonspaceColumn - column
        indented = indent >= 4
    }

    private func advanceNextNonspace() {
        offset = nextNonspace
        column = nextNonspaceColumn
        partiallyConsumedTab = false
    }

    private func advanceOffset(_ count: Int, columns: Bool) {
        var count = count
        while count > 0, let c = peek(offset) {
            if c == 0x09 {
                let charsToTab = 4 - (column % 4)
                if columns {
                    partiallyConsumedTab = charsToTab > count
                    let charsToAdvance = min(charsToTab, count)
                    column += charsToAdvance
                    offset += partiallyConsumedTab ? 0 : 1
                    count -= charsToAdvance
                } else {
                    partiallyConsumedTab = false
                    column += charsToTab
                    offset += 1
                    count -= 1
                }
            } else {
                partiallyConsumedTab = false
                offset += 1
                column += 1
                count -= 1
            }
        }
    }

    private func addLine() {
        let s = state(tip)
        if partiallyConsumedTab {
            offset += 1
            let charsToTab = 4 - (column % 4)
            for _ in 0..<charsToTab {
                s.content.chars.append(0x20)
                s.content.map.append(lineStart + offset - 1)
            }
        }
        var i = offset
        while i < lineLength {
            s.content.chars.append(chars[lineStart + i])
            s.content.map.append(lineStart + i)
            i += 1
        }
        s.content.chars.append(0x0A)
        s.content.map.append(lineStart + lineLength)
    }

    @discardableResult
    private func addChild(_ kind: MarkdownNode.Kind, at lineOffset: Int) -> MarkdownNode {
        while !canContain(tip, kind) {
            finalize(tip)
        }
        let node = MarkdownNode(kind, range: NSRange(location: lineStart + lineOffset, length: 0))
        let s = state(node)
        s.startLine = lineNumber
        s.endLine = lineNumber
        s.endOffset = lineStart + lineLength
        tip.appendChild(node)
        tip = node
        return node
    }

    private func canContain(_ parent: MarkdownNode, _ child: MarkdownNode.Kind) -> Bool {
        let isItem: Bool
        if case .listItem = child { isItem = true } else { isItem = false }
        switch type(parent) {
        case .document, .blockQuote, .footnoteDefinition, .item: return !isItem
        case .list: return isItem
        default: return false
        }
    }

    private func acceptsLines(_ node: MarkdownNode) -> Bool {
        switch type(node) {
        case .paragraph, .codeBlock, .htmlBlock, .table: return true
        default: return false
        }
    }

    private func isParagraphLike(_ node: MarkdownNode) -> Bool {
        let t = type(node)
        return t == .paragraph || t == .table
    }

    /// Marks `node` and its ancestors as extending to the end of the current line.
    private func touch(_ node: MarkdownNode?) {
        var current = node
        let end = lineStart + lineLength
        while let n = current, n !== root {
            let s = state(n)
            if s.endLine < lineNumber || s.endOffset < end {
                s.endLine = lineNumber
                s.endOffset = end
            }
            current = n.parent
        }
    }

    private func closeUnmatchedBlocks() {
        if !allClosed {
            while oldtip !== lastMatchedContainer {
                guard let parent = oldtip.parent else { break }
                finalize(oldtip)
                oldtip = parent
            }
            allClosed = true
        }
    }

    // MARK: - Line processing

    private func incorporateLine() {
        var allMatched = true
        var container = root
        oldtip = tip
        offset = 0
        column = 0
        blank = false
        partiallyConsumedTab = false
        lineNumber += 1

        while let last = container.lastChild, state(last).open, last.kind.isBlock {
            container = last
            findNextNonspace()
            switch continueBlock(container) {
            case 0: continue
            case 1:
                allMatched = false
            default:
                return   // line fully consumed (closing code fence)
            }
            break
        }
        if !allMatched, let parent = container.parent {
            container = parent
        }
        allClosed = (container === oldtip)
        lastMatchedContainer = container

        var matchedLeaf = !isParagraphLike(container) && acceptsLines(container)
        while !matchedLeaf {
            findNextNonspace()
            if !indented, let c = peek(nextNonspace), !maybeSpecial(c) {
                advanceNextNonspace()
                break
            }
            var started = false
            for start in 0..<10 {
                let result = tryBlockStart(start, container: container)
                if result == 1 {
                    container = tip
                    started = true
                    break
                } else if result == 2 {
                    container = tip
                    matchedLeaf = true
                    started = true
                    break
                }
            }
            if !started {
                advanceNextNonspace()
                break
            }
        }

        if !allClosed && !blank && type(tip) == .paragraph {
            // Lazy paragraph continuation
            addLine()
            touch(tip)
        } else {
            closeUnmatchedBlocks()
            let t = type(container)
            if acceptsLines(container) {
                if t == .table {
                    if !blank && offset < lineLength {
                        addTableRow(to: container)
                        touch(container)
                    }
                } else {
                    addLine()
                    if !blank { touch(container) }
                    if t == .htmlBlock {
                        let htmlType = state(container).htmlBlockType
                        if htmlType >= 1 && htmlType <= 5 && MarkdownSyntax.htmlBlockClose(htmlType, lineSlice(from: offset)) {
                            touch(container)
                            finalize(container)
                        }
                    }
                }
            } else if offset < lineLength && !blank {
                let paragraph = addChild(.paragraph, at: nextNonspace)
                advanceNextNonspace()
                addLine()
                paragraph.range.location = lineStart + offset
                touch(paragraph)
            } else if !blank {
                touch(container)
            }
        }
    }

    private func maybeSpecial(_ c: UInt16) -> Bool {
        switch c {
        case 0x23, 0x60, 0x7E, 0x2A, 0x2B, 0x5F, 0x3D, 0x3C, 0x3E, 0x2D, 0x7C, 0x3A, 0x5B: return true // # ` ~ * + _ = < > - | : [
        case 0x30...0x39: return true
        default: return false
        }
    }

    /// 0 = matched, 1 = not matched, 2 = line consumed
    private func continueBlock(_ container: MarkdownNode) -> Int {
        let s = state(container)
        switch type(container) {
        case .document, .list:
            return 0
        case .blockQuote:
            if !indented && peek(nextNonspace) == 0x3E {
                let markerStart = nextNonspace
                advanceNextNonspace()
                advanceOffset(1, columns: false)
                if isSpaceOrTab(peek(offset)) { advanceOffset(1, columns: true) }
                container.markers.append(NSRange(location: lineStart + markerStart, length: offset - markerStart))
                touch(container)
                return 0
            }
            return 1
        case .item:
            guard let data = s.listData else { return 1 }
            if blank {
                if container.firstChild == nil { return 1 }
                advanceNextNonspace()
            } else if indent >= data.markerOffset + data.padding {
                advanceOffset(data.markerOffset + data.padding, columns: true)
            } else {
                return 1
            }
            return 0
        case .footnoteDefinition:
            if blank {
                if container.firstChild == nil { return 1 }
                advanceNextNonspace()
            } else if indent >= 4 {
                advanceOffset(4, columns: true)
            } else {
                return 1
            }
            return 0
        case .heading, .thematicBreak, .frontMatter, .other:
            return 1
        case .codeBlock:
            if s.isFenced {
                if indent <= 3, peek(nextNonspace) == s.fenceChar {
                    var j = nextNonspace
                    while peek(j) == s.fenceChar { j += 1 }
                    let length = j - nextNonspace
                    var k = j
                    while isSpaceOrTab(peek(k)) { k += 1 }
                    if length >= s.fenceLength && peek(k) == nil {
                        container.markers.append(NSRange(location: lineStart + nextNonspace, length: lineLength - nextNonspace))
                        touch(container)
                        finalize(container)
                        return 2
                    }
                }
                var i = s.fenceOffset
                while i > 0 && isSpaceOrTab(peek(offset)) {
                    advanceOffset(1, columns: true)
                    i -= 1
                }
            } else {
                if indent >= 4 {
                    advanceOffset(4, columns: true)
                } else if blank {
                    advanceNextNonspace()
                } else {
                    return 1
                }
            }
            return 0
        case .htmlBlock:
            return (blank && (s.htmlBlockType == 6 || s.htmlBlockType == 7)) ? 1 : 0
        case .paragraph, .table:
            return blank ? 1 : 0
        }
    }

    // MARK: - Block starts

    /// 0 = no match, 1 = matched container start, 2 = matched leaf start
    private func tryBlockStart(_ index: Int, container: MarkdownNode) -> Int {
        switch index {
        case 0: return startBlockQuote()
        case 1: return startATXHeading()
        case 2: return startFencedCode()
        case 3: return startHTMLBlock(container)
        case 4: return startTable(container)
        case 5: return startSetextHeading(container)
        case 6: return startThematicBreak()
        case 7: return startFootnoteDefinition(container)
        case 8: return startListItem(container)
        case 9: return startIndentedCode()
        default: return 0
        }
    }

    private func startBlockQuote() -> Int {
        guard !indented, peek(nextNonspace) == 0x3E else { return 0 }
        let markerStart = nextNonspace
        advanceNextNonspace()
        advanceOffset(1, columns: false)
        if isSpaceOrTab(peek(offset)) { advanceOffset(1, columns: true) }
        closeUnmatchedBlocks()
        let quote = addChild(.blockQuote, at: markerStart)
        quote.markers.append(NSRange(location: lineStart + markerStart, length: offset - markerStart))
        touch(quote)
        return 1
    }

    private func startATXHeading() -> Int {
        guard !indented, peek(nextNonspace) == 0x23 else { return 0 }
        var level = 0
        var j = nextNonspace
        while peek(j) == 0x23 { level += 1; j += 1 }
        guard level <= 6, peek(j) == nil || isSpaceOrTab(peek(j)) else { return 0 }
        let markerStart = nextNonspace
        advanceNextNonspace()
        advanceOffset(level, columns: false)
        while isSpaceOrTab(peek(offset)) { advanceOffset(1, columns: false) }
        closeUnmatchedBlocks()
        let heading = addChild(.heading(level: level, setext: false), at: markerStart)
        heading.markers.append(NSRange(location: lineStart + markerStart, length: offset - markerStart))

        // Content, minus an optional closing sequence of #s
        var contentEnd = lineLength
        while contentEnd > offset && isSpaceOrTab(peek(contentEnd - 1)) { contentEnd -= 1 }
        var hashStart = contentEnd
        while hashStart > offset && peek(hashStart - 1) == 0x23 { hashStart -= 1 }
        if hashStart < contentEnd && (hashStart == offset || isSpaceOrTab(peek(hashStart - 1))) {
            var closingStart = hashStart
            while closingStart > offset && isSpaceOrTab(peek(closingStart - 1)) { closingStart -= 1 }
            heading.markers.append(NSRange(location: lineStart + closingStart, length: lineLength - closingStart))
            contentEnd = closingStart
        }
        let s = state(heading)
        s.headingLevel = level
        for i in offset..<max(offset, contentEnd) {
            s.content.chars.append(chars[lineStart + i])
            s.content.map.append(lineStart + i)
        }
        touch(heading)
        advanceOffset(lineLength - offset, columns: false)
        return 2
    }

    private func startFencedCode() -> Int {
        guard !indented, let c = peek(nextNonspace), c == 0x60 || c == 0x7E else { return 0 }
        var j = nextNonspace
        while peek(j) == c { j += 1 }
        let fenceLength = j - nextNonspace
        guard fenceLength >= 3 else { return 0 }
        if c == 0x60 {
            var k = j
            while let ch = peek(k) {
                if ch == 0x60 { return 0 }
                k += 1
            }
        }
        closeUnmatchedBlocks()
        let markerStart = nextNonspace
        let code = addChild(.codeBlock(fenced: true, info: ""), at: markerStart)
        let s = state(code)
        s.isFenced = true
        s.fenceLength = fenceLength
        s.fenceChar = c
        s.fenceOffset = indent
        code.markers.append(NSRange(location: lineStart + markerStart, length: lineLength - markerStart))
        advanceNextNonspace()
        advanceOffset(fenceLength, columns: false)
        touch(code)
        return 2
    }

    private func startHTMLBlock(_ container: MarkdownNode) -> Int {
        guard !indented, peek(nextNonspace) == 0x3C else { return 0 }
        let rest = lineSlice(from: nextNonspace)
        for blockType in 1...7 {
            if MarkdownSyntax.htmlBlockOpen(blockType, rest) &&
                (blockType < 7 || (!isParagraphLike(container) && !(!allClosed && !blank && type(tip) == .paragraph))) {
                closeUnmatchedBlocks()
                let html = addChild(.htmlBlock, at: offset)
                state(html).htmlBlockType = blockType
                return 2
            }
        }
        return 0
    }

    private func startSetextHeading(_ container: MarkdownNode) -> Int {
        guard !indented, type(container) == .paragraph, let c = peek(nextNonspace), c == 0x3D || c == 0x2D else { return 0 }
        var j = nextNonspace
        while peek(j) == c { j += 1 }
        while isSpaceOrTab(peek(j)) { j += 1 }
        guard peek(j) == nil else { return 0 }
        closeUnmatchedBlocks()
        let s = state(container)
        extractReferenceDefinitions(from: container)
        guard s.content.chars.contains(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A }) else { return 0 }
        let heading = MarkdownNode(.heading(level: c == 0x3D ? 1 : 2, setext: true), range: container.range)
        let hs = state(heading)
        hs.content = s.content
        hs.startLine = s.startLine
        hs.setext = true
        heading.markers.append(NSRange(location: lineStart + nextNonspace, length: lineLength - nextNonspace))
        container.insertAfter(heading)
        container.unlink()
        tip = heading
        touch(heading)
        advanceOffset(lineLength - offset, columns: false)
        return 2
    }

    private func startThematicBreak() -> Int {
        guard !indented, let c = peek(nextNonspace), c == 0x2A || c == 0x5F || c == 0x2D else { return 0 }
        var count = 0
        var j = nextNonspace
        while let ch = peek(j) {
            if ch == c { count += 1 }
            else if !isSpaceOrTab(ch) { return 0 }
            j += 1
        }
        guard count >= 3 else { return 0 }
        closeUnmatchedBlocks()
        let rule = addChild(.thematicBreak, at: nextNonspace)
        rule.markers.append(NSRange(location: lineStart + nextNonspace, length: lineLength - nextNonspace))
        touch(rule)
        advanceOffset(lineLength - offset, columns: false)
        return 2
    }

    private func startFootnoteDefinition(_ container: MarkdownNode) -> Int {
        guard options.contains(.footnotes), !indented, peek(nextNonspace) == 0x5B, peek(nextNonspace + 1) == 0x5E else { return 0 }
        var j = nextNonspace + 2
        while let ch = peek(j), ch != 0x5D, ch != 0x20, ch != 0x09 { j += 1 }
        guard j > nextNonspace + 2, peek(j) == 0x5D, peek(j + 1) == 0x3A else { return 0 }
        let label = String(utf16CodeUnits: Array(chars[(lineStart + nextNonspace + 2)..<(lineStart + j)]), count: j - nextNonspace - 2)
        closeUnmatchedBlocks()
        let markerStart = nextNonspace
        advanceNextNonspace()
        advanceOffset(j + 2 - nextNonspace, columns: false)
        while isSpaceOrTab(peek(offset)) { advanceOffset(1, columns: true) }
        let normalized = MarkdownSyntax.normalizeLabel(label)
        footnoteLabels.insert(normalized)
        let def = addChild(.footnoteDefinition(label: label), at: markerStart)
        def.markers.append(NSRange(location: lineStart + markerStart, length: offset - markerStart))
        touch(def)
        return 1
    }

    private func startListItem(_ container: MarkdownNode) -> Int {
        guard !indented || type(container) == .list else { return 0 }
        guard indent < 4 else { return 0 }
        let markerStart = nextNonspace
        var data = ListData(isOrdered: false, bulletChar: 0, start: 1, delimiter: 0, padding: 0, markerOffset: indent)
        var markerLength = 0
        guard let c = peek(nextNonspace) else { return 0 }
        let interruptsParagraph = isParagraphLike(container)
        if c == 0x2A || c == 0x2B || c == 0x2D {
            data.bulletChar = c
            markerLength = 1
        } else if c >= 0x30 && c <= 0x39 {
            var j = nextNonspace
            var number = 0
            while let d = peek(j), d >= 0x30 && d <= 0x39, j - nextNonspace < 9 {
                number = number * 10 + Int(d - 0x30)
                j += 1
            }
            guard let delim = peek(j), delim == 0x2E || delim == 0x29 else { return 0 }
            guard !interruptsParagraph || number == 1 else { return 0 }
            data.isOrdered = true
            data.start = number
            data.delimiter = delim
            markerLength = j + 1 - nextNonspace
        } else {
            return 0
        }
        let after = peek(nextNonspace + markerLength)
        guard after == nil || isSpaceOrTab(after) else { return 0 }
        if interruptsParagraph {
            var k = nextNonspace + markerLength
            while isSpaceOrTab(peek(k)) { k += 1 }
            if peek(k) == nil { return 0 }
        }
        advanceNextNonspace()
        advanceOffset(markerLength, columns: true)
        let spacesStartColumn = column
        let spacesStartOffset = offset
        repeat {
            advanceOffset(1, columns: true)
        } while column - spacesStartColumn < 5 && isSpaceOrTab(peek(offset))
        let blankItem = peek(offset) == nil
        let spacesAfterMarker = column - spacesStartColumn
        if spacesAfterMarker >= 5 || spacesAfterMarker < 1 || blankItem {
            data.padding = markerLength + 1
            column = spacesStartColumn
            offset = spacesStartOffset
            if isSpaceOrTab(peek(offset)) { advanceOffset(1, columns: true) }
        } else {
            data.padding = markerLength + spacesAfterMarker
        }

        closeUnmatchedBlocks()
        if type(tip) != .list || !listsMatch(state(tip).listData, data) {
            let list = addChild(.list(ordered: data.isOrdered, start: data.start,
                                      delimiter: Character(Unicode.Scalar(data.isOrdered ? data.delimiter : 0x2E) ?? "."),
                                      bullet: Character(Unicode.Scalar(data.isOrdered ? 0x2D : data.bulletChar) ?? "-"),
                                      tight: true), at: markerStart)
            state(list).listData = data
        }
        let item = addChild(.listItem(task: nil), at: markerStart)
        state(item).listData = data
        item.markers.append(NSRange(location: lineStart + markerStart, length: offset - markerStart))
        touch(item)
        return 1
    }

    private func listsMatch(_ a: ListData?, _ b: ListData) -> Bool {
        guard let a = a else { return false }
        return a.isOrdered == b.isOrdered && a.delimiter == b.delimiter && a.bulletChar == b.bulletChar
    }

    private func startIndentedCode() -> Int {
        guard indented, !isParagraphLike(tip), !blank else { return 0 }
        advanceOffset(4, columns: true)
        closeUnmatchedBlocks()
        addChild(.codeBlock(fenced: false, info: ""), at: offset)
        return 2
    }

    // MARK: - Tables (GFM)

    private func startTable(_ container: MarkdownNode) -> Int {
        guard options.contains(.tables), !indented, type(container) == .paragraph, container === tip else { return 0 }
        let delimiterCells = splitRow(lineFrom: nextNonspace)
        guard !delimiterCells.cells.isEmpty else { return 0 }
        var alignments: [TableAlignment] = []
        for cell in delimiterCells.cells {
            let text = String(utf16CodeUnits: cell.chars, count: cell.chars.count)
            guard text.range(of: "^:?-+:?$", options: .regularExpression) != nil else { return 0 }
            let left = text.hasPrefix(":"), right = text.hasSuffix(":")
            alignments.append(left && right ? .center : right ? .right : left ? .left : .defaultAlignment)
        }
        // Header row = the paragraph's last line
        let ps = state(container)
        var content = ps.content
        if content.chars.last == 0x0A { content.chars.removeLast(); content.map.removeLast() }
        var headerStart = content.chars.count
        while headerStart > 0 && content.chars[headerStart - 1] != 0x0A { headerStart -= 1 }
        let header = MarkdownInlineSource(chars: Array(content.chars[headerStart...]), map: Array(content.map[headerStart...]))
        let headerRow = splitRow(header)
        guard headerRow.cells.count == alignments.count, delimiterCells.hasPipe || headerRow.hasPipe else { return 0 }

        closeUnmatchedBlocks()
        let table = MarkdownNode(.table(alignments: alignments), range: NSRange(location: header.map.first ?? lineStart, length: 0))
        let ts = state(table)
        ts.alignments = alignments
        ts.columnCount = alignments.count
        ts.startLine = lineNumber - 1
        container.insertAfter(table)
        if headerStart > 0 {
            // Lines before the header stay a paragraph
            ps.content = MarkdownInlineSource(chars: Array(ps.content.chars[0..<headerStart]), map: Array(ps.content.map[0..<headerStart]))
            ps.endLine = lineNumber - 2
            ps.endOffset = (ps.content.map.last ?? container.range.location)
            finalize(container)
        } else {
            container.unlink()
        }
        let head = MarkdownNode(.tableHead, range: .init(location: header.map.first ?? 0, length: 0))
        table.appendChild(head)
        head.appendChild(makeRow(headerRow, isHeader: true, alignments: alignments))
        head.range = head.firstChild!.range
        table.markers.append(NSRange(location: lineStart + nextNonspace, length: lineLength - nextNonspace))
        tip = table
        touch(table)
        advanceOffset(lineLength - offset, columns: false)
        return 2
    }

    private struct SplitRow {
        var cells: [MarkdownInlineSource] = []
        var pipes: [Int] = []
        var hasPipe = false
        var range = NSRange(location: 0, length: 0)
    }

    private func splitRow(lineFrom start: Int) -> SplitRow {
        var source = MarkdownInlineSource()
        var i = start
        while i < lineLength {
            source.chars.append(chars[lineStart + i])
            source.map.append(lineStart + i)
            i += 1
        }
        return splitRow(source)
    }

    /// Splits a table row on unescaped pipes; `\|` becomes a literal pipe in the cell content.
    private func splitRow(_ line: MarkdownInlineSource) -> SplitRow {
        var row = SplitRow()
        var lo = 0, hi = line.chars.count
        while lo < hi && (line.chars[lo] == 0x20 || line.chars[lo] == 0x09) { lo += 1 }
        while hi > lo && (line.chars[hi - 1] == 0x20 || line.chars[hi - 1] == 0x09) { hi -= 1 }
        guard lo < hi else { return row }
        row.range = NSRange(location: line.map[lo], length: line.map[hi - 1] + 1 - line.map[lo])
        if line.chars[lo] == 0x7C { row.pipes.append(line.map[lo]); row.hasPipe = true; lo += 1 }
        if hi > lo && line.chars[hi - 1] == 0x7C && !(hi - 2 >= lo && line.chars[hi - 2] == 0x5C) {
            row.pipes.append(line.map[hi - 1]); row.hasPipe = true; hi -= 1
        }
        var current = MarkdownInlineSource()
        var i = lo
        func flush() {
            var a = 0, b = current.chars.count
            while a < b && (current.chars[a] == 0x20 || current.chars[a] == 0x09) { a += 1 }
            while b > a && (current.chars[b - 1] == 0x20 || current.chars[b - 1] == 0x09) { b -= 1 }
            row.cells.append(MarkdownInlineSource(chars: Array(current.chars[a..<b]), map: Array(current.map[a..<b])))
            current = MarkdownInlineSource()
        }
        while i < hi {
            let c = line.chars[i]
            if c == 0x5C && i + 1 < hi && line.chars[i + 1] == 0x7C {
                current.chars.append(0x7C)
                current.map.append(line.map[i + 1])
                i += 2
                continue
            }
            if c == 0x7C {
                row.pipes.append(line.map[i])
                row.hasPipe = true
                flush()
                i += 1
                continue
            }
            current.chars.append(c)
            current.map.append(line.map[i])
            i += 1
        }
        flush()
        return row
    }

    private func makeRow(_ split: SplitRow, isHeader: Bool, alignments: [TableAlignment]) -> MarkdownNode {
        let row = MarkdownNode(.tableRow, range: split.range)
        row.markers = split.pipes.map { NSRange(location: $0, length: 1) }
        for column in 0..<alignments.count {
            let source = column < split.cells.count ? split.cells[column] : MarkdownInlineSource()
            let location = source.map.first ?? (split.range.location + split.range.length)
            let length = source.map.isEmpty ? 0 : source.map.last! + 1 - location
            let cell = MarkdownNode(.tableCell(alignment: alignments[column], isHeader: isHeader), range: NSRange(location: location, length: length))
            inlineSources[ObjectIdentifier(cell)] = (cell, source)
            row.appendChild(cell)
        }
        return row
    }

    private func addTableRow(to table: MarkdownNode) {
        let split = splitRow(lineFrom: offset)
        guard !split.cells.isEmpty else { return }
        table.appendChild(makeRow(split, isHeader: false, alignments: state(table).alignments))
    }

    // MARK: - Front matter (Swash)

    /// Parses `---` YAML front matter at the very start of the document; returns where block parsing resumes.
    private func parseFrontMatter() -> Int {
        let text = source as NSString
        guard text.length >= 3, text.hasPrefix("---") else { return 0 }
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, range, _, stop in
            lines.append(range)
            if lines.count > 500 { stop.pointee = true }
        }
        guard lines.count >= 3, text.substring(with: lines[0]).trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        // The first content line must look like YAML (`key:`), so a leading thematic break is not mistaken for front matter
        let firstContent = text.substring(with: lines[1])
        guard firstContent.range(of: "^[A-Za-z0-9_-]+[ \\t]*:", options: .regularExpression) != nil else { return 0 }
        for index in 1..<lines.count {
            let line = text.substring(with: lines[index]).trimmingCharacters(in: .whitespaces)
            if line == "---" || line == "..." {
                let close = lines[index]
                let node = MarkdownNode(.frontMatter, range: NSRange(location: 0, length: close.location + close.length))
                node.markers = [lines[0], close]
                let bodyStart = lines[1].location
                node.literal = text.substring(with: NSRange(location: bodyStart, length: max(0, close.location - bodyStart)))
                state(node).open = false
                root.appendChild(node)
                lineNumber = index
                var resume = close.location + close.length
                if resume < chars.count && chars[resume] == 0x0D { resume += 1 }
                if resume < chars.count && chars[resume] == 0x0A { resume += 1 }
                return resume
            }
        }
        return 0
    }

    // MARK: - Finalisation

    private func finalize(_ block: MarkdownNode) {
        let s = state(block)
        let above = block.parent
        s.open = false

        switch type(block) {
        case .paragraph:
            extractReferenceDefinitions(from: block)
            if !s.content.chars.contains(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A }) {
                block.unlink()
            }
        case .codeBlock:
            var content = s.content
            if s.isFenced {
                // First line is the info string
                let newline = content.chars.firstIndex(of: 0x0A) ?? content.chars.count
                let infoRaw = String(utf16CodeUnits: Array(content.chars[0..<newline]), count: newline)
                let info = MarkdownSyntax.unescape(infoRaw.trimmingCharacters(in: .whitespaces))
                let restStart = min(newline + 1, content.chars.count)
                content = MarkdownInlineSource(chars: Array(content.chars[restStart...]), map: Array(content.map[restStart...]))
                block.kind = .codeBlock(fenced: true, info: info)
            } else {
                // Strip trailing blank lines, keep one final newline
                var end = content.chars.count
                var lastNewline = end
                var i = end - 1
                while i >= 0 {
                    let c = content.chars[i]
                    if c == 0x0A { lastNewline = i }
                    else if c != 0x20 { break }
                    i -= 1
                }
                end = lastNewline < content.chars.count ? lastNewline + 1 : end
                content = MarkdownInlineSource(chars: Array(content.chars[0..<end]), map: Array(content.map[0..<end]))
            }
            block.literal = String(utf16CodeUnits: content.chars, count: content.chars.count)
        case .htmlBlock:
            var text = String(utf16CodeUnits: s.content.chars, count: s.content.chars.count)
            if let range = text.range(of: "(\\n *)+$", options: .regularExpression) {
                text.removeSubrange(range)
            }
            block.literal = text
        case .list:
            var tight = true
            var item = block.firstChild
            outer: while let it = item {
                if it.nextSibling != nil && endsWithBlankLine(it) { tight = false; break }
                var sub = it.firstChild
                while let st = sub {
                    if st.nextSibling != nil && endsWithBlankLine(st) { tight = false; break outer }
                    sub = st.nextSibling
                }
                item = it.nextSibling
            }
            if case .list(let ordered, let start, let delimiter, let bullet, _) = block.kind {
                block.kind = .list(ordered: ordered, start: start, delimiter: delimiter, bullet: bullet, tight: tight)
            }
        default:
            break
        }

        if block !== root {
            block.range.length = max(0, s.endOffset - block.range.location)
        }
        tip = above ?? root
    }

    /// True when a blank line separates this block from its next sibling.
    private func endsWithBlankLine(_ block: MarkdownNode) -> Bool {
        guard let next = block.nextSibling else { return false }
        return state(block).endLine < state(next).startLine - 1
    }

    /// Moves leading link reference definitions out of a paragraph into their own nodes.
    private func extractReferenceDefinitions(from paragraph: MarkdownNode) {
        let s = state(paragraph)
        while s.content.chars.first == 0x5B,
              let parsed = inlineParser.parseReference(s.content, refmap: &refmap) {
            let consumed = parsed.consumed
            let def = (label: parsed.label, destination: parsed.destination, title: parsed.title,
                       lines: max(1, s.content.chars[0..<consumed].filter { $0 == 0x0A }.count))
            var end = consumed
            while end > 0 && (s.content.chars[end - 1] == 0x0A || s.content.chars[end - 1] == 0x20) { end -= 1 }
            let start = s.content.map[0]
            let node = MarkdownNode(.linkReferenceDefinition(label: def.label, destination: def.destination, title: def.title),
                                    range: NSRange(location: start, length: end > 0 ? s.content.map[end - 1] + 1 - start : 0))
            node.markers = [node.range]
            let ns = state(node)
            ns.startLine = s.startLine
            ns.endLine = s.startLine + def.lines - 1
            ns.endOffset = node.range.location + node.range.length
            ns.open = false
            s.startLine += def.lines
            paragraph.insertBefore(node)
            s.content = MarkdownInlineSource(chars: Array(s.content.chars[consumed...]), map: Array(s.content.map[consumed...]))
            if let first = s.content.map.first { paragraph.range.location = first }
        }
    }

    // MARK: - Post-processing (task lists, alerts)

    private func postProcess(_ node: MarkdownNode) {
        var child = node.firstChild
        while let c = child {
            let next = c.nextSibling
            postProcess(c)
            child = next
        }
        switch node.kind {
        case .listItem where options.contains(.taskLists):
            guard let paragraph = node.firstChild, case .paragraph = paragraph.kind else { return }
            let s = state(paragraph)
            let ch = s.content.chars
            guard ch.count >= 4, ch[0] == 0x5B, ch[2] == 0x5D,
                  ch[1] == 0x20 || ch[1] == 0x78 || ch[1] == 0x58,
                  ch[3] == 0x20 || ch[3] == 0x09 || ch[3] == 0x0A else { return }
            node.kind = .listItem(task: ch[1] == 0x20 ? .unchecked : .checked)
            node.markers.append(NSRange(location: s.content.map[0], length: s.content.map[3] + 1 - s.content.map[0]))
            s.content = MarkdownInlineSource(chars: Array(ch[4...]), map: Array(s.content.map[4...]))
            moveStart(of: paragraph, to: s.content.map.first)
            if !s.content.chars.contains(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A }) { paragraph.unlink() }
        case .blockQuote where options.contains(.alerts):
            guard let paragraph = node.firstChild, case .paragraph = paragraph.kind else { return }
            let s = state(paragraph)
            let text = String(utf16CodeUnits: s.content.chars, count: s.content.chars.count)
            guard let match = text.range(of: "^\\[![A-Za-z]+\\]", options: .regularExpression) else { return }
            let name = text[match].dropFirst(2).dropLast().lowercased()
            guard let alertType = AlertType(rawValue: name) else { return }
            var end = text.utf16.distance(from: text.startIndex, to: match.upperBound)
            let markerEnd = end
            while end < s.content.chars.count && (s.content.chars[end] == 0x20 || s.content.chars[end] == 0x09) { end += 1 }
            if end < s.content.chars.count && s.content.chars[end] == 0x0A { end += 1 }
            node.kind = .alert(alertType)
            node.markers.append(NSRange(location: s.content.map[0], length: s.content.map[markerEnd - 1] + 1 - s.content.map[0]))
            s.content = MarkdownInlineSource(chars: Array(s.content.chars[end...]), map: Array(s.content.map[end...]))
            moveStart(of: paragraph, to: s.content.map.first)
            if !s.content.chars.contains(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x0A }) { paragraph.unlink() }
        default:
            break
        }
    }

    /// Moves a block's start forward while keeping its end fixed.
    private func moveStart(of node: MarkdownNode, to location: Int?) {
        guard let location = location else { return }
        let end = node.range.location + node.range.length
        node.range = NSRange(location: min(location, end), length: max(0, end - location))
    }
    
    // MARK: - Inlines

    private func processInlines(_ node: MarkdownNode) {
        inlineParser.refmap = refmap
        inlineParser.footnoteLabels = footnoteLabels
        node.walk { block in
            switch block.kind {
            case .paragraph, .heading:
                inlineParser.parse(state(block).content, into: block)
            case .tableCell:
                inlineParser.parse(inlineSources[ObjectIdentifier(block)]?.source ?? MarkdownInlineSource(), into: block)
            default:
                break
            }
        }
    }
}
