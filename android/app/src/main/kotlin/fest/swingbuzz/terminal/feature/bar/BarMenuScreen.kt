package fest.swingbuzz.terminal.feature.bar

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
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
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbHeading
import fest.swingbuzz.terminal.domain.Drink

/**
 * The bar's order screen: tap drinks, then scan once at the end.
 *
 * Note the interaction the design is protecting — one scan per round, not one
 * per drink. Bar staff have wet hands and a queue; the bracelet comes out once.
 */
@Composable
fun BarMenuScreen(model: AppModel, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp)
                .padding(top = 14.dp, bottom = SBSpace.x2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Order", style = sbHeading(24.sp), color = SB.ink, modifier = Modifier.weight(1f))
            Text(
                text = "Tap drinks, then scan once",
                style = sbBody(11.5.sp),
                color = SB.ink(0.55f),
            )
        }

        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.weight(1f),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                start = 18.dp, end = 18.dp, bottom = SBSpace.x3,
            ),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(model.menu, key = { it.id }) { drink ->
                DrinkCard(
                    drink = drink,
                    quantity = model.cart.quantity(drink),
                    onClick = { model.add(drink) },
                )
            }
        }

        if (!model.cart.isEmpty) CartBar(model)
    }
}

@Composable
private fun DrinkCard(drink: Drink, quantity: Int, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 82.dp)
            .background(if (pressed) SB.accent.copy(alpha = 0.14f) else Color.Transparent)
            .border(1.dp, SB.divider)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 12.dp)
            .padding(top = 12.dp, bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(SBSpace.x2),
    ) {
        Text(
            text = drink.name,
            style = sbHeading(15.5.sp),
            color = SB.ink,
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(Modifier.weight(1f))

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = drink.price.toString(),
                style = sbBody(13.sp),
                color = SB.ink(0.7f),
                modifier = Modifier.weight(1f),
            )
            // Quantity in the accent — the one spot of colour on the grid, so a
            // half-built round is obvious at a glance.
            if (quantity > 0) {
                Text("× $quantity", style = sbBody(11.sp), color = SB.accent)
            }
        }
    }
}

@Composable
private fun CartBar(model: AppModel) {
    Column {
        SBDivider()
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(SB.surface)
                .padding(horizontal = 18.dp)
                .padding(top = SBSpace.x3, bottom = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(SBSpace.x3),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(
                Modifier
                    .weight(1f)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = model::goToCart,
                    )
            ) {
                Text(
                    text = "${model.cartCountLabel} · edit",
                    style = sbBody(11.sp),
                    color = SB.ink(0.55f),
                )
                Text(model.cartTotal.toString(), style = sbHeading(24.sp), color = SB.ink)
            }

            SBButton(
                label = "Scan to pay",
                onClick = { model.beginScan(AppModel.ScanState.Purpose.PAYMENT) },
                minHeight = 48.dp,
                fontSize = 15.sp,
            )
        }
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun BarMenuPreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        BarMenuScreen(AppModel())
    }
}
