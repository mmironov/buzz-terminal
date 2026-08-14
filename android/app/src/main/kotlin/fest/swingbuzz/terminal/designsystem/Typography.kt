package fest.swingbuzz.terminal.designsystem

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.R

/**
 * Archivo, the one typeface Modernist uses: "set entirely in Archivo".
 *
 * The bundled `archivo.ttf` is Google Fonts' **variable** font, with a Weight
 * axis from 100 to 900 — the same file the iOS app carries. Compose reaches the
 * axis through [FontVariation], so each weight below is the one real file asked
 * for a different `wght`, not a separate static cut. That is why the family is
 * built from four `Font(…, variationSettings = …)` entries rather than four
 * font resources.
 *
 * Variable-font settings are honoured from API 26, which is this app's minSdk.
 */
object SBFont {

    private fun archivo(weight: Int) = Font(
        R.font.archivo,
        FontWeight(weight),
        variationSettings = FontVariation.Settings(FontVariation.weight(weight)),
    )

    /**
     * Weights the design actually uses, matching the CSS `@import` of
     * Archivo 400/600/800 plus the 700 used for screen titles.
     */
    val family = FontFamily(
        archivo(400),
        archivo(600),
        archivo(700),
        archivo(800),
    )

    val regular = FontWeight(400)
    val semibold = FontWeight(600)
    val bold = FontWeight(700)
    val extrabold = FontWeight(800)

    /**
     * Tabular figures are on for everything rather than only for numerals: the
     * design sets `font-feature-settings:'tnum'` on every balance, price and
     * total, and keeping one text pipeline is simpler than two. Proportional
     * figures are only better in running prose, of which this app has none.
     */
    private const val TABULAR = "tnum"

    fun style(
        size: TextUnit,
        weight: FontWeight,
        /**
         * CSS letter-spacing in `em`, copied literally from the design. Compose
         * takes `em` directly, which the SwiftUI side had to convert to points.
         */
        trackingEm: Float = 0f,
        /**
         * CSS `line-height` as a multiplier of the size, again copied literally.
         * Null leaves Archivo's natural leading alone.
         */
        lineHeightMultiple: Float? = null,
    ) = TextStyle(
        fontFamily = family,
        fontSize = size,
        fontWeight = weight,
        letterSpacing = trackingEm.em,
        lineHeight = lineHeightMultiple?.let { size * it } ?: TextUnit.Unspecified,
        fontFeatureSettings = TABULAR,
    )
}

// ─── Semantic roles ─────────────────────────────────────────────────────────

/** Display type: the 32–66sp numbers and names that carry each screen. */
fun sbDisplay(size: TextUnit, trackingEm: Float = 0f, lineHeightMultiple: Float? = null) =
    SBFont.style(size, SBFont.extrabold, trackingEm, lineHeightMultiple)

/** Screen and section titles. */
fun sbHeading(
    size: TextUnit,
    weight: FontWeight = SBFont.bold,
    trackingEm: Float = 0f,
) = SBFont.style(size, weight, trackingEm)

/** Running interface text. */
fun sbBody(size: TextUnit, trackingEm: Float = 0f, lineHeightMultiple: Float? = null) =
    SBFont.style(size, SBFont.regular, trackingEm, lineHeightMultiple)

// ─── The kicker ─────────────────────────────────────────────────────────────

/**
 * The small uppercase label that sits above almost every block in the design:
 * 9.5sp, wide tracking, uppercase — "BALANCE", "CASH RECEIVED", "NEW BALANCE".
 */
@Composable
fun SBKicker(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = SB.ink(0.5f),
    size: TextUnit = 9.5.sp,
    trackingEm: Float = 0.14f,
    textAlign: TextAlign? = null,
) {
    Text(
        text = text.uppercase(),
        modifier = modifier,
        style = SBFont.style(size, SBFont.extrabold, trackingEm),
        color = color,
        textAlign = textAlign,
    )
}
