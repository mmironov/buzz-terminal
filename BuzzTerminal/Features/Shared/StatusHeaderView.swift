import SwiftUI

/// The persistent chrome above every signed-in screen: who you are, what the
/// connection is doing, and the way out.
struct StatusHeaderView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SBSpace.x2) {
                VStack(alignment: .leading, spacing: 0) {
                    SBKicker(text: model.festivalName, color: .sbAccent, tracking: 0.16)
                    Text(model.role?.label ?? "")
                        .font(.sbHeading(19))
                        .sbLineHeight(1.15, size: 19)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                networkToggle

                Button("Sign out") {
                    Task { await model.signOut() }
                }
                .buttonStyle(.sbGhost)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, SBSpace.x3)

            SBDivider()

            if model.isOffline {
                offlineBanner
            }
        }
    }

    private var networkToggle: some View {
        Button {
            model.toggleOffline()
        } label: {
            HStack(spacing: 6) {
                // A hard 8pt square, not a circle — radius 0 applies to status
                // dots too.
                Rectangle()
                    .fill(model.networkDotColor)
                    .frame(width: 8, height: 8)
                Text(model.networkLabel)
                    .font(.sbBody(11))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(NetworkToggleStyle())
    }

    private var offlineBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: SBSpace.x2) {
                SBKicker(text: "Offline", color: .sbAccent800, tracking: 0.1)
                Text(model.queueLabel)
                    .font(.sbBody(11.5))
                    .foregroundStyle(.sbAccent800)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, SBSpace.x2)
            .background(Color.sbAccent100)

            SBDivider(weight: SBRule.hairline)
        }
    }
}

private struct NetworkToggleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.sbInk)
            .background(configuration.isPressed ? Color.sbInk(0.07) : .clear)
            .overlay {
                Rectangle().stroke(Color.sbDivider, lineWidth: SBRule.hairline)
            }
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.isOffline = true
    model.queuedTransactions = 3
    return VStack {
        StatusHeaderView().environment(model)
        Spacer()
    }
    .background(Color.sbBackground)
}
