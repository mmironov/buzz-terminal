package fest.swingbuzz.terminal.feature.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBand
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDetailRow
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay
import fest.swingbuzz.terminal.domain.Receipt

/**
 * One screen serving all three successful outcomes — check-in, top-up, payment.
 *
 * Worth noticing in the design: the new balance is the largest thing on the
 * screen, in green, under its own 2dp rule. Whatever just happened, the number
 * the guest will ask about is the one they can read from a metre away.
 */
@Composable
fun ReceiptScreen(model: AppModel, modifier: Modifier = Modifier) {
    // Unreachable in practice; keeps the screen total rather than crashing if a
    // transition ever lands here without a receipt.
    val receipt = model.receipt ?: return

    Column(modifier.fillMaxSize().padding(bottom = 20.dp)) {
        SBBand(
            text = receipt.bandText,
            contentPadding = PaddingValues(horizontal = 22.dp, vertical = 14.dp),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 22.dp)
                .padding(top = 22.dp)
        ) {
            Text(
                text = receipt.title,
                style = sbDisplay(32.sp, trackingEm = -0.02f, lineHeightMultiple = 1.1f),
                color = SB.ink,
                modifier = Modifier.padding(bottom = 6.dp),
            )

            Text(
                text = receipt.note,
                style = sbBody(13.5.sp, lineHeightMultiple = 1.6f),
                color = SB.ink(0.65f),
            )

            SBDivider(Modifier.padding(vertical = SBSpace.x4))

            receipt.rows.forEach { row -> SBDetailRow(row.key, row.value) }

            NewBalance(receipt)

            Spacer(Modifier.weight(1f).size(SBSpace.x4))

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SBBlockButton(
                    label = receipt.primaryActionLabel,
                    onClick = model::receiptPrimaryAction,
                    minHeight = 48.dp,
                )
                SBBlockButton(
                    label = receipt.secondaryActionLabel,
                    onClick = model::goHome,
                    kind = SBButtonKind.SECONDARY,
                    minHeight = 42.dp,
                    fontSize = 14.sp,
                )
            }
        }
    }
}

@Composable
private fun NewBalance(receipt: Receipt) {
    Column(Modifier.fillMaxWidth().padding(top = 22.dp)) {
        SBDivider(weight = SBRule.strong, color = SB.ok)
        SBKicker(
            text = "New balance",
            color = SB.okDeep,
            modifier = Modifier.padding(top = 10.dp),
        )
        Text(
            text = receipt.balance.toString(),
            style = sbDisplay(58.sp, trackingEm = -0.03f, lineHeightMultiple = 1.05f),
            color = SB.okDeep,
        )
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun ReceiptPreview() {
    val model = AppModel()
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        ReceiptScreen(model)
    }
}
