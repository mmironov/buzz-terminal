import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  The itemisation a charge carries into the ledger.
//
//  `backend/firestore.rules` checks this shape exactly — four keys, no more, and
//  line totals that add up to the amount the balance moves by. A mismatch is not a
//  cosmetic bug in the admin panel's receipt: it is PERMISSION_DENIED at the bar,
//  mid-service, on a payment that has already been read out to a guest.
//
//  So the payload builder is pure and tested here, rather than being a dictionary
//  literal inside a Firestore batch that nothing can exercise without a network.
//  The corresponding server-side assertions live in
//  `backend/rules-tests/rules.test.mjs`, "a charge says what it bought".
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Ledger itemisation")
struct LedgerItemTests {

    private let beer = Drink(id: "beer", name: "Draught beer", price: Money(euros: 4))
    private let water = Drink(id: "water", name: "Water", price: Money(euros: 2))

    @Test("A line carries the drink, its unit price and how many")
    func singleLine() {
        let item = CartLine(drink: beer, quantity: 3).ledgerItem

        #expect(item[Fire.TransactionItem.drinkId] as? String == "beer")
        #expect(item[Fire.TransactionItem.name] as? String == "Draught beer")
        #expect(item[Fire.TransactionItem.quantity] as? Int == 3)
        // The UNIT price, not the line total. Writing 1200 here would still add up
        // against a total computed the same wrong way, so the rules would accept a
        // receipt claiming beer costs 12 €. Nothing downstream catches that.
        #expect(item[Fire.TransactionItem.unitPrice] as? Int == 400)
    }

    @Test("A line carries nothing else")
    func exactKeys() {
        // `hasOnly` in the rules: an extra key is a declined payment, not a
        // harmless annotation. Pinned so that adding one is a failing test here
        // rather than a discovery at the bar.
        let keys = Set(CartLine(drink: beer, quantity: 1).ledgerItem.keys)
        #expect(keys == ["drinkId", "name", "unitPrice", "quantity"])
    }

    @Test("Lines keep menu order")
    func order() {
        let items = [CartLine(drink: beer, quantity: 1), CartLine(drink: water, quantity: 1)]
            .ledgerItems
        #expect(items.map { $0[Fire.TransactionItem.drinkId] as? String } == ["beer", "water"])
    }

    @Test("The total is what the lines add up to")
    func totalAgreesWithLines() {
        // The invariant `itemisationAddsUp` enforces server-side. Both numbers in
        // the write come from this one array, which is the only reason they cannot
        // drift apart.
        let lines = [CartLine(drink: beer, quantity: 3), CartLine(drink: water, quantity: 2)]

        let summed = lines.ledgerItems.reduce(0) { running, item in
            running + (item[Fire.TransactionItem.unitPrice] as? Int ?? 0)
                * (item[Fire.TransactionItem.quantity] as? Int ?? 0)
        }
        #expect(lines.ledgerTotal == Money(euros: 16))
        #expect(summed == lines.ledgerTotal.cents)
    }

    @Test("An empty round itemises to nothing")
    func empty() {
        // The repository writes no `items` key at all in this case. A charge with
        // an empty array is refused by the rules, which is correct — a round that
        // bought nothing is not a round.
        #expect([CartLine]().ledgerItems.isEmpty)
        #expect([CartLine]().ledgerTotal == .zero)
    }

    @Test("A free drink is still a line")
    func freeDrink() {
        let tap = Drink(id: "tap", name: "Tap water", price: .zero)
        let lines = [CartLine(drink: beer, quantity: 1), CartLine(drink: tap, quantity: 2)]

        #expect(lines.ledgerItems.count == 2)
        #expect(lines.ledgerTotal == Money(euros: 4))
    }
}
