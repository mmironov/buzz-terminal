import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  Selling a pass at the door.
//
//  The rules refuse a malformed sale, but a refusal arrives as a red banner in
//  front of a guest holding cash. Everything asserted here is what stops the
//  desk getting that far.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Door sale")
struct DoorSaleTests {

    private let fullPass = DoorPass(
        id: "full-pass", name: TicketType.fullPass, price: Money(euros: 205)
    )
    private let partyPass = DoorPass(
        id: "party-pass", name: TicketType.partyPass, price: Money(euros: 120)
    )
    private let evening = DoorPass(
        id: "evening-ticket", name: TicketType.eveningTicket, price: .zero, kind: .evening
    )

    private func draft(
        name: String = "Jana Novak",
        role: DanceRole? = .follower,
        level: String = "Advanced",
        email: String = ""
    ) -> DoorSaleDraft {
        DoorSaleDraft(name: name, danceRole: role, level: level, email: email)
    }

    // MARK: What the desk must fill in

    @Test("A complete Full Pass sale goes through")
    func complete() {
        #expect(draft().isComplete(for: fullPass))
    }

    @Test("Every missing field names itself, in the order the screen is filled in")
    func blockers() {
        #expect(draft(name: "  ").blocker(for: fullPass) == "Enter the guest’s name")
        #expect(draft(role: nil).blocker(for: fullPass) == "Choose leader or follower")
        #expect(draft(level: "").blocker(for: fullPass) == "Choose a level")
        #expect(draft(email: "not an address").blocker(for: fullPass) == "Check the email address")
        #expect(draft().blocker(for: fullPass) == nil)
    }

    @Test("THE ONE THAT MATTERS: only Full Pass and Full Pass Gold ask for a level")
    func levelOnlyWhereItSplits() {
        // The same two pass types the wristband colours split by, and the same
        // two `Participant.levelForDisplay` prints. Three copies of one festival
        // decision, which is why each is asserted.
        #expect(fullPass.asksForLevel)
        #expect(DoorPass(id: "g", name: TicketType.fullPassGold, price: .zero).asksForLevel)
        #expect(partyPass.asksForLevel == false)
        #expect(evening.asksForLevel == false)

        // …so a Party Pass sells without one.
        #expect(draft(level: "").isComplete(for: partyPass))
    }

    @Test("A level typed under one pass does not follow the buyer to another")
    func levelIsDroppedWhereItDoesNotApply() {
        // The screen keeps what was typed when somebody goes back and picks a
        // different pass — losing a name over a mis-tap would be worse — so the
        // dropping happens at the point of sale instead.
        let carried = draft(level: "Pro")
        #expect(carried.level(for: partyPass) == "")
        #expect(carried.level(for: fullPass) == "Pro")
    }

    @Test("Pass-type matching survives the Sheet's stray whitespace and casing")
    func matchingIsForgiving() {
        #expect(DoorPass(id: "x", name: "  full pass  ", price: .zero).asksForLevel)
        #expect(DoorPass(id: "x", name: "FULL PASS GOLD", price: .zero).asksForLevel)
    }

    @Test("THE CHANGE: an evening ticket needs a name, and asks nothing else")
    func eveningWantsOnlyAName() {
        // It used to ask for nothing at all. Now the name is the one required
        // field — no dance role, no level, and the email is not even on screen.
        #expect(DoorSaleDraft().blocker(for: evening) == "Enter the guest’s name")
        #expect(DoorSaleDraft(name: "Petar Dimitrov").isComplete(for: evening))
        // …while the same empty draft fails a Full Pass for three more reasons.
        #expect(DoorSaleDraft(name: "Petar Dimitrov").isComplete(for: fullPass) == false)
    }

    @Test("An evening ticket records the name and drops the rest")
    func eveningKeepsOnlyTheName() {
        // A buyer form filled in for a Full Pass, then switched to an evening
        // ticket: the level must not follow, exactly as it does not follow to a
        // Party Pass.
        let carried = draft(level: "Pro")
        #expect(carried.level(for: evening) == "")
    }

    // MARK: The email

    @Test("A blank email is fine — a pass is sold either way")
    func emailIsOptional() {
        #expect(draft(email: "").isComplete(for: fullPass))
        #expect(draft(email: "   ").isComplete(for: fullPass))
    }

    @Test("An address is checked shallowly, the same way the rules check it")
    func emailShape() {
        #expect(draft(email: "jana@example.com").isComplete(for: fullPass))
        #expect(draft(email: "jana+tag@sub.example.co.uk").isComplete(for: fullPass))
        #expect(draft(email: "jana").isComplete(for: fullPass) == false)
        #expect(draft(email: "jana@").isComplete(for: fullPass) == false)
        #expect(draft(email: "@example.com").isComplete(for: fullPass) == false)
        #expect(draft(email: "jana example@com").isComplete(for: fullPass) == false)
    }

    @Test("An address is stored lowercased and trimmed")
    func emailIsNormalised() {
        #expect(draft(email: "  Jana@Example.COM ").trimmedEmail == "jana@example.com")
    }

    @Test("A name is trimmed, and an over-long one is refused rather than cut")
    func nameBounds() {
        #expect(draft(name: "  Jana Novak  ").trimmedName == "Jana Novak")
        // 80 is what firestore.rules accepts; truncating here would file somebody
        // under a name they never gave.
        let tooLong = String(repeating: "a", count: 81)
        #expect(draft(name: tooLong).blocker(for: fullPass) == "That name is too long")
        #expect(draft(name: String(repeating: "a", count: 80)).isComplete(for: fullPass))
    }

    // MARK: The document that reaches Firestore

    @Test("THE OTHER ONE: the sale carries no email on the participant")
    func participantHasNoEmail() {
        // The rules refuse a participant with an address attached. This is the
        // Swift side of that: whatever was typed, the buyer document is built
        // from these fields and no others.
        let buyer = Participant.doorPass(
            fullPass,
            number: 7,
            draft: draft(email: "jana@example.com"),
            bracelet: SampleData.braceletA
        )
        #expect(buyer.name == "Jana Novak")
        #expect(buyer.ticketType == TicketType.fullPass)
        #expect(buyer.level == "Advanced")
        #expect(buyer.danceRole == "follower")
        #expect(buyer.country == "")
        #expect(buyer.balance == .zero)
        #expect(buyer.source == .door)
    }

    @Test("The id, the ticket reference and the number agree")
    func idsAgree() {
        // `firestore.rules` checks all three against each other, so a mismatch
        // here is a refused sale rather than a wrong-looking screen.
        let buyer = Participant.doorPass(
            partyPass, number: 12, draft: draft(), bracelet: SampleData.braceletA
        )
        #expect(buyer.id.rawValue == "door-12")
        #expect(buyer.ticketRef == "DOOR-12")
        #expect(buyer.doorNumber == 12)
        #expect(buyer.passId == "party-pass")
        // A Party Pass has no level, whatever the form was holding.
        #expect(buyer.level == "")
    }

    @Test("An unpriced pass says so rather than reading 0.00 €")
    func unpricedReadsAsAWarning() {
        #expect(evening.priceLabel == "No price set")
        #expect(fullPass.priceLabel == "205.00 €")
        // The screens above the scan read as a sentence, which "No price set to
        // collect" is not.
        #expect(fullPass.collectLabel == "205.00 € to collect")
        #expect(evening.collectLabel == "No price set in the admin panel")
    }
}
