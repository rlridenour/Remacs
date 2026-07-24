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
    /// Creates a color from a 24-bit RGB hex value, e.g. `PlatformColor(hex: 0xFF6B35)`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    static var orgBackground: PlatformColor { PlatformColor(hex: 0xFFFCF0) }

    static var orgText: PlatformColor { PlatformColor(hex: 0x100F0F) }

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

    static func orgHeadlineColor(level: Int) -> PlatformColor { PlatformColor(hex: 0x100F0F) }

    static var orgTodo: PlatformColor { PlatformColor(hex: 0xAF3029) }
    static var orgDone: PlatformColor { PlatformColor(hex: 0x66800B) }
    static var orgTag: PlatformColor { PlatformColor(hex: 0x5E409D) }
    static var orgCode: PlatformColor { PlatformColor(hex: 0xBC5215) }
    static var orgLink: PlatformColor { PlatformColor(hex: 0x205EA6) }

    static var orgCodeBackground: PlatformColor {
        #if os(macOS)
        return NSColor.textBackgroundColor.blended(withFraction: 0.06, of: .labelColor) ?? .textBackgroundColor
        #else
        return .secondarySystemBackground
        #endif
    }
}
