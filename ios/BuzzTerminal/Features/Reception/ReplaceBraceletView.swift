import SwiftUI

/// Who has lost a wristband: the list of everybody who has one.
///
/// The mirror image of the check-in list, and it exists for one reason — the
/// thing that would normally find somebody, their chip, is the thing that is
/// missing. So this flow starts from a name, and the list is the complement of
/// the check-in one: people *with* a bracelet rather than without.
///
/// Nothing here writes anything. Picking somebody opens their screen, where the
/// reason and the fee are filled in and the fresh chip is read last — the same
/// order every other irreversible thing in this app follows.
struct ReplaceBraceletView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: SBSpace.x2) {
                Text("Replace a bracelet")
                    .font(.sbHeading(26))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { model.goHome() }
                    .buttonStyle(.sbGhost)
            }

            Text("Find the guest, then read the new bracelet")
                .font(.sbBody(11.5))
                .foregroundStyle(.sbInk(0.55))
                .padding(.top, 2)

            SBDivider()
                .padding(.vertical, 14)

            SBSearchField(text: $model.search)

            list
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, SBSpace.x4)
        .padding(.bottom, 20)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.replacementCandidates) { guest in
                    Button {
                        model.select(forReplacement: guest)
                    } label: {
                        row(guest)
                    }
                    .buttonStyle(RowStyle())
                }

                if model.replacementCandidates.isEmpty {
                    Text(
                        model.isLoadingCheckedIn
                            ? "Reading the roster…"
                            : "Nobody checked in matches that. Only people who already have a bracelet are here."
                    )
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

    private func row(_ guest: Participant) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(guest.name)
                        .font(.sbHeading(16))
                    // The chip they are about to lose, because two guests with
                    // the same name is the case where the desk needs to be sure
                    // which record it is about to change.
                    Text("\(guest.ticketType) · \(guest.braceletId?.rawValue ?? "—")")
                        .font(.sbBody(11))
                        .foregroundStyle(.sbInk(0.55))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SBTag(text: "Select", style: .outline)
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 2)

            SBDivider(weight: SBRule.hairline)
        }
    }
}

#Preview {
    let model = AppModel()
    model.role = .reception
    model.screen = .replaceSearch
    return ReplaceBraceletView()
        .environment(model)
        .background(Color.sbBackground)
}
