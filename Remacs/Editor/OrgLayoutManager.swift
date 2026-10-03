//
//  OrgLayoutManager.swift
//  Remacs
//
//  Draws an ellipsis after the opening line of every folded headline, block, or drawer,
//  like Emacs does, and a full-width tinted background behind source and example blocks.
//  Both are drawn only, never inserted into the text, so they can't be selected or saved.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class OrgLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        drawCodeBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawCodeBlockBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let textStorage = textStorage as? OrgTextStorage else { return }
        PlatformColor.orgCodeBackground.setFill()

        for block in textStorage.codeBlocks {
            // Skip blocks hidden inside a folded headline: their glyphs are null and would
            // otherwise borrow the line fragment of the next visible line.
            guard textStorage.attribute(.orgFolded, at: block.lineStart, effectiveRange: nil) == nil else { continue }
            // A folded block shows only its opening line.
            let end = textStorage.foldedLineStarts.contains(block.lineStart) ? block.lineEnd : block.bodyEnd
            let blockGlyphs = glyphRange(forCharacterRange: NSRange(location: block.lineStart, length: end - block.lineStart), actualCharacterRange: nil)
            let visibleGlyphs = NSIntersectionRange(blockGlyphs, glyphsToShow)
            guard visibleGlyphs.length > 0 else { continue }

            enumerateLineFragments(forGlyphRange: visibleGlyphs) { rect, _, _, _, _ in
                let fill = rect.offsetBy(dx: origin.x, dy: origin.y)
                #if os(macOS)
                fill.fill()
                #else
                UIRectFill(fill)
                #endif
            }
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage = textStorage as? OrgTextStorage else { return }

        for lineEnd in textStorage.foldedOpeningLineEnds {
            // Draw just past the opening line's last character, where its newline sits.
            let newlineIndex = lineEnd - 1
            let glyphIndex = glyphIndexForCharacter(at: newlineIndex)
            guard NSLocationInRange(glyphIndex, glyphsToShow) else { continue }

            let font = textStorage.attribute(.font, at: newlineIndex, effectiveRange: nil) as? PlatformFont ?? .orgBody
            let ellipsis = NSAttributedString(string: " …", attributes: [
                .font: font,
                .foregroundColor: PlatformColor.orgSecondaryText
            ])
            let fragment = lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let baseline = location(forGlyphAt: glyphIndex)
            ellipsis.draw(at: CGPoint(
                x: origin.x + fragment.minX + baseline.x,
                y: origin.y + fragment.minY + baseline.y - font.ascender
            ))
        }
    }
}
