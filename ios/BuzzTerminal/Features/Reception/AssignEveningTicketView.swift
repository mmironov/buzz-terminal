import SwiftUI

/// Which night an evening ticket is for, and who it is for.
///
/// Reached from the pass picker when the chosen pass is the numbered evening
/// ticket. It is this pass's whole "buyer details" step, and it asks for exactly
/// two things: a night and a name. No dance role, no level, no email — one night
/// at a door with a queue behind it builds no class lists and sends no mail.
///
/// The wristband is scanned after this, as the last act, exactly as on the buyer
/// form beside it. A chip that already belongs to somebody is refused then.
struct AssignEveningTicketView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: SBSpace.x2) {
                Text("Evening ticket")
                    .font(.sbHeading(26))
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Back to the passes, not home: picking the wrong row is the
                // likely correction, and nothing has been paired yet.
                Button("Back") { model.backToPassPicker() }
                    .buttonStyle(.sbGhost)
            }

            Text("\(model.selectedPass?.collectLabel ?? "—") · the bracelet comes last")
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
            .padding(.bottom, SBSpace.x4)

            SBKicker(text: "Which evening")
                .padding(.bottom, 10)

            VStack(spacing: SBSpace.x2) {
                ForEach(Evening.allCases, id: \.self) { evening in
                    Button {
                        model.eveningSelection = evening
                    } label: {
                        Text(evening.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(EveningChoiceStyle(isSelected: model.eveningSelection == evening))
                }
            }

            Text("Only the name is recorded — no level, no email. The ticket is valid for the evening above; an organiser freezes it afterwards from the admin panel.")
                .font(.sbBody(11.5))
                .foregroundStyle(.sbInk(0.55))
                .sbLineHeight(1.5, size: 11.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SBSpace.x4)

            Spacer(minLength: SBSpace.x4)

            VStack(alignment: .leading, spacing: 0) {
                SBDivider(weight: SBRule.hairline)
                // Says what is missing rather than sitting there greyed out,
                // the same rule the buyer form and the keypad follow.
                let blocker = model.selectedPass.flatMap { model.doorSale.blocker(for: $0) }
                Button(blocker ?? "Continue · \(model.eveningSelection.label)") {
                    model.previewDoorSale()
                }
                .buttonStyle(.sbBlock(.primary, minHeight: 50, fontSize: 15))
                .disabled(blocker != nil || model.isWorking)
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, SBSpace.x4)
        .padding(.bottom, 20)
    }
}

/// A large one-handed choice. Selected is a solid accent fill — Modernist uses the
/// accent for the thing that is currently true, not for decoration.
private struct EveningChoiceStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sbHeading(18, weight: .extrabold))
            .foregroundStyle(isSelected ? .sbBackground : .sbInk)
            .padding(.horizontal, SBSpace.x3 * 1.2)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(background(pressed: configuration.isPressed))
            .overlay {
                if !isSelected {
                    Rectangle().stroke(Color.sbDivider, lineWidth: SBRule.hairline)
                }
            }
            .contentShape(Rectangle())
    }

    private func background(pressed: Bool) -> Color {
        if isSelected { return pressed ? .sbAccent700 : .sbAccent }
        return pressed ? Color.sbAccent.opacity(0.18) : .clear
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.doorPasses = SampleData.doorPasses
    model.selectedPass = SampleData.doorPasses.first { $0.kind == .evening }
    model.screen = .assignEvening
    return AssignEveningTicketView()
        .environment(model)
        .background(Color.sbBackground)
}
