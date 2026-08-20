import SwiftUI

/// The persistent chrome above every signed-in screen: who you are, what the
/// connection is doing, and the way out.
struct StatusHeaderView: View {
    @Environment(AppModel.self) private var model
    @State private var showingFailures = false

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

            // One banner, three things to say: offline, queued, or refused. It
            // appears whenever there is something worth saying rather than only
            // when offline — a write refused an hour ago still matters once the
            // wifi is back, and that is exactly when nobody would look.
            if let message = model.syncMessage {
                syncBanner(message)
            }
        }
    }

    private var networkToggle: some View {
        Button {
            Task { await model.toggleOffline() }
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

    private func syncBanner(_ message: String) -> some View {
        VStack(spacing: 0) {
            Button {
                // Only a failure has anywhere to go. Queued and offline are
                // statements, not invitations.
                if model.syncIsAlarming { showingFailures = true }
            } label: {
                HStack(spacing: SBSpace.x2) {
                    SBKicker(
                        text: model.syncIsAlarming ? "Failed" : (model.isOffline ? "Offline" : "Syncing"),
                        color: .sbAccent800,
                        tracking: 0.1
                    )
                    Text(message)
                        .font(.sbBody(11.5))
                        .foregroundStyle(.sbAccent800)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if model.syncIsAlarming {
                        Text("View")
                            .font(.sbBody(11.5))
                            .foregroundStyle(.sbAccent800)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, SBSpace.x2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.syncIsAlarming)
            .background(model.syncIsAlarming ? Color.sbAccent200 : Color.sbAccent100)

            SBDivider(weight: SBRule.hairline)
        }
        .sheet(isPresented: $showingFailures) { FailedWritesView() }
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
    model.sync.simulate(offline: true, pending: 3)
    return VStack {
        StatusHeaderView().environment(model)
        Spacer()
    }
    .background(Color.sbBackground)
}
