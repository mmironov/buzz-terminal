package fest.swingbuzz.terminal.feature.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
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
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Transactions the server refused after the till had already said yes.
 *
 * A reconciliation screen, not an error log. Every row is money that moved in the
 * real world and did not move in the database, so each says what happened, to whom,
 * and what to do about it — and can be marked as dealt with, so a shift can work
 * through the list rather than staring at it.
 *
 * Ships in release. It is the one place the offline queue's failures become visible,
 * and a festival will meet them at the least convenient moment.
 */
// The one place this app uses Material chrome. Everything else is Modernist from
// the ground up — but a modal sheet is platform furniture, exactly as the iOS twin
// uses a UIKit-presented sheet, and reimplementing scrim and drag handle to avoid
// three lines of Material would be the wrong trade for a screen an organiser sees
// twice a festival. `containerColor` keeps the surface itself Modernist.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FailedWritesSheet(model: AppModel, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = SB.background,
    ) {
        Column(Modifier.fillMaxWidth()) {
            Text(
                "Failed to sync",
                style = sbHeading(19.sp),
                color = SB.ink,
                modifier = Modifier.padding(horizontal = 18.dp),
            )
            Text(
                "These were accepted at the till and refused by the server afterwards. " +
                    "The guest already has the drink, or already handed over the cash.",
                style = sbBody(12.5.sp),
                color = SB.neutral700,
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 10.dp),
            )

            if (model.failedWrites.isEmpty()) {
                Text(
                    "Nothing outstanding.",
                    style = sbBody(13.sp),
                    color = SB.neutral700,
                    modifier = Modifier.padding(18.dp),
                )
            }

            LazyColumn {
                items(model.failedWrites, key = { it.id }) { write ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 18.dp, vertical = 14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(SBSpace.x2),
                            verticalAlignment = Alignment.Top,
                        ) {
                            Text(
                                write.summary,
                                style = sbHeading(14.sp),
                                color = SB.ink,
                                modifier = Modifier.weight(1f),
                            )
                            Text(
                                TIME.format(write.attemptedAt.atZone(ZoneId.systemDefault())),
                                style = sbBody(11.sp),
                                color = SB.neutral600,
                            )
                        }

                        Text(write.advice, style = sbBody(12.sp), color = SB.ink(0.75f))

                        // The detail nobody needs until they need it badly: which
                        // till, which transaction id to search for, and what the
                        // server actually said.
                        Text(
                            "${write.terminalId} · ${write.transactionId}",
                            style = sbBody(10.5.sp),
                            color = SB.neutral600,
                        )
                        Text(write.reason, style = sbBody(10.5.sp), color = SB.neutral600)

                        SBButton(
                            label = "Mark as sorted",
                            onClick = { model.settleFailure(write.id) },
                            kind = SBButtonKind.SECONDARY,
                            fontSize = 12.sp,
                        )
                    }
                    SBDivider(weight = SBRule.hairline)
                }
            }
        }
    }
}

private val TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

@Composable
private fun Text(
    text: String,
    style: androidx.compose.ui.text.TextStyle,
    color: androidx.compose.ui.graphics.Color,
    modifier: Modifier = Modifier,
) = androidx.compose.material3.Text(
    text = text,
    style = style,
    color = color,
    modifier = modifier,
    textAlign = TextAlign.Start,
)
