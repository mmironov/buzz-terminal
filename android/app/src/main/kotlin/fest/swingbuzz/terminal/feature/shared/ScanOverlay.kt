package fest.swingbuzz.terminal.feature.shared

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBGlyph
import fest.swingbuzz.terminal.designsystem.SBGlyphView
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay
import fest.swingbuzz.terminal.designsystem.sbHeading

/**
 * The scan sheet: a near-black full-bleed overlay, which is both a design choice
 * and a functional one — it kills every other tap target while the phone is
 * being held against someone's wrist.
 */
@Composable
fun ScanOverlay(model: AppModel, state: AppModel.ScanState, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            // The fill goes edge to edge, under the status bar and the gesture
            // bar — the operator needs the whole slab dark and inert while the
            // phone is on somebody's wrist. `safeDrawingPadding` is applied
            // *after* it, so the fill reaches the bezel but the controls do not
            // hide behind the system bars.
            .background(SB.neutral900)
            // Swallows taps that miss a control, so nothing behind the overlay
            // can be reached.
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) {}
            .safeDrawingPadding()
            .padding(horizontal = SBSpace.x6)
            .padding(top = 70.dp, bottom = 44.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))

        Target(state)

        Spacer(Modifier.size(26.dp))

        Text(
            text = if (state.isReading) "Reading chip…" else "Hold the bracelet",
            style = sbDisplay(27.sp, trackingEm = -0.01f),
            color = SB.neutral100,
        )
        Spacer(Modifier.size(SBSpace.x2))
        Text(
            text = if (state.isReading) {
                "Keep it still for a moment"
            } else {
                "Against the back of the phone, near the top"
            },
            style = sbBody(12.5.sp),
            color = SB.neutral100.copy(alpha = 0.6f),
            textAlign = TextAlign.Center,
        )

        Spacer(Modifier.weight(1f))

        // Only offered while there is no hardware reader and no read in flight.
        // A real NFC reader removes it.
        if (!model.readerIsHardwareBacked && !state.isReading) {
            SimulatorPanel(model)
        }

        CancelButton(onClick = model::cancelScan, modifier = Modifier.padding(top = 14.dp))
    }
}

@Composable
private fun Target(state: AppModel.ScanState) {
    Box(Modifier.size(180.dp), contentAlignment = Alignment.Center) {
        if (state.isReading) {
            RotatingRule()
        } else {
            listOf(0, 660, 1330).forEach { delayMillis -> PulseRing(delayMillis) }
            SBGlyphView(SBGlyph.NFC_WAVE, 52.dp, color = SB.accent300)
        }
    }
}

/**
 * One expanding, fading square outline. Three of these on staggered delays make
 * the design's `sbRing` pulse.
 *
 * The stagger is a keyframe hold at the start value rather than an initial
 * delay: `infiniteRepeatable` applies its delay once, before the first cycle,
 * so three rings started with different delays would drift into phase after the
 * first repeat. Holding inside the keyframes keeps them permanently offset.
 */
@Composable
private fun PulseRing(delayMillis: Int) {
    val cycle = 2000
    val transition = rememberInfiniteTransition(label = "pulse")

    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = keyframes {
                durationMillis = cycle + delayMillis
                0f at 0
                0f at delayMillis
                1f at cycle + delayMillis
            },
            repeatMode = RepeatMode.Restart,
        ),
        label = "pulse-progress",
    )

    Box(
        Modifier
            .fillMaxSize()
            .scale(0.72f + progress * 0.53f)
            .border(2.dp, SB.accent400.copy(alpha = 0.55f * (1f - progress)))
    )
}

/**
 * The busy indicator. A rotating quarter of a square outline rather than the
 * usual circular spinner — Modernist does not round corners, so neither does its
 * progress indicator.
 */
