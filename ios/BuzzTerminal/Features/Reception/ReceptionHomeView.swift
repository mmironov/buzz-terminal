import SwiftUI

/// The reception idle screen: one scan target, and two deliberate starts.
///
/// Every action the desk performs now begins here, by name, rather than being
/// discovered part-way through a scan. Reading a bracelet *only* answers "whose
/// is this?" — it never turns into a check-in or a door sale on its own, because
/// both of those pair a chip permanently and that should never be something an
/// operator falls into from the wrong pile of wristbands.
struct ReceptionHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            Text("Reading a bracelet only says whose it is. Check-in and door sales start below.")
                .font(.sbBody(14))
                .foregroundStyle(.sbInk(0.65))
                .sbLineHeight(1.6, size: 14)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 270)

            scanTarget
                // Same reason as `actions` below: the outermost ring is drawn
                // 26pt outside its own frame, so the stack's spacing alone is
                // not clearance.
                .padding(.top, 20)

            actions

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                SBDivider(weight: SBRule.hairline)
                Text("Read → who it is, and top up · By name → check-in · Door → evening ticket")
                    .font(.sbBody(11))
                    .foregroundStyle(.sbInk(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 30)
    }

    /// Both below the scan target on purpose. All three are one tap, but a chip
    /// read answers "who is this?" in a second and needs no typing, so it stays
    /// the thing a thumb finds without looking.
    private var actions: some View {
        VStack(spacing: 10) {
            VStack(spacing: 5) {
                Button("Check in participant") { model.goToCheckInSearch() }
                    .buttonStyle(.sbBlock(.secondary, minHeight: 46, fontSize: 15))
                Text("Search the roster, then pair a bracelet")
                    .font(.sbBody(10.5))
                    .foregroundStyle(.sbInk(0.5))
            }

            VStack(spacing: 5) {
                Button("Sell evening ticket") { model.beginEveningTicketSale() }
                    .buttonStyle(.sbBlock(.secondary, minHeight: 46, fontSize: 15))
                Text("Sold at the door · no name needed")
                    .font(.sbBody(10.5))
                    .foregroundStyle(.sbInk(0.5))
            }
        }
        .frame(maxWidth: 270)
        // The scan target's outermost ring is drawn with a -26 negative padding,
        // so it extends past its own frame and the stack's spacing alone lets
        // this sit on top of it.
        .padding(.top, 24)
    }

    private var scanTarget: some View {
        Button {
            model.beginScan(for: .identify)
        } label: {
            VStack(spacing: SBSpace.x3) {
                SBGlyphView(glyph: .nfcWave, size: 46)
                Text("Read bracelet")
                    .font(.sbHeading(20))
                Text("Hold to the back of the phone")
                    .font(.sbBody(11))
                    .tracking(0.04 * 11)
                    .foregroundStyle(.sbInk(0.55))
            }
            .frame(width: 224, height: 224)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScanTargetStyle())
    }
}

/// Three concentric square outlines, fading outwards — the design's way of
/// drawing "radio waves" without an animation on an idle screen.
private struct ScanTargetStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.sbInk)
            .background(
                configuration.isPressed
                    ? Color.sbAccent.opacity(0.2)
                    : Color.clear
            )
            .overlay {
                Rectangle().stroke(Color.sbAccent, lineWidth: SBRule.hairline)
            }
            .overlay {
                Rectangle()
                    .stroke(Color.sbAccent.opacity(0.35), lineWidth: SBRule.hairline)
                    .padding(-12)
            }
            .overlay {
                Rectangle()
                    .stroke(Color.sbAccent.opacity(0.16), lineWidth: SBRule.hairline)
                    .padding(-26)
            }
    }
}

#Preview {
    ReceptionHomeView()
        .environment(AppModel())
        .background(Color.sbBackground)
}
