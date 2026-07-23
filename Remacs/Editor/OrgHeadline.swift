//
//  OrgHeadline.swift
//  Remacs
//

import Foundation

/// A parsed org-mode headline (a line starting with one or more `*`).
struct OrgHeadline: Equatable {
    /// Number of leading asterisks, i.e. outline depth (1 = top level).
    let level: Int
    /// Character offset of the start of the headline's own line.
    let lineStart: Int
    /// Character offset just past the end of the headline's own line (including its trailing newline).
    let lineEnd: Int
    /// Character offset of the end of this headline's subtree (start of the next sibling/ancestor
    /// headline, or the end of the document).
    var bodyEnd: Int = 0

    /// Whether this headline has any body content that could be hidden by folding.
    var canFold: Bool { bodyEnd > lineEnd }
}
