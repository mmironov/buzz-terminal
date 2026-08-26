package fest.swingbuzz.terminal

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.app.RootScreen
import fest.swingbuzz.terminal.app.TerminalBackend
import fest.swingbuzz.terminal.data.BraceletReader
import fest.swingbuzz.terminal.designsystem.ScanFeedback
import fest.swingbuzz.terminal.data.SyncCenter
import fest.swingbuzz.terminal.data.TerminalRepository
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

        // Chosen here rather than inside the ViewModel so that the decision — and
        // the release build's refusal to run on fixtures — happens once, at
        // launch, with a Context to hand. Nothing has touched Firestore yet,
        // which is what lets the emulator override take effect.
        // One SyncCenter, shared: the repository reports into it and the model
        // reads from it. Created here rather than by either, because a refused
        // write has to outlive both — it is persisted, and it is the record of
        // money that went missing.
        val sync = SyncCenter(applicationContext)
        val repository = TerminalBackend.choose(this, intent, sync)

        // Real chips whenever the hardware can read them, the prototype panel
        // otherwise — an emulator has no chip to present. `--es sbScanner simulated`
        // forces the panel on a device, for rehearsing without a bracelet in hand.
        val reader = TerminalBackend.reader(this, intent)
        val feedback = ScanFeedback(applicationContext)

        setContent { BuzzTerminalApp(repository, sync, reader, feedback) }
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
fun BuzzTerminalApp(
    repository: TerminalRepository,
    sync: SyncCenter,
    reader: BraceletReader,
    feedback: ScanFeedback,
) {
    CompositionLocalProvider(LocalTextStyle provides sbBody(14.sp).copy(color = SB.ink)) {
        // No safe-area inset here on purpose: `RootScreen` applies it to the
        // screen content, so the scan overlay can still reach the status bar
        // and the gesture bar. From targetSdk 35 the window is edge-to-edge
        // whether we ask for it or not, so this is the only place that choice
        // can be made.
        Box(Modifier.fillMaxSize().background(SB.background)) {
            // A factory rather than `viewModel()`, so the repository chosen at
            // launch is the one the model gets — while the ViewModel still
            // outlives configuration changes, which is the whole point of it.
            RootScreen(
                viewModel(
                    factory = viewModelFactory {
                        initializer { AppModel(repository, reader, sync, feedback) }
                    }
                )
            )
        }
    }
}
