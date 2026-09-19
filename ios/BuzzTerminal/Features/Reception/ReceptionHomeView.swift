import SwiftUI

/// The reception idle screen: the scan target, and the other way in.
///
/// Two ways to start, because the desk has two jobs that begin differently. A
/// guest arriving with a bracelet already on their wrist is a chip; a guest
/// arriving to *collect* one is a name. Making everything start with a chip meant
/// the second case had to be discovered by scanning a blank wristband first,
/// which is a thing you have to be told.
struct ReceptionHomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            Text("Read a bracelet to see who it belongs to, or check somebody in by name.")
                .font(.sbBody(14))
                .foregroundStyle(.sbInk(0.65))
                .sbLineHeight(1.6, size: 14)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)

            scanTarget

            checkInButton

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                SBDivider(weight: SBRule.hairline)
                HStack(spacing: 18) {
                    Text("Known bracelet → top-up")
                    Text("|").foregroundStyle(.sbDivider)
                    Text("By name → check-in")
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

    /// Secondary, and below the scan target on purpose. Both are one tap, but a
    /// chip read answers "who is this?" in a second and needs no typing, so it
    /// stays the thing a thumb finds without looking.
    private var checkInButton: some View {
        VStack(spacing: 6) {
            Button("Check in new participant") { model.goToCheckInSearch() }
                .buttonStyle(.sbBlock(.secondary, minHeight: 48, fontSize: 15))
                // The scan target's outermost ring is drawn with a -26 negative
                // padding, so it extends past its own frame and the stack's
                // spacing alone lets the button sit on top of it.
                .padding(.top, 24)
            Text("Search the roster, then pair a bracelet")
                .font(.sbBody(11))
                .foregroundStyle(.sbInk(0.5))
        }
        .frame(maxWidth: 260)
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
