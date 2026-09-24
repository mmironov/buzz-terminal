import SwiftUI

/// The bar's order screen: tap drinks, then scan once at the end.
///
/// Note the interaction the design is protecting — one scan per round, not one
/// per drink. Bar staff have wet hands and a queue; the bracelet comes out once.
struct BarMenuView: View {
    @Environment(AppModel.self) private var model

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: BarMenuLayout.spacing),
        count: BarMenuLayout.columns
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            menuGrid
            if model.cart.isEmpty {
                balanceBar
            } else {
                cartBar
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Order")
                .font(.sbHeading(24))
            Spacer()
            Text("Tap drinks, then scan once")
                .font(.sbBody(11.5))
                .foregroundStyle(.sbInk(0.55))
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, SBSpace.x2)
    }

    /// The grid measures itself so the whole menu lands on one screen where it
    /// can: rows tighten as drinks are added rather than running off the bottom.
    /// It still scrolls, for the menu long enough to need it.
    private var menuGrid: some View {
        GeometryReader { proxy in
            let rowHeight = BarMenuLayout.rowHeight(
                forDrinks: model.menu.count,
                availableHeight: proxy.size.height - SBSpace.x2
            )

            ScrollView {
                LazyVGrid(columns: columns, spacing: BarMenuLayout.spacing) {
                    ForEach(model.menu) { drink in
                        Button { model.add(drink) } label: {
                            drinkCard(drink, height: rowHeight)
                        }
                        .buttonStyle(DrinkCardStyle())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, SBSpace.x2)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func drinkCard(_ drink: Drink, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: SBSpace.x1) {
            Text(drink.name)
                .font(.sbHeading(19))
                .sbLineHeight(1.12, size: 19)
                // Two lines at most, and a hair smaller rather than a third
                // line: one long name must not set the height of every row.
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                Text(drink.price.description)
                    .font(.sbBody(16))
                    .foregroundStyle(.sbInk(0.75))
                Spacer()
                // Quantity in the accent — the one spot of colour on the grid,
                // so a half-built round is obvious at a glance. The largest
                // thing on the card after the name, because "have I tapped the
                // beer twice or three times" is the question being asked with a
                // queue waiting.
                let quantity = model.cart.quantity(of: drink)
                if quantity > 0 {
                    Text("× \(quantity)")
                        .font(.sbHeading(18))
                        .foregroundStyle(.sbAccent)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minHeight: height, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    /// "Can you check how much I've got?" — the question a guest asks before
    /// they order, so it lives where the total will be once they do.
    ///
    /// Only with an empty order, and that is the point: the same corner of the
    /// screen must never offer to read a balance and to charge a round at the
    /// same time. It also means a bartender mid-round cannot reach it, which is
    /// correct — the question comes first or not at all.
    private var balanceBar: some View {
        VStack(spacing: 0) {
            SBDivider()
            Button("Check balance") {
                model.beginScan(for: .checkBalance)
            }
            .buttonStyle(.sbBlock(.secondary, minHeight: 48, fontSize: 15))
            .padding(.horizontal, 18)
            .padding(.top, SBSpace.x3)
            .padding(.bottom, 14)
            .background(Color.sbSurface)
        }
    }

    /// The running total, a way to throw the round away, and the scan.
    ///
    /// The total used to be a button into a line-by-line editor. It is plain
    /// text now: correcting a round on a busy bar is "start again", not "find
    /// the beer and press minus", and the tap target for the editor sat under
    /// the number staff are reading rather than tapping.
    private var cartBar: some View {
        VStack(spacing: 0) {
            SBDivider()
            HStack(spacing: SBSpace.x3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.cartCountLabel)
                        .font(.sbBody(11))
                        .foregroundStyle(.sbInk(0.55))
                    Text(model.cartTotal.description)
                        .font(.sbHeading(24))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Outlined rather than solid: it undoes work, and it is beside
                // the one button on this screen that must not be mistaken for
                // anything else.
                Button("Reset") { model.clearCart() }
                    .buttonStyle(SBButtonStyle(kind: .secondary, minHeight: 48, fontSize: 14))

                Button("Scan to pay") {
                    model.beginScan(for: .payment)
                }
                .buttonStyle(SBButtonStyle(kind: .primary, minHeight: 48, fontSize: 15))
            }
            .padding(.horizontal, 18)
            .padding(.top, SBSpace.x3)
            .padding(.bottom, 14)
            .background(Color.sbSurface)
        }
    }
}

private struct DrinkCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.sbInk)
            .background(configuration.isPressed ? Color.sbAccent.opacity(0.14) : .clear)
            .overlay {
                Rectangle().stroke(Color.sbDivider, lineWidth: SBRule.hairline)
            }
    }
}

#Preview {
    let model = AppModel()
    model.role = .bar
    model.menu = SampleData.drinks
    model.add(SampleData.drinks[0])
    model.add(SampleData.drinks[0])
    model.add(SampleData.drinks[5])
    return BarMenuView()
        .environment(model)
        .background(Color.sbBackground)
}
