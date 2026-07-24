//
//  OrgHeadlineReturn.swift
//  Remacs
//
//  Shared (platform-agnostic) logic for headline editing: the Return-key behavior
//  (starting a new sibling heading, and clearing an empty one back to a plain line), and
//  demoting/promoting a heading's level on Option-Right/Option-Left.
//

import Foundation

enum OrgHeadlineReturn {
    struct Action {
        let replaceRange: NSRange
        let replacement: String
        let newCursorLocation: Int
    }

    /// Determines the special Return-key behavior for `headline`, if any applies. Returns
    /// `nil` when the cursor isn't at the end of the headline's own line content, in which
    /// case the caller should fall back to inserting a plain newline.
    static func action(headline: OrgHeadline?, cursorLocation: Int, text: NSString) -> Action? {
        guard let headline else { return nil }

        var contentsEnd = 0
        text.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: headline.lineStart, length: 0))
        guard cursorLocation == contentsEnd else { return nil }

        let stars = String(repeating: "*", count: headline.level)
        let lineContent = text.substring(with: NSRange(location: headline.lineStart, length: contentsEnd - headline.lineStart))
        guard lineContent.hasPrefix(stars) else { return nil }
        let rest = lineContent.dropFirst(headline.level)

        if rest.allSatisfy({ $0 == " " || $0 == "\t" }) {
            // An empty heading (e.g. one a prior Return just created) -- clear it back to a
            // plain, empty line instead of nesting yet another heading below it.
            let range = NSRange(location: headline.lineStart, length: contentsEnd - headline.lineStart)
            return Action(replaceRange: range, replacement: "", newCursorLocation: headline.lineStart)
        }

        // Start a new sibling heading of the same level, cursor after its two-space gap.
        let insertion = "\n" + stars + "  "
        let range = NSRange(location: cursorLocation, length: 0)
        return Action(replaceRange: range, replacement: insertion, newCursorLocation: cursorLocation + (insertion as NSString).length)
    }
}

enum OrgHeadlineIndent {
    struct Action {
        let replaceRange: NSRange
        let replacement: String
        let newCursorLocation: Int
    }

    /// Adds one asterisk to `headline`'s level, wherever the cursor sits on its line.
    static func demote(headline: OrgHeadline, cursorLocation: Int) -> Action {
        let insertLocation = headline.lineStart + headline.level
        let range = NSRange(location: insertLocation, length: 0)
        let newCursorLocation = cursorLocation >= insertLocation ? cursorLocation + 1 : cursorLocation
        return Action(replaceRange: range, replacement: "*", newCursorLocation: newCursorLocation)
    }

    /// Removes one asterisk from `headline`'s level, wherever the cursor sits on its line.
    /// Returns `nil` if the heading is already at the top level.
    static func promote(headline: OrgHeadline, cursorLocation: Int) -> Action? {
        guard headline.level > 1 else { return nil }
        let removeStart = headline.lineStart + headline.level - 1
        let removeEnd = removeStart + 1
        let range = NSRange(location: removeStart, length: 1)
        let newCursorLocation: Int
        if cursorLocation >= removeEnd {
            newCursorLocation = cursorLocation - 1
        } else if cursorLocation > removeStart {
            newCursorLocation = removeStart
        } else {
            newCursorLocation = cursorLocation
        }
        return Action(replaceRange: range, replacement: "", newCursorLocation: newCursorLocation)
    }
}
