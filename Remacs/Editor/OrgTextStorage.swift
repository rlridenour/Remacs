//
//  OrgTextStorage.swift
//  Remacs
//
//  Custom NSTextStorage that re-highlights org-mode syntax on every edit and marks
//  folded headline subtrees so the layout manager can hide their glyphs. The visible
//  string is never mutated for highlighting/folding purposes -- only attributes change,
//  so the saved document text is always the exact plain-text source.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    /// Marks a character range that belongs to a currently-folded headline subtree.
    static let orgFolded = NSAttributedString.Key("OrgFolded")
}

final class OrgTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    private(set) var headlines: [OrgHeadline] = []

    var foldedHeadlineStarts: Set<Int> = [] {
        didSet {
            guard oldValue != foldedHeadlineStarts else { return }
            applyFoldingAttributes()
        }
    }

    override var string: String { backingStore.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        let delta = (str as NSString).length - range.length
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: delta)
        remapFoldedHeadlines(editedRange: range, delta: delta)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        highlight()
        super.processEditing()
    }

    // MARK: - Highlighting

    private func highlight() {
        let full = backingStore.string as NSString
        let fullRange = NSRange(location: 0, length: full.length)

        backingStore.setAttributes([
            .font: PlatformFont.orgBody,
            .foregroundColor: PlatformColor.orgText
        ], range: fullRange)

        let result = OrgSyntaxHighlighter.highlight(full)
        headlines = result.headlines
        for (range, attrs) in result.attributeRuns {
            backingStore.addAttributes(attrs, range: range)
        }
        applyFoldingAttributes()
    }

    private func applyFoldingAttributes() {
        let length = backingStore.length
        guard length > 0 else { return }
        let fullRange = NSRange(location: 0, length: length)
        backingStore.removeAttribute(.orgFolded, range: fullRange)
        if !foldedHeadlineStarts.isEmpty {
            for headline in headlines where foldedHeadlineStarts.contains(headline.lineStart) {
                guard headline.canFold else { continue }
                let range = NSRange(location: headline.lineEnd, length: headline.bodyEnd - headline.lineEnd)
                backingStore.addAttribute(.orgFolded, value: true, range: range)
            }
        }
        // Attribute mutations on `backingStore` alone don't notify the layout manager, and
        // the `.orgFolded` glyph-hiding is baked in at glyph-generation time, so folding
        // toggled outside of a text edit needs an explicit invalidation to take effect.
        for layoutManager in layoutManagers {
            layoutManager.invalidateGlyphs(forCharacterRange: fullRange, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        }
    }

    // MARK: - Fold state bookkeeping

    private func remapFoldedHeadlines(editedRange: NSRange, delta: Int) {
        guard !foldedHeadlineStarts.isEmpty else { return }
        let editEnd = editedRange.location + editedRange.length
        let remapped: Set<Int> = Set(foldedHeadlineStarts.compactMap { start in
            if start >= editEnd { return start + delta }
            if start >= editedRange.location { return nil }
            return start
        })
        if remapped != foldedHeadlineStarts {
            foldedHeadlineStarts = remapped
        }
    }

    // MARK: - Queries

    func headline(atCharacterIndex index: Int) -> OrgHeadline? {
        headlines.first { $0.lineStart <= index && index < $0.lineEnd }
    }

    func isFolded(_ headline: OrgHeadline) -> Bool {
        foldedHeadlineStarts.contains(headline.lineStart)
    }

    func toggleFold(for headline: OrgHeadline) {
        guard headline.canFold else { return }
        if foldedHeadlineStarts.contains(headline.lineStart) {
            foldedHeadlineStarts.remove(headline.lineStart)
        } else {
            foldedHeadlineStarts.insert(headline.lineStart)
        }
    }
}
