import SwiftUI

/// "Can you check my bracelet and tell me how much I've got?"
///
/// The whole screen is one number said out loud, so the number is the biggest
/// thing on it and everything else is there to make sure it is the right
/// person's. Nothing here charges, reserves or writes anything — the way back
/// is the order screen the bar was already on.
struct BalanceView: View {
    @Environment(AppModel.self) private var model

    private var check: BalanceCheck {
        model.balanceCheck ?? .of(nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SBBand(
                text: check.band,
                tone: check.isProblem ? .alert : .ok,
                glyph: .nfcWave
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(check.headline)
                    .font(.sbDisplay(check.amount == nil ? 34 : 52))
                    .tracking(-0.02 * 52)
                    .sbLineHeight(1.0, size: 52)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)

                // Named, because the guest is standing there and the wristband
                // in the bartender's hand is not always the one they think it
                // is. Two people share a surname at every festival.
                if let name = check.name {
                    Text(name)
                        .font(.sbHeading(20))
                        .sbLineHeight(1.15, size: 20)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(ticketLine)
                    .font(.sbBody(12))
                    .foregroundStyle(.sbInk(0.6))
                    .padding(.top, 3)

                SBDivider()
                    .padding(.vertical, SBSpace.x4)

                Text(check.note)
                    .font(.sbBody(13.5))
                    .foregroundStyle(check.isProblem ? .sbAccent800 : .sbInk(0.7))
                    .sbLineHeight(1.6, size: 13.5)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: SBSpace.x4)

                Button("Check another bracelet") {
                    model.beginScan(for: .checkBalance)
                }
                .buttonStyle(.sbBlock(.secondary, minHeight: 46, fontSize: 14))

                Button("Back to order") { model.goToMenu() }
                    .buttonStyle(.sbBlock(.primary, minHeight: 48, fontSize: 15))
                    .padding(.top, 9)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
    }

    private var ticketLine: String {
        guard let ticket = check.ticket else { return "Bracelet \(model.braceletLabel)" }
        return "\(ticket) · Bracelet \(model.braceletLabel)"
    }
}

#Preview("Has money") {
    let model = AppModel()
    model.role = .bar
    model.bracelet = SampleData.braceletB
    model.balanceCheck = .of(SampleData.participant(withBracelet: SampleData.braceletB))
    model.screen = .balance
    return BalanceView().environment(model).background(Color.sbBackground)
}

#Preview("Not checked in") {
    let model = AppModel()
    model.role = .bar
    model.bracelet = SampleData.braceletA
    model.balanceCheck = .of(nil)
    model.screen = .balance
    return BalanceView().environment(model).background(Color.sbBackground)
}
