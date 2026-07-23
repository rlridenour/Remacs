//
//  OrgFoldingLayoutManagerDelegate.swift
//  Remacs
//
//  Hides the glyphs of folded headline subtrees at layout time. This never touches the
//  underlying text, so folding is purely visual and the saved document is unaffected.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class OrgFoldingLayoutManagerDelegate: NSObject, NSLayoutManagerDelegate {
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: PlatformFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let textStorage = layoutManager.textStorage else { return 0 }

        var mutableProps = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var didChange = false
        for i in 0..<glyphRange.length {
            let charIndex = characterIndexes[i]
            if textStorage.attribute(.orgFolded, at: charIndex, effectiveRange: nil) != nil {
                mutableProps[i].insert(.null)
                didChange = true
            }
        }
        guard didChange else { return 0 }

        layoutManager.setGlyphs(glyphs, properties: mutableProps, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }
}
