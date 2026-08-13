import SwiftUI

// MARK: - Colour

/// The Modernist palette, transcribed from the design system's `styles.css`.
///
/// These are deliberately **fixed** colours, not asset-catalogue colours that
/// adapt to dark mode. Modernist is a single-look system — "a near-mono red on
/// white" — and inverting it would not be the same design. The app pins itself
/// to the light appearance in `RootView`; if a dark variant is ever wanted it
/// needs designing, not deriving.
///
/// Declared on `ShapeStyle where Self == Color` rather than on `Color` directly.
/// That is what makes the leading-dot form work in both positions:
///
///     .foregroundStyle(.sbAccent)      // ShapeStyle position
///     let c: Color = .sbAccent         // Color position
///
/// Putting them on `Color` only gets you the second. Putting them on both is a
/// redeclaration error, since `Color` conforms to `ShapeStyle`.
extension ShapeStyle where Self == Color {

    // Core roles
    static var sbBackground: Color { Color(hex: 0xF3F2F2) }
    static var sbSurface: Color { Color(hex: 0xEAE9E9) }
    static var sbInk: Color { Color(hex: 0x201E1D) }
    static var sbAccent: Color { Color(hex: 0xEC3013) }

    /// `--color-divider`: the ink at 40%. Every rule in the design is this.
    static var sbDivider: Color { Color(hex: 0x201E1D).opacity(0.4) }

    /// Success green. Lives in the screen file in the design (`--sb-ok`) rather
    /// than the shared system, because it is this app's addition to Modernist.
    static var sbOk: Color { Color(hex: 0x0D7A3A) }
    static var sbOkTint: Color { Color(hex: 0xE4F3E9) }
    static var sbOkDeep: Color { Color(hex: 0x0A5A2B) }

    // Neutral ramp
    static var sbNeutral100: Color { Color(hex: 0xF8F4F4) }
    static var sbNeutral200: Color { Color(hex: 0xEAE7E7) }
    static var sbNeutral300: Color { Color(hex: 0xD7D3D3) }
    static var sbNeutral400: Color { Color(hex: 0xBAB6B6) }
    static var sbNeutral500: Color { Color(hex: 0x9B9797) }
    static var sbNeutral600: Color { Color(hex: 0x7D7979) }
    static var sbNeutral700: Color { Color(hex: 0x605D5D) }
    static var sbNeutral800: Color { Color(hex: 0x444141) }
    static var sbNeutral900: Color { Color(hex: 0x2D2B2B) }

    // Accent ramp
    static var sbAccent100: Color { Color(hex: 0xFFF2EF) }
    static var sbAccent200: Color { Color(hex: 0xFFE0D9) }
    static var sbAccent300: Color { Color(hex: 0xFFC4B8) }
    static var sbAccent400: Color { Color(hex: 0xFF9783) }
    static var sbAccent500: Color { Color(hex: 0xFF563C) }
    static var sbAccent600: Color { Color(hex: 0xDD2B0F) }
    static var sbAccent700: Color { Color(hex: 0xAE1800) }
    static var sbAccent800: Color { Color(hex: 0x7C1405) }
    static var sbAccent900: Color { Color(hex: 0x4D170E) }

    /// The design leans on `color-mix(… var(--color-text) N%, transparent)` for
    /// secondary and tertiary text. This is that, spelled once.
    static func sbInk(_ opacity: Double) -> Color {
        Color(hex: 0x201E1D).opacity(opacity)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Spacing

/// `--space-1` … `--space-8`. CSS px map 1:1 to points here: the design was
/// drawn at 402×874, which is an iPhone 16/17 Pro in logical points.
enum SBSpace {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
}

// MARK: - Radius

/// `--radius-sm/md/lg` are all `0px`. From the design system's don'ts:
/// "Do not round a corner anywhere — `--radius-md` is 0 on purpose."
/// Named rather than inlined so the intent survives, and so a future retune is
/// one edit.
enum SBRadius {
    static let sm: CGFloat = 0
    static let md: CGFloat = 0
    static let lg: CGFloat = 0
}

// MARK: - Rules

/// Modernist organises with dividers, not whitespace, and the design uses two
/// weights: hairlines inside lists and 2pt between major sections.
enum SBRule {
    static let hairline: CGFloat = 1
    static let strong: CGFloat = 2
}
