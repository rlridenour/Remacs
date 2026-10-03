//
//  OrgFoldRegion.swift
//  Remacs
//

import Foundation

/// A foldable region that isn't a headline subtree: a `#+begin_…`/`#+end_…` block or a
/// `:NAME:`/`:END:` drawer. Folding hides everything after the opening line up to and
/// including the closing line, leaving only the opening line visible.
struct OrgFoldRegion: Equatable {
    enum Kind: Equatable {
        case block
        case drawer
    }

    let kind: Kind
    /// Character offset of the start of the opening (`#+begin_…` or `:NAME:`) line.
    let lineStart: Int
    /// Character offset just past the end of the opening line (including its trailing newline).
    let lineEnd: Int
    /// Character offset of the start of the closing (`#+end_…` or `:END:`) line.
    let closingLineStart: Int
    /// Character offset just past the end of the closing line (including its trailing newline).
    let bodyEnd: Int

    /// Whether this region has any content that could be hidden by folding.
    var canFold: Bool { bodyEnd > lineEnd }
}
