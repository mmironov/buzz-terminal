package fest.swingbuzz.terminal.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Every Modernist primitive on one scrolling page.
 *
 * The iOS side gets this from Xcode's `#Preview` canvases; Android Studio's
 * preview does the same job, but a scrollable gallery you can actually launch is
 * worth more here — variable-font rendering, tabular figures and stroke weights
 * are things you want to check on the glass, not in a render host.
 *
 * It is also, for now, what `MainActivity` shows. The real `RootScreen` takes
 * that slot as soon as the sign-in flow lands; this stays reachable for design
 * review.
 */
@Composable
fun DesignSystemGallery(modifier: Modifier = Modifier) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(SB.background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = SBSpace.x6, vertical = SBSpace.x8),
        verticalArrangement = Arrangement.spacedBy(SBSpace.x4),
    ) {
        // ── Type scale ──
        SBKicker("Swing Buzz Festival", color = SB.accent, size = 10.sp, trackingEm = 0.18f)
        Text(
            text = "Staff\nTerminal",
            style = sbDisplay(44.sp, trackingEm = -0.02f, lineHeightMultiple = 1.0f),
            color = SB.ink,
        )
        SBDivider()
        Text("Who is this?", style = sbHeading(26.sp), color = SB.ink)
        Text(
            text = "23.50 €",
            style = sbDisplay(66.sp, trackingEm = -0.03f, lineHeightMultiple = 1.05f),
            color = SB.ink,
        )
        Text(
            text = "Bracelet check-in, balance top-up and bar payments.",
            style = sbBody(13.sp, lineHeightMultiple = 1.6f),
            color = SB.ink(0.6f),
        )

        // ── Weight check ──
        // Worth its space, because the failure this guards against does not look
        // like a failure. Archivo's variable default is wght 600, so a family
        // that loaded but never applied its variation settings renders every
        // weight at semibold — plausible, and wrong everywhere. Archivo Regular
        // also resembles Roboto closely enough at 13sp to fool the eye, so the
        // platform default on the last line is the control: if an Archivo line
        // matches it, that weight is falling back.
        SBDivider()
        SBKicker("Weight check")
        for (weight in listOf(400, 600, 700, 800)) {
            Text(
                text = "Participant 123 — Archivo $weight",
                style = SBFont.style(15.sp, FontWeight(weight)),
                color = SB.ink,
            )
        }
        Text(
            text = "Participant 123 — platform default",
            style = TextStyle(fontFamily = FontFamily.Default, fontSize = 15.sp),
            color = SB.ink,
        )

        // ── Glyphs ──
        SBDivider()
        SBKicker("Glyphs")
        Row(horizontalArrangement = Arrangement.spacedBy(SBSpace.x6)) {
            SBGlyphView(SBGlyph.NFC_WAVE, 46.dp)
            SBGlyphView(SBGlyph.CHECK, 32.dp, color = SB.ok)
            SBGlyphView(SBGlyph.BLOCKED, 32.dp)
            SBGlyphView(SBGlyph.ALERT, 32.dp)
            SBGlyphView(SBGlyph.BACKSPACE, 32.dp, color = SB.ink)
        }

        // ── Controls ──
        SBDivider()
        SBKicker("Controls")
        SBBlockButton("Sign in", {})
        SBBlockButton(
            "Scan another bracelet", {},
            kind = SBButtonKind.SECONDARY,
            minHeight = 44.dp,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(SBSpace.x2),
        ) {
            SBButton("Cancel", {}, kind = SBButtonKind.GHOST, fontSize = 12.sp)
            SBIconButton("−", {})
            SBIconButton("+", {})
        }
        SBBlockButton("Disabled", {}, enabled = false)

        SBTextField(
            label = "Email",
            placeholder = "name@swingbuzz.fest",
            value = email,
            onValueChange = { email = it },
            keyboardType = KeyboardType.Email,
        )
        SBTextField(
            label = "Password",
            placeholder = "••••••••",
            value = password,
            onValueChange = { password = it },
            isSecure = true,
            keyboardType = KeyboardType.Password,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(SBSpace.x2)) {
            SBTag("Checked in Fri 17:12")
            SBTag("Assign", style = SBTagStyle.OUTLINE)
            SBTag("Evening", style = SBTagStyle.ACCENT)
        }

        // ── Outcomes ──
        SBDivider()
        SBKicker("Outcomes")
        SBBand("Payment approved")
        SBBand("Bracelet blocked", tone = SBBandTone.ALERT, glyph = SBGlyph.BLOCKED)
        SBBand("Declined", tone = SBBandTone.ALERT, glyph = SBGlyph.ALERT)

        Column {
            SBDetailRow("Participant", "Marta Lindqvist")
            SBDetailRow("Bracelet", "04:B4:2F:11")
            SBDetailRow("New balance", "19.50 €", showsDivider = false)
        }
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 874)
@Composable
private fun GalleryPreview() = DesignSystemGallery()
