package fest.swingbuzz.terminal.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ─── Buttons ────────────────────────────────────────────────────────────────

/** The `.btn` family: `.btn-primary`, `.btn-secondary`, `.btn-ghost`. */
enum class SBButtonKind {
    /** Solid accent fill. One per screen — "use the accent sparingly". */
    PRIMARY,

    /** Outlined in the divider colour. */
    SECONDARY,

    /** Accent text, no chrome. */
    GHOST,
}

/**
 * Modernist's button, including the rule that trips people up:
 * "Button labels are flush left — a button wider than its label starts the text
 * at the left padding edge (trailing icon and all), never centered."
 *
 * So a full-width button is start-aligned, not centred. That is the opposite of
 * every Material button and the single most visible thing to get wrong here —
 * which is also why this is a composable of our own rather than a restyled
 * `Button`, whose `contentPadding` and centred `Row` would have to be fought
 * the whole way.
 */
@Composable
fun SBButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: SBButtonKind = SBButtonKind.PRIMARY,
    /** Full width, label flush left. */
    block: Boolean = false,
    enabled: Boolean = true,
    minHeight: Dp? = null,
    fontSize: TextUnit = 14.sp,
    fontWeight: FontWeight = SBFont.extrabold,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    val foreground = when (kind) {
        SBButtonKind.PRIMARY -> SB.background
        SBButtonKind.SECONDARY -> SB.ink
        SBButtonKind.GHOST -> SB.accent
    }
    val background = when (kind) {
        // `:active { background: var(--color-accent-700) }`
        SBButtonKind.PRIMARY -> if (pressed) SB.accent700 else SB.accent
        SBButtonKind.SECONDARY -> if (pressed) SB.ink(0.14f) else Color.Transparent
        SBButtonKind.GHOST -> if (pressed) SB.accent.copy(alpha = 0.18f) else Color.Transparent
    }
    // `padding: var(--space-2) calc(var(--space-3) * 1.2)` = 8px 14.4px,
    // and `.btn-ghost { padding-inline: var(--space-1) }`.
    val horizontal = if (kind == SBButtonKind.GHOST) SBSpace.x1 else 14.4.dp
    val vertical = if (kind == SBButtonKind.GHOST) 0.dp else SBSpace.x2

    Box(
        modifier = modifier
            .then(if (block) Modifier.fillMaxWidth() else Modifier)
            .alpha(if (enabled) 1f else 0.45f)
            // `--radius-md` is 0, so there is no shape to clip to: a Box with a
            // background is already a rectangle.
            .background(background)
            .then(
                if (kind == SBButtonKind.SECONDARY) {
                    Modifier.border(SBRule.hairline, SB.divider)
                } else {
                    Modifier
                }
            )
            .clickable(enabled = enabled, interactionSource = interaction, indication = null) {
                onClick()
            }
            .then(minHeight?.let { Modifier.defaultMinSize(minHeight = it) } ?: Modifier)
            .padding(horizontal = horizontal, vertical = vertical),
        contentAlignment = if (block) Alignment.CenterStart else Alignment.Center,
    ) {
        Text(
            text = label,
            style = sbHeading(fontSize, fontWeight),
            color = foreground,
        )
    }
}

/** The full-width, flush-left action at the bottom of most screens. */
@Composable
fun SBBlockButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: SBButtonKind = SBButtonKind.PRIMARY,
    enabled: Boolean = true,
    minHeight: Dp = 46.dp,
    fontSize: TextUnit = 15.sp,
) = SBButton(
    label = label,
    onClick = onClick,
    modifier = modifier,
    kind = kind,
    block = true,
    enabled = enabled,
    minHeight = minHeight,
    fontSize = fontSize,
)

/** `.btn-icon` — the 36×36 square used by the cart's − and + controls. */
@Composable
fun SBIconButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    fontSize: TextUnit = 18.sp,
) = SBButton(
    label = label,
    onClick = onClick,
    modifier = modifier.width(36.dp),
    kind = SBButtonKind.SECONDARY,
    enabled = enabled,
    minHeight = 36.dp,
    fontSize = fontSize,
)

// ─── Rules ──────────────────────────────────────────────────────────────────

/**
 * `.hr` — the strong 2dp rule. Modernist's don'ts: "Do not soften the rules
 * into hairlines or drop them for whitespace."
 */
@Composable
fun SBDivider(
    modifier: Modifier = Modifier,
    weight: Dp = SBRule.strong,
    color: Color = SB.divider,
) {
    Box(modifier.fillMaxWidth().height(weight).background(color))
}

// ─── Tags ───────────────────────────────────────────────────────────────────

enum class SBTagStyle { NEUTRAL, OUTLINE, ACCENT }

/** `.tag` with `.tag-neutral` / `.tag-outline`. */
@Composable
fun SBTag(
    text: String,
    modifier: Modifier = Modifier,
    style: SBTagStyle = SBTagStyle.NEUTRAL,
) {
    val foreground = when (style) {
        SBTagStyle.NEUTRAL -> SB.neutral800
        SBTagStyle.OUTLINE -> SB.accent
        SBTagStyle.ACCENT -> SB.accent800
    }
    val fill = when (style) {
        SBTagStyle.NEUTRAL -> SB.neutral100
        SBTagStyle.OUTLINE -> Color.Transparent
        SBTagStyle.ACCENT -> SB.accent100
    }

    Text(
        text = text,
        modifier = modifier
            .background(fill)
            .then(
                if (style == SBTagStyle.OUTLINE) {
                    Modifier.border(SBRule.hairline, SB.accent)
                } else {
                    Modifier
                }
            )
            .padding(horizontal = 10.dp, vertical = 3.dp),
        style = sbBody(11.sp, trackingEm = 0.02f),
        color = foreground,
    )
}

