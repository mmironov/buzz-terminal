package fest.swingbuzz.terminal.feature.signin

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fest.swingbuzz.terminal.app.AppModel
import fest.swingbuzz.terminal.designsystem.SB
import fest.swingbuzz.terminal.designsystem.SBBlockButton
import fest.swingbuzz.terminal.designsystem.SBButton
import fest.swingbuzz.terminal.designsystem.SBButtonKind
import fest.swingbuzz.terminal.designsystem.SBDivider
import fest.swingbuzz.terminal.designsystem.SBFont
import fest.swingbuzz.terminal.designsystem.SBKicker
import fest.swingbuzz.terminal.designsystem.SBRule
import fest.swingbuzz.terminal.designsystem.SBSpace
import fest.swingbuzz.terminal.designsystem.SBTextField
import fest.swingbuzz.terminal.designsystem.sbBody
import fest.swingbuzz.terminal.designsystem.sbDisplay
import fest.swingbuzz.terminal.domain.StaffRole

@Composable
fun SignInScreen(model: AppModel, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            // Scrollable so the soft keyboard pushing the window up cannot clip
            // the primary action — `adjustResize` handles the window, this
            // handles the content.
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 30.dp)
            .padding(bottom = 40.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(Modifier.height(SBSpace.x8))

        SBKicker(
            text = model.festivalName,
            color = SB.accent,
            size = 10.sp,
            trackingEm = 0.18f,
            modifier = Modifier.padding(bottom = 10.dp),
        )

        Text(
            text = "Staff\nTerminal",
            style = sbDisplay(44.sp, trackingEm = -0.02f, lineHeightMultiple = 1.0f),
            color = SB.ink,
        )

        SBDivider(Modifier.padding(vertical = SBSpace.x4))

        Text(
            text = "Bracelet check-in, balance top-up and bar payments. Sign in with your " +
                "festival staff account.",
            style = sbBody(13.sp, lineHeightMultiple = 1.6f),
            color = SB.ink(0.6f),
            modifier = Modifier.padding(bottom = 22.dp),
        )

        SBTextField(
            label = "Email",
            placeholder = "name@swingbuzz.fest",
            value = model.email,
            onValueChange = { model.email = it },
            modifier = Modifier.padding(bottom = 14.dp),
            keyboardType = KeyboardType.Email,
        )

        SBTextField(
            label = "Password",
            placeholder = "••••••••",
            value = model.password,
            onValueChange = { model.password = it },
            modifier = Modifier.padding(bottom = 8.dp),
            isSecure = true,
            keyboardType = KeyboardType.Password,
            imeAction = ImeAction.Done,
        )

        model.signInErrorText?.let { message ->
            // The design draws form errors as an accent rule on the leading
            // edge, not as a filled alert box. `IntrinsicSize.Min` is what lets
            // that rule match the height of however many lines the message
            // wraps to.
            Row(
                modifier = Modifier
                    .height(IntrinsicSize.Min)
                    .padding(bottom = 10.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Spacer(
                    Modifier
                        .width(3.dp)
                        .fillMaxHeight()
                        .background(SB.accent)
                )
                Text(message, style = sbBody(12.sp), color = SB.accent700)
            }
        }

        SBBlockButton(
            label = if (model.isWorking) "Signing in…" else "Sign in",
            onClick = model::signIn,
            modifier = Modifier.padding(top = SBSpace.x3),
            // Deliberately not disabled on an empty field: the design validates
            // on submit and shows the inline error above. A greyed-out primary
            // action on first launch reads as "app is broken".
            enabled = !model.isWorking,
        )

        if (model.offersDemoAccounts) {
            DemoAccounts(model, Modifier.padding(top = 26.dp))
        }

        Spacer(Modifier.height(SBSpace.x8))
    }
}

/**
 * Only shown on the fixture backend. Against Firebase these credentials cannot
 * work, and offering them there turns a real authentication failure into a
 * puzzle — see [AppModel.offersDemoAccounts].
 */
@Composable
private fun DemoAccounts(model: AppModel, modifier: Modifier = Modifier) {
    Column(modifier) {
        SBDivider(weight = SBRule.hairline)

        SBKicker(
            text = "Demo accounts",
            modifier = Modifier.padding(top = SBSpace.x4, bottom = 10.dp),
        )

        Column(verticalArrangement = Arrangement.spacedBy(SBSpace.x2)) {
            DemoButton(model, StaffRole.RECEPTION, "reception@swingbuzz.fest — Reception")
            DemoButton(model, StaffRole.BAR, "bar@swingbuzz.fest — Bar")
        }
    }
}

@Composable
private fun DemoButton(model: AppModel, role: StaffRole, label: String) {
    SBButton(
        label = label,
        onClick = { model.fillDemoAccount(role) },
        modifier = Modifier.fillMaxWidth(),
        kind = SBButtonKind.SECONDARY,
        block = true,
        // Body weight, not the heading weight, per the design — these read as
        // data rather than as actions.
        fontSize = 12.5.sp,
        fontWeight = SBFont.regular,
    )
}

@Preview(showBackground = true, widthDp = 402, heightDp = 874)
@Composable
private fun SignInPreview() {
    Column(Modifier.fillMaxSize().background(SB.background)) {
        SignInScreen(AppModel())
    }
}
