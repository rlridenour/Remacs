//
//  OrgTextStorage.swift
//  Remacs
//
//  Custom NSTextStorage that re-highlights org-mode syntax on every edit and marks
//  folded headline subtrees, blocks, and drawers so the layout manager can hide their glyphs. The visible
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
    /// Marks a character range that belongs to a currently-folded headline subtree, block, or drawer.
    static let orgFolded = NSAttributedString.Key("OrgFolded")
}

final class OrgTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    private(set) var headlines: [OrgHeadline] = []
    private(set) var foldRegions: [OrgFoldRegion] = []

    /// Line starts of the folded headlines, blocks, and drawers. A line can open at most
    /// one of these, so a single set covers all three kinds.
    private(set) var foldedLineStarts: Set<Int> = []

    /// The tab stops left in the most recently expanded snippet. Kept here rather than in
    /// the view because every edit, including undo, passes through `replaceCharacters`.
    var snippetSession: OrgSnippetSession?

    override var string: String { backingStore.string }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        let delta = (str as NSString).length - range.length
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: delta)
        remapFoldedLineStarts(editedRange: range, delta: delta)
        snippetSession?.remap(editedRange: range, delta: delta)
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
        foldRegions = result.foldRegions
        for (range, attrs) in result.attributeRuns {
            backingStore.addAttributes(attrs, range: range)
        }
        applyFoldingAttributes()
    }

    /// Refreshes the `.orgFolded` attribute on the backing store to match `foldedLineStarts`.
    /// Safe to call from within `processEditing()` since it only touches the private backing
    /// store directly and never talks to the layout manager.
    private func applyFoldingAttributes() {
        let length = backingStore.length
        guard length > 0 else { return }
        let fullRange = NSRange(location: 0, length: length)
        backingStore.removeAttribute(.orgFolded, range: fullRange)
        guard !foldedLineStarts.isEmpty else { return }
        for headline in headlines where foldedLineStarts.contains(headline.lineStart) {
            guard headline.canFold else { continue }
            let range = NSRange(location: headline.lineEnd, length: headline.bodyEnd - headline.lineEnd)
            backingStore.addAttribute(.orgFolded, value: true, range: range)
        }
        for region in foldRegions where foldedLineStarts.contains(region.lineStart) {
            guard region.canFold else { continue }
            let range = NSRange(location: region.lineEnd, length: region.bodyEnd - region.lineEnd)
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

    private func remapFoldedLineStarts(editedRange: NSRange, delta: Int) {
        guard !foldedLineStarts.isEmpty else { return }
        let editEnd = editedRange.location + editedRange.length
        foldedLineStarts = Set(foldedLineStarts.compactMap { start in
            if start >= editEnd { return start + delta }
            if start >= editedRange.location { return nil }
            return start
        })
    }

    // MARK: - Snippet tab stops

    /// Removes and returns the active snippet's next tab stop, provided `cursor` is still
    /// inside the snippet. Returns nil (ending the session) otherwise.
    func popSnippetStop(cursor: Int) -> Int? {
        guard var session = snippetSession, session.contains(cursor), !session.stops.isEmpty else {
            snippetSession = nil
            return nil
        }
        let stop = session.stops.removeFirst()
        snippetSession = session.stops.isEmpty ? nil : session
        return stop
    }

    /// Ends the active snippet session once the cursor leaves the snippet.
    func endSnippetSession(ifOutside location: Int) {
        if let session = snippetSession, !session.contains(location) {
            snippetSession = nil
        }
    }

    // MARK: - Queries

    /// Source and example blocks, which get a tinted background.
    var codeBlocks: [OrgFoldRegion] {
        foldRegions.filter { $0.kind == .block && ($0.name == "src" || $0.name == "example") }
    }

    func headline(atCharacterIndex index: Int) -> OrgHeadline? {
        headlines.first { $0.lineStart <= index && index < $0.lineEnd }
    }

    /// The block or drawer whose opening or closing line contains `index`.
    func foldRegion(atCharacterIndex index: Int) -> OrgFoldRegion? {
        // A cursor at the very end of the document is on the last line only if that line
        // has no trailing newline (otherwise it's on a new, empty line).
        let atEndOfUnterminatedLastLine = index == length && !string.hasSuffix("\n")
        return foldRegions.first { region in
            if region.lineStart <= index && index < region.lineEnd { return true }
            if region.closingLineStart <= index && index < region.bodyEnd { return true }
            return atEndOfUnterminatedLastLine && index == region.bodyEnd
        }
    }

    /// If `index` falls inside folded (hidden) text, returns the end of the visible opening
    /// line that hides it, so the cursor can be moved somewhere visible. Otherwise returns
    /// `index` unchanged.
    func locationOutsideFold(_ index: Int) -> Int {
        let probe = index < length ? index : index - 1
        guard probe >= 0 else { return index }
        var folded = NSRange()
        guard attribute(.orgFolded, at: probe, longestEffectiveRange: &folded, in: NSRange(location: 0, length: length)) != nil else {
            return index
        }
        return max(folded.location - 1, 0)
    }

    /// Line ends (just past the newline) of the opening lines of every currently-folded
    /// headline, block, and drawer -- where the layout manager draws the fold ellipsis.
    var foldedOpeningLineEnds: [Int] {
        guard !foldedLineStarts.isEmpty else { return [] }
        let headlineEnds = headlines
            .filter { $0.canFold && foldedLineStarts.contains($0.lineStart) }
            .map(\.lineEnd)
        let regionEnds = foldRegions
            .filter { $0.canFold && foldedLineStarts.contains($0.lineStart) }
            .map(\.lineEnd)
        return headlineEnds + regionEnds
    }

    func isFolded(_ headline: OrgHeadline) -> Bool {
        foldedLineStarts.contains(headline.lineStart)
    }

    /// Toggles folding for `headline`. Must be called from a top-level event handler
    /// (e.g. Tab key or tap gesture), not from within a text-editing transaction.
    func toggleFold(for headline: OrgHeadline) {
        guard headline.canFold else { return }
        toggleFold(lineStart: headline.lineStart)
    }

    /// Toggles folding for the headline, block, or drawer whose opening line (or, for a
    /// block or drawer, closing line) contains `index`. Returns false if there's nothing foldable there. Same calling constraints
    /// as `toggleFold(for:)`.
    @discardableResult
    func toggleFold(atCharacterIndex index: Int) -> Bool {
        if let headline = headline(atCharacterIndex: index) {
            guard headline.canFold else { return false }
            toggleFold(lineStart: headline.lineStart)
            return true
        }
        if let region = foldRegion(atCharacterIndex: index), region.canFold {
            toggleFold(lineStart: region.lineStart)
            return true
        }
        return false
    }

    private func toggleFold(lineStart: Int) {
        if foldedLineStarts.contains(lineStart) {
            foldedLineStarts.remove(lineStart)
        } else {
            foldedLineStarts.insert(lineStart)
        }
        applyFoldingAttributes()
        invalidateDisplayForFolding()
    }
}
