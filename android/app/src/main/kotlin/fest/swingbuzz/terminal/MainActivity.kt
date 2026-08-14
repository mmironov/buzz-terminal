package fest.swingbuzz.terminal

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import fest.swingbuzz.terminal.app.RootScreen
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.sbBody

/**
 * The single activity. Everything above it is Compose, and navigation is the
 * `Screen` state machine in `:domain` rather than a NavHost — the same shape as
 * the iOS app's flat `Screen` enum, for the same reason: a till is a state
 * machine, not a browsing history.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { BuzzTerminalApp() }
    }
}

/**
 * The app's one theme wrapper. Deliberately not `MaterialTheme`: Modernist
 * defines every colour, every type role and every shape itself, so a Material
 * scheme underneath would only be a second set of defaults to keep overriding.
 * What is needed instead is exactly this — the Modernist background, and Archivo
 * as the default text style so nothing falls back to Roboto by omission.
 */
@Composable
fun BuzzTerminalApp() {
    CompositionLocalProvider(LocalTextStyle provides sbBody(14.sp).copy(color = SB.ink)) {
        Box(
            Modifier
                .fillMaxSize()
                .background(SB.background)
                .safeDrawingPadding()
        ) {
            RootScreen(viewModel())
        }
    }
}
