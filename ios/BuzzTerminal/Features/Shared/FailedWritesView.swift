import SwiftUI

/// Transactions the server refused after the till had already said yes.
///
/// This is a reconciliation screen, not an error log. Every row is money that
/// moved in the real world and did not move in the database, so each one says what
/// happened, to whom, and what to do about it — and can be marked as dealt with, so
/// a shift can work through the list rather than staring at it.
///
/// Ships in release. It is the one place the offline queue's failures become
/// visible, and a festival will meet them at the least convenient moment.
struct FailedWritesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    intro

                    ForEach(model.failedWrites) { write in
                        row(write)
                        SBDivider(weight: SBRule.hairline)
                    }

                    if model.failedWrites.isEmpty {
                        Text("Nothing outstanding.")
                            .font(.sbBody(13))
                            .foregroundStyle(.sbNeutral700)
                            .padding(.horizontal, 18)
                            .padding(.top, 20)
                    }
                }
                .padding(.bottom, 28)
            }
            .background(Color.sbBackground)
            .navigationTitle("Failed to sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var intro: some View {
        Text("""
            These were accepted at the till and refused by the server afterwards. \
            The guest already has the drink, or already handed over the cash.
            """)
            .font(.sbBody(12.5))
            .foregroundStyle(.sbNeutral700)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 14)
    }

    private func row(_ write: FailedWrite) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: SBSpace.x2) {
                Text(write.summary)
                    .font(.sbHeading(14))
                Spacer(minLength: 0)
                Text(write.attemptedAt.formatted(date: .omitted, time: .shortened))
                    .font(.sbBody(11))
                    .foregroundStyle(.sbNeutral600)
            }

            Text(write.advice)
                .font(.sbBody(12))
                .foregroundStyle(.sbInk(0.75))
                .fixedSize(horizontal: false, vertical: true)

            // The detail nobody needs until they need it badly: which till, which
            // transaction id to search for, and what the server actually said.
            Text("\(write.terminalId) · \(write.transactionId)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.sbNeutral600)
                .textSelection(.enabled)

            Text(write.reason)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.sbNeutral600)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button("Mark as sorted") {
                model.settleFailure(write.id)
            }
            .buttonStyle(SBButtonStyle(kind: .secondary, block: false))
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
