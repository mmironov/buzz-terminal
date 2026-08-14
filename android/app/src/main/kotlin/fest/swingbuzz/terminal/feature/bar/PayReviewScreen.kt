package fest.swingbuzz.terminal.feature.bar

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import fest.swingbuzz.terminal.designsystem.SBBandTone
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBFont
import fest.swingbuzz.terminal.designsystem.SBGlyph
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay
import fest.swingbuzz.terminal.designsystem.sbHeading
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.PaymentDecision
import fest.swingbuzz.terminal.feature.shared.CheckedInIdentityCard

/**
 * The moment of truth at the bar: a bracelet has been read, here is what will
 * happen. Also where all three refusals surface.
 */
@Composable
fun PayReviewScreen(model: AppModel, modifier: Modifier = Modifier) {
    val decision = model.paymentDecision ?: PaymentDecision.NotAssigned

    Column(modifier.fillMaxSize()) {
        // The refusal band bleeds to the screen edges, so it sits outside the
        // inset column rather than inside it with negative padding — Compose has
        // no negative padding, and this reads better anyway.
        if (!decision.isApproved) {
            SBBand(
                text = decision.bandText,
                tone = SBBandTone.ALERT,
                glyph = SBGlyph.ALERT,
                contentPadding = PaddingValues(horizontal = 18.dp, vertical = 13.dp),
            )
        }

        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = 18.dp, vertical = 18.dp)
        ) {
            if (decision.isApproved) {
                CheckedInIdentityCard(
                    name = model.participant?.name ?: "—",
                    subtitle = "${model.participant?.ticketDescription ?: "—"} · " +
                        "Bracelet ${model.braceletLabel}",
                    nameSize = 30.sp,
                )
            } else {
                RefusalBody(decision, model.cartTotal)
            }

            SBDivider(Modifier.padding(vertical = SBSpace.x4))

            Breakdown(model, decision, Modifier.weight(1f))

            Actions(model, decision)
        }
    }
}

@Composable
private fun RefusalBody(decision: PaymentDecision, total: Money) {
    Column {
        Text(
            text = decision.title,
            style = sbDisplay(30.sp, trackingEm = -0.02f, lineHeightMultiple = 1.1f),
            color = SB.ink,
            modifier = Modifier.padding(bottom = SBSpace.x2),
        )

        Row(
            modifier = Modifier.height(IntrinsicSize.Min),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Spacer(Modifier.width(3.dp).fillMaxHeight().background(SB.accent))
            Text(
                text = decision.note(total),
                style = sbBody(13.5.sp, lineHeightMultiple = 1.65f),
                color = SB.accent800,
            )
        }
    }
}

@Composable
private fun Breakdown(model: AppModel, decision: PaymentDecision, modifier: Modifier = Modifier) {
    Column(modifier.verticalScroll(rememberScrollState())) {
        model.cartLines.forEach { line ->
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = SBSpace.x2),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = line.label,
                    style = sbBody(13.5.sp),
                    color = SB.ink,
                    modifier = Modifier.weight(1f),
                )
                Text(line.total.toString(), style = sbBody(13.5.sp), color = SB.ink)
            }
            SBDivider(weight = SBRule.hairline)
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(top = SBSpace.x3),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SBKicker("To charge", color = SB.ink, size = 10.sp, modifier = Modifier.weight(1f))
            Text(model.cartTotal.toString(), style = sbDisplay(30.sp), color = SB.ink)
        }

        if (decision is PaymentDecision.Approved) {
            Column(Modifier.padding(top = 10.dp)) {
                SBDivider(weight = SBRule.strong, color = SB.ok)
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Balance ${model.participant?.balance ?: Money.ZERO} → after",
                        style = sbBody(13.sp),
                        color = SB.okDeep,
                        modifier = Modifier.weight(1f),
                    )
                    Text(
                        text = decision.balanceAfter.toString(),
                        style = sbHeading(13.sp, SBFont.bold),
                        color = SB.okDeep,
                    )
                }
            }
        }
    }
}

@Composable
private fun Actions(model: AppModel, decision: PaymentDecision) {
    Column(
        modifier = Modifier.padding(top = SBSpace.x3),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        if (decision.isApproved) {
            SBBlockButton(
                label = "Charge ${model.cartTotal}",
                onClick = model::confirmPayment,
                enabled = !model.isWorking,
                minHeight = 50.dp,
            )
        }

        SBBlockButton(
            label = "Scan another bracelet",
            onClick = { model.beginScan(AppModel.ScanState.Purpose.PAYMENT) },
            kind = SBButtonKind.SECONDARY,
            minHeight = 44.dp,
            fontSize = 14.sp,
        )

        SBButton(
            label = "Back to order",
            onClick = model::goToMenu,
            kind = SBButtonKind.GHOST,
            fontSize = 12.sp,
        )
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun PayReviewPreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        PayReviewScreen(AppModel())
    }
}
