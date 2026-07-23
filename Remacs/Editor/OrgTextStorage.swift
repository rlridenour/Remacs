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

    private(set) var foldedHeadlineStarts: Set<Int> = []

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

    /// Refreshes the `.orgFolded` attribute on the backing store to match `foldedHeadlineStarts`.
    /// Safe to call from within `processEditing()` since it only touches the private backing
    /// store directly and never talks to the layout manager.
    private func applyFoldingAttributes() {
        let length = backingStore.length
        guard length > 0 else { return }
        let fullRange = NSRange(location: 0, length: length)
        backingStore.removeAttribute(.orgFolded, range: fullRange)
        guard !foldedHeadlineStarts.isEmpty else { return }
        for headline in headlines where foldedHeadlineStarts.contains(headline.lineStart) {
            guard headline.canFold else { continue }
            let range = NSRange(location: headline.lineEnd, length: headline.bodyEnd - headline.lineEnd)
            backingStore.addAttribute(.orgFolded, value: true, range: range)
        }
    }

    /// Forces the layout manager to regenerate glyphs so a fold toggled outside of a text
    /// edit actually collapses on screen (the `.orgFolded` glyph-hiding is baked in at glyph
    /// generation time). Must only be called from a top-level event handler (e.g. Tab/tap),
    /// never from within `processEditing()`/`replaceCharacters` -- calling these layout
    /// manager APIs before the layout manager has been told about a pending edit raises an
    /// internal-consistency exception.
    private func invalidateDisplayForFolding() {
        let length = backingStore.length
        guard length > 0 else { return }
        let fullRange = NSRange(location: 0, length: length)
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
        foldedHeadlineStarts = Set(foldedHeadlineStarts.compactMap { start in
            if start >= editEnd { return start + delta }
            if start >= editedRange.location { return nil }
            return start
        })
    }

    // MARK: - Queries

    func headline(atCharacterIndex index: Int) -> OrgHeadline? {
        headlines.first { $0.lineStart <= index && index < $0.lineEnd }
    }

    func isFolded(_ headline: OrgHeadline) -> Bool {
        foldedHeadlineStarts.contains(headline.lineStart)
    }

    /// Toggles folding for `headline`. Must be called from a top-level event handler
    /// (e.g. Tab key or tap gesture), not from within a text-editing transaction.
    func toggleFold(for headline: OrgHeadline) {
        guard headline.canFold else { return }
        if foldedHeadlineStarts.contains(headline.lineStart) {
            foldedHeadlineStarts.remove(headline.lineStart)
        } else {
            foldedHeadlineStarts.insert(headline.lineStart)
        }
        applyFoldingAttributes()
        invalidateDisplayForFolding()
    }
}
