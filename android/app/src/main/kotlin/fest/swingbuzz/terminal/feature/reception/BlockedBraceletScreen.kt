package fest.swingbuzz.terminal.feature.reception

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBand
import fest.swingbuzz.terminal.designsystem.SBBandTone
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBGlyph
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay
import fest.swingbuzz.terminal.domain.Money

/**
 * A bracelet an organiser froze in the admin panel. Deliberately a dead end: the
 * only action is "Done", because nothing can be done from the terminal.
 */
@Composable
fun BlockedBraceletScreen(model: AppModel, modifier: Modifier = Modifier) {
    val participant = model.participant

    Column(modifier.fillMaxSize()) {
        SBBand("Bracelet blocked", tone = SBBandTone.ALERT, glyph = SBGlyph.BLOCKED)

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 18.dp)
                .padding(top = 22.dp, bottom = 18.dp)
        ) {
            Text(
                text = participant?.name ?: "—",
                style = sbDisplay(32.sp, trackingEm = -0.02f, lineHeightMultiple = 1.05f),
                color = SB.ink,
                modifier = Modifier.padding(bottom = 4.dp),
            )

            Text(
                text = "${participant?.ticketDescription ?: "—"} · Bracelet ${model.braceletLabel}",
                style = sbBody(12.sp),
                color = SB.ink(0.6f),
            )

            // Accent-800, not the raw accent: the design system notes the
            // accent-to-ground pair only reaches 3:1, which is fine for chrome
            // but not for paragraph text.
            Row(
                modifier = Modifier
                    .height(IntrinsicSize.Min)
                    .padding(top = 18.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Spacer(Modifier.width(3.dp).fillMaxHeight().background(SB.accent))
                Text(
                    text = participant?.blockReason ?: "",
                    style = sbBody(13.5.sp, lineHeightMultiple = 1.65f),
                    color = SB.accent800,
                )
            }

            SBDivider(Modifier.padding(vertical = SBSpace.x4))

            SBKicker("Balance frozen", color = SB.ink(0.45f))

            Text(
                text = (participant?.balance ?: Money.ZERO).toString(),
                style = sbDisplay(52.sp, trackingEm = -0.03f)
                    .copy(textDecoration = TextDecoration.LineThrough),
                color = SB.ink(0.4f),
            )

            Spacer(Modifier.weight(1f).size(SBSpace.x4))

            SBDivider(weight = SBRule.hairline)

            Text(
                text = "No top-ups and no payments on this bracelet. An organiser lifts the " +
                    "block from the web admin panel.",
                style = sbBody(12.sp, lineHeightMultiple = 1.5f),
                color = SB.ink(0.55f),
                modifier = Modifier.padding(top = 10.dp),
            )

            SBBlockButton(
                label = "Done",
                onClick = model::goHome,
                modifier = Modifier.padding(top = 10.dp),
                kind = SBButtonKind.SECONDARY,
                minHeight = 46.dp,
            )
        }
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun BlockedPreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        BlockedBraceletScreen(AppModel())
    }
}
