package fest.swingbuzz.terminal.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbHeading
import fest.swingbuzz.terminal.domain.Screen
import fest.swingbuzz.terminal.feature.signin.SignInScreen

/**
 * The one place [Screen] is turned into pixels.
 *
 * A `when` over the state rather than a NavHost, for the reasons in [AppModel].
 * Screens that do not exist yet fall through to [NotBuiltYet], which is honest
 * about it rather than showing an empty box.
 */
@Composable
fun RootScreen(model: AppModel, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().background(SB.background)) {
        when (model.screen) {
            Screen.SignIn -> SignInScreen(model)
            else -> NotBuiltYet(model)
        }

        // Distinct from the inline sign-in error the design draws under the
        // password field: this is for the failures a screen cannot explain
        // in place, e.g. a catalogue read the rules refused.
        model.errorMessage?.let { message ->
            AlertDialog(
                onDismissRequest = { model.errorMessage = null },
                confirmButton = {
                    TextButton(onClick = { model.errorMessage = null }) {
                        Text("OK", style = sbHeading(14.sp), color = SB.accent)
                    }
                },
                title = { Text("Something went wrong", style = sbHeading(16.sp), color = SB.ink) },
                text = { Text(message, style = sbBody(13.sp), color = SB.ink(0.7f)) },
                containerColor = SB.background,
            )
        }
    }
}

/**
 * The placeholder every not-yet-ported screen lands on. It names the screen and
 * offers the way out, which is more use during the port than a blank surface —
 * and it makes an accidental transition into an unbuilt screen obvious rather
 * than silent.
 */
@Composable
private fun NotBuiltYet(model: AppModel) {
    Column(
        modifier = Modifier.fillMaxSize().padding(SBSpace.x6),
        verticalArrangement = Arrangement.spacedBy(SBSpace.x3),
    ) {
        SBKicker(model.role?.label ?: "Signed in", color = SB.accent, size = 10.sp)
        Text(
            text = model.screen::class.simpleName ?: "Screen",
            style = sbHeading(32.sp, trackingEm = -0.02f),
            color = SB.ink,
        )
        SBDivider()
        Text(
            text = "This screen is not ported yet. The catalogue behind it is loaded: " +
                "${model.menu.size} drinks, ${model.awaitingCheckIn.size} awaiting check-in.",
            style = sbBody(13.sp, lineHeightMultiple = 1.6f),
            color = SB.ink(0.6f),
        )
        SBBlockButton("Sign out", model::signOut, kind = SBButtonKind.SECONDARY)
    }
}

@Preview(showBackground = true, widthDp = 402, heightDp = 874)
@Composable
private fun RootPreview() = RootScreen(AppModel())
