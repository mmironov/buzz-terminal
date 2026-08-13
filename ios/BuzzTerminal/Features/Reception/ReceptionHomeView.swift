import SwiftUI

/// The reception idle screen: one enormous scan target and nothing else.
/// "Every action starts with a bracelet."
struct ReceptionHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 0)

            Text("Every action starts with a bracelet. Read the chip, then choose check-in or top-up.")
                .font(.sbBody(14))
                .foregroundStyle(.sbInk(0.65))
                .sbLineHeight(1.6, size: 14)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)

            scanTarget

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                SBDivider(weight: SBRule.hairline)
                HStack(spacing: 18) {
                    Text("New bracelet → check-in")
                    Text("|").foregroundStyle(.sbDivider)
                    Text("Known bracelet → top-up")
                }
                .font(.sbBody(11.5))
                .foregroundStyle(.sbInk(0.55))
                .padding(.top, 14)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 20)
        .padding(.bottom, 30)
    }

    private var scanTarget: some View {
        Button {
            model.beginScan(for: .checkInOrTopUp)
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
