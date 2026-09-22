import SwiftUI

/// A chip nobody owns. A dead end on purpose.
///
/// Reading a bracelet asks one question — whose is this? — and this is the
/// answer. It used to slide straight into the check-in list, which made a
/// permanent pairing something an operator could arrive at by scanning a
/// wristband from the wrong pile. Both things that pair a chip now start
/// deliberately from the home screen instead.
///
/// So the only action here is "Done", the same shape as `BlockedBraceletView`,
/// and for the same reason: the screen states a fact, and the next move belongs
/// somewhere the operator chooses on purpose.
struct UnassignedBraceletView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SBBand(text: "Not assigned", tone: .alert, glyph: .nfcWave)

            VStack(alignment: .leading, spacing: 0) {
                Text("Nobody has this bracelet")
                    .font(.sbDisplay(32))
                    .tracking(-0.02 * 32)
                    .sbLineHeight(1.05, size: 32)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)

                Text("Bracelet \(model.braceletLabel)")
                    .font(.sbBody(12))
                    .foregroundStyle(.sbInk(0.6))

                SBDivider()
                    .padding(.vertical, SBSpace.x4)

                Text("A fresh wristband, or one nobody has been checked in with yet. There is nothing on it and nothing to spend.")
                    .font(.sbBody(13.5))
                    .foregroundStyle(.sbInk(0.7))
                    .sbLineHeight(1.6, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: SBSpace.x4)

                SBDivider(weight: SBRule.hairline)

                // Named rather than hinted at, because an operator holding an
                // unassigned wristband is one tap from the thing they actually
                // wanted, and guessing which screen it is on is the kind of
                // friction that produces a queue.
                // Plain, not markdown-bold: Archivo is loaded at fixed weights
                // and the `**` emphasis parsed but rendered identically, which
                // is dead markup pretending to be emphasis.
                Text("To give it to somebody, go back and choose “Check in participant”, or “Sell evening ticket” for a door sale.")
                    .font(.sbBody(12))
                    .foregroundStyle(.sbInk(0.55))
                    .sbLineHeight(1.5, size: 12)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                Button("Done") { model.goHome() }
                    .buttonStyle(.sbBlock(.primary, minHeight: 48, fontSize: 15))
                    .padding(.top, 14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.bracelet = SampleData.braceletA
    return UnassignedBraceletView()
        .environment(model)
        .background(Color.sbBackground)
}
