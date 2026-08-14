import SwiftUI

/// The moment of truth at the bar: a bracelet has been read, here is what will
/// happen. Also where all three refusals surface.
struct PayReviewView: View {
    @Environment(AppModel.self) private var model

    private var decision: PaymentDecision {
        model.paymentDecision ?? .notAssigned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if decision.isApproved {
                approvedHeader
            } else {
                refusedHeader
            }

            SBDivider()
                .padding(.vertical, SBSpace.x4)

            breakdown

            actions
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        // A short fade so a refusal registers as a change of state rather than
        // appearing to have always been there. Matches the design's `sbFade`.
        .transition(.opacity)
    }

    // MARK: Headers

    private var approvedHeader: some View {
        VStack(spacing: 0) {
            SBBand(
                text: "Checked-In",
                glyphSize: 18,
                fontSize: 12.5,
                padding: EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(model.participant?.name ?? "—")
                    .font(.sbDisplay(30))
                    .tracking(-0.02 * 30)
                    .sbLineHeight(1.05, size: 30)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(model.participant?.ticketDescription ?? "—") · Bracelet \(model.braceletLabel)")
                    .font(.sbBody(12))
                    .foregroundStyle(.sbInk(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 13)
        }
        .overlay { Rectangle().stroke(Color.sbOk, lineWidth: 3) }
    }

    private var refusedHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The band bleeds to the screen edges even though the content column
            // is inset by 18 — hence the negative horizontal padding.
            SBBand(
                text: decision.bandText,
                tone: .alert,
                glyph: .alert,
                padding: EdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18)
            )
            .padding(.horizontal, -18)
            .padding(.top, -18)

            Text(decision.title)
                .font(.sbDisplay(30))
                .tracking(-0.02 * 30)
                .sbLineHeight(1.1, size: 30)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .padding(.bottom, SBSpace.x2)

            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(Color.sbAccent).frame(width: 3)
                Text(decision.note(total: model.cartTotal))
                    .font(.sbBody(13.5))
                    .foregroundStyle(.sbAccent800)
                    .sbLineHeight(1.65, size: 13.5)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Breakdown

    private var breakdown: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.cartLines) { line in
                    VStack(spacing: 0) {
                        HStack {
                            Text(line.label)
                            Spacer()
                            Text(line.total.description)
                        }
                        .font(.sbBody(13.5))
                        .padding(.vertical, SBSpace.x1 * 2)

                        SBDivider(weight: SBRule.hairline)
                    }
                }

                HStack(alignment: .center) {
                    SBKicker(text: "To charge", color: .sbInk, size: 10)
                    Spacer()
                    Text(model.cartTotal.description)
                        .font(.sbDisplay(30))
                }
                .padding(.top, SBSpace.x3)

                if case .approved(let after) = decision {
                    VStack(spacing: 0) {
                        SBDivider(weight: SBRule.strong, color: .sbOk)
                        HStack {
                            Text("Balance \((model.participant?.balance ?? .zero).description) → after")
                            Spacer()
                            Text(after.description)
                                .font(.sbHeading(13, weight: .bold))
                        }
                        .font(.sbBody(13))
                        .foregroundStyle(.sbOkDeep)
                        .padding(.vertical, 10)
                    }
                    .padding(.top, 10)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 9) {
            if decision.isApproved {
                Button("Charge \(model.cartTotal.description)") {
                    Task { await model.confirmPayment() }
                }
                .buttonStyle(.sbBlock(.primary, minHeight: 50, fontSize: 15))
                .disabled(model.isWorking)
            }

            Button("Scan another bracelet") {
                model.beginScan(for: .payment)
            }
            .buttonStyle(.sbBlock(.secondary, minHeight: 44, fontSize: 14))

            Button("Back to order") { model.goToMenu() }
                .buttonStyle(.sbGhost)
        }
        .padding(.top, SBSpace.x3)
    }
}

#Preview("Approved") {
    let model = AppModel()
    model.role = .bar
    model.menu = SampleData.drinks
    model.add(SampleData.drinks[0])
    model.bracelet = SampleData.braceletB
    model.participant = SampleData.participant(withBracelet: SampleData.braceletB)
    model.paymentDecision = .approved(balanceAfter: Money(euros: 19, cents: 50))
    return PayReviewView().environment(model).background(Color.sbBackground)
}

#Preview("Blocked") {
    let model = AppModel()
    model.role = .bar
    model.menu = SampleData.drinks
    model.add(SampleData.drinks[0])
    model.bracelet = SampleData.braceletD
    let blocked = SampleData.participant(withBracelet: SampleData.braceletD)!
    model.participant = blocked
    model.paymentDecision = .blocked(participant: blocked)
    return PayReviewView().environment(model).background(Color.sbBackground)
}