@Composable
private fun RotatingRule() {
    val transition = rememberInfiniteTransition(label = "spin")
    val angle by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(
            animation = tween(900, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "spin-angle",
    )

    Canvas(
        Modifier
            .size(40.dp)
            .rotate(angle)
    ) {
        val stroke = 3.dp.toPx()
        val inset = stroke / 2
        val box = Size(size.width - stroke, size.height - stroke)

        drawRect(
            color = SB.neutral100.copy(alpha = 0.3f),
            topLeft = Offset(inset, inset),
            size = box,
            style = Stroke(width = stroke),
        )
        // The lit quarter: the top edge and nothing else, which is what
        // `trim(from: 0, to: 0.25)` draws on the SwiftUI side.
        drawLine(
            color = SB.accent300,
            start = Offset(inset, inset),
            end = Offset(inset + box.width, inset),
            strokeWidth = stroke,
        )
    }
}

@Composable
private fun SimulatorPanel(model: AppModel) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .drawDashedBorder()
            .padding(horizontal = SBSpace.x3)
            .padding(top = SBSpace.x3, bottom = 13.dp),
    ) {
        SBKicker(
            text = if (model.runsOnFixtures) {
                "Prototype · simulate a bracelet"
            } else {
                "Prototype · simulate a bracelet · live data"
            },
            color = SB.accent300,
            size = 9.sp,
            trackingEm = 0.16f,
            modifier = Modifier.padding(bottom = 9.dp),
        )

        Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
            model.simulatedBracelets.forEach { bracelet ->
                SimulatorRow(
                    // The hints describe `SampleData`, so on any other backend
                    // they are false — and confidently so, which is worse than
                    // silence. The chip this one calls "fresh, not yet assigned"
                    // is a checked-in guest on Firestore, and the participant
                    // screen that correctly appears then looks like a bug.
                    hint = bracelet.hint.takeIf { model.runsOnFixtures },
                    id = bracelet.id.rawValue,
                    onClick = { model.selectSimulatedBracelet(bracelet.id) },
                )
            }
        }
    }
}

@Composable
private fun SimulatorRow(hint: String?, id: String, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .border(
                1.dp,
                if (pressed) SB.accent300 else SB.neutral100.copy(alpha = 0.22f),
            )
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 11.dp, vertical = 9.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (hint != null) {
            Text(hint, style = sbBody(12.5.sp), color = SB.neutral100, modifier = Modifier.weight(1f))
            Text(id, style = sbBody(11.sp), color = SB.neutral100.copy(alpha = 0.55f))
        } else {
            // With nothing truthful to say about the chip, the id carries the row
            // on its own rather than being demoted to a trailing detail.
            Text(id, style = sbBody(12.5.sp), color = SB.neutral100, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun CancelButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()

    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(if (pressed) SB.neutral100.copy(alpha = 0.12f) else Color.Transparent)
            .border(1.dp, SB.neutral100.copy(alpha = 0.3f))
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .defaultMinSize(minHeight = 44.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text("Cancel", style = sbHeading(14.sp), color = SB.neutral100)
    }
}

/**
 * The dashed rule the design draws around the prototype-only panel. Dashed
 * because it is scaffolding: this panel does not exist once a real chip can be
 * read. `Modifier.border` cannot dash, hence drawing it.
 */
private fun Modifier.drawDashedBorder() = drawBehind {
    drawRect(
        color = SB.neutral100.copy(alpha = 0.25f),
        style = Stroke(
            width = 1.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(
                floatArrayOf(4.dp.toPx(), 3.dp.toPx())
            ),
        ),
    )
}

@Preview(showBackground = true, widthDp = 402, heightDp = 874)
@Composable
private fun ScanWaitingPreview() =
    ScanOverlay(AppModel(), AppModel.ScanState(AppModel.ScanState.Purpose.CHECK_IN_OR_TOP_UP))

@Preview(showBackground = true, widthDp = 402, heightDp = 874)
@Composable
private fun ScanReadingPreview() =
    ScanOverlay(
        AppModel(),
        AppModel.ScanState(AppModel.ScanState.Purpose.PAYMENT, isReading = true),
    )
