//
//  OrgSnippets.swift
//  Remacs
//
//  Expands a keyword typed just before the cursor into a longer piece of text when Tab is
//  pressed, e.g. typing "date" then Tab inserts today's date, or "<q" then Tab wraps into
//  a #+begin_quote/#+end_quote block with the cursor left inside it.
//

import Foundation

enum OrgSnippets {
    struct Action {
        let replaceRange: NSRange
        let replacement: String
        let newCursorLocation: Int
    }

    /// Marks where the cursor should land inside a template; stripped before insertion.
    /// Templates that omit it place the cursor at the end of the expansion instead.
    private static let cursorMarker = "\u{0}"

    /// Keyword -> expansion text. "date"/"time" are computed per-call so they reflect the
    /// current moment rather than being frozen at app launch. The `<x` entries mirror
    /// Emacs org-tempo's structure-template keys.
    private static var snippets: [String: String] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let marker = cursorMarker

        return [
            "date": dateFormatter.string(from: Date()),
            "time": timeFormatter.string(from: Date()),

            "<q": "#+begin_quote\n\(marker)\n#+end_quote",
            "<s": "#+begin_src \n\(marker)\n#+end_src",
            "<v": "#+begin_verse\n\(marker)\n#+end_verse",
            "<c": "#+begin_center\n\(marker)\n#+end_center",

            "ttable": "#+ATTR_TYPST: :stroke none :columns auto :align",
            "tsfh": "#+TOUYING_IMPORT: \"@local/standard-form:0.2.0\": *",
            "sfh": "#+TYPST: #import \"@local/standard-form:0.2.0\": standard-form",
            "t2c": "#+begin_columns\n#+begin_column\n\(marker)\n#+end_column\n#+begin_column\n\n#+end_column\n#+end_columns",
            "tff": "#+begin_fullslide\n\(marker)\n#+end_fullslide",
            "timg": "#+ATTR_TOUYING: :width auto :height auto :fit \"contain\"",
            "tmp": "#+begin_fullslide\n#+ATTR_TOUYING: :size 2em\n#+begin_statement\n\(marker)\n#+end_statement\n#+end_fullslide",
            "tn": "#+begin_speakernote\n\(marker)\n#+end_speakernote\n\n#+begin_handoutnote\n\n#+end_handoutnote",
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

        let markerRange = (template as NSString).range(of: cursorMarker)
        let replacement = template.replacingOccurrences(of: cursorMarker, with: "")
        let cursorOffset = markerRange.location == NSNotFound ? (replacement as NSString).length : markerRange.location
        let newCursorLocation = wordStart + cursorOffset
        return Action(replaceRange: range, replacement: replacement, newCursorLocation: newCursorLocation)
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
