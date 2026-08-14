package fest.swingbuzz.terminal.feature.reception

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSearchField
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.SBTag
import fest.swingbuzz.terminal.designsystem.SBTagStyle
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbHeading
import fest.swingbuzz.terminal.domain.Participant

/** Check-in: a fresh chip was read, now pick who it belongs to. */
@Composable
fun AssignBraceletScreen(model: AppModel, modifier: Modifier = Modifier) {
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
                text = "Who is this?",
                style = sbHeading(26.sp),
                color = SB.ink,
                modifier = Modifier.weight(1f),
            )
            SBButton("Cancel", model::goHome, kind = SBButtonKind.GHOST, fontSize = 12.sp)
        }

        Text(
            text = "Bracelet ${model.braceletLabel} · not assigned yet",
            style = sbBody(11.5.sp),
            color = SB.ink(0.55f),
            modifier = Modifier.padding(top = 2.dp),
        )

        SBDivider(Modifier.padding(vertical = 14.dp))

        SBSearchField(value = model.search, onValueChange = { model.search = it })

        // `weight` rather than a fixed height: the list takes whatever is left
        // after the door-sale block below has claimed its space, so that block
        // is always reachable however long the roster is.
        CandidateList(model, Modifier.weight(1f).padding(top = 6.dp))

        // Door sales. Below the list rather than above it, because scanning a
        // fresh chip usually means somebody from the roster — the door ticket is
        // the less common case and should not be the first thing thumbed.
        SBDivider(weight = SBRule.hairline)
        SBBlockButton(
            label = "Assign evening ticket",
            onClick = model::goToAssignEvening,
            modifier = Modifier.padding(top = 10.dp),
            kind = SBButtonKind.SECONDARY,
            minHeight = 46.dp,
            fontSize = 14.sp,
        )
        Text(
            text = "Sold at the door · no name needed",
            style = sbBody(11.sp),
            color = SB.ink(0.5f),
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

@Composable
private fun CandidateList(model: AppModel, modifier: Modifier = Modifier) {
    val candidates = model.candidates

    LazyColumn(modifier) {
        items(candidates, key = { it.id.rawValue }) { guest ->
            CandidateRow(guest, onClick = { model.assign(guest) })
        }

        if (candidates.isEmpty()) {
            item {
                Text(
                    text = "No matching participant awaiting check-in.",
                    style = sbBody(12.5.sp),
                    color = SB.ink(0.55f),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = SBSpace.x4, horizontal = 2.dp),
                )
            }
        }
    }
}

/** A tappable list row: no chrome, a hairline underneath, and a wash on press. */
@Composable
private fun CandidateRow(guest: Participant, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Column(
        Modifier
            .fillMaxWidth()
            .background(if (pressed) SB.ink(0.05f) else Color.Transparent)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 13.dp, horizontal = 2.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(guest.name, style = sbHeading(16.sp), color = SB.ink)
                Text(
                    text = "${guest.ticketType} · ${guest.country}",
                    style = sbBody(11.sp),
                    color = SB.ink(0.55f),
                )
            }
            SBTag("Assign", style = SBTagStyle.OUTLINE)
        }
        SBDivider(weight = SBRule.hairline)
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun AssignPreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        AssignBraceletScreen(AppModel())
    }
}
