import SwiftUI

/// A bracelet an organiser froze in the admin panel. Deliberately a dead end:
/// the only action is "Done", because nothing can be done from the terminal.
struct BlockedBraceletView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SBBand(text: "Bracelet blocked", tone: .alert, glyph: .blocked)

            VStack(alignment: .leading, spacing: 0) {
                Text(model.participant?.name ?? "—")
                    .font(.sbDisplay(32))
                    .tracking(-0.02 * 32)
                    .sbLineHeight(1.05, size: 32)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

                Text("\(model.participant?.ticketDescription ?? "—") · Bracelet \(model.braceletLabel)")
                    .font(.sbBody(12))
                    .foregroundStyle(.sbInk(0.6))

                // Accent-700, not the raw accent: the design system notes the
                // accent-to-ground pair only reaches 3:1, which is fine for
                // chrome but not for paragraph text.
                HStack(alignment: .top, spacing: 12) {
                    Rectangle()
                        .fill(Color.sbAccent)
                        .frame(width: 3)
                    Text(model.participant?.blockReason ?? "")
                        .font(.sbBody(13.5))
                        .foregroundStyle(.sbAccent800)
                        .sbLineHeight(1.65, size: 13.5)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

                SBDivider()
                    .padding(.vertical, SBSpace.x4)

                SBKicker(text: "Balance frozen", color: .sbInk(0.45))

                Text((model.participant?.balance ?? .zero).description)
                    .font(.sbDisplay(52))
                    .tracking(-0.03 * 52)
                    .foregroundStyle(.sbInk(0.4))
                    .strikethrough(true, pattern: .solid, color: .sbInk(0.4))

                Spacer(minLength: SBSpace.x4)

                SBDivider(weight: SBRule.hairline)

                Text("No top-ups and no payments on this bracelet. An organiser lifts the block from the web admin panel.")
                    .font(.sbBody(12))
                    .foregroundStyle(.sbInk(0.55))
                    .sbLineHeight(1.5, size: 12)
                    .padding(.top, 10)

                Button("Done") { model.goHome() }
                    .buttonStyle(.sbBlock(.secondary, minHeight: 46, fontSize: 15))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.bracelet = SampleData.braceletD
    model.participant = SampleData.participant(withBracelet: SampleData.braceletD)
    return BlockedBraceletView()
        .environment(model)
        .background(Color.sbBackground)
}
