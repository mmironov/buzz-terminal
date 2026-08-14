package fest.swingbuzz.terminal.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * The five line glyphs the design draws inline as SVG.
 *
 * Drawn as paths on a [Canvas] rather than shipped as vector drawables for the
 * same reason the iOS side draws them as `Shape`s: stroke weight stays under our
 * control, and Modernist cares about stroke weight — the marks are 1.1–3.0 units
 * in a 24-unit box depending on context.
 *
 * Coordinates are transcribed from the design's `viewBox="0 0 24 24"` paths, so
 * this file and `ios/BuzzTerminal/DesignSystem/Glyphs.swift` can be diffed by
 * eye.
 */
enum class SBGlyph(
    /** Stroke width in viewBox units, as authored in the design. */
    val authoredStrokeWidth: Float,
) {
    NFC_WAVE(1.2f),
    CHECK(2.4f),
    BLOCKED(2.4f),
    ALERT(2.4f),
    BACKSPACE(2.0f),
}

/** Renders an [SBGlyph] at a size in dp, scaling the stroke the way SVG does. */
@Composable
fun SBGlyphView(
    glyph: SBGlyph,
    size: Dp,
    modifier: Modifier = Modifier,
    strokeWidth: Float? = null,
    color: Color = SB.accent,
) {
    Canvas(modifier.size(size)) {
        val s = minOf(this.size.width, this.size.height) / 24f
        drawPath(
            path = glyph.path(s),
            color = color,
            style = Stroke(
                width = (strokeWidth ?: glyph.authoredStrokeWidth) * s,
                cap = StrokeCap.Round,
                join = StrokeJoin.Round,
                pathEffect = PathEffect.cornerPathEffect(0f),
            ),
        )
    }
}

private fun SBGlyph.path(s: Float): Path {
    fun x(v: Float) = v * s
    fun y(v: Float) = v * s

    val path = Path()
    when (this) {
        SBGlyph.NFC_WAVE -> {
            // Three nested arcs, widest on the left — the radio-wave mark.
            // <path d="M6 5c3.2 2.4 3.2 11.6 0 14"/> and two smaller siblings.
            path.moveTo(x(6f), y(5f))
            path.cubicTo(x(9.2f), y(7.4f), x(9.2f), y(16.6f), x(6f), y(19f))
            path.moveTo(x(10.5f), y(7f))
            path.cubicTo(x(12.7f), y(8.7f), x(12.7f), y(15.3f), x(10.5f), y(17f))
            path.moveTo(x(15f), y(9.2f))
            path.cubicTo(x(16.2f), y(10.2f), x(16.2f), y(13.8f), x(15f), y(14.8f))
        }

        SBGlyph.CHECK -> {
            // <path d="M4 12.5l5 5L20 6.5"/>
            path.moveTo(x(4f), y(12.5f))
            path.lineTo(x(9f), y(17.5f))
            path.lineTo(x(20f), y(6.5f))
        }

        SBGlyph.BLOCKED -> {
            // A circle struck through — <circle r="8.5"/> + <path d="M6.5 17.5L17.5 6.5"/>
            path.addOval(Rect(Offset(x(3.5f), y(3.5f)), Size(x(17f), y(17f))))
            path.moveTo(x(6.5f), y(17.5f))
            path.lineTo(x(17.5f), y(6.5f))
        }

        SBGlyph.ALERT -> {
            // A bar and a dot — <path d="M12 6.5v8"/> + <path d="M12 18h.01"/>
            path.moveTo(x(12f), y(6.5f))
            path.lineTo(x(12f), y(14.5f))
            path.moveTo(x(12f), y(18f))
            path.lineTo(x(12.01f), y(18f))
        }

        SBGlyph.BACKSPACE -> {
            // Lucide's `delete`, with its 2-unit corner radii squared off —
            // Modernist does not round a corner anywhere, including in an icon.
            path.moveTo(x(2f), y(12f))
            path.lineTo(x(9f), y(5f))
            path.lineTo(x(22f), y(5f))
            path.lineTo(x(22f), y(19f))
            path.lineTo(x(9f), y(19f))
            path.close()
            // The X inside.
            path.moveTo(x(12f), y(9f))
            path.lineTo(x(18f), y(15f))
            path.moveTo(x(18f), y(9f))
            path.lineTo(x(12f), y(15f))
        }
    }
    return path
}

@Preview(showBackground = true, backgroundColor = 0xFFF3F2F2)
@Composable
private fun GlyphsPreview() {
    Row(
        modifier = Modifier.padding(SBSpace.x6),
        horizontalArrangement = Arrangement.spacedBy(SBSpace.x6),
    ) {
        SBGlyphView(SBGlyph.NFC_WAVE, 46.dp)
        SBGlyphView(SBGlyph.CHECK, 32.dp, color = SB.ok)
        SBGlyphView(SBGlyph.BLOCKED, 32.dp)
        SBGlyphView(SBGlyph.ALERT, 32.dp)
        SBGlyphView(SBGlyph.BACKSPACE, 32.dp, color = SB.ink)
    }
}
