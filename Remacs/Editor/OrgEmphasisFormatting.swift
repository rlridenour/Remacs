//
//  OrgEmphasisFormatting.swift
//  Remacs
//
//  Shared (platform-agnostic) logic for the emphasis keyboard shortcuts: wrapping a
//  selection, or the word under the cursor, with org-mode emphasis markers.
//

import Foundation

enum OrgEmphasis: String {
    case bold = "*"
    case italic = "/"
    case underline = "_"
    case code = "="
}

enum OrgEmphasisFormatting {
    /// Resolves the range of text a shortcut should wrap: the current selection if
    /// non-empty, otherwise the word under the cursor (via `wordRangeProvider`). Returns
    /// `nil` if there's no selection and the cursor isn't on a word.
    static func targetRange(selectedRange: NSRange, in text: NSString, wordRangeProvider: () -> NSRange?) -> NSRange? {
        if selectedRange.length > 0 { return selectedRange }
        guard let wordRange = wordRangeProvider(), wordRange.length > 0 else { return nil }
        let content = text.substring(with: wordRange)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return wordRange
    }

    /// Wraps `range` with the emphasis marker, returning the replacement text and the
    /// range (within the replacement) that the emphasized content -- excluding markers --
    /// should be selected as afterwards.
    static func wrap(_ range: NSRange, in text: NSString, with emphasis: OrgEmphasis) -> (replacement: String, innerSelection: NSRange) {
        let marker = emphasis.rawValue
        let replacement = marker + text.substring(with: range) + marker
        return (replacement, NSRange(location: range.location + 1, length: range.length))
    }
}
