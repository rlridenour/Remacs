//
//  OrgFind.swift
//  Remacs
//
//  Shared (platform-agnostic) logic for the find/replace bar: locating matches and
//  picking which one comes next/previous relative to the current selection.
//

import Foundation

enum OrgFind {
    /// Every occurrence of `query` in `text`, case-insensitive, in document order.
    static func matches(of query: String, in text: NSString) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: query, options: .caseInsensitive, range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let nextLocation = found.location + max(found.length, 1)
            searchRange = NSRange(location: nextLocation, length: text.length - nextLocation)
        }
        return ranges
    }

    /// The match to select for "find next": the first one starting at or after
    /// `selection`'s end, wrapping around to the first match if there is none.
    static func indexAfter(_ selection: NSRange, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        let selectionEnd = selection.location + selection.length
        return matches.firstIndex { $0.location >= selectionEnd } ?? 0
    }

    /// The match to select for "find previous": the last one starting before
    /// `selection`'s start, wrapping around to the last match if there is none.
    static func indexBefore(_ selection: NSRange, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.lastIndex { $0.location < selection.location } ?? (matches.count - 1)
    }
}
