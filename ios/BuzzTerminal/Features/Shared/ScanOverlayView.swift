import SwiftUI

/// The scan sheet: a near-black full-bleed overlay, which is both a design
/// choice and a functional one — it kills every other tap target while the phone
/// is being held against someone's wrist.
struct ScanOverlayView: View {
    @Environment(AppModel.self) private var model

    let state: AppModel.ScanState

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 26) {
                target

                VStack(spacing: SBSpace.x2) {
                    Text(state.isReading ? "Reading chip…" : title)
                        .font(.sbDisplay(27))
                        .tracking(-0.01 * 27)
                        .multilineTextAlignment(.center)
                    Text(state.isReading
                         ? "Keep it still for a moment"
                         : subtitle)
                        .font(.sbBody(12.5))
                        .foregroundStyle(Color.sbNeutral100.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }

            Spacer(minLength: 0)

            // Only offered while there is no hardware reader and no read in
            // flight. Iteration 3 removes it on devices that have Core NFC.
            if !model.readerIsHardwareBacked && !state.isReading {
                simulatorPanel
            }

            Button("Cancel") { model.cancelScan() }
                .buttonStyle(CancelStyle())
                .padding(.top, 14)
        }
        .foregroundStyle(Color.sbNeutral100)
        .padding(.horizontal, SBSpace.x6)
        .padding(.top, 70)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sbNeutral900)
    }

    /// A participant-first check-in names the guest, because the wristband about
    /// to be held against the phone becomes theirs permanently. On hardware
    /// Apple's own sheet covers this overlay during the read and carries the same
    /// sentence (see `AppModel.scanPrompt`); here it is what the prototype panel
    /// is read against.
    private var title: String {
        switch state.purpose {
        case .assignToSelected: "Pair a bracelet"
        case .doorSale: "Fresh bracelet"
        case .identify, .payment: "Hold the bracelet"
        }
    }

    private var subtitle: String {
        switch state.purpose {
        case .assignToSelected:
            guard let guest = model.participant else { return Self.genericSubtitle }
            return "This bracelet becomes \(guest.name)’s for the whole festival"
        case .doorSale:
            guard let pass = model.selectedPass else { return Self.genericSubtitle }
            // Everything is decided by now, so this can name it — and naming it
            // is the last chance to notice the wrong wristband is in hand.
            // Named on both branches now that an evening ticket has a guest on
            // it — this is the last screen before the pairing is permanent.
            let who = model.doorSale.trimmedName
            return pass.kind == .evening
                ? "It becomes \(who)’s ticket for \(model.eveningSelection.label)"
                : "It becomes \(who)’s \(pass.name)"
        case .identify, .payment:
            return Self.genericSubtitle
        }
    }

    private static let genericSubtitle = "Against the back of the phone, near the top"

    private var target: some View {
        ZStack {
            if !state.isReading {
                ForEach(Array([0.0, 0.66, 1.33].enumerated()), id: \.offset) { _, delay in
                    PulseRing(delay: delay)
                }
            }

            if state.isReading {
                RotatingRule()
            } else {
                SBGlyphView(glyph: .nfcWave, size: 52, color: .sbAccent300)
            }
        }
        .frame(width: 180, height: 180)
    }

    /// One tappable chip. `label` is nil while a live status is still loading,
    /// which leaves the id carrying the row rather than showing a placeholder
    /// that would be mistaken for a status.
    private func simulatorRow(
        label: String?,
        id: BraceletID,
        emphasised: Bool = false
    ) -> some View {
        Button {
            Task { await model.selectSimulatedBracelet(id) }
        } label: {
            HStack(spacing: 10) {
                if let label {
                    Text(label)
                        .font(.sbBody(12.5))
                        .foregroundStyle(emphasised ? Color.sbAccent300 : Color.sbNeutral100)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(id.rawValue)
                        .font(.sbBody(11))
                        .foregroundStyle(Color.sbNeutral100.opacity(0.55))
                } else {
                    Text(id.rawValue)
                        .font(.sbBody(12.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(SimulatorRowStyle())
    }

    private var simulatorPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            SBKicker(
                text: model.runsOnFixtures
                    ? "Prototype · simulate a bracelet"
                    : "Prototype · simulate a bracelet · live data",
                color: .sbAccent300,
                size: 9,
                tracking: 0.16
            )
            .padding(.bottom, 9)

            VStack(spacing: 7) {
                // Only off the fixtures, where the five fixed chips can be used
                // up: pairing is permanent, so the first check-in retires one for
                // good and there would otherwise be no way to rehearse check-in
                // again without resetting the database.
                if !model.runsOnFixtures {
                    simulatorRow(
                        label: "New chip, never seen",
                        id: model.freshChip,
                        emphasised: true
                    )
                }

                ForEach(model.simulatedBracelets) { bracelet in
                    // The hints describe `SampleData`, so on a real backend they
                    // are false — and confidently so, which is worse than silence.
                    // What replaces them is not silence but the truth: one point
                    // read per chip, so the row says what the database says.
                    simulatorRow(
                        label: model.runsOnFixtures
                            ? bracelet.hint
                            : model.simulatedChipStatus[bracelet.id],
                        id: bracelet.id
                    )
                }
            }
        }
        .padding(.horizontal, SBSpace.x3)
        .padding(.top, SBSpace.x3)
        .padding(.bottom, 13)
        .overlay {
            Rectangle()
                .stroke(
                    Color.sbNeutral100.opacity(0.25),
                    style: StrokeStyle(lineWidth: SBRule.hairline, dash: [4, 3])
                )
        }
    }
}

// MARK: - Animated parts

/// One expanding, fading square outline. Three of these on staggered delays make
/// the design's `sbRing` pulse.
private struct PulseRing: View {
    let delay: Double
    @State private var expanded = false

    var body: some View {
        Rectangle()
            .stroke(Color.sbAccent400, lineWidth: 2)
            .scaleEffect(expanded ? 1.25 : 0.72)
            .opacity(expanded ? 0 : 0.55)
            .animation(
                .easeOut(duration: 2).repeatForever(autoreverses: false).delay(delay),
                value: expanded
            )
            .onAppear { expanded = true }
    }
}

/// The busy indicator. A rotating quarter of a square outline rather than the
/// usual circular spinner — Modernist does not round corners, so neither does
/// its progress indicator.
private struct RotatingRule: View {
    @State private var spinning = false

    var body: some View {
        Rectangle()
            .stroke(Color.sbNeutral100.opacity(0.3), lineWidth: 3)
            .overlay {
                Rectangle()
                    .trim(from: 0, to: 0.25)
                    .stroke(Color.sbAccent300, lineWidth: 3)
            }
            .frame(width: 40, height: 40)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

// MARK: - Styles local to the dark overlay

private struct SimulatorRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.sbNeutral100)
            .overlay {
                Rectangle().stroke(
                    configuration.isPressed ? Color.sbAccent300 : Color.sbNeutral100.opacity(0.22),
                    lineWidth: SBRule.hairline
                )
            }
    }
}

private struct CancelStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sbHeading(14))
            .foregroundStyle(Color.sbNeutral100)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(configuration.isPressed ? Color.sbNeutral100.opacity(0.12) : .clear)
            .overlay {
                Rectangle().stroke(Color.sbNeutral100.opacity(0.3), lineWidth: SBRule.hairline)
            }
            .contentShape(Rectangle())
    }
}

#Preview("Waiting") {
    ScanOverlayView(state: .init(purpose: .identify))
        .environment(AppModel())
}

#Preview("Reading") {
    ScanOverlayView(state: .init(purpose: .payment, isReading: true))
        .environment(AppModel())
}
