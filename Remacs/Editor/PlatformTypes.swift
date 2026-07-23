//
//  PlatformTypes.swift
//  Remacs
//
//  Cross-platform (AppKit/UIKit) type aliases and styling helpers used by the org-mode editor.
//

import Foundation

#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

extension PlatformFont {
    static let orgBody: PlatformFont = .monospacedSystemFont(ofSize: 15, weight: .regular)

    static func orgHeadline(level: Int) -> PlatformFont {
        let size: CGFloat = max(15, 22 - CGFloat(max(0, level - 1)) * 1.5)
        #if os(macOS)
        return NSFont.boldSystemFont(ofSize: size)
        #else
        return UIFont.systemFont(ofSize: size, weight: .bold)
        #endif
    }

    var orgItalic: PlatformFont {
        #if os(macOS)
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
        #else
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitItalic) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
        #endif
    }

    var orgMonospaced: PlatformFont {
        .monospacedSystemFont(ofSize: pointSize, weight: .regular)
    }
}

extension PlatformColor {
    static var orgText: PlatformColor {
        #if os(macOS)
        return .labelColor
        #else
        return .label
        #endif
    }

    static var orgSecondaryText: PlatformColor {
        #if os(macOS)
        return .secondaryLabelColor
        #else
        return .secondaryLabel
        #endif
    }

    static var orgTertiaryText: PlatformColor {
        #if os(macOS)
        return .tertiaryLabelColor
        #else
        return .tertiaryLabel
        #endif
    }

    static func orgHeadlineColor(level: Int) -> PlatformColor {
        let palette: [PlatformColor] = [
            .systemBlue, .systemTeal, .systemIndigo, .systemPurple,
            .systemPink, .systemOrange, .systemGreen, .systemBrown
        ]
        return palette[max(0, level - 1) % palette.count]
    }

    static var orgTodo: PlatformColor { .systemRed }
    static var orgDone: PlatformColor { .systemGreen }
    static var orgTag: PlatformColor { .systemPurple }
    static var orgCode: PlatformColor { .systemOrange }
    static var orgLink: PlatformColor { .systemBlue }

    static var orgCodeBackground: PlatformColor {
        #if os(macOS)
        return NSColor.textBackgroundColor.blended(withFraction: 0.06, of: .labelColor) ?? .textBackgroundColor
        #else
        return .secondarySystemBackground
        #endif
    }
}
