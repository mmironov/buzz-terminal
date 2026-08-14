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
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBGlyph
import fest.swingbuzz.terminal.designsystem.SBGlyphView
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay
import fest.swingbuzz.terminal.designsystem.sbHeading
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.TopUpEntry

/** Taking cash and crediting the bracelet. A till, essentially. */
@Composable
fun TopUpScreen(model: AppModel, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 18.dp)
            .padding(top = SBSpace.x4, bottom = 18.dp)
    ) {
        Header(model)
        AmountDisplay(model)
        Presets(model)
        Keypad(model)
        // No spacer above: the design stacks the confirm button directly under
        // the pad rather than pinning it to the bottom of the screen.
        SBBlockButton(
            label = model.topUp.confirmButtonTitle,
            onClick = model::confirmTopUp,
            modifier = Modifier.padding(top = SBSpace.x4),
            enabled = model.topUp.isConfirmable && !model.isWorking,
            minHeight = 50.dp,
        )
        Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun Header(model: AppModel) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        SBButton("Back", model::backToParticipant, kind = SBButtonKind.GHOST, fontSize = 12.sp)
        Spacer(Modifier.weight(1f))
        Text(
            text = "${model.participant?.name ?: "—"} · " +
                "${model.participant?.balance ?: Money.ZERO}",
            style = sbBody(12.sp),
            color = SB.ink(0.6f),
        )
    }
}

@Composable
private fun AmountDisplay(model: AppModel) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 14.dp, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        SBKicker("Cash received")
        Text(
            text = model.topUp.display,
            style = sbDisplay(62.sp, trackingEm = -0.03f, lineHeightMultiple = 1.1f),
            color = SB.ink,
        )
        // A short rule under the figure, inset from the edges — the design's way
        // of saying "this is a field being typed into".
        Box(
            Modifier
                .padding(horizontal = 30.dp, vertical = 2.dp)
                .fillMaxWidth()
                .height(1.dp)
                .background(SB.divider)
        )
    }
}

@Composable
private fun Presets(model: AppModel) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 14.dp, bottom = SBSpace.x4),
        horizontalArrangement = Arrangement.spacedBy(SBSpace.x2),
    ) {
        TopUpEntry.presets.forEach { preset ->
            SBButton(
                label = preset.compact,
                onClick = { model.applyTopUpPreset(preset) },
                modifier = Modifier.weight(1f),
                kind = SBButtonKind.SECONDARY,
                minHeight = 42.dp,
            )
        }
    }
}

/**
 * The pad from the design: 1-9, then `.`, `0`, `⌫`, three across.
 *
 * A hand-built grid rather than `LazyVerticalGrid`, which would need a fixed
 * height inside this column and would be lazy about twelve permanently visible
 * keys.
 */
@Composable
private fun Keypad(model: AppModel) {
    Column(verticalArrangement = Arrangement.spacedBy(SBSpace.x2)) {
        TopUpEntry.keys.chunked(3).forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(SBSpace.x2),
            ) {
                row.forEach { key -> KeypadKey(key, onClick = { model.pressTopUp(key) }) }
            }
        }
    }
}

/**
 * A keypad key: outlined, square-cornered, 52dp tall so it is hittable without
 * looking. Pressed state is an accent wash, per the design system.
 */
@Composable
private fun RowScope.KeypadKey(key: TopUpEntry.Key, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Box(
        modifier = Modifier
            .weight(1f)
            .defaultMinSize(minHeight = 52.dp)
            .background(if (pressed) SB.accent.copy(alpha = 0.18f) else Color.Transparent)
            .border(1.dp, SB.divider)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .semantics {
                contentDescription = if (key == TopUpEntry.Key.Backspace) "Backspace" else key.label
            },
        contentAlignment = Alignment.Center,
    ) {
        // Archivo has no U+232B, so the backspace key would fall back to a
        // system face at a visibly lighter weight. Drawing it keeps the whole
        // pad in one visual language.
        if (key == TopUpEntry.Key.Backspace) {
            SBGlyphView(SBGlyph.BACKSPACE, 24.dp, color = SB.ink)
        } else {
            Text(key.label, style = sbHeading(22.sp), color = SB.ink)
        }
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 800)
@Composable
private fun TopUpPreview() {
    Column(Modifier.fillMaxWidth().background(SB.background)) {
        TopUpScreen(AppModel())
    }
}
