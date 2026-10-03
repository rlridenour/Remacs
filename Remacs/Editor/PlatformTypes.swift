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
    static let orgBody: PlatformFont = .monospacedSystemFont(ofSize: 16, weight: .regular)

    static func orgHeadline(level: Int) -> PlatformFont {
        let size: CGFloat = max(16, 23 - CGFloat(max(0, level - 1)) * 1.5)
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

    /// Creates a color that resolves to one 24-bit RGB hex value in light appearance and
    /// another in dark appearance.
    convenience init(light: UInt32, dark: UInt32) {
        #if os(macOS)
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return PlatformColor(hex: isDark ? dark : light)
        }
        #else
        self.init { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? PlatformColor(hex: dark) : PlatformColor(hex: light)
        }
        #endif
    }

    static var orgBackground: PlatformColor { PlatformColor(light: 0xFAFAFA, dark: 0x121212) }

    static var orgText: PlatformColor { PlatformColor(light: 0x0A0A0A, dark: 0xD4D4D4) }

    static var orgSecondaryText: PlatformColor { PlatformColor(light: 0x737373, dark: 0x868686) }

    static var orgTertiaryText: PlatformColor { PlatformColor(light: 0xA3A3A3, dark: 0x565656) }

    static func orgHeadlineColor(level: Int) -> PlatformColor { .orgText }

    static var orgTodo: PlatformColor { PlatformColor(light: 0xB91C1C, dark: 0xF87171) }
    static var orgDone: PlatformColor { PlatformColor(light: 0x15803D, dark: 0x4ADE80) }
    static var orgTag: PlatformColor { PlatformColor(light: 0x6D28D9, dark: 0xA78BFA) }
    static var orgCode: PlatformColor { .orgText }
    static var orgLink: PlatformColor { PlatformColor(light: 0x1D4ED8, dark: 0x60A5FA) }

    static var orgCodeBackground: PlatformColor { .orgBackground }
}
