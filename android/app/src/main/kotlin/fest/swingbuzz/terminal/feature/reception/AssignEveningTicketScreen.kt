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
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
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
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBFont
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbHeading
import fest.swingbuzz.terminal.domain.Evening

/**
 * Selling a pass on the door. Reached from the check-in screen, on a bracelet
 * that has already been scanned.
 *
 * Deliberately the shortest screen in the app: pick an evening, confirm. Nothing
 * is asked of the guest, because evening tickets are anonymous — the whole point
 * is that a queue at the door moves.
 */
@Composable
fun AssignEveningTicketScreen(model: AppModel, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 18.dp)
            .padding(top = SBSpace.x4, bottom = 20.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(SBSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Evening ticket",
                style = sbHeading(26.sp),
                color = SB.ink,
                modifier = Modifier.weight(1f),
            )
            SBButton("Cancel", model::backToAssign, kind = SBButtonKind.GHOST, fontSize = 12.sp)
        }

        Text(
            text = "Bracelet ${model.braceletLabel} · sold at the door",
            style = sbBody(11.5.sp),
            color = SB.ink(0.55f),
            modifier = Modifier.padding(top = 2.dp),
        )

        SBDivider(Modifier.padding(vertical = 14.dp))

        SBKicker("Which evening", modifier = Modifier.padding(bottom = 10.dp))

        Column(verticalArrangement = Arrangement.spacedBy(SBSpace.x2)) {
            Evening.entries.forEach { evening ->
                EveningChoice(
                    label = evening.label,
                    isSelected = model.eveningSelection == evening,
                    onClick = { model.eveningSelection = evening },
                )
            }
        }

        Text(
            text = "No name or details are recorded. The ticket is valid for the evening " +
                "above; an organiser freezes it afterwards from the admin panel.",
            style = sbBody(11.5.sp, lineHeightMultiple = 1.5f),
            color = SB.ink(0.55f),
            modifier = Modifier.padding(top = SBSpace.x4),
        )

        Spacer(Modifier.weight(1f).size(SBSpace.x4))

        SBDivider(weight = SBRule.hairline)
        SBBlockButton(
            label = "Assign · ${model.eveningSelection.label}",
            onClick = model::assignEveningTicket,
            modifier = Modifier.padding(top = 10.dp),
            enabled = !model.isWorking,
            minHeight = 50.dp,
        )
    }
}

/**
 * A large one-handed choice. Selected is a solid accent fill — Modernist uses
 * the accent for the thing that is currently true, not for decoration.
 */
@Composable
private fun EveningChoice(label: String, isSelected: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    val background = when {
        isSelected && pressed -> SB.accent700
        isSelected -> SB.accent
        pressed -> SB.accent.copy(alpha = 0.18f)
        else -> Color.Transparent
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 52.dp)
            .background(background)
            .then(if (isSelected) Modifier else Modifier.border(SBRule.hairline, SB.divider))
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 14.4.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Text(
            text = label,
            style = sbHeading(18.sp, SBFont.extrabold),
            color = if (isSelected) SB.background else SB.ink,
        )
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun AssignEveningPreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        AssignEveningTicketScreen(AppModel())
    }
}
