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

    private let jazz = DoorPass(
        id: "jazz-patrik", name: "Jazz with Patrik", price: Money(euros: 25), kind: .session
    )
    private let fullPass = DoorPass(
        id: "full-pass", name: TicketType.fullPass, price: Money(euros: 205)
    )
    private let evening = DoorPass(
        id: "evening-ticket", name: TicketType.eveningTicket, price: .zero, kind: .evening
    )

    @Test("THE ONE THAT MATTERS: a class is never something the door sells")
    func sessionsAreNotDoorPasses() {
        // `firestore.rules` refuses a door sale pointing at one, because it
        // would mint a participant called "Jazz with Patrik". The catalogue is
        // shared, so this is the flag both sides read.
        #expect(jazz.isSession)
        #expect(fullPass.isSession == false)
        #expect(evening.isSession == false)
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

    @Test("The name and the price are the catalogue's at the moment of sale")
    func snapshots() {
        // Renaming a class or repricing it next week must not rewrite what was
        // taken today — the same rule a ledger line follows for a drink.
        var catalogue = jazz
        let sale = SessionSale(
            sessionId: catalogue.id, name: catalogue.name, price: catalogue.price,
            method: .cash, soldAt: .now, soldBy: "uid"
        )
        catalogue = DoorPass(
            id: "jazz-patrik", name: "Jazz with Patrik (Sunday)",
            price: Money(euros: 30), kind: .session
        )
        #expect(sale.name == "Jazz with Patrik")
        #expect(sale.price == Money(euros: 25))
        #expect(catalogue.price == Money(euros: 30))
    }
}