// ─── Text fields ────────────────────────────────────────────────────────────

/**
 * `.field` + `label` + `.input`.
 *
 * A [BasicTextField] with a decoration box rather than Material's `TextField`:
 * the design wants a 1dp divider-coloured rectangle on a surface fill, with no
 * floating label, no indicator line and no rounded corner — which is most of
 * what a Material field is.
 */
@Composable
fun SBTextField(
    label: String,
    placeholder: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    isSecure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Next,
) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(label, style = sbBody(12.sp), color = SB.ink(0.7f))

        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier
                .fillMaxWidth()
                .background(SB.surface)
                .border(SBRule.hairline, SB.divider)
                .defaultMinSize(minHeight = 36.dp)
                .padding(horizontal = 10.dp),
            textStyle = sbBody(14.sp).copy(color = SB.ink),
            singleLine = true,
            // `caret-color: var(--color-accent)`
            cursorBrush = SolidColor(SB.accent),
            visualTransformation =
                if (isSecure) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                keyboardType = keyboardType,
                imeAction = imeAction,
            ),
            decorationBox = { innerTextField ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (value.isEmpty()) {
                        Text(placeholder, style = sbBody(14.sp), color = SB.ink(0.35f))
                    }
                    innerTextField()
                }
            },
        )
    }
}

/** The bare `.input` without a `.field` label, as used for search. */
@Composable
fun SBSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "Search participant or ticket",
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier
            .fillMaxWidth()
            .background(SB.surface)
            .border(SBRule.hairline, SB.divider)
            .defaultMinSize(minHeight = 36.dp)
            .padding(horizontal = 10.dp),
        textStyle = sbBody(14.sp).copy(color = SB.ink),
        singleLine = true,
        cursorBrush = SolidColor(SB.accent),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            imeAction = ImeAction.Search,
        ),
        decorationBox = { innerTextField ->
            Box(contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty()) {
                    Text(placeholder, style = sbBody(14.sp), color = SB.ink(0.35f))
                }
                innerTextField()
            }
        },
    )
}

// ─── Status bands ───────────────────────────────────────────────────────────

enum class SBBandTone(val fill: Color) {
    OK(SB.ok),
    ALERT(SB.accent),
}

/**
 * The full-bleed coloured band that announces an outcome: green for approved,
 * accent red for blocked or declined. Used on the participant, blocked,
 * receipt and pay-review screens.
 */
@Composable
fun SBBand(
    text: String,
    modifier: Modifier = Modifier,
    tone: SBBandTone = SBBandTone.OK,
    glyph: SBGlyph = SBGlyph.CHECK,
    glyphSize: Dp = 24.dp,
    fontSize: TextUnit = 15.sp,
    contentPadding: PaddingValues = PaddingValues(horizontal = 18.dp, vertical = 14.dp),
) {
    Row(
        modifier = modifier.fillMaxWidth().background(tone.fill).padding(contentPadding),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SBGlyphView(glyph, glyphSize, color = Color.White)
        Text(
            text = text.uppercase(),
            style = sbHeading(fontSize, SBFont.extrabold, trackingEm = 0.14f),
            color = Color.White,
        )
    }
}

// ─── Key/value rows ─────────────────────────────────────────────────────────

/**
 * The receipt's line rows: label left in muted ink, value right in tabular
 * figures, hairline underneath.
 */
@Composable
fun SBDetailRow(
    key: String,
    value: String,
    modifier: Modifier = Modifier,
    showsDivider: Boolean = true,
) {
    Column(modifier) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(SBSpace.x3),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = key,
                modifier = Modifier.weight(1f, fill = true),
                style = sbBody(13.5.sp),
                color = SB.ink(0.6f),
            )
            Text(text = value, style = sbBody(13.5.sp), color = SB.ink)
        }
        if (showsDivider) SBDivider(weight = SBRule.hairline)
    }
}

// ─── Preview ────────────────────────────────────────────────────────────────

@Preview(showBackground = true, backgroundColor = 0xFFF3F2F2, widthDp = 402)
@Composable
private fun ComponentsPreview() {
    CompositionLocalProvider(LocalTextStyle provides sbBody(14.sp)) {
        Column(
            modifier = Modifier.padding(SBSpace.x4),
            verticalArrangement = Arrangement.spacedBy(SBSpace.x4),
        ) {
            SBBlockButton("Sign in", {})
            SBBlockButton("Scan another bracelet", {}, kind = SBButtonKind.SECONDARY, minHeight = 44.dp)
            Row(horizontalArrangement = Arrangement.spacedBy(SBSpace.x2)) {
                SBButton("Cancel", {}, kind = SBButtonKind.GHOST, fontSize = 12.sp)
                SBIconButton("−", {})
                SBIconButton("+", {})
            }
            SBDivider()
            Row(horizontalArrangement = Arrangement.spacedBy(SBSpace.x2)) {
                SBTag("Checked in Fri 17:12")
                SBTag("Assign", style = SBTagStyle.OUTLINE)
            }
            SBTextField("Email", "name@swingbuzz.fest", "", {})
            SBBand("Payment approved")
            SBBand("Bracelet blocked", tone = SBBandTone.ALERT, glyph = SBGlyph.BLOCKED)
            SBDetailRow("Participant", "Marta Lindqvist")
        }
    }
}
