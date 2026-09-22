import SwiftUI

/// Which pass is being sold. The first question of a door sale.
///
/// The list is the admin panel's `doorPasses`, in the order organisers put them
/// in, and it is the whole of what reception may sell — `firestore.rules` checks
/// the sale against the same collection as it is written, so a pass that is not
/// here cannot be minted by a terminal that somehow offered it.
///
/// The price beside each is what the desk collects. Nothing in this app takes
/// it: a pass is not credit on a bracelet, so there is no ledger entry and no
/// balance. That is the same line the evening ticket has always held.
struct DoorPassPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: SBSpace.x2) {
                Text("Sell a pass")
                    .font(.sbHeading(26))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { model.goHome() }
                    .buttonStyle(.sbGhost)
            }

            Text("Sold at the door · the bracelet is scanned last")
                .font(.sbBody(11.5))
                .foregroundStyle(.sbInk(0.55))
                .padding(.top, 2)

            SBDivider()
                .padding(.vertical, 14)

            if model.doorPasses.isEmpty {
                if model.isLoadingDoorPasses {
                    Text("Reading the price list…")
                        .font(.sbBody(13))
                        .foregroundStyle(.sbInk(0.55))
                        .padding(.top, SBSpace.x2)
                } else if model.doorPassesUnavailable {
                    unreadable
                } else {
                    empty
                }
            } else {
                SBKicker(text: "What are they buying")
                    .padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: SBSpace.x2) {
                        ForEach(model.doorPasses) { pass in
                            Button { model.select(pass: pass) } label: {
                                PassLabel(pass: pass)
                            }
                            .buttonStyle(PassChoiceStyle())
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)

                Text("Prices come from the admin panel. Take the money at the desk — the app records the pass, not the payment.")
                    .font(.sbBody(11.5))
                    .foregroundStyle(.sbInk(0.55))
                    .sbLineHeight(1.5, size: 11.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, SBSpace.x4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, SBSpace.x4)
        .padding(.bottom, 20)
    }

    /// The list could not be read at all.
    ///
    /// A different sentence from "nothing on sale", and the difference is the
    /// whole point: one is an organiser who has not filled the catalogue in, the
    /// other is a phone that could not reach it. Told apart on screen because
    /// they are told apart in the model — the same mistake as swallowing a
    /// permission error into "ordered nothing", which cost an evening once.
    private var unreadable: some View {
        VStack(alignment: .leading, spacing: SBSpace.x3) {
            SBBand(text: "Could not read the passes", tone: .alert, glyph: .nfcWave)
            Text("The price list did not load, so there is nothing to sell from. Check the connection and try again — nothing has been paired yet.")
                .font(.sbBody(13))
                .foregroundStyle(.sbInk(0.7))
                .sbLineHeight(1.5, size: 13)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                Task { await model.refreshDoorPasses() }
            }
            .buttonStyle(.sbBlock(.primary, minHeight: 50, fontSize: 15))
            .disabled(model.isLoadingDoorPasses)
            .padding(.top, SBSpace.x2)
            Button("Cancel the sale") { model.goHome() }
                .buttonStyle(.sbBlock(.secondary, minHeight: 46, fontSize: 14))
        }
    }

    /// Nobody has set the catalogue up. Says which screen fixes it, because the
    /// person holding the phone is not the person who can.
    private var empty: some View {
        VStack(alignment: .leading, spacing: SBSpace.x3) {
            SBBand(text: "Nothing on sale", tone: .alert, glyph: .nfcWave)
            Text("No passes are set up in the admin panel, so there is nothing to sell at the door. An organiser adds them under Door passes.")
                .font(.sbBody(13))
                .foregroundStyle(.sbInk(0.7))
                .sbLineHeight(1.5, size: 13)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { model.goHome() }
                .buttonStyle(.sbBlock(.primary, minHeight: 50, fontSize: 15))
                .padding(.top, SBSpace.x2)
        }
    }
}

/// One row: what it is on the left, what it costs on the right.
private struct PassLabel: View {
    let pass: DoorPass

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SBSpace.x3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pass.name)
                    .font(.sbHeading(17, weight: .extrabold))
                    .multilineTextAlignment(.leading)
                if pass.kind == .evening {
                    Text("Priced per night")
                        .font(.sbBody(10.5))
                        .foregroundStyle(.sbInk(0.5))
                }
            }
            Spacer(minLength: 0)
            // An evening ticket costs a different amount on each night, so the
            // number belongs beside the nights rather than here, where it could
            // only be one of three and would be read out as if it were the one.
            if pass.kind != .evening {
                Text(pass.priceLabel())
                    .font(.sbHeading(15, weight: .extrabold))
                    // An unpriced pass reads as a warning rather than as a
                    // number, because the desk is about to say it out loud.
                    .foregroundStyle(pass.price.isPositive ? Color.sbInk : Color.sbAccent)
            }
        }
    }
}

/// Outlined, tall enough to hit without looking, pressed state an accent wash —
/// the same language as the keypad and the evening buttons beside it.
private struct PassChoiceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.sbInk)
            .padding(.horizontal, SBSpace.x3 * 1.2)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(configuration.isPressed ? Color.sbAccent.opacity(0.18) : .clear)
            .overlay { Rectangle().stroke(Color.sbDivider, lineWidth: SBRule.hairline) }
            .contentShape(Rectangle())
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.doorPasses = SampleData.doorPasses
    model.screen = .doorPass
    return DoorPassPickerView()
        .environment(model)
        .background(Color.sbBackground)
}
