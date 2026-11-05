//
//  StyledLayoutManager.swift
//  Swash
//
//  TextKit 1 layout manager for the iOS Edit Text editor. It draws what the macOS
//  SwashLayoutManager and NSTextBlock draw there: quote, alert and code boxes and rules
//  (`.blockDecorations`), list bullets and checkboxes, code-block language badges, alert icons and
//  rendered math and Mermaid previews.
//

#if os(iOS)
import UIKit

final class StyledLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawBlockDecorations(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = textStorage else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.codeBadge, in: charRange, options: []) { value, range, _ in
            guard let badge = value as? CodeBadgeInfo else { return }
            let lineRect = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: range.location), effectiveRange: nil)
            let rect = badge.rect(in: textLineRect(lineRect, at: range.location)).offsetBy(dx: origin.x, dy: origin.y)
            (badge.title as NSString).draw(at: CGPoint(x: rect.minX + 2, y: rect.minY + 1), withAttributes: CodeBadgeInfo.attributes)
        }

        textStorage.enumerateAttribute(.alertIcon, in: charRange, options: []) { value, range, _ in
            guard let icon = value as? AlertIconInfo, let image = icon.image else { return }
            let glyph = glyphIndexForCharacter(at: range.location)
            let lineRect = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let used = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let titleX = lineRect.origin.x + location(forGlyphAt: glyph).x
            let size = image.size
            image.draw(in: CGRect(x: origin.x + titleX - size.width - 5, y: origin.y + used.midY - size.height / 2, width: size.width, height: size.height))
        }

        textStorage.enumerateAttribute(.richPreview, in: charRange, options: []) { value, range, _ in
            guard let info = value as? RichPreviewInfo else { return }
            drawRichPreview(info, atCharacter: range.location, origin: origin)
        }

        textStorage.enumerateAttribute(.listMarker, in: charRange, options: []) { value, range, _ in
            guard let marker = value as? ListMarkerInfo else { return }
            let markerGlyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let used = lineFragmentUsedRect(forGlyphAt: markerGlyphs.location, effectiveRange: nil)
            let lineRect = lineFragmentRect(forGlyphAt: markerGlyphs.location, effectiveRange: nil)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13 * MarkdownEditorStyler.fontScale, weight: .regular),
                .foregroundColor: marker.color ?? UIColor.secondaryLabel,
            ]
            let size = (marker.text as NSString).size(withAttributes: attributes)
            // Just left of where the item's text starts, so it lines up inside boxes too
            let contentGlyph = min(NSMaxRange(markerGlyphs), max(0, numberOfGlyphs - 1))
            let contentX = lineRect.origin.x + location(forGlyphAt: contentGlyph).x
            let x = origin.x + (contentX > 0 ? contentX : marker.indent) - size.width - 10
            let y = origin.y + used.midY - size.height / 2
            (marker.text as NSString).draw(in: CGRect(x: x, y: y, width: size.width + 4, height: size.height), withAttributes: attributes)
        }
    }

    /// Every code-block language badge, in text-container coordinates.
    func codeBadgeRects() -> [(location: Int, info: CodeBadgeInfo, rect: CGRect)] {
        guard let storage = textStorage else { return [] }
        var result: [(location: Int, info: CodeBadgeInfo, rect: CGRect)] = []
        storage.enumerateAttribute(.codeBadge, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            guard let badge = value as? CodeBadgeInfo else { return }
            let lineRect = lineFragmentRect(forGlyphAt: glyphIndexForCharacter(at: range.location), effectiveRange: nil)
            result.append((range.location, badge, badge.rect(in: textLineRect(lineRect, at: range.location))))
        }
        return result
    }

    /// The line fragment narrowed to the content area of the innermost box around `location`, as
    /// NSTextBlock line fragments are on macOS.
    private func textLineRect(_ lineRect: CGRect, at location: Int) -> CGRect {
        guard let storage = textStorage, location < storage.length,
              let box = (storage.attribute(.blockDecorations, at: location, effectiveRange: nil) as? [BlockDecoration])?.last else { return lineRect }
        let padding = textContainers.first?.lineFragmentPadding ?? 0
        let left = box.left + box.leftBorderWidth
        let right = box.right + box.borderWidth
        return CGRect(x: lineRect.minX + padding + left, y: lineRect.minY,
                      width: max(0, lineRect.width - padding * 2 - left - right), height: lineRect.height)
    }

    // MARK: Boxes and rules

    /// Paints each visible decoration once, over the full height of the paragraphs it covers.
    private func drawBlockDecorations(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var painted = Set<ObjectIdentifier>()
        storage.enumerateAttribute(.blockDecorations, in: charRange, options: []) { value, range, _ in
            guard let decorations = value as? [BlockDecoration] else { return }
            for decoration in decorations where !painted.contains(ObjectIdentifier(decoration)) {
                painted.insert(ObjectIdentifier(decoration))
                let extent = self.extent(of: decoration, around: range.location, in: storage)
                let glyphs = glyphRange(forCharacterRange: extent, actualCharacterRange: nil)
                guard glyphs.length > 0 else { continue }
                var top = CGFloat.greatestFiniteMagnitude
                var bottom = -CGFloat.greatestFiniteMagnitude
                var lineMinX: CGFloat = 0
                var lineMaxX: CGFloat = container.size.width
                enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                    top = min(top, rect.minY)
                    bottom = max(bottom, rect.maxY)
                    lineMinX = rect.minX
                    lineMaxX = rect.maxX
                }
                guard top < bottom else { continue }
                let padding = container.lineFragmentPadding
                let left = origin.x + lineMinX + padding + decoration.left
                let right = origin.x + lineMaxX - padding - decoration.right
                let box = CGRect(x: left, y: origin.y + top, width: max(0, right - left), height: bottom - top)
                draw(decoration, in: box)
            }
        }
    }

    private func draw(_ decoration: BlockDecoration, in box: CGRect) {
        switch decoration.kind {
        case .rule:
            decoration.fill?.setFill()
            UIRectFillUsingBlendMode(CGRect(x: box.minX, y: box.midY - 0.5, width: box.width, height: 1), .normal)
        case .box:
            if let fill = decoration.fill {
                fill.setFill()
                UIRectFillUsingBlendMode(box, .normal)
            }
            guard let border = decoration.borderColor else { return }
            border.setFill()
            if decoration.borderWidth > 0 {
                let w = decoration.borderWidth
                UIRectFillUsingBlendMode(CGRect(x: box.minX, y: box.minY, width: box.width, height: w), .normal)
                UIRectFillUsingBlendMode(CGRect(x: box.minX, y: box.maxY - w, width: box.width, height: w), .normal)
                UIRectFillUsingBlendMode(CGRect(x: box.maxX - w, y: box.minY, width: w, height: box.height), .normal)
            }
            if decoration.leftBorderWidth > 0 {
                UIRectFillUsingBlendMode(CGRect(x: box.minX, y: box.minY, width: decoration.leftBorderWidth, height: box.height), .normal)
            }
        }
    }

    /// The characters whose `.blockDecorations` include `decoration`, around `location`.
    private func extent(of decoration: BlockDecoration, around location: Int, in storage: NSTextStorage) -> NSRange {
        func contains(_ index: Int) -> NSRange? {
            guard index >= 0, index < storage.length else { return nil }
            var run = NSRange()
            let value = storage.attribute(.blockDecorations, at: index, effectiveRange: &run) as? [BlockDecoration]
            return value?.contains(where: { $0 === decoration }) == true ? run : nil
        }
        guard var range = contains(location) else { return NSRange(location: location, length: 0) }
        while let previous = contains(range.location - 1) { range = NSUnionRange(range, previous) }
        while let next = contains(NSMaxRange(range)) { range = NSUnionRange(range, next) }
        return range
    }

    // MARK: Rendered math and diagrams

    /// Draws a rendered formula or diagram centred in the paragraph spacing below its block's last line.
    private func drawRichPreview(_ info: RichPreviewInfo, atCharacter location: Int, origin: CGPoint) {
        let glyph = glyphIndexForCharacter(at: location)
        guard glyph < numberOfGlyphs else { return }
        let lineRect = textLineRect(lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil), at: location)
        let used = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        var y = origin.y + used.maxY + RichPreviewInfo.spacing
        if let error = info.error {
            ("⚠︎ " + error as NSString).draw(with: CGRect(x: origin.x + lineRect.minX + 4, y: y, width: max(0, lineRect.width - 8), height: RichPreviewInfo.errorHeight),
                                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: RichPreviewInfo.errorAttributes, context: nil)
            y += RichPreviewInfo.errorHeight
        }
        guard info.size.width > 0, info.size.height > 0 else { return }
        var size = info.size
        let available = max(20, lineRect.width - 8)
        if size.width > available {
            size = CGSize(width: available, height: size.height * available / size.width)
        }
        let rect = CGRect(x: origin.x + lineRect.minX + (lineRect.width - size.width) / 2, y: y, width: size.width, height: size.height)
        info.image.draw(in: rect, blendMode: .normal, alpha: info.alpha)
    }
}
#endif
