import SwiftUI

/// Who is buying the pass. Asked before any wristband is touched.
///
/// Four questions, and no more. A door sale competes with a queue, so everything
/// here has to earn its place:
///
///   · **Name** — a Full Pass is a weekend-long thing and a lost wristband has to
///     be traceable to somebody. This is the field that separates a door pass
///     from an evening ticket, which asks for a name and nothing else.
///   · **Dance role** — leader or follower, which is what class lists are built
///     from. Stored as `danceRole`, never `role`; that name belongs to the staff
///     claim the security rules read.
///   · **Level** — only for Full Pass and Full Pass Gold, the two whose classes
///     actually split by it. Every other pass hides the field entirely.
///   · **Email** — optional, and it does **not** go on the participant document.
///     It is written to `contact/details`, which the bar cannot read. Every other
///     field here is visible to every terminal, exactly as the Sheet's roster
///     already is; an address is not.
struct DoorBuyerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let pass = model.selectedPass

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: SBSpace.x2) {
                    Text(pass?.name ?? "Door pass")
                        .font(.sbHeading(24))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // Back to the passes rather than home: changing your mind
                    // about which pass is the likely correction here, and
                    // nothing has been paired yet to undo.
                    Button("Back") { model.backToPassPicker() }
                        .buttonStyle(.sbGhost)
                }

                Text("\(pass?.collectLabel() ?? "—") · the bracelet comes last")
                    .font(.sbBody(11.5))
                    .foregroundStyle(.sbInk(0.55))
                    .padding(.top, 2)

                SBDivider()
                    .padding(.vertical, 14)

                SBTextField(
                    label: "Name",
                    placeholder: "As they say it",
                    text: $model.doorSale.name,
                    autocapitalization: .words
                )

                SBKicker(text: "Dances as")
                    .padding(.top, SBSpace.x4)
                    .padding(.bottom, SBSpace.x2)

                HStack(spacing: SBSpace.x2) {
                    ForEach(DanceRole.allCases) { role in
                        SBChoiceBox(
                            title: role.label,
                            isSelected: model.doorSale.danceRole == role,
                            select: { model.doorSale.danceRole = role }
                        )
                    }
                }

                if pass?.asksForLevel == true {
                    SBKicker(text: "Level")
                        .padding(.top, SBSpace.x4)
                        .padding(.bottom, SBSpace.x2)

                    // Two to a row rather than all across: at 16pt these labels
                    // do not fit a third of a phone, and a level chosen by
                    // mis-tapping a cramped row is worse than a taller screen.
                    let levels = DoorSaleDraft.levels
                    VStack(spacing: SBSpace.x2) {
                        ForEach(Array(stride(from: 0, to: levels.count, by: 2)), id: \.self) { start in
                            HStack(spacing: SBSpace.x2) {
                                ForEach(levels[start..<min(start + 2, levels.count)], id: \.self) { level in
                                    SBChoiceBox(
                                        title: level,
                                        isSelected: model.doorSale.level == level,
                                        // Shown, not hidden: a full class that
                                        // vanished would leave reception
                                        // explaining a gap to somebody asking
                                        // for Advanced.
                                        note: DoorSaleDraft.isSoldOut(level) ? "Sold out" : nil,
                                        isEnabled: !DoorSaleDraft.isSoldOut(level),
                                        select: { model.doorSale.level = level }
                                    )
                                }
                                // Three levels leave the last one alone on its
                                // row, and a box that fills the width reads as a
                                // different, bigger control than the two above.
                                if levels.count - start == 1 {
                                    Color.clear.frame(maxWidth: .infinity, minHeight: 46)
                                }
                            }
                        }
                    }
                }

                SBTextField(
                    label: "Email (optional)",
                    placeholder: "name@example.com",
                    text: $model.doorSale.email,
                    keyboard: .emailAddress,
                    textContentType: .emailAddress
                )
                .padding(.top, SBSpace.x4)

                Text("The email is kept where only reception and the organiser panel can read it. The bar sees the name and the pass, like everybody else on the roster.")
                    .font(.sbBody(11))
                    .foregroundStyle(.sbInk(0.5))
                    .sbLineHeight(1.5, size: 11)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SBSpace.x2)

                methodPicker

                if let pass {
                    confirm(pass)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, SBSpace.x4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Cash or card, nothing pre-selected — the same control and the same rule
    /// as the top-up screen, because it is the same question about the same cash
    /// box. Last on the form, because it is the last thing to happen: the pass is
    /// agreed, then the money is handed over.
    private var methodPicker: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: SBSpace.x2) {
            SBKicker(text: "Paid by")
            HStack(spacing: SBSpace.x2) {
                ForEach(PaymentMethod.allCases) { method in
                    SBChoiceBox(
                        title: method.label,
                        isSelected: model.doorSale.method == method,
                        // No un-picking by tapping again: one of the two is
                        // true, and a double tap must not quietly clear it.
                        select: { model.doorSale.method = method }
                    )
                }
            }
        }
        .padding(.top, SBSpace.x4)
    }

    /// The button says what is missing rather than sitting there greyed out —
    /// the same rule the top-up screen follows.
    private func confirm(_ pass: DoorPass) -> some View {
        let blocker = model.doorSale.blocker(for: pass)
        return VStack(alignment: .leading, spacing: 0) {
            SBDivider(weight: SBRule.hairline)
                .padding(.top, SBSpace.x4)
            // Onward to the same confirmation screen a check-in gets, where the
            // scan happens. Until every field is filled the button names what is
            // missing instead.
            Button(blocker ?? "Continue · \(pass.priceLabel())") {
                model.previewDoorSale()
            }
            .buttonStyle(.sbBlock(.primary, minHeight: 50, fontSize: 15))
            .disabled(blocker != nil || model.isWorking)
            .padding(.top, 10)
        }
    }
}

#Preview("Full Pass — asks for a level") {
    let model = AppModel()
    model.role = .reception
    model.doorPasses = SampleData.doorPasses
    model.selectedPass = SampleData.doorPasses.first { $0.id == "full-pass" }
    model.screen = .doorBuyer
    return DoorBuyerView()
        .environment(model)
        .background(Color.sbBackground)
}

#Preview("Party Pass — no level") {
    let model = AppModel()
    model.role = .reception
    model.doorPasses = SampleData.doorPasses
    model.selectedPass = SampleData.doorPasses.first { $0.id == "party-pass" }
    model.screen = .doorBuyer
    return DoorBuyerView()
        .environment(model)
        .background(Color.sbBackground)
}
