package fest.swingbuzz.terminal.app

import android.app.Activity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbHeading
import fest.swingbuzz.terminal.domain.Screen
import fest.swingbuzz.terminal.feature.reception.AssignBraceletScreen
import fest.swingbuzz.terminal.feature.reception.AssignEveningTicketScreen
import fest.swingbuzz.terminal.feature.reception.BlockedBraceletScreen
import fest.swingbuzz.terminal.feature.reception.ParticipantScreen
import fest.swingbuzz.terminal.feature.reception.ReceptionHomeScreen
import fest.swingbuzz.terminal.feature.reception.TopUpScreen
import fest.swingbuzz.terminal.feature.shared.ReceiptScreen
import fest.swingbuzz.terminal.feature.shared.ScanOverlay
import fest.swingbuzz.terminal.feature.shared.StatusHeader
import fest.swingbuzz.terminal.feature.signin.SignInScreen

/**
 * Assembles the chrome, the current screen and the scan overlay.
 *
 * A `when` over [Screen] rather than a NavHost, for the reasons in [AppModel].
 * Screens that do not exist yet fall through to [NotBuiltYet], which is honest
 * about it rather than showing an empty box.
 */
@Composable
fun RootScreen(model: AppModel, modifier: Modifier = Modifier) {
    // The status-bar icons are dark on our light ground, and would vanish once
    // the near-black scan overlay slides under them. Flipping them here rather
    // than inside ScanOverlay keeps the window-level concern in one place.
    LightStatusBarIcons(enabled = model.scan == null)

    Box(modifier.fillMaxSize().background(SB.background)) {
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            if (model.screen != Screen.SignIn) StatusHeader(model)

            Crossfade(
                targetState = model.screen,
                animationSpec = tween(250),
                label = "screen",
            ) { screen ->
                when (screen) {
                    Screen.SignIn -> SignInScreen(model)

                    // Reception
                    Screen.ReceptionHome -> ReceptionHomeScreen(model)
                    Screen.Assign -> AssignBraceletScreen(model)
                    Screen.AssignEvening -> AssignEveningTicketScreen(model)
                    Screen.Participant -> ParticipantScreen(model)
                    Screen.Blocked -> BlockedBraceletScreen(model)
                    Screen.TopUp -> TopUpScreen(model)

                    // Shared
                    Screen.Receipt -> ReceiptScreen(model)

                    // Bar — not ported yet
                    else -> NotBuiltYet(model)
                }
            }
        }

        // Above everything including the status header: the operator needs the
        // whole slab dark and inert while the phone is on somebody's wrist.
        AnimatedVisibility(
            visible = model.scan != null,
            enter = fadeIn(tween(250)),
            exit = fadeOut(tween(250)),
        ) {
            model.scan?.let { ScanOverlay(model, it) }
        }

        // Distinct from the inline sign-in error the design draws under the
        // password field: this is for failures a screen cannot explain in
        // place, e.g. a catalogue read the rules refused.
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
 * Sets whether the system bars draw their icons dark (for a light background)
 * or light (for a dark one). A no-op in a preview, which has no window.
 */
@Composable
private fun LightStatusBarIcons(enabled: Boolean) {
    val view = LocalView.current
    if (view.isInEditMode) return

    SideEffect {
        val window = (view.context as? Activity)?.window ?: return@SideEffect
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = enabled
            isAppearanceLightNavigationBars = enabled
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
