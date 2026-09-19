import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  What the desk reads off the screen while somebody waits for their t-shirt.
//  Small logic, but it is assembled from optional parts — a tote bag has no
//  size, a guest can leave the colour blank — and a stray separator or a
//  missing word is the sort of thing that ships to fifty screens unnoticed.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Preordered merch")
struct MerchOrderTests {

    @Test("A full order reads thing, size, colour")
    func fullOrder() {
        let order = MerchOrder(item: .shirt, size: "M", colour: "Sky Blue")
        #expect(order.summary == "T-shirt · M · Sky Blue")
    }

    /// The awkward case: a tote bag has neither. A naive join leaves
    /// "Tote bag · · " on the screen.
    @Test("A tote bag has no size or colour, and no dangling separators")
    func toteOnly() {
        #expect(MerchOrder(item: .tote, size: nil, colour: nil).summary == "Tote bag")
    }

    @Test("A missing colour does not leave a gap")
    func partialOrder() {
        #expect(MerchOrder(item: .shirt, size: "L", colour: nil).summary == "T-shirt · L")
        #expect(MerchOrder(item: .shirt, size: nil, colour: "Natural").summary == "T-shirt · Natural")
    }

    @Test("Both items are named, because the desk hands over two things")
    func both() {
        let order = MerchOrder(item: .shirtAndTote, size: "S", colour: "Pale Pink")
        #expect(order.summary == "T-shirt and tote bag · S · Pale Pink")
    }

    // MARK: Collection

    @Test("Nothing is collected until it is")
    func notCollected() {
        let order = MerchOrder(item: .shirt, size: "M", colour: "Natural")
        #expect(order.isCollected == false)
        #expect(order.collectedLabel == nil)
    }

    @Test("A collected order says when, in the same format as a check-in")
    func collected() {
        // 2026-08-22 was a Saturday.
        let when = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone.current,
            year: 2026, month: 8, day: 22, hour: 17, minute: 12
        ).date!
        let order = MerchOrder(item: .tote, collectedAt: when, collectedBy: "uid-1")
        #expect(order.isCollected)
        #expect(order.collectedLabel == "Collected Sat 17:12")
    }

    // MARK: What there is to hand over

    /// A withdrawn order keeps its document — the record that something was
    /// handed over outlives the order — but there is nothing to give anybody,
    /// so the screen must treat it as if there were no order at all.
    @Test("A withdrawn order has nothing to collect")
    func withdrawn() {
        #expect(MerchOrder(item: .none).hasSomethingToCollect == false)
        #expect(MerchOrder(item: .shirt).hasSomethingToCollect)
        #expect(MerchOrder(item: .tote).hasSomethingToCollect)
        #expect(MerchOrder(item: .shirtAndTote).hasSomethingToCollect)
    }

    /// The case that decides whether a guest goes away with their shirt. A form
    /// option the importer never heard of must reach the desk as "ask them",
    /// never as "you ordered nothing".
    @Test("An unrecognised item is still something, and says so")
    func unknownItem() {
        let order = MerchOrder(item: .unknown)
        #expect(order.hasSomethingToCollect)
        #expect(order.summary == "Merch ordered — check the Sheet")
    }

    // MARK: The wire

    @Test("Wire values map to items, and anything else becomes unknown")
    func wireValues() {
        #expect(MerchOrder.Item(wire: "shirt") == .shirt)
        #expect(MerchOrder.Item(wire: "tote") == .tote)
        #expect(MerchOrder.Item(wire: "shirtAndTote") == .shirtAndTote)
        #expect(MerchOrder.Item(wire: "none") == .none)
        // A sixth option added to the form next year.
        #expect(MerchOrder.Item(wire: "cap") == .unknown)
        #expect(MerchOrder.Item(wire: nil) == .unknown)
    }

    /// These strings are a contract with `mapping.mjs` and with the security
    /// rules. Renaming a case would silently turn every stored order into
    /// "unknown" on the next launch.
    @Test("The wire strings are pinned")
    func wireStringsArePinned() {
        #expect(MerchOrder.Item.shirt.rawValue == "shirt")
        #expect(MerchOrder.Item.tote.rawValue == "tote")
        #expect(MerchOrder.Item.shirtAndTote.rawValue == "shirtAndTote")
        #expect(MerchOrder.Item.none.rawValue == "none")
        #expect(MerchOrder.Item.unknown.rawValue == "unknown")
    }
}
