import SwiftUI

struct SignInView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The idiom for getting bindings out of an `@Observable` object that
        // arrived through the environment: re-declare it locally as `@Bindable`.
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            SBKicker(text: model.festivalName, color: .sbAccent, size: 10, tracking: 0.18)
                .padding(.bottom, 10)

            Text("Staff\nTerminal")
                .font(.sbDisplay(44))
                .tracking(-0.02 * 44)
                .sbLineHeight(1.0, size: 44)

            SBDivider()
                .padding(.vertical, SBSpace.x4)

            Text("Bracelet check-in, balance top-up and bar payments. Sign in with your festival staff account.")
                .font(.sbBody(13))
                .foregroundStyle(.sbInk(0.6))
                .sbLineHeight(1.6, size: 13)
                .padding(.bottom, 22)

            SBTextField(
                label: "Email",
                placeholder: "name@swingbuzz.fest",
                text: $model.email,
                keyboard: .emailAddress,
                textContentType: .username
            )
            .padding(.bottom, 14)

            SBTextField(
                label: "Password",
                placeholder: "••••••••",
                text: $model.password,
                isSecure: true,
                textContentType: .password
            )
            .padding(.bottom, 8)

            if model.loginFailed {
                // The design draws form errors as an accent rule on the leading
                // edge, not as a filled alert box.
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color.sbAccent)
                        .frame(width: 3)
                    Text("Unknown account. Use one of the staff logins below.")
                        .font(.sbBody(12))
                        .foregroundStyle(.sbAccent700)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            }

            Button("Sign in") {
                Task { await model.signIn() }
            }
            .buttonStyle(.sbBlock(.primary, minHeight: 46, fontSize: 15))
            // Deliberately not disabled on an empty field: the design validates
            // on submit and shows the inline error above. A greyed-out primary
            // action on first launch reads as "app is broken".
            .disabled(model.isWorking)
            .padding(.top, SBSpace.x3)

            demoAccounts
                .padding(.top, 26)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var demoAccounts: some View {
        VStack(alignment: .leading, spacing: 0) {
            SBDivider(weight: SBRule.hairline)

            SBKicker(text: "Demo accounts")
                .padding(.top, SBSpace.x4)
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: SBSpace.x2) {
                demoButton(.reception, label: "reception@swingbuzz.fest — Reception")
                demoButton(.bar, label: "bar@swingbuzz.fest — Bar")
            }
        }
    }

    private func demoButton(_ role: StaffRole, label: String) -> some View {
        Button {
            model.fillDemoAccount(role)
        } label: {
            // Body font, not the heading font, per the design — these read as
            // data rather than as actions.
            Text(label)
                .font(.sbBody(12.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SBButtonStyle(kind: .secondary, block: true))
    }
}

#Preview {
    SignInView()
        .environment(AppModel())
        .background(Color.sbBackground)
}
