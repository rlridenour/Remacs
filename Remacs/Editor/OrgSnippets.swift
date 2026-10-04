//
//  OrgSnippets.swift
//  Remacs
//
//  Expands a keyword typed just before the cursor into a longer piece of text when Tab is
//  pressed, e.g. typing "date" then Tab inserts today's date, or "<q" then Tab wraps into
//  a #+begin_quote/#+end_quote block with the cursor left inside it.
//
//  Snippets come from an org file the user chooses (see OrgSnippetLibrary), falling back
//  to `defaultLibraryText`.
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

    // MARK: - Snippet library

    /// The snippets used when no snippets file has been chosen, and the starting content of
    /// a new snippets file. The `<x` entries mirror Emacs org-tempo's structure templates.
    static let defaultLibraryText = #"""
    #+title: Remacs Snippets

    # Each headline defines one snippet. Its first word is the keyword: type it, then
    # press Tab to expand it. Keywords are letters and digits, optionally starting with
    # "<". Anything after the keyword on the headline is ignored, so you can use it as a
    # description.
    #
    # The text under the headline is the expansion (blank lines around it are trimmed).
    # $1, $2, ... are tab stops, visited in order with Tab, and $0 is where the cursor
    # ends up (the end of the expansion if there's no $0). Write \$ for a literal dollar
    # sign before a digit. {{date}} and {{time}} insert the current date and time.
    # Start a line with ",*" for an expansion line that begins with "*".

    * date  Today's date
    {{date}}

    * time  The current time
    {{time}}

    * <q  Quote block
    #+begin_quote
    $0
    #+end_quote

    * <s  Source block
    #+begin_src $1
    $0
    #+end_src

    * <v  Verse block
    #+begin_verse
    $0
    #+end_verse

    * <c  Center block
    #+begin_center
    $0
    #+end_center

    * ttable  Typst table attributes
    #+ATTR_TYPST: :stroke none :columns auto :align

    * tsfh  Touying standard-form import
    #+TOUYING_IMPORT: "@local/standard-form:0.2.0": *

    * sfh  Typst standard-form import
    #+TYPST: #import "@local/standard-form:0.2.0": standard-form

    * t2c  Touying two columns
    #+begin_columns
    #+begin_column
    $1
    #+end_column
    #+begin_column
    $2
    #+end_column
    #+end_columns

    * tff  Touying full slide
    #+begin_fullslide
    $0
    #+end_fullslide

    * timg  Touying image attributes
    #+ATTR_TOUYING: :width auto :height auto :fit "contain"

    * tmp  Touying statement slide
    #+begin_fullslide
    #+ATTR_TOUYING: :size 2em
    #+begin_statement
    $0
    #+end_statement
    #+end_fullslide

    * tn  Touying speaker and handout notes
    #+begin_speakernote
    $1
    #+end_speakernote

    #+begin_handoutnote
    $2
    #+end_handoutnote

    * tp  Touying pause
    @@typst:#pause@@
    """#

    static let builtInTemplates = parseLibrary(defaultLibraryText)

    /// Parses a snippets org file into keyword -> template. Each headline starts a snippet
    /// keyed by the headline's first word; the lines under it (up to the next headline,
    /// with surrounding blank lines trimmed) are its template. Text before the first
    /// headline is ignored, as are headlines whose keyword could never be typed. If a
    /// keyword appears twice, the first one wins.
    static func parseLibrary(_ text: String) -> [String: String] {
        var templates: [String: String] = [:]
        var keyword: String?
        var body: [String] = []

        func finishSnippet() {
            defer { keyword = nil; body = [] }
            guard let keyword, templates[keyword] == nil else { return }
            while body.first?.allSatisfy(\.isWhitespace) == true { body.removeFirst() }
            while body.last?.allSatisfy(\.isWhitespace) == true { body.removeLast() }
            templates[keyword] = body.joined(separator: "\n")
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
            if let headlineKeyword = snippetKeyword(inHeadline: line) {
                finishSnippet()
                keyword = isValidKeyword(headlineKeyword) ? headlineKeyword : nil
            } else if keyword != nil {
                body.append(unescapeBodyLine(line))
            }
        }
        finishSnippet()
        return templates
    }

    /// The first word after the stars, if `line` is a headline; "" for a headline with no text.
    private static func snippetKeyword(inHeadline line: String) -> String? {
        let afterStars = line.drop { $0 == "*" }
        guard afterStars.count < line.count else { return nil }
        if afterStars.isEmpty { return "" }
        guard afterStars.first == " " || afterStars.first == "\t" else { return nil }
        return afterStars.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    }

    /// Matches what `keywordStart(text:before:)` can find before the cursor: letters and
    /// digits, optionally preceded by a single "<".
    private static func isValidKeyword(_ keyword: String) -> Bool {
        let word = keyword.hasPrefix("<") ? keyword.dropFirst() : Substring(keyword)
        return !word.isEmpty && word.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    /// Org's escaping for literal lines: a comma before "*" or "#+" (or before further
    /// commas leading up to one) is dropped, so ",*" yields a line starting with "*".
    private static func unescapeBodyLine(_ line: String) -> String {
        guard line.hasPrefix(",") else { return line }
        let rest = line.dropFirst().drop { $0 == "," }
        return rest.hasPrefix("*") || rest.hasPrefix("#+") ? String(line.dropFirst()) : line
    }

    /// Fills in the `{{date}}` and `{{time}}` placeholders with the current moment.
    private static func fillPlaceholders(_ template: String) -> String {
        guard template.contains("{{") else { return template }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let now = Date()
        return template
            .replacingOccurrences(of: "{{date}}", with: dateFormatter.string(from: now))
            .replacingOccurrences(of: "{{time}}", with: timeFormatter.string(from: now))
    }

    // MARK: - Expansion

    /// Returns the expansion for the keyword immediately before `cursorLocation`, or `nil`
    /// if there's no such keyword (or it doesn't match a snippet), so the caller can fall
    /// back to its normal Tab behavior.
    static func expansion(text: NSString, cursorLocation: Int) -> Action? {
        guard let wordStart = keywordStart(text: text, before: cursorLocation) else { return nil }
        let range = NSRange(location: wordStart, length: cursorLocation - wordStart)
        let keyword = text.substring(with: range)
        guard let template = OrgSnippetLibrary.shared.templates[keyword] else { return nil }

        let (replacement, stopOffsets) = parseTabStops(fillPlaceholders(template))
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
