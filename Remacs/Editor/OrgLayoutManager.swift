//
//  OrgLayoutManager.swift
//  Remacs
//
//  Draws an ellipsis after the opening line of every folded headline, block, or drawer,
//  like Emacs does. The ellipsis is drawn only, never inserted into the text, so it can't
//  be selected or saved.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class OrgLayoutManager: NSLayoutManager {
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
