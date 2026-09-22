import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  The free shirt.
//
//  It differs from a preordered order in one way and the tests are all about
//  it: the Sheet says WHO is owed one, and the desk says WHICH one, when it is
//  handed over. So the size and the colour are written by the terminal here,
//  and the rules refuse a handover that does not name them.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Free shirt")
struct FreeShirtTests {

    @Test("THE ONE THAT MATTERS: nothing is handed over until both halves are chosen")
    func needsSizeAndColour() {
        // `firestore.rules` refuses a collection with a null size or colour. The
        // same rule lives here so it arrives as a disabled button rather than a
        // red banner in front of somebody already holding a shirt.
        #expect(FreeShirt(entitled: true).canBeHandedOver == false)
        #expect(FreeShirt(entitled: true, size: "M").canBeHandedOver == false)
        #expect(FreeShirt(entitled: true, colour: "Natural").canBeHandedOver == false)
        #expect(FreeShirt(entitled: true, size: "M", colour: "Natural").canBeHandedOver)
    }

    @Test("The summary says what is chosen, or what is still missing")
    func summary() {
        #expect(FreeShirt(entitled: true).choiceSummary == "Pick a size and a colour")
        #expect(FreeShirt(entitled: true, size: "M").choiceSummary == "M · pick a colour")
        #expect(FreeShirt(entitled: true, colour: "Natural").choiceSummary == "Natural · pick a size")
        #expect(FreeShirt(entitled: true, size: "M", colour: "Natural").choiceSummary == "M · Natural")
    }

    @Test("Handed over or not, and when")
    func collection() {
        let owed = FreeShirt(entitled: true, size: "L", colour: "Sky Blue")
        #expect(owed.isCollected == false)
        #expect(owed.collectedLabel == nil)

        let given = FreeShirt(
            entitled: true, size: "L", colour: "Sky Blue",
            collectedAt: Date(timeIntervalSince1970: 1_790_000_000), collectedBy: "uid"
        )
        #expect(given.isCollected)
        #expect(given.collectedLabel?.hasPrefix("Handed over ") == true)
    }

    @Test("The pickers offer what the festival printed")
    func options() {
        // Four colours, in the Sheet's own spelling, so the desk reads one
        // vocabulary across the preorder and the free shirt.
        #expect(FreeShirt.colours == ["Sky Blue", "Natural", "French Navy", "Pale Pink"])
        #expect(FreeShirt.sizes == ["XS", "S", "M", "L", "XL"])
        // Bounded by the rules at 8 and 40 characters; nothing offered is close.
        #expect(FreeShirt.sizes.allSatisfy { $0.count <= 8 })
        #expect(FreeShirt.colours.allSatisfy { $0.count <= 40 })
    }

    @Test("Somebody off the list keeps the record of what they were given")
    func withdrawnKeepsHistory() {
        // The importer retires an entitlement rather than deleting the document,
        // because the shirt is already on somebody's back. The screen stops
        // offering it; the record stays.
        let withdrawn = FreeShirt(
            entitled: false, size: "M", colour: "Pale Pink",
            collectedAt: .now, collectedBy: "uid"
        )
        #expect(withdrawn.isCollected)
        #expect(withdrawn.entitled == false)
    }
}
