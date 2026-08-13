import SwiftUI

/// Editing the round before the bracelet comes out.
struct CartView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("This round")
                    .font(.sbHeading(24))
                Spacer()
                Button("Add more") { model.goToMenu() }
                    .buttonStyle(.sbGhost)
            }

            SBDivider()
                .padding(.vertical, SBSpace.x3)

            lines

            totalRow

            Button("Scan bracelet to charge") {
                model.beginScan(for: .payment)
            }
            .buttonStyle(.sbBlock(.primary, minHeight: 50, fontSize: 15))

            Button("Clear order") { model.clearCart() }
                .buttonStyle(.sbGhost)
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, SBSpace.x4)
    }

    private var lines: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.cartLines) { line in
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(line.drink.name)
                                    .font(.sbHeading(16))
                                Text(line.unitLabel)
                                    .font(.sbBody(11.5))
                                    .foregroundStyle(.sbInk(0.55))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button("−") { model.bump(line.drink, by: -1) }
                                .buttonStyle(.sbIcon())

                            Text("\(line.quantity)")
                                .font(.sbBody(15))
                                .frame(minWidth: 20)
                                .multilineTextAlignment(.center)

                            Button("+") { model.bump(line.drink, by: 1) }
                                .buttonStyle(.sbIcon())

                            Text(line.total.description)
                                .font(.sbBody(14))
                                .frame(minWidth: 56, alignment: .trailing)
                        }
                        .padding(.vertical, 11)

                        SBDivider(weight: SBRule.hairline)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var totalRow: some View {
        VStack(spacing: 0) {
            // Full-strength ink, not the 40% divider: this is the strongest rule
            // in the app because it is the number staff are accountable for.
            SBDivider(weight: SBRule.strong, color: .sbInk)

            HStack(alignment: .firstTextBaseline) {
                SBKicker(text: "Total", color: .sbInk, size: 10)
                Spacer()
                Text(model.cartTotal.description)
                    .font(.sbDisplay(36))
            }
            .padding(.top, 14)
            .padding(.bottom, 4)
        }
    }
}

#Preview {
    let model = AppModel()
    model.role = .bar
    model.menu = SampleData.drinks
    model.add(SampleData.drinks[0])
    model.add(SampleData.drinks[0])
    model.add(SampleData.drinks[6])
    return CartView()
        .environment(model)
        .background(Color.sbBackground)
}
