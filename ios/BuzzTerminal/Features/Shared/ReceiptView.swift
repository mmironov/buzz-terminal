import SwiftUI

/// One screen serving all three successful outcomes — check-in, top-up, payment.
///
/// Worth noticing in the design: the new balance is the largest thing on the
/// screen, in green, under its own 2pt rule. Whatever just happened, the number
/// the guest will ask about is the one they can read from a metre away.
struct ReceiptView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let receipt = model.receipt {
            content(receipt)
        } else {
            // Unreachable in practice; keeps the view total rather than crashing
            // if a transition ever lands here without a receipt.
            Color.sbBackground
        }
    }

    /// The band and the buttons hold still; the itemisation between them
    /// scrolls.
    ///
    /// A round can be eight distinct drinks — the rules' own ceiling — and the
    /// receipt grows a row per drink, so the tallest one does not fit. It used
    /// to squeeze the app's header up under the status bar instead of
    /// scrolling, which is the same bug the participant screen had.
    private func content(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SBBand(
                text: receipt.bandText,
                padding: EdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(receipt.title)
                        .font(.sbDisplay(32))
                        .tracking(-0.02 * 32)
                        .sbLineHeight(1.1, size: 32)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)

                    Text(receipt.note)
                        .font(.sbBody(13.5))
                        .foregroundStyle(.sbInk(0.65))
                        .sbLineHeight(1.6, size: 13.5)
                        .fixedSize(horizontal: false, vertical: true)

                    SBDivider()
                        .padding(.vertical, SBSpace.x4)

                    ForEach(receipt.rows) { row in
                        SBDetailRow(key: row.key, value: row.value)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, SBSpace.x2)
            }
            .scrollBounceBehavior(.basedOnSize)

            // The balance is pinned with the buttons rather than left at the end
            // of the itemisation. It is the number the guest asks for and the
            // one the operator reads back, and on the longest round it was
            // sitting half-hidden behind the button until somebody scrolled.
            VStack(alignment: .leading, spacing: 0) {
                newBalance(receipt)
                actions(receipt)
                    .padding(.top, SBSpace.x4)
            }
            .padding(.horizontal, 22)
        }
        .padding(.bottom, 20)
    }

    private func newBalance(_ receipt: Receipt) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SBDivider(weight: SBRule.strong, color: .sbOk)
            SBKicker(text: "New balance", color: .sbOkDeep)
                .padding(.top, 10)
            Text(receipt.balance.description)
                .font(.sbDisplay(58))
                .tracking(-0.03 * 58)
                .sbLineHeight(1.05, size: 58)
                .foregroundStyle(.sbOkDeep)
        }
        .padding(.top, 22)
    }

    private func actions(_ receipt: Receipt) -> some View {
        VStack(spacing: 10) {
            Button(receipt.primaryActionLabel) {
                model.receiptPrimaryAction()
            }
            .buttonStyle(.sbBlock(.primary, minHeight: 48, fontSize: 15))

            if let secondary = receipt.secondaryActionLabel {
                Button(secondary) {
                    model.goHome()
                }
                .buttonStyle(.sbBlock(.secondary, minHeight: 42, fontSize: 14))
            }
        }
    }
}

#Preview("Top-up") {
    let model = AppModel()
    model.role = .reception
    model.receipt = Receipt(
        kind: .topUp,
        title: "Balance topped up",
        note: "Cash taken at reception and added to the participant’s account.",
        rows: [
            .init(key: "Participant", value: "Marta Lindqvist"),
            .init(key: "Added", value: "20.00 €"),
            .init(key: "Previous balance", value: "23.50 €"),
        ],
        balance: Money(euros: 43, cents: 50)
    )
    return ReceiptView().environment(model).background(Color.sbBackground)
}
