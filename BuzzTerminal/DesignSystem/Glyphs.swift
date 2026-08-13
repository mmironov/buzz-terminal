import SwiftUI

/// The four line glyphs the design draws inline as SVG.
///
/// Drawn as SwiftUI `Shape`s rather than shipped as assets or SF Symbols for one
/// reason that matters and one that is a bonus. The reason: SF Symbols has no
/// NFC-wave mark, and the design's is a specific three-arc form. The bonus:
/// stroke weight stays under our control, and Modernist cares about stroke
/// weight — the marks are 1.1–3.0 units in a 24-unit box depending on context.
///
/// Coordinates are transcribed from the design's `viewBox="0 0 24 24"` paths, so
/// the two can be diffed by eye.
enum SBGlyph {
    case nfcWave
    case check
    case blocked
    case alert
    case backspace

    /// Stroke width in viewBox units, as authored in the design.
    var authoredStrokeWidth: CGFloat {
        switch self {
        case .nfcWave: 1.2
        case .check: 2.4
        case .blocked: 2.4
        case .alert: 2.4
        case .backspace: 2.0
        }
    }
}

/// Renders an `SBGlyph` at a point size, scaling the stroke the way SVG does.
struct SBGlyphView: View {
    let glyph: SBGlyph
    var size: CGFloat
    var strokeWidth: CGFloat?
    var color: Color = .sbAccent

    var body: some View {
        let scale = size / 24
        let width = (strokeWidth ?? glyph.authoredStrokeWidth) * scale
        GlyphShape(glyph: glyph)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
    }
}

private struct GlyphShape: Shape {
    let glyph: SBGlyph

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }

        var path = Path()
        switch glyph {
        case .nfcWave:
            // Three nested arcs, widest on the left — the radio-wave mark.
            // <path d="M6 5c3.2 2.4 3.2 11.6 0 14"/> and two smaller siblings.
            path.move(to: p(6, 5))
            path.addCurve(to: p(6, 19), control1: p(9.2, 7.4), control2: p(9.2, 16.6))
            path.move(to: p(10.5, 7))
            path.addCurve(to: p(10.5, 17), control1: p(12.7, 8.7), control2: p(12.7, 15.3))
            path.move(to: p(15, 9.2))
            path.addCurve(to: p(15, 14.8), control1: p(16.2, 10.2), control2: p(16.2, 13.8))

        case .check:
            // <path d="M4 12.5l5 5L20 6.5"/>
            path.move(to: p(4, 12.5))
            path.addLine(to: p(9, 17.5))
            path.addLine(to: p(20, 6.5))

        case .blocked:
            // A circle struck through — <circle r="8.5"/> + <path d="M6.5 17.5L17.5 6.5"/>
            path.addEllipse(in: CGRect(
                x: rect.minX + 3.5 * s, y: rect.minY + 3.5 * s,
                width: 17 * s, height: 17 * s
            ))
            path.move(to: p(6.5, 17.5))
            path.addLine(to: p(17.5, 6.5))

        case .alert:
            // A bar and a dot — <path d="M12 6.5v8"/> + <path d="M12 18h.01"/>
            path.move(to: p(12, 6.5))
            path.addLine(to: p(12, 14.5))
            path.move(to: p(12, 18))
            path.addLine(to: p(12.01, 18))

        case .backspace:
            // Lucide's `delete`, with its 2-unit corner radii squared off —
            // Modernist does not round a corner anywhere, including in an icon.
            path.move(to: p(2, 12))
            path.addLine(to: p(9, 5))
            path.addLine(to: p(22, 5))
            path.addLine(to: p(22, 19))
            path.addLine(to: p(9, 19))
            path.closeSubpath()
            // The X inside.
            path.move(to: p(12, 9))
            path.addLine(to: p(18, 15))
            path.move(to: p(18, 9))
            path.addLine(to: p(12, 15))
        }
        return path
    }
}

#Preview("Glyphs") {
    HStack(spacing: SBSpace.x6) {
        SBGlyphView(glyph: .nfcWave, size: 46)
        SBGlyphView(glyph: .check, size: 32, color: .sbOk)
        SBGlyphView(glyph: .blocked, size: 32)
        SBGlyphView(glyph: .alert, size: 32)
    }
    .padding(SBSpace.x6)
    .background(Color.sbBackground)
}
