package fest.swingbuzz.terminal.feature.reception

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBGlyph
import fest.swingbuzz.terminal.designsystem.SBGlyphView
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbHeading

/**
 * The reception idle screen: one enormous scan target and nothing else.
 * "Every action starts with a bracelet."
 */
@Composable
fun ReceptionHomeScreen(model: AppModel, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 26.dp)
            .padding(top = 20.dp, bottom = 30.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))

        Text(
            text = "Every action starts with a bracelet. Read the chip, then choose " +
                "check-in or top-up.",
            style = sbBody(14.sp, lineHeightMultiple = 1.6f),
            color = SB.ink(0.65f),
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 250.dp),
        )

        Spacer(Modifier.size(30.dp))

        ScanTarget(onClick = { model.beginScan(AppModel.ScanState.Purpose.CHECK_IN_OR_TOP_UP) })

        Spacer(Modifier.weight(1f))

        SBDivider(weight = SBRule.hairline)
        Row(
            modifier = Modifier.padding(top = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Text("New bracelet → check-in", style = sbBody(11.5.sp), color = SB.ink(0.55f))
            Text("|", style = sbBody(11.5.sp), color = SB.divider)
            Text("Known bracelet → top-up", style = sbBody(11.5.sp), color = SB.ink(0.55f))
        }
    }
}

/**
 * Three concentric square outlines, fading outwards — the design's way of
 * drawing "radio waves" without an animation on an idle screen.
 *
 * The outer two are drawn as padded boxes behind the target rather than as
 * negative padding, which Compose has no equivalent of.
 */
@Composable
private fun ScanTarget(onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Box(
        modifier = Modifier.size(276.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(276.dp).border(SBRule.hairline, SB.accent.copy(alpha = 0.16f)))
        Box(Modifier.size(248.dp).border(SBRule.hairline, SB.accent.copy(alpha = 0.35f)))

        Column(
            modifier = Modifier
                .size(224.dp)
                .background(if (pressed) SB.accent.copy(alpha = 0.2f) else Color.Transparent)
                .border(SBRule.hairline, SB.accent)
                .clickable(interactionSource = interaction, indication = null, onClick = onClick),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            SBGlyphView(SBGlyph.NFC_WAVE, 46.dp)
            Spacer(Modifier.size(SBSpace.x3))
            Text("Read bracelet", style = sbHeading(20.sp), color = SB.ink)
            Spacer(Modifier.size(SBSpace.x3))
            Text(
                text = "Hold to the back of the phone",
                style = sbBody(11.sp, trackingEm = 0.04f),
                color = SB.ink(0.55f),
            )
        }
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun ReceptionHomePreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        ReceptionHomeScreen(AppModel())
    }
}
