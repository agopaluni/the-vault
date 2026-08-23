//
//  Theme.swift
//  The Vault
//
//  Centralized dark-mode-first palette and styling tokens. Design direction:
//  "Final Cut Pro meets Lightroom" — deep neutral background, a single warm
//  amber accent (reads more "filmmaker" than electric blue), SF Pro type.
//

import SwiftUI

enum Theme {
    // Backgrounds (deep neutrals)
    static let background       = Color(hex: "#1A1A1E")!      // app background
    static let surface          = Color(hex: "#222227")!      // panels / cards
    static let surfaceRaised     = Color(hex: "#2B2B31")!     // raised controls
    static let surfaceHover     = Color(hex: "#33333A")!
    static let stroke           = Color(hex: "#3A3A42")!      // hairline borders

    // Accent — warm amber
    static let accent           = Color(hex: "#FFB020")!
    static let accentMuted      = Color(hex: "#C98A1A")!

    // Text
    static let textPrimary      = Color(hex: "#F2F2F5")!
    static let textSecondary    = Color(hex: "#A0A0AA")!
    static let textTertiary     = Color(hex: "#6E6E78")!

    // Status
    static let online           = Color(hex: "#7DD957")!
    static let offline          = Color(hex: "#6E6E78")!

    // Geometry
    static let cornerRadius: CGFloat = 8
    static let thumbnailCorner: CGFloat = 6
}

extension Color {
    /// Parse "#RRGGBB" or "#RRGGBBAA" (with or without leading #).
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Hex string (without alpha) for persistence.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
