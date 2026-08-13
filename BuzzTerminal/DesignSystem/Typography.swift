import CoreText
import SwiftUI
import UIKit

/// Archivo, the one typeface Modernist uses: "set entirely in Archivo".
///
/// The bundled `Archivo.ttf` is Google Fonts' **variable** font, with a Weight
/// axis from 100 to 900. That matters for how you ask for a weight:
/// `Font.custom("Archivo-ExtraBold", size:)` does *not* work — CoreText does not
/// expose most named instances of this file by PostScript name and silently
/// falls back to Helvetica. Instead we build a descriptor that sets the `wght`
/// variation axis directly, which is exact and gives us any weight we like.
enum SBFont {

    /// The four-character `wght` axis tag as the integer CoreText wants.
    /// (`'w' << 24 | 'g' << 16 | 'h' << 8 | 't'` = 2003265652.)
    private static let weightAxis = 2003265652

    /// Weights the design actually uses, matching the CSS `@import` of
    /// Archivo 400/600/800 plus the 700 used for screen titles.
    enum Weight: Double {
        case regular = 400
        case semibold = 600
        case bold = 700
        case extrabold = 800
    }

    private static let familyName = "Archivo"

    /// True when the bundled font registered successfully. Checked once so a
    /// missing font degrades to the system face instead of Helvetica.
    private static let isAvailable: Bool = {
        UIFont.fontNames(forFamilyName: familyName).isEmpty == false
            || UIFont(name: familyName, size: 12)?.familyName == familyName
    }()

    /// A `UIFont` for Archivo at an arbitrary weight, with tabular figures.
    ///
    /// Tabular figures are on for everything rather than only for numerals: the
    /// design sets `font-feature-settings:'tnum'` on every balance, price and
    /// total, and keeping one font pipeline is simpler than two. Proportional
    /// figures are only better in running prose, of which this app has none.
    static func uiFont(size: CGFloat, weight: Weight) -> UIFont {
        guard isAvailable else {
            return .systemFont(ofSize: size, weight: weight.systemEquivalent)
        }
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: familyName,
            kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [
                weightAxis: weight.rawValue
            ],
            .featureSettings: [
                [
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]
            ],
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    static func font(size: CGFloat, weight: Weight) -> Font {
        Font(uiFont(size: size, weight: weight))
    }
}

private extension SBFont.Weight {
    /// Used only when Archivo is unavailable.
    var systemEquivalent: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .semibold: .semibold
        case .bold: .bold
        case .extrabold: .heavy
        }
    }
}

// MARK: - Semantic roles

extension Font {
    /// Display type: the 32–66pt numbers and names that carry each screen.
    static func sbDisplay(_ size: CGFloat) -> Font {
        SBFont.font(size: size, weight: .extrabold)
    }

    /// Screen and section titles.
    static func sbHeading(_ size: CGFloat, weight: SBFont.Weight = .bold) -> Font {
        SBFont.font(size: size, weight: weight)
    }

    /// Running interface text.
    static func sbBody(_ size: CGFloat) -> Font {
        SBFont.font(size: size, weight: .regular)
    }
}

// MARK: - Tracking

/// CSS letter-spacing is in `em`; SwiftUI's `.tracking` is in points. This does
/// the conversion so the design's values can be copied across literally.
extension View {
    func sbTracking(em: CGFloat, size: CGFloat) -> some View {
        tracking(em * size)
    }
}

/// CSS `line-height` has no direct SwiftUI equivalent — `lineSpacing` adds to
/// the font's natural leading rather than replacing it. Archivo's natural line
/// height is roughly 1.25×, so this converts a CSS multiplier into the delta
/// SwiftUI wants. Needed because the design sets `line-height:1` on the 44pt
/// login headline and `1.05` on the big display numbers.
extension View {
    func sbLineHeight(_ multiplier: CGFloat, size: CGFloat) -> some View {
        lineSpacing((multiplier - 1.25) * size)
    }
}

// MARK: - The kicker

/// The small uppercase label that sits above almost every block in the design:
/// 9.5pt, wide tracking, uppercase — "BALANCE", "CASH RECEIVED", "NEW BALANCE".
struct SBKicker: View {
    let text: String
    var color: Color = .sbInk(0.5)
    var size: CGFloat = 9.5
    var tracking: CGFloat = 0.14

    var body: some View {
        Text(text.uppercased())
            .font(.sbHeading(size, weight: .extrabold))
            .tracking(tracking * size)
            .foregroundStyle(color)
    }
}

#Preview("Type scale") {
    VStack(alignment: .leading, spacing: SBSpace.x3) {
        SBKicker(text: "Swing Buzz Festival", color: .sbAccent)
        Text("Staff\nTerminal")
            .font(.sbDisplay(44))
            .tracking(-0.02 * 44)
        Text("Who is this?").font(.sbHeading(26))
        Text("23.50 €").font(.sbDisplay(66)).tracking(-0.03 * 66)
        Text("Bracelet check-in, balance top-up and bar payments.")
            .font(.sbBody(13))
            .foregroundStyle(.sbInk(0.6))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(SBSpace.x6)
    .background(Color.sbBackground)
}
