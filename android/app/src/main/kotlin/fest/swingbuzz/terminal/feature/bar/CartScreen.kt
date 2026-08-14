package fest.swingbuzz.terminal.feature.bar

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBIconButton
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay
import fest.swingbuzz.terminal.designsystem.sbHeading
import fest.swingbuzz.terminal.domain.CartLine

/** Editing the round before the bracelet comes out. */
@Composable
fun CartScreen(model: AppModel, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 18.dp, vertical = SBSpace.x4)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "This round",
                style = sbHeading(24.sp),
                color = SB.ink,
                modifier = Modifier.weight(1f),
            )
            SBButton("Add more", model::goToMenu, kind = SBButtonKind.GHOST, fontSize = 12.sp)
        }

        SBDivider(Modifier.padding(vertical = SBSpace.x3))

        LazyColumn(Modifier.weight(1f)) {
            items(model.cartLines, key = { it.id }) { line ->
                CartRow(line, onBump = { delta -> model.bump(line.drink, delta) })
            }
        }

        TotalRow(model)

        SBBlockButton(
            label = "Scan bracelet to charge",
            onClick = { model.beginScan(AppModel.ScanState.Purpose.PAYMENT) },
            minHeight = 50.dp,
        )

        SBButton(
            label = "Clear order",
            onClick = model::clearCart,
            modifier = Modifier.padding(top = 6.dp),
            kind = SBButtonKind.GHOST,
            fontSize = 12.sp,
        )
    }
}

@Composable
private fun CartRow(line: CartLine, onBump: (Int) -> Unit) {
    Column {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 11.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(line.drink.name, style = sbHeading(16.sp), color = SB.ink)
                Text(line.unitLabel, style = sbBody(11.5.sp), color = SB.ink(0.55f))
            }

            SBIconButton("−", { onBump(-1) })

            Text(
                text = "${line.quantity}",
                style = sbBody(15.sp),
                color = SB.ink,
                textAlign = TextAlign.Center,
                modifier = Modifier.widthIn(min = 20.dp),
            )

            SBIconButton("+", { onBump(1) })

            Text(
                text = line.total.toString(),
                style = sbBody(14.sp),
                color = SB.ink,
                textAlign = TextAlign.End,
                modifier = Modifier.widthIn(min = 56.dp),
            )
        }
        SBDivider(weight = SBRule.hairline)
    }
}

@Composable
private fun TotalRow(model: AppModel) {
    Column {
        // Full-strength ink, not the 40% divider: this is the strongest rule in
        // the app because it is the number staff are accountable for.
        SBDivider(weight = SBRule.strong, color = SB.ink)

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 14.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SBKicker("Total", color = SB.ink, size = 10.sp, modifier = Modifier.weight(1f))
            Text(model.cartTotal.toString(), style = sbDisplay(36.sp), color = SB.ink)
        }
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun CartPreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        CartScreen(AppModel())
    }
}
