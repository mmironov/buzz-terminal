import SwiftUI

/// A wristband that was replaced. A dead end, and an ordinary one.
///
/// This is what somebody holding a found wristband gets, at either terminal.
/// It is deliberately a screen rather than an error alert: at the bar it is a
/// normal thing to happen on a Saturday night, not a fault, and "Something went
/// wrong" is the wrong sentence to put in front of a guest who has picked a
/// wristband up off the floor.
///
/// **It does not say whose it was.** The chip still knows — the document keeps
/// pointing at its owner, which is the record of who had it and until when — but
/// whoever is holding it now is not necessarily them, and reception is one
/// conversation away.
struct ReplacedBraceletView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SBBand(text: "No longer valid", tone: .alert, glyph: .nfcWave)

            VStack(alignment: .leading, spacing: 0) {
                Text("This bracelet was replaced")
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

                Text("It stopped working when a new one was issued. Nothing can be bought with it and it opens nobody’s account.")
                    .font(.sbBody(13.5))
                    .foregroundStyle(.sbInk(0.7))
                    .sbLineHeight(1.6, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: SBSpace.x4)

                SBDivider(weight: SBRule.hairline)

                Text("If somebody handed it in, reception knows whose it was. If they are standing here saying it is theirs, they have a new one — this is the old.")
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
    model.role = .bar
    model.bracelet = SampleData.braceletA
    model.screen = .replacedBracelet
    return ReplacedBraceletView()
        .environment(model)
        .background(Color.sbBackground)
}
