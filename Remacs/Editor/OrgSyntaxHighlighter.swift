//
//  OrgSyntaxHighlighter.swift
//  Remacs
//
//  Regex-based syntax highlighter for org-mode text. Pure and stateless: given the full
//  document text it returns the outline structure (for folding) and a list of attribute
//  runs to apply. The underlying plain-text storage is never modified by this pass.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum OrgSyntaxHighlighter {

    struct Result {
        var headlines: [OrgHeadline]
        var foldRegions: [OrgFoldRegion]
        var attributeRuns: [(NSRange, [NSAttributedString.Key: Any])]
    }

    // MARK: - Patterns

    private static let headlineRegex = try! NSRegularExpression(
        pattern: #"^(\*+)[ \t]+(?:(TODO|NEXT|WAITING|SOMEDAY|DONE|CANCELLED)[ \t]+)?(?:\[#([A-C])\][ \t]+)?(.*?)[ \t]*((?::[\w@%]+)+:)?[ \t]*$"#,
        options: [.anchorsMatchLines]
    )
    private static let blockBeginRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*#\+begin_(\w+).*$"#, options: [.anchorsMatchLines, .caseInsensitive]
    )
    private static let blockEndRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*#\+end_(\w+)[ \t]*$"#, options: [.anchorsMatchLines, .caseInsensitive]
    )
    private static let metaLineRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*#\+[\w-]+:.*$"#, options: [.anchorsMatchLines]
    )
    private static let commentLineRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*#([ \t].*)?$"#, options: [.anchorsMatchLines]
    )
    private static let drawerLineRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*:([\w-]+):[ \t]*$"#, options: [.anchorsMatchLines]
    )
    private static let checkboxRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:[-+]|\d+[.)])[ \t]+\[([ Xx-])\]"#, options: [.anchorsMatchLines]
    )
    private static let dashBulletRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*[-+][ \t]+"#, options: [.anchorsMatchLines]
    )
    private static let starBulletRegex = try! NSRegularExpression(
        pattern: #"^[ \t]+\*[ \t]+"#, options: [.anchorsMatchLines]
    )
    private static let numberedListRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*\d+[.)][ \t]+"#, options: [.anchorsMatchLines]
    )
    private static let linkRegex = try! NSRegularExpression(
        pattern: #"\[\[([^\]\n]+)\](?:\[([^\]\n]+)\])?\]"#
    )
    private static let horizontalRuleRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*-{5,}[ \t]*$"#, options: [.anchorsMatchLines]
    )

    private static func emphasisRegex(escapedMarker m: String) -> NSRegularExpression {
        let pattern = "\(m)([^\\s\(m)](?:[^\(m)\\n]*[^\\s\(m)])?)\(m)"
        return try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let boldRegex = emphasisRegex(escapedMarker: "\\*")
    private static let italicRegex = emphasisRegex(escapedMarker: "/")
    private static let underlineRegex = emphasisRegex(escapedMarker: "_")
    private static let codeRegex = emphasisRegex(escapedMarker: "=")
    private static let verbatimRegex = emphasisRegex(escapedMarker: "~")
    private static let strikeRegex = emphasisRegex(escapedMarker: "\\+")

    // MARK: - Entry point

    static func highlight(_ text: NSString) -> Result {
        let fullRange = NSRange(location: 0, length: text.length)
        var runs: [(NSRange, [NSAttributedString.Key: Any])] = []

        let blocks = findBlocks(in: text)
        let blockRanges = blocks.map(\.range)
        func isInsideBlock(_ range: NSRange) -> Bool {
            blockRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        for block in blockRanges {
            runs.append((block, [
                .font: PlatformFont.orgBody.orgMonospaced,
                .foregroundColor: PlatformColor.orgCode
            ]))
        }

        // Headlines
        var headlines: [OrgHeadline] = []
        var headlineLineRanges: [NSRange] = []
        headlineRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match else { return }
            let lineRange = text.lineRange(for: NSRange(location: match.range.location, length: 0))
            let level = match.range(at: 1).length
            headlines.append(OrgHeadline(level: level, lineStart: lineRange.location, lineEnd: lineRange.location + lineRange.length))
            headlineLineRanges.append(lineRange)

            runs.append((lineRange, [
                .font: PlatformFont.orgHeadline(level: level),
                .foregroundColor: PlatformColor.orgHeadlineColor(level: level)
            ]))

            let keywordRange = match.range(at: 2)
            if keywordRange.location != NSNotFound {
                let keyword = text.substring(with: keywordRange)
                let color: PlatformColor = keyword == "DONE" || keyword == "CANCELLED" ? .orgDone : .orgTodo
                runs.append((keywordRange, [.foregroundColor: color]))
            }

            let tagsRange = match.range(at: 5)
            if tagsRange.location != NSNotFound {
                runs.append((tagsRange, [
                    .foregroundColor: PlatformColor.orgTag,
                    .font: PlatformFont.orgBody.orgMonospaced
                ]))
            }
        }

        // Resolve subtree (fold) ranges
        for i in headlines.indices {
            let level = headlines[i].level
            var bodyEnd = text.length
            for j in (i + 1)..<headlines.count where headlines[j].level <= level {
                bodyEnd = headlines[j].lineStart
                break
            }
            headlines[i].bodyEnd = bodyEnd
        }

        func isInsideHeadline(_ range: NSRange) -> Bool {
            headlineLineRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        // Block and drawer fold regions
        var foldRegions: [OrgFoldRegion] = blocks.map { (block, name) in
            let openingLine = text.lineRange(for: NSRange(location: block.location, length: 0))
            return OrgFoldRegion(
                kind: .block,
                name: name,
                lineStart: block.location,
                lineEnd: NSMaxRange(openingLine),
                closingLineStart: text.lineRange(for: NSRange(location: NSMaxRange(block) - 1, length: 0)).location,
                bodyEnd: NSMaxRange(text.lineRange(for: block))
            )
        }
        foldRegions += findDrawers(in: text, excluding: blockRanges, headlineLineRanges: headlineLineRanges)
        func isExcluded(_ range: NSRange) -> Bool {
            isInsideBlock(range) || isInsideHeadline(range)
        }

        // Block delimiter lines (dim them, they're not content)
        blockBeginRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match else { return }
            runs.append((match.range, [.foregroundColor: PlatformColor.orgSecondaryText, .font: PlatformFont.orgBody.orgMonospaced]))
        }
        blockEndRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match else { return }
            runs.append((match.range, [.foregroundColor: PlatformColor.orgSecondaryText, .font: PlatformFont.orgBody.orgMonospaced]))
        }

        // Metadata / comment / drawer lines
        for regex in [metaLineRegex, commentLineRegex, drawerLineRegex] {
            regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
                guard let match, !isInsideBlock(match.range) else { return }
                runs.append((match.range, [.foregroundColor: PlatformColor.orgTertiaryText]))
            }
        }

        // Horizontal rules
        horizontalRuleRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match, !isExcluded(match.range) else { return }
            runs.append((match.range, [.foregroundColor: PlatformColor.orgSecondaryText]))
        }

        // Checkboxes
        checkboxRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match, !isExcluded(match.range) else { return }
            let box = match.range(at: 1)
            let checked = text.substring(with: box).lowercased() == "x"
            runs.append((box, [.foregroundColor: checked ? PlatformColor.orgDone : PlatformColor.orgTodo]))
        }

        // List bullets
        for regex in [dashBulletRegex, starBulletRegex, numberedListRegex] {
            regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
                guard let match, !isExcluded(match.range) else { return }
                runs.append((match.range, [.foregroundColor: PlatformColor.orgText]))
            }
        }

        // Links
        linkRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match, !isExcluded(match.range) else { return }
            runs.append((match.range, [.foregroundColor: PlatformColor.orgLink, .underlineStyle: 1]))
        }

        // Emphasis markers
        let emphasisStyles: [(NSRegularExpression, [NSAttributedString.Key: Any])] = [
            (boldRegex, [.font: PlatformFont.orgBody]),
            (italicRegex, [.font: PlatformFont.orgBody.orgItalic]),
            (underlineRegex, [.underlineStyle: 1]),
            (codeRegex, [.foregroundColor: PlatformColor.orgCode, .font: PlatformFont.orgBody.orgMonospaced]),
            (verbatimRegex, [.foregroundColor: PlatformColor.orgCode, .font: PlatformFont.orgBody.orgMonospaced]),
            (strikeRegex, [.strikethroughStyle: 1])
        ]
        for (regex, attrs) in emphasisStyles {
            regex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
                guard let match, !isExcluded(match.range) else { return }
                var finalAttrs = attrs
                if regex === boldRegex {
                    #if os(macOS)
                    finalAttrs[.font] = NSFontManager.shared.convert(PlatformFont.orgBody, toHaveTrait: .boldFontMask)
                    #else
                    finalAttrs[.font] = PlatformFont.orgBody.fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: PlatformFont.orgBody.pointSize) } ?? PlatformFont.orgBody
                    #endif
                }
                runs.append((match.range, finalAttrs))
            }
        }

        return Result(headlines: headlines, foldRegions: foldRegions, attributeRuns: runs)
    }

    // MARK: - Blocks

    /// Returns each block's range (from the start of its `#+begin_` line to the end of its
    /// `#+end_` line, excluding the trailing newline) and its lowercased type, e.g. "src".
    private static func findBlocks(in text: NSString) -> [(range: NSRange, name: String)] {
        let fullRange = NSRange(location: 0, length: text.length)
        var events: [(location: Int, isBegin: Bool, lineEnd: Int, name: String)] = []
        blockBeginRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match else { return }
            events.append((match.range.location, true, match.range.location + match.range.length, text.substring(with: match.range(at: 1)).lowercased()))
        }
        blockEndRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match else { return }
            events.append((match.range.location, false, match.range.location + match.range.length, text.substring(with: match.range(at: 1)).lowercased()))
        }
        events.sort { $0.location < $1.location }

        var blocks: [(range: NSRange, name: String)] = []
        var stack: [(location: Int, name: String)] = []
        for event in events {
            if event.isBegin {
                stack.append((event.location, event.name))
            } else if let start = stack.popLast() {
                blocks.append((NSRange(location: start.location, length: event.lineEnd - start.location), start.name))
            }
        }
        return blocks
    }

    // MARK: - Drawers

    /// Pairs each `:NAME:` line with the next `:END:` line. A drawer can't contain a
    /// headline, and drawer-like lines inside blocks are ignored.
    private static func findDrawers(in text: NSString, excluding blockRanges: [NSRange], headlineLineRanges: [NSRange]) -> [OrgFoldRegion] {
        let fullRange = NSRange(location: 0, length: text.length)
        var drawers: [OrgFoldRegion] = []
        var openingLine: NSRange?
        var openingName = ""
        drawerLineRegex.enumerateMatches(in: text as String, range: fullRange) { match, _, _ in
            guard let match,
                  !blockRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return }
            let lineRange = text.lineRange(for: NSRange(location: match.range.location, length: 0))
            let name = text.substring(with: match.range(at: 1)).lowercased()
            guard name == "end" else {
                openingLine = lineRange
                openingName = name
                return
            }
            guard let opening = openingLine else { return }
            openingLine = nil
            let crossesHeadline = headlineLineRanges.contains {
                $0.location >= NSMaxRange(opening) && $0.location < lineRange.location
            }
            guard !crossesHeadline else { return }
            drawers.append(OrgFoldRegion(
                kind: .drawer,
                name: openingName,
                lineStart: opening.location,
                lineEnd: NSMaxRange(opening),
                closingLineStart: lineRange.location,
                bodyEnd: NSMaxRange(lineRange)
            ))
        }
        return drawers
    }
}
