import SwiftUI

/// Who this is, what they have, and the one thing to do next.
///
/// Reached two ways since the check-in flow changed: by reading a paired
/// bracelet, and by picking a name off the check-in list. In the second case the
/// guest has no bracelet yet, so the screen is the confirmation step before an
/// irreversible pairing — which is the whole reason it sits between the list and
/// the chip. `CheckInAction` decides which of the two it is showing.
struct ParticipantView: View {
    @Environment(AppModel.self) private var model

    private var action: CheckInAction { model.participantAction ?? .scanAndAssign }
    private var isAwaitingCheckIn: Bool { action.isCheckIn }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SBTag(text: model.participant?.checkedInLabel ?? "Checked in")
                Spacer()
                Button(isAwaitingCheckIn ? "Back" : "Done") { model.leaveParticipant() }
                    .buttonStyle(.sbGhost)
            }

            identityCard
                .padding(.top, SBSpace.x4)

            SBDivider()
                .padding(.vertical, SBSpace.x4)

            // A guest with no bracelet has a balance of zero and no way to spend
            // it, so showing 0 € in 66pt would be answering a question nobody
            // asked and burying the one that matters — is this the right person.
            if isAwaitingCheckIn {
                SBKicker(text: "Ticket")
                Text(model.participant?.ticketDescription ?? "—")
                    .font(.sbDisplay(30))
                    .tracking(-0.02 * 30)
                    .sbLineHeight(1.1, size: 30)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            } else {
                SBKicker(text: "Balance")
                Text((model.participant?.balance ?? .zero).description)
                    .font(.sbDisplay(66))
                    .tracking(-0.03 * 66)
                    .padding(.top, 6)
            }

            Spacer(minLength: SBSpace.x4)

            VStack(alignment: .leading, spacing: 0) {
                SBDivider(weight: SBRule.hairline)
                Text(footnote)
                    .font(.sbBody(11.5))
                    .foregroundStyle(.sbInk(0.55))
                    .sbLineHeight(1.5, size: 11.5)
                    .padding(.top, 10)
            }

            Button(action.label) { perform(action) }
                .buttonStyle(.sbBlock(.primary, minHeight: 48, fontSize: 15))
                .disabled(model.isWorking)
                .padding(.top, 20)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 20)
    }

    private func perform(_ action: CheckInAction) {
        switch action {
        case .topUp:
            model.goToTopUp()
        case .scanAndAssign:
            model.scanToAssignBracelet()
        }
    }

    private var footnote: String {
        let name = model.participant?.name ?? "this guest"
        switch action {
        case .topUp:
            return "This bracelet is permanently paired with \(name). Checking in someone else needs a new bracelet."
        case .scanAndAssign:
            return "Check the name, then hold a fresh bracelet to the phone. The pairing is permanent, so the wrong wristband cannot be taken back."
        }
    }

    /// The identity block. The heavy 3pt border plus the filled band is the
    /// design's "this person is cleared" signal, readable from arm's length in a
    /// dark venue — so it must not be green for somebody who is not cleared yet.
    /// A guest awaiting check-in gets the accent band instead, which the design
    /// already uses to mean "your attention is needed here".
    private var identityCard: some View {
        VStack(spacing: 0) {
            SBBand(
                text: isAwaitingCheckIn ? "Awaiting check-in" : "Checked-In",
                tone: isAwaitingCheckIn ? .alert : .ok,
                glyph: isAwaitingCheckIn ? .nfcWave : .check,
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
                Text(subtitle)
                    .font(.sbBody(12))
                    .foregroundStyle(.sbInk(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 13)
        }
        .overlay {
            Rectangle().stroke(isAwaitingCheckIn ? Color.sbAccent : Color.sbOk, lineWidth: 3)
        }
    }

    /// Ticket and country identify a guest at the desk; the bracelet id only
    /// exists once there is one. Printing "Bracelet —" under somebody's name is
    /// noise at exactly the moment the operator is checking they have the right
    /// person.
    private var subtitle: String {
        guard let participant = model.participant else { return "—" }
        guard !isAwaitingCheckIn else {
            return "\(participant.ticketRef) · \(participant.country)"
        }
        return "\(participant.ticketDescription) · Bracelet \(model.braceletLabel)"
    }
}

#Preview("Checked in") {
    let model = AppModel()
    model.role = .reception
    model.bracelet = SampleData.braceletB
    model.participant = SampleData.participant(withBracelet: SampleData.braceletB)
    return ParticipantView()
        .environment(model)
        .background(Color.sbBackground)
}

#Preview("Awaiting check-in") {
    let model = AppModel()
    model.role = .reception
    model.participant = SampleData.awaitingCheckIn.first
    return ParticipantView()
        .environment(model)
        .background(Color.sbBackground)
}
