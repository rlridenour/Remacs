//
//  OrgEmphasisFormatting.swift
//  Remacs
//
//  Shared (platform-agnostic) logic for the emphasis keyboard shortcuts: toggling org-mode
//  emphasis markers on a selection, or the word under the cursor.
//

import Foundation

enum OrgEmphasis: String {
    case bold = "*"
    case italic = "/"
    case underline = "_"
    case code = "="
}

enum OrgEmphasisFormatting {
    /// Resolves the range of text a shortcut should act on: the current selection if
    /// non-empty, otherwise the word under the cursor (via `wordRangeProvider`). If
    /// there's no selection and the cursor isn't on a word, returns a zero-length range
    /// at the cursor so the caller inserts (or removes) an empty marker pair there instead.
    static func targetRange(selectedRange: NSRange, in text: NSString, wordRangeProvider: () -> NSRange?) -> NSRange {
        if selectedRange.length > 0 { return selectedRange }
        if let wordRange = wordRangeProvider(), wordRange.length > 0 {
            let content = text.substring(with: wordRange)
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return wordRange
            }
        }
        return NSRange(location: selectedRange.location, length: 0)
    }

    /// Toggles the emphasis marker on `range`: removes it if `range` is already wrapped
    /// (either the markers sit just outside `range`, or `range` itself includes them),
    /// otherwise adds it. Returns the range to replace, its replacement text, and the
    /// range (within the new text) that should end up selected afterwards.
    static func toggle(_ range: NSRange, in text: NSString, with emphasis: OrgEmphasis) -> (replaceRange: NSRange, replacement: String, newSelection: NSRange) {
        let marker = emphasis.rawValue as NSString
        let markerLength = marker.length

        // Markers sit immediately outside `range`, e.g. the cursor/selection is on "bold"
        // within "*bold*", or the cursor sits between an empty pair like "*|*".
        if range.location >= markerLength,
           range.location + range.length + markerLength <= text.length,
           text.substring(with: NSRange(location: range.location - markerLength, length: markerLength)) == marker as String,
           text.substring(with: NSRange(location: range.location + range.length, length: markerLength)) == marker as String {
            let outer = NSRange(location: range.location - markerLength, length: range.length + 2 * markerLength)
            let inner = text.substring(with: range)
            return (outer, inner, NSRange(location: outer.location, length: (inner as NSString).length))
        }

        // `range` itself includes the markers, e.g. the whole "*bold*" is selected.
        if range.length >= 2 * markerLength {
            let content = text.substring(with: range)
            if content.hasPrefix(marker as String), content.hasSuffix(marker as String) {
                let inner = String(content.dropFirst(markerLength).dropLast(markerLength))
                return (range, inner, NSRange(location: range.location, length: (inner as NSString).length))
            }
        }

        let replacement = (marker as String) + text.substring(with: range) + (marker as String)
        return (range, replacement, NSRange(location: range.location + markerLength, length: range.length))
    }
}
