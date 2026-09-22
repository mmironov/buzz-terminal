import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  Special sessions — an extra class bought at the desk.
//
//  It looks like the free shirt on screen and behaves like a door sale
//  underneath: money changes hands, so it says cash or card and what it cost,
//  and the record is written once rather than edited.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Special sessions")
struct SessionSaleTests {

    private let jazz = SpecialSession(
        id: "jazz-patrik", name: "Jazz with Patrik", price: Money(euros: 25)
    )

    @Test("THE ONE THAT MATTERS: a class is not a pass, and has its own catalogue")
    func sessionsAreNotPasses() {
        // It shared `doorPasses` for one afternoon, behind a `kind`, and
        // everything that followed — filtering the door picker, a rule stopping
        // a class being sold as a ticket — was work spent keeping two different
        // things apart in one list. They are separate types now, so a class
        // cannot reach the door flow at all: it is not a `DoorPass`.
        #expect(DoorPass.Kind.allCasesForTesting == [.pass, .evening])
        #expect(DoorPass.Kind(wire: "session") == .pass)
    }

    @Test("An unpriced class says so rather than reading 0.00 €")
    func unpriced() {
        #expect(jazz.priceLabel == "25.00 €")
        #expect(SpecialSession(id: "x", name: "y", price: .zero).priceLabel == "No price set")
    }

    @Test("A sale says what it was, what it cost and how it was paid")
    func saleCarriesTheFacts() {
        let sale = SessionSale(
            sessionId: jazz.id,
            name: jazz.name,
            price: jazz.price,
            method: .card,
            soldAt: Date(timeIntervalSince1970: 1_790_000_000),
            soldBy: "uid-reception"
        )
        #expect(sale.id == "jazz-patrik")
        #expect(sale.price == Money(euros: 25))
        #expect(sale.method == .card)
        #expect(sale.soldLabel.hasPrefix("Sold "))
        #expect(sale.soldLabel.hasSuffix("· Card"))
    }

    /// The server's timestamp is not readable in the instant between writing and
    /// reading back. The label still has to say what happened.
    @Test("Before the clock lands, it still says it was sold and how")
    func labelWithoutATimestamp() {
        let sale = SessionSale(
            sessionId: jazz.id, name: jazz.name, price: jazz.price,
            method: .cash, soldAt: nil, soldBy: "uid"
        )
        #expect(sale.soldLabel == "Sold · Cash")
    }

    @Test("THE CHANGE: one class each, and the path is what enforces it")
    func oneEach() {
        // The sale lives at a fixed document id, so Firestore's
        // create-fails-if-exists does the work — the same
        // deduplication-by-construction `door-7` uses. Which class it was is a
        // field, which is why `sessionId` is on the document at all.
        let sale = SessionSale(
            sessionId: "lindy-sakarias-elice", name: "Lindy Hop with Sakarias & Elice",
            price: Money(euros: 25), method: .cash, soldAt: .now, soldBy: "uid"
        )
        #expect(sale.sessionId == "lindy-sakarias-elice")
        #expect(sale.id == sale.sessionId)
    }

    @Test("The name and the price are the catalogue's at the moment of sale")
    func snapshots() {
        // Renaming a class or repricing it next week must not rewrite what was
        // taken today — the same rule a ledger line follows for a drink.
        var catalogue = jazz
        let sale = SessionSale(
            sessionId: catalogue.id, name: catalogue.name, price: catalogue.price,
            method: .cash, soldAt: .now, soldBy: "uid"
        )
        catalogue = SpecialSession(
            id: "jazz-patrik", name: "Jazz with Patrik (Sunday)", price: Money(euros: 30)
        )
        #expect(sale.name == "Jazz with Patrik")
        #expect(sale.price == Money(euros: 25))
        #expect(catalogue.price == Money(euros: 30))
    }
}
