package fest.swingbuzz.terminal.feature.shared

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBand
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay

/**
 * The green-bordered "this person is cleared" block: a filled band over the name
 * and their ticket, inside a heavy 3dp rule. Readable from arm's length in a
 * dark venue, which is the whole point of it.
 *
 * Shared by the reception participant screen and the bar's approved pay-review
 * header. The SwiftUI side has the same block written out twice, differing only
 * in the name's point size — [nameSize] is that difference, and the rest is not
 * worth duplicating.
 */
@Composable
fun CheckedInIdentityCard(
    name: String,
    subtitle: String,
    modifier: Modifier = Modifier,
    nameSize: TextUnit = 32.sp,
) {
    Column(modifier.fillMaxWidth().border(3.dp, SB.ok)) {
        SBBand(
            text = "Checked-In",
            glyphSize = 18.dp,
            fontSize = 12.5.sp,
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 7.dp),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp)
                .padding(top = 12.dp, bottom = 13.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(
                text = name,
                style = sbDisplay(nameSize, trackingEm = -0.02f, lineHeightMultiple = 1.05f),
                color = SB.ink,
            )
            Text(subtitle, style = sbBody(12.sp), color = SB.ink(0.6f))
        }
    }
}
