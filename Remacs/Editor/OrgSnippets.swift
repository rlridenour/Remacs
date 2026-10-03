//
//  OrgSnippets.swift
//  Remacs
//
//  Expands a keyword typed just before the cursor into a longer piece of text when Tab is
//  pressed, e.g. typing "date" then Tab inserts today's date, or "<q" then Tab wraps into
//  a #+begin_quote/#+end_quote block with the cursor left inside it.
//
//  Templates mark tab stops yasnippet-style: `$1`, `$2`, … are visited in order with Tab,
//  and `$0` is the final position (the end of the expansion if omitted). A literal dollar
//  sign before a digit is written `\$`.
//

import Foundation

enum OrgSnippets {
    struct Action {
        let replaceRange: NSRange
        let replacement: String
        let newCursorLocation: Int
        /// The tab stops still to visit after `newCursorLocation`, or nil if there are none.
        let session: OrgSnippetSession?
    }

    /// Keyword -> expansion text. "date"/"time" are computed per-call so they reflect the
    /// current moment rather than being frozen at app launch. The `<x` entries mirror
    /// Emacs org-tempo's structure-template keys.
    private static var snippets: [String: String] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        return [
            "date": dateFormatter.string(from: Date()),
            "time": timeFormatter.string(from: Date()),

            "<q": "#+begin_quote\n$0\n#+end_quote",
            "<s": "#+begin_src $1\n$0\n#+end_src",
            "<v": "#+begin_verse\n$0\n#+end_verse",
            "<c": "#+begin_center\n$0\n#+end_center",

            "ttable": "#+ATTR_TYPST: :stroke none :columns auto :align",
            "tsfh": "#+TOUYING_IMPORT: \"@local/standard-form:0.2.0\": *",
            "sfh": "#+TYPST: #import \"@local/standard-form:0.2.0\": standard-form",
            "t2c": "#+begin_columns\n#+begin_column\n$1\n#+end_column\n#+begin_column\n$2\n#+end_column\n#+end_columns",
            "tff": "#+begin_fullslide\n$0\n#+end_fullslide",
            "timg": "#+ATTR_TOUYING: :width auto :height auto :fit \"contain\"",
            "tmp": "#+begin_fullslide\n#+ATTR_TOUYING: :size 2em\n#+begin_statement\n$0\n#+end_statement\n#+end_fullslide",
            "tn": "#+begin_speakernote\n$1\n#+end_speakernote\n\n#+begin_handoutnote\n$2\n#+end_handoutnote",
            "tp": "@@typst:#pause@@"
        ]
    }

    /// Returns the expansion for the keyword immediately before `cursorLocation`, or `nil`
    /// if there's no such keyword (or it doesn't match a snippet), so the caller can fall
    /// back to its normal Tab behavior.
    static func expansion(text: NSString, cursorLocation: Int) -> Action? {
        guard let wordStart = keywordStart(text: text, before: cursorLocation) else { return nil }
        let range = NSRange(location: wordStart, length: cursorLocation - wordStart)
        let keyword = text.substring(with: range)
        guard let template = snippets[keyword] else { return nil }

        let (replacement, stopOffsets) = parseTabStops(template)
        let stops = stopOffsets.map { wordStart + $0 }
        let remaining = Array(stops.dropFirst())
        let session = remaining.isEmpty ? nil : OrgSnippetSession(
            stops: remaining,
            range: NSRange(location: wordStart, length: (replacement as NSString).length)
        )
        return Action(replaceRange: range, replacement: replacement, newCursorLocation: stops[0], session: session)
    }

    /// Strips the `$N` markers out of `template`, returning the plain text and the UTF-16
    /// offsets of its tab stops in visiting order: `$1`, `$2`, … then `$0` (or the end of
    /// the text when there's no `$0`). Always returns at least one stop.
    static func parseTabStops(_ template: String) -> (text: String, stops: [Int]) {
        var text = ""
        var numbered: [(number: Int, offset: Int)] = []
        var finalStop: Int?
        var characters = template.makeIterator()
        var pending = characters.next()
        while let character = pending {
            pending = characters.next()
            if character == "\\", pending == "$" {
                text.append("$")
                pending = characters.next()
            } else if character == "$", let next = pending, let number = next.wholeNumberValue, next.isASCII {
                let offset = text.utf16.count
                if number == 0 {
                    finalStop = finalStop ?? offset
                } else {
                    numbered.append((number, offset))
                }
                pending = characters.next()
            } else {
                text.append(character)
            }
        }
        // Stable sort keeps repeated numbers in the order they appear.
        let ordered = numbered.enumerated()
            .sorted { ($0.element.number, $0.offset) < ($1.element.number, $1.offset) }
            .map(\.element.offset)
        return (text, ordered + [finalStop ?? text.utf16.count])
    }

    /// Finds the start of the run of letters/digits immediately before `cursorLocation` --
    /// i.e. the keyword the cursor is sitting right after -- including one leading "<" if
    /// present, to match org-tempo-style structure-template triggers like "<q". Returns
    /// `nil` if the character right before the cursor isn't a letter or digit at all.
    private static func keywordStart(text: NSString, before cursorLocation: Int) -> Int? {
        guard cursorLocation > 0 else { return nil }
        let searchRange = NSRange(location: 0, length: cursorLocation)
        let boundary = text.rangeOfCharacter(from: .alphanumerics.inverted, options: .backwards, range: searchRange)
        var start = boundary.location == NSNotFound ? 0 : boundary.location + boundary.length
        guard start < cursorLocation else { return nil }
        if start > 0, text.character(at: start - 1) == UInt16(UnicodeScalar("<").value) {
            start -= 1
        }
        return start
    }
}

/// The tab stops left to visit in a just-expanded snippet. Positions are kept in step
/// with edits by `remap(editedRange:delta:)` so they stay put while you type.
struct OrgSnippetSession: Equatable {
    /// Remaining stops, in visiting order.
    var stops: [Int]
    /// The extent of the expanded snippet. Moving the cursor outside it ends the session.
    var range: NSRange

    func contains(_ location: Int) -> Bool {
        range.location <= location && location <= NSMaxRange(range)
    }

    /// Shifts positions after an edit replacing `editedRange` with text `delta` characters
    /// longer (or shorter). Text typed exactly at a position goes before it, so a stop
    /// stays after anything typed at an earlier stop sharing its location.
    mutating func remap(editedRange: NSRange, delta: Int) {
        func remapped(_ position: Int) -> Int {
            let editEnd = NSMaxRange(editedRange)
            if position >= editEnd { return position + delta }
            if position > editedRange.location { return editedRange.location }
            return position
        }
        stops = stops.map(remapped)
        let start = remapped(range.location)
        // The range's start stays put when typing exactly at it.
        let adjustedStart = range.location == editedRange.location ? range.location : start
        range = NSRange(location: adjustedStart, length: max(remapped(NSMaxRange(range)) - adjustedStart, 0))
    }
}
