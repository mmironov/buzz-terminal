import SwiftUI

/// A known bracelet was read: show who it is, what they have, and offer a top-up.
struct ParticipantView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SBTag(text: model.participant?.checkedInLabel ?? "Checked in")
                Spacer()
                Button("Done") { model.goHome() }
                    .buttonStyle(.sbGhost)
            }

            identityCard
                .padding(.top, SBSpace.x4)

            SBDivider()
                .padding(.vertical, SBSpace.x4)

            SBKicker(text: "Balance")

            Text((model.participant?.balance ?? .zero).description)
                .font(.sbDisplay(66))
                .tracking(-0.03 * 66)
                .padding(.top, 6)

            Spacer(minLength: SBSpace.x4)

            VStack(alignment: .leading, spacing: 0) {
                SBDivider(weight: SBRule.hairline)
                Text("This bracelet is permanently paired with \(model.participant?.name ?? "this guest"). Checking in someone else needs a new bracelet.")
                    .font(.sbBody(11.5))
                    .foregroundStyle(.sbInk(0.55))
                    .sbLineHeight(1.5, size: 11.5)
                    .padding(.top, 10)
            }

            Button("Add money") { model.goToTopUp() }
                .buttonStyle(.sbBlock(.primary, minHeight: 48, fontSize: 15))
                .padding(.top, 20)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    /// The green-bordered identity block. The heavy 3pt border plus the filled
    /// band is the design's "this person is cleared" signal, readable from arm's
    /// length in a dark venue.
    private var identityCard: some View {
        VStack(spacing: 0) {
            SBBand(
                text: "Checked-In",
                glyphSize: 18,
                fontSize: 12.5,
                padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(model.participant?.name ?? "—")
                    .font(.sbDisplay(32))
                    .tracking(-0.02 * 32)
                    .sbLineHeight(1.05, size: 32)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(model.participant?.ticketType ?? "—") · Bracelet \(model.braceletLabel)")
                    .font(.sbBody(12))
                    .foregroundStyle(.sbInk(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 13)
        }
        .overlay {
            Rectangle().stroke(Color.sbOk, lineWidth: 3)
        }
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.bracelet = SampleData.braceletB
    model.participant = SampleData.participant(withBracelet: SampleData.braceletB)
    return ParticipantView()
        .environment(model)
        .background(Color.sbBackground)
}
