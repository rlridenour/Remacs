//
//  OrgListFormatting.swift
//  Remacs
//
//  Shared (platform-agnostic) logic for list editing: continuing/clearing an item on
//  Return (renumbering enumerated lists as needed), and demoting/promoting an item's
//  indentation on Tab/Shift-Tab.
//

import Foundation

/// A parsed org-mode list item line (a line starting with `-`, `+`, an indented `*`, or a
/// number followed by `.` or `)`).
struct OrgListLine {
    let indentation: String
    let bulletChar: Character?
    let number: Int?
    let delimiter: Character?
    let spacing: String
    let content: String
}

enum OrgListFormatting {
    private static let listLineRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)([-+]|\d+[.)]|\*)([ \t]+)(.*)$"#
    )

    /// Parses `line` (a single line's text, no newline) as a list item, or `nil` if it
    /// isn't one. A bare `*` at the very start of the line is a headline, not a list item.
    static func parse(_ line: String) -> OrgListLine? {
        let ns = line as NSString
        guard let match = listLineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let indentation = ns.substring(with: match.range(at: 1))
        let marker = ns.substring(with: match.range(at: 2))
        let spacing = ns.substring(with: match.range(at: 3))
        let content = ns.substring(with: match.range(at: 4))

        if marker == "*" {
            guard !indentation.isEmpty else { return nil }
            return OrgListLine(indentation: indentation, bulletChar: "*", number: nil, delimiter: nil, spacing: spacing, content: content)
        }
        if marker == "-" || marker == "+" {
            return OrgListLine(indentation: indentation, bulletChar: Character(marker), number: nil, delimiter: nil, spacing: spacing, content: content)
        }
        let delimiter = marker.last!
        guard let number = Int(marker.dropLast()) else { return nil }
        return OrgListLine(indentation: indentation, bulletChar: nil, number: number, delimiter: delimiter, spacing: spacing, content: content)
    }

    /// Renumbers the run of numbered-list siblings starting at `scanStart` (which must be
    /// the start of a line) that match `indentation` and `delimiter`, assigning them
    /// sequential numbers beginning at `startNumber`. Returns the reconstructed lines and
    /// the character offset just past the last one's content (or `scanStart` if none matched).
    fileprivate static func renumberSiblings(
        text: NSString, from scanStart: Int, indentation: String, delimiter: Character, startNumber: Int
    ) -> (lines: [String], runEnd: Int) {
        var lines: [String] = []
        var runEnd = scanStart
        var scanLoc = scanStart
        var expected = startNumber
        while scanLoc < text.length {
            var sLineStart = 0, sLineEnd = 0, sContentsEnd = 0
            text.getLineStart(&sLineStart, end: &sLineEnd, contentsEnd: &sContentsEnd, for: NSRange(location: scanLoc, length: 0))
            let sLineText = text.substring(with: NSRange(location: sLineStart, length: sContentsEnd - sLineStart))
            guard let sItem = OrgListFormatting.parse(sLineText),
                  sItem.indentation == indentation,
                  sItem.delimiter == delimiter else { break }
            lines.append(indentation + "\(expected)\(delimiter)" + sItem.spacing + sItem.content)
            runEnd = sContentsEnd
            expected += 1
            guard sLineEnd < text.length else { break }
            scanLoc = sLineEnd
        }
        return (lines, runEnd)
    }
}

enum OrgListReturn {
    struct Action {
        let replaceRange: NSRange
        let replacement: String
        let newCursorLocation: Int
    }

    /// Determines the special Return-key behavior for the list item at `cursorLocation`,
    /// if any applies. Returns `nil` when the cursor isn't at the end of a list item's own
    /// line content, in which case the caller should fall back to a plain newline.
    static func action(text: NSString, cursorLocation: Int) -> Action? {
        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: cursorLocation, length: 0))
        guard cursorLocation == contentsEnd else { return nil }

        let lineText = text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        guard let item = OrgListFormatting.parse(lineText) else { return nil }

        let scanStart = lineEnd

        if item.content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item -- clear it back to a plain, empty line, renumbering any
            // subsequent numbered siblings down to close the gap.
            var runEnd = contentsEnd
            var replacement = ""
            if let delimiter = item.delimiter, let number = item.number {
                let (siblingLines, siblingRunEnd) = OrgListFormatting.renumberSiblings(
                    text: text, from: scanStart, indentation: item.indentation, delimiter: delimiter, startNumber: number
                )
                if !siblingLines.isEmpty {
                    runEnd = siblingRunEnd
                    replacement = "\n" + siblingLines.joined(separator: "\n")
                }
            }
            let range = NSRange(location: lineStart, length: runEnd - lineStart)
            return Action(replaceRange: range, replacement: replacement, newCursorLocation: lineStart)
        }

        if let number = item.number, let delimiter = item.delimiter {
            // Numbered list -- start the next item, renumbering subsequent siblings up.
            let newItemLine = item.indentation + "\(number + 1)\(delimiter)" + item.spacing
            let (siblingLines, runEnd) = OrgListFormatting.renumberSiblings(
                text: text, from: scanStart, indentation: item.indentation, delimiter: delimiter, startNumber: number + 2
            )
            let replacement = "\n" + ([newItemLine] + siblingLines).joined(separator: "\n")
            let range = NSRange(location: cursorLocation, length: runEnd - cursorLocation)
            let newCursorLocation = cursorLocation + 1 + (newItemLine as NSString).length
            return Action(replaceRange: range, replacement: replacement, newCursorLocation: newCursorLocation)
        }

        // Bullet list (-, +, or an indented *) -- no renumbering involved.
        let newLine = item.indentation + String(item.bulletChar!) + item.spacing
        let insertion = "\n" + newLine
        let range = NSRange(location: cursorLocation, length: 0)
        return Action(replaceRange: range, replacement: insertion, newCursorLocation: cursorLocation + (insertion as NSString).length)
    }
}

enum OrgListIndent {
    struct Action {
        let replaceRange: NSRange
        let replacement: String
        let newCursorLocation: Int
    }

    private static let step = "  "

    /// Adds one indentation step to the list item's line, wherever the cursor sits within it.
    static func demote(text: NSString, cursorLocation: Int) -> Action? {
        guard let (lineStart, _) = currentListLine(text: text, cursorLocation: cursorLocation) else { return nil }
        let range = NSRange(location: lineStart, length: 0)
        return Action(replaceRange: range, replacement: step, newCursorLocation: cursorLocation + (step as NSString).length)
    }

    /// Removes up to one indentation step from the list item's line, wherever the cursor
    /// sits within it. Returns `nil` if the item has no indentation left to remove.
    static func promote(text: NSString, cursorLocation: Int) -> Action? {
        guard let (lineStart, item) = currentListLine(text: text, cursorLocation: cursorLocation) else { return nil }
        let removable = min((item.indentation as NSString).length, (step as NSString).length)
        guard removable > 0 else { return nil }
        let range = NSRange(location: lineStart, length: removable)
        let newCursorLocation = max(lineStart, cursorLocation - removable)
        return Action(replaceRange: range, replacement: "", newCursorLocation: newCursorLocation)
    }

    private static func currentListLine(text: NSString, cursorLocation: Int) -> (lineStart: Int, item: OrgListLine)? {
        var lineStart = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: cursorLocation, length: 0))
        let lineText = text.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
        guard let item = OrgListFormatting.parse(lineText) else { return nil }
        return (lineStart, item)
    }
}
