package fest.swingbuzz.terminal.feature.reception

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBand
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.SBTag
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay
import fest.swingbuzz.terminal.domain.Money

/** A known bracelet was read: show who it is, what they have, and offer a top-up. */
@Composable
fun ParticipantScreen(model: AppModel, modifier: Modifier = Modifier) {
    val participant = model.participant

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 18.dp)
            .padding(top = 18.dp, bottom = 20.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SBTag(participant?.checkedInLabel ?: "Checked in")
            Spacer(Modifier.weight(1f))
            SBButton("Done", model::goHome, kind = SBButtonKind.GHOST, fontSize = 12.sp)
        }

        IdentityCard(
            name = participant?.name ?: "—",
            subtitle = "${participant?.ticketDescription ?: "—"} · Bracelet ${model.braceletLabel}",
            modifier = Modifier.padding(top = SBSpace.x4),
        )

        SBDivider(Modifier.padding(vertical = SBSpace.x4))

        SBKicker("Balance")

        Text(
            text = (participant?.balance ?: Money.ZERO).toString(),
            style = sbDisplay(66.sp, trackingEm = -0.03f),
            color = SB.ink,
            modifier = Modifier.padding(top = 6.dp),
        )

        Spacer(Modifier.weight(1f).size(SBSpace.x4))

        SBDivider(weight = SBRule.hairline)
        Text(
            text = "This bracelet is permanently paired with ${participant?.name ?: "this guest"}. " +
                "Checking in someone else needs a new bracelet.",
            style = sbBody(11.5.sp, lineHeightMultiple = 1.5f),
            color = SB.ink(0.55f),
            modifier = Modifier.padding(top = 10.dp),
        )

        SBBlockButton(
            label = "Add money",
            onClick = model::goToTopUp,
            modifier = Modifier.padding(top = 20.dp),
            minHeight = 48.dp,
        )
    }
}

/**
 * The green-bordered identity block. The heavy 3dp border plus the filled band
 * is the design's "this person is cleared" signal, readable from arm's length in
 * a dark venue.
 */
@Composable
private fun IdentityCard(name: String, subtitle: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().border(3.dp, SB.ok)) {
        SBBand(
            text = "Checked-In",
            glyphSize = 18.dp,
            fontSize = 12.5.sp,
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 7.dp),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .padding(top = 12.dp, bottom = 13.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(
                text = name,
                style = sbDisplay(32.sp, trackingEm = -0.02f, lineHeightMultiple = 1.05f),
                color = SB.ink,
            )
            Text(subtitle, style = sbBody(12.sp), color = SB.ink(0.6f))
        }
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun ParticipantPreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        ParticipantScreen(AppModel())
    }
}
