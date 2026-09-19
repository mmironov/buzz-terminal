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

                // Its own line rather than appended to the pass type: the
                // operator is scanning for one word, and "Full Pass Gold · Pro"
                // at 30pt wraps and buries it.
                if let level = model.participant?.levelForDisplay {
                    Text(level)
                        .font(.sbHeading(15))
                        .foregroundStyle(.sbInk(0.6))
                        .padding(.top, 4)
                }
            } else {
                SBKicker(text: "Balance")
                Text((model.participant?.balance ?? .zero).description)
                    .font(.sbDisplay(66))
                    .tracking(-0.03 * 66)
                    .padding(.top, 6)
            }

            if let merch = model.merch, merch.hasSomethingToCollect {
                merchSection(merch)
                    .padding(.top, SBSpace.x4)
            } else if model.merchUnavailable {
                // Said out loud, because "nothing ordered" and "could not find
                // out" are the same blank space otherwise — and the difference
                // is a guest going home without a t-shirt they paid for.
                VStack(alignment: .leading, spacing: 0) {
                    SBDivider(weight: SBRule.hairline)
                    Text("Preorders could not be read. Check with an organiser before telling anybody they ordered nothing.")
                        .font(.sbBody(11.5))
                        .foregroundStyle(.sbAccent800)
                        .sbLineHeight(1.5, size: 11.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .padding(.top, SBSpace.x4)
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

    /// Preordered merch, and the one thing to do with it.
    ///
    /// Only drawn when something was actually ordered — 28 of 105 people on the
    /// real Sheet — so the other 77 screens are unchanged rather than carrying
    /// an empty "Merch: none" row that trains everybody to stop reading.
    ///
    /// Collected state is a filled band rather than a tick beside the text: the
    /// question at the desk is "have they had it?", asked across a counter, and
    /// it should be answerable from the colour alone.
    private func merchSection(_ merch: MerchOrder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SBDivider(weight: SBRule.hairline)

            HStack(alignment: .firstTextBaseline, spacing: SBSpace.x2) {
                SBKicker(text: "Preordered")
                Spacer(minLength: 0)
                if let collected = merch.collectedLabel {
                    Text(collected)
                        .font(.sbBody(11))
                        .foregroundStyle(.sbOk)
                }
            }
            .padding(.top, 12)

            Text(merch.summary)
                .font(.sbHeading(19))
                .foregroundStyle(merch.isCollected ? .sbInk(0.45) : .sbInk)
                .strikethrough(merch.isCollected, pattern: .solid, color: .sbInk(0.4))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            Button(merch.isCollected ? "Undo — not handed over" : "Mark as collected") {
                Task { await model.setMerchCollected(!merch.isCollected) }
            }
            .buttonStyle(.sbBlock(.secondary, minHeight: 44, fontSize: 14))
            .disabled(model.isWorking)
            .padding(.top, 12)
        }
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

                if let colour = model.participantColour {
                    braceletColourRow(colour)
                        .padding(.top, 7)
                }
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

    /// Which colour wristband this guest gets.
    ///
    /// Inside the identity card, under the ticket line, because it answers a
    /// question about this person rather than about the festival — reception is
    /// reaching for a pile of wristbands while looking at this block.
    ///
    /// A full-width bar with the name written on it, rather than a small square
    /// beside a label. The operator is matching this against a physical band in
    /// whatever light the venue has: a 16pt chip was too little colour to judge,
    /// and at arm's length across a desk it read as an icon rather than as the
    /// colour itself. A band that spans the card is the thing being compared.
    ///
    /// The text on it flips between dark and white by luminance — an organiser
    /// can pick a pale yellow, and white on that is unreadable. The hairline
    /// border keeps a near-white colour from dissolving into the card.
    private func braceletColourRow(_ colour: BraceletColour) -> some View {
        Text("\(colour.label) bracelet".uppercased())
            .font(.sbHeading(13, weight: .extrabold))
            .tracking(0.1 * 13)
            .foregroundStyle(colour.prefersDarkText ? Color.sbInk : Color.sbNeutral100)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color(hex: colour.hex) ?? .clear)
            .overlay {
                Rectangle().stroke(Color.sbInk(0.18), lineWidth: SBRule.hairline)
            }
    }

    /// Ticket and country identify a guest at the desk; the bracelet id only
    /// exists once there is one. Printing "Bracelet —" under somebody's name is
    /// noise at exactly the moment the operator is checking they have the right
    /// person.
    /// The level rides here rather than on its own line, because this state has
    /// no "Ticket" section to hang it under — the 66pt balance takes that space
    /// — and this is the line already carrying the pass type.
    private var subtitle: String {
        guard let participant = model.participant else { return "—" }
        guard !isAwaitingCheckIn else {
            return "\(participant.ticketRef) · \(participant.country)"
        }
        let level = participant.levelForDisplay.map { " · \($0)" } ?? ""
        return "\(participant.ticketDescription)\(level) · Bracelet \(model.braceletLabel)"
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
