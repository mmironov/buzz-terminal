import SwiftUI

/// Taking cash and crediting the bracelet. A till, essentially.
struct TopUpView: View {
    @Environment(AppModel.self) private var model

    private let columns3 = Array(repeating: GridItem(.flexible(), spacing: SBSpace.x2), count: 3)
    private let columns4 = Array(repeating: GridItem(.flexible(), spacing: SBSpace.x2), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            amountDisplay
            presets
            keypad
            // No spacer: the design stacks the confirm button directly under the
            // pad rather than pinning it to the bottom of the screen.
            confirmButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, SBSpace.x4)
        .padding(.bottom, 18)
    }

    private var header: some View {
        HStack {
            Button("Back") { model.backToParticipant() }
                .buttonStyle(.sbGhost)
            Spacer()
            Text("\(model.participant?.name ?? "—") · \((model.participant?.balance ?? .zero).description)")
                .font(.sbBody(12))
                .foregroundStyle(.sbInk(0.6))
        }
    }

    private var amountDisplay: some View {
        VStack(spacing: 0) {
            SBKicker(text: "Cash received")
            Text(model.topUp.display)
                .font(.sbDisplay(62))
                .tracking(-0.03 * 62)
                .sbLineHeight(1.1, size: 62)
            // A short rule under the figure, inset from the edges — the design's
            // way of saying "this is a field being typed into".
            Rectangle()
                .fill(Color.sbDivider)
                .frame(height: 1)
                .padding(.horizontal, 30)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var presets: some View {
        LazyVGrid(columns: columns4, spacing: SBSpace.x2) {
            ForEach(TopUpEntry.presets, id: \.cents) { preset in
                Button(preset.compactDescription) {
                    model.topUp.apply(preset: preset)
                }
                .buttonStyle(SBButtonStyle(kind: .secondary, minHeight: 42, fontSize: 14))
            }
        }
        .padding(.top, 14)
        .padding(.bottom, SBSpace.x4)
    }

    private var keypad: some View {
        LazyVGrid(columns: columns3, spacing: SBSpace.x2) {
            ForEach(Array(TopUpEntry.keys.enumerated()), id: \.offset) { _, key in
                Button {
                    model.topUp.press(key)
                } label: {
                    // Archivo has no U+232B, so the backspace key would fall
                    // back to a system face at a visibly lighter weight. Drawing
                    // it keeps the whole pad in one visual language.
                    if key == .backspace {
                        SBGlyphView(glyph: .backspace, size: 24, color: .sbInk)
                    } else {
                        Text(key.label)
                    }
                }
                .buttonStyle(KeypadStyle())
                .accessibilityLabel(key == .backspace ? "Backspace" : key.label)
            }
        }
    }

    private var confirmButton: some View {
        Button(model.topUp.confirmButtonTitle) {
            Task { await model.confirmTopUp() }
        }
        .buttonStyle(.sbBlock(.primary, minHeight: 50, fontSize: 15))
        .disabled(!model.topUp.isConfirmable || model.isWorking)
        .padding(.top, SBSpace.x4)
    }
}

/// A keypad key: outlined, square-cornered, 52pt tall so it is hittable without
/// looking. Pressed state is an accent wash, per the design system.
private struct KeypadStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sbHeading(22))
            .foregroundStyle(.sbInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(configuration.isPressed ? Color.sbAccent.opacity(0.18) : .clear)
            .overlay {
                Rectangle().stroke(Color.sbDivider, lineWidth: SBRule.hairline)
            }
            .contentShape(Rectangle())
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.bracelet = SampleData.braceletB
    model.participant = SampleData.participants[SampleData.braceletB]
    return TopUpView()
        .environment(model)
        .background(Color.sbBackground)
}
