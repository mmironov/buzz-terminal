package fest.swingbuzz.terminal.designsystem

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

// ─── Colour ─────────────────────────────────────────────────────────────────

/**
 * The Modernist palette, transcribed from the design system's `styles.css` and
 * kept identical to `ios/BuzzTerminal/DesignSystem/Tokens.swift`.
 *
 * These are deliberately **fixed** colours, not a Material colour scheme that
 * adapts to dark mode. Modernist is a single-look system — "a near-mono red on
 * white" — and inverting it would not be the same design. The activity theme
 * pins the app to the light appearance; if a dark variant is ever wanted it
 * needs designing, not deriving.
 *
 * A plain object rather than a `CompositionLocal`: there is exactly one palette,
 * so threading a theme through the tree would buy nothing but indirection.
 */
object SB {

    // Core roles
    val background = Color(0xFFF3F2F2)
    val surface = Color(0xFFEAE9E9)
    val ink = Color(0xFF201E1D)
    val accent = Color(0xFFEC3013)

    /** `--color-divider`: the ink at 40%. Every rule in the design is this. */
    val divider = Color(0xFF201E1D).copy(alpha = 0.4f)

    /**
     * Success green. Lives in the screen file in the design (`--sb-ok`) rather
     * than the shared system, because it is this app's addition to Modernist.
     */
    val ok = Color(0xFF0D7A3A)
    val okTint = Color(0xFFE4F3E9)
    val okDeep = Color(0xFF0A5A2B)

    // Neutral ramp
    val neutral100 = Color(0xFFF8F4F4)
    val neutral200 = Color(0xFFEAE7E7)
    val neutral300 = Color(0xFFD7D3D3)
    val neutral400 = Color(0xFFBAB6B6)
    val neutral500 = Color(0xFF9B9797)
    val neutral600 = Color(0xFF7D7979)
    val neutral700 = Color(0xFF605D5D)
    val neutral800 = Color(0xFF444141)
    val neutral900 = Color(0xFF2D2B2B)

    // Accent ramp
    val accent100 = Color(0xFFFFF2EF)
    val accent200 = Color(0xFFFFE0D9)
    val accent300 = Color(0xFFFFC4B8)
    val accent400 = Color(0xFFFF9783)
    val accent500 = Color(0xFFFF563C)
    val accent600 = Color(0xFFDD2B0F)
    val accent700 = Color(0xFFAE1800)
    val accent800 = Color(0xFF7C1405)
    val accent900 = Color(0xFF4D170E)

    /**
     * The design leans on `color-mix(… var(--color-text) N%, transparent)` for
     * secondary and tertiary text. This is that, spelled once.
     */
    fun ink(alpha: Float): Color = ink.copy(alpha = alpha)
}

// ─── Spacing ────────────────────────────────────────────────────────────────

/**
 * `--space-1` … `--space-8`. CSS px map 1:1 to dp here, exactly as they map 1:1
 * to points on iOS: the design was drawn at 402×874, a phone in logical units.
 */
object SBSpace {
    val x1: Dp = 4.dp
    val x2: Dp = 8.dp
    val x3: Dp = 12.dp
    val x4: Dp = 16.dp
    val x6: Dp = 24.dp
    val x8: Dp = 32.dp
}

// ─── Radius ─────────────────────────────────────────────────────────────────

/**
 * `--radius-sm/md/lg` are all `0px`. From the design system's don'ts:
 * "Do not round a corner anywhere — `--radius-md` is 0 on purpose."
 * Named rather than inlined so the intent survives, and so a future retune is
 * one edit.
 */
object SBRadius {
    val sm: Dp = 0.dp
    val md: Dp = 0.dp
    val lg: Dp = 0.dp
}

// ─── Rules ──────────────────────────────────────────────────────────────────

/**
 * Modernist organises with dividers, not whitespace, and the design uses two
 * weights: hairlines inside lists and 2dp between major sections.
 */
object SBRule {
    val hairline: Dp = 1.dp
    val strong: Dp = 2.dp
}
