import SwiftUI

/// Check-in: a fresh chip was read, now pick who it belongs to.
struct AssignBraceletView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: SBSpace.x2) {
                Text("Who is this?")
                    .font(.sbHeading(26))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { model.goHome() }
                    .buttonStyle(.sbGhost)
            }

            Text("Bracelet \(model.braceletLabel) · not assigned yet")
                .font(.sbBody(11.5))
                .foregroundStyle(.sbInk(0.55))
                .padding(.top, 2)

            SBDivider()
                .padding(.vertical, 14)

            SBSearchField(text: $model.search)

            candidateList
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, SBSpace.x4)
        .padding(.bottom, 20)
    }

    private var candidateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.candidates) { guest in
                    Button {
                        Task { await model.assign(to: guest) }
                    } label: {
                        candidateRow(guest)
                    }
                    .buttonStyle(RowStyle())
                }

                if model.candidates.isEmpty {
                    Text("No matching participant awaiting check-in.")
                        .font(.sbBody(12.5))
                        .foregroundStyle(.sbInk(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, SBSpace.x4)
                        .padding(.horizontal, 2)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func candidateRow(_ guest: Participant) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(guest.name)
                        .font(.sbHeading(16))
                    Text("\(guest.ticketType) · \(guest.country)")
                        .font(.sbBody(11))
                        .foregroundStyle(.sbInk(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SBTag(text: "Assign", style: .outline)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 2)

            SBDivider(weight: SBRule.hairline)
        }
    }
}

/// A tappable list row: no chrome, a hairline underneath, and a wash on press.
private struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.sbInk)
            .background(configuration.isPressed ? Color.sbInk(0.05) : .clear)
            .contentShape(Rectangle())
    }
}

/// The bare `.input` without a `.field` label, as used for search.
struct SBSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search participant or ticket"

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.sbBody(14))
            .foregroundStyle(.sbInk)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .tint(.sbAccent)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(Color.sbSurface)
            .overlay {
                Rectangle().stroke(Color.sbDivider, lineWidth: SBRule.hairline)
            }
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.bracelet = SampleData.braceletA
    model.awaitingCheckIn = SampleData.awaitingCheckIn
    return AssignBraceletView()
        .environment(model)
        .background(Color.sbBackground)
}
