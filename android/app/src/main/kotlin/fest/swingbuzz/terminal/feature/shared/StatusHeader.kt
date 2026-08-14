package fest.swingbuzz.terminal.feature.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbHeading

/**
 * The persistent chrome above every signed-in screen: who you are, what the
 * connection is doing, and the way out.
 */
@Composable
fun StatusHeader(model: AppModel, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp)
                .padding(top = 6.dp, bottom = SBSpace.x3),
            horizontalArrangement = Arrangement.spacedBy(SBSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                SBKicker(model.festivalName, color = SB.accent, trackingEm = 0.16f)
                Text(
                    text = model.role?.label ?: "",
                    style = sbHeading(19.sp),
                    color = SB.ink,
                )
            }

            NetworkToggle(model)

            SBButton(
                label = "Sign out",
                onClick = model::signOut,
                kind = SBButtonKind.GHOST,
                fontSize = 12.sp,
            )
        }

        SBDivider()

        if (model.isOffline) OfflineBanner(model)
    }
}

@Composable
private fun NetworkToggle(model: AppModel) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Row(
        modifier = Modifier
            .background(if (pressed) SB.ink(0.07f) else Color.Transparent)
            .border(SBRule.hairline, SB.divider)
            .clickable(interactionSource = interaction, indication = null) {
                model.toggleOffline()
            }
            .padding(horizontal = 9.dp, vertical = 5.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // A hard 8dp square, not a circle — radius 0 applies to status dots too.
        Box(
            Modifier
                .size(8.dp)
                .background(if (model.isOffline) SB.accent else SB.neutral600)
        )
        Text(model.networkLabel, style = sbBody(11.sp), color = SB.ink)
    }
}

@Composable
private fun OfflineBanner(model: AppModel) {
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(SB.accent100)
                .padding(horizontal = 18.dp, vertical = SBSpace.x2),
            horizontalArrangement = Arrangement.spacedBy(SBSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SBKicker("Offline", color = SB.accent800, trackingEm = 0.1f)
            Text(model.queueLabel, style = sbBody(11.5.sp), color = SB.accent800)
        }
        SBDivider(weight = SBRule.hairline)
    }
}

@Preview(showBackground = true, widthDp = 402)
@Composable
private fun StatusHeaderPreview() {
    val model = AppModel().apply {
        signIn()
        toggleOffline()
    }
    Column(Modifier.background(SB.background)) { StatusHeader(model) }
}
