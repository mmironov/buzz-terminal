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
        level: String = "Intermediate",
        email: String = "",
        method: PaymentMethod? = .card
    ) -> DoorSaleDraft {
        DoorSaleDraft(name: name, danceRole: role, level: level, email: email, method: method)
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
        #expect(draft(method: nil).blocker(for: fullPass) == "Choose cash or card")
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

    @Test("THE CHANGE: the desk is offered three levels, and Other is not one")
    func levelsOffered() {
        // `Other` is the registration form's way of saying "not applicable" —
        // what a Party Pass holder answers — and there is no Other wristband to
        // hand anybody: the panel colours Full Pass INT, ADV and PRO. It stays a
        // valid value on a participant, because the Sheet still produces it.
        #expect(DoorSaleDraft.levels == ["Intermediate", "Advanced", "Pro"])
        #expect(DoorSaleDraft.levels.contains("Other") == false)
    }

    @Test("THE CHANGE: a sale starts on Intermediate, the one level still open")
    func startsOnTheOpenLevel() {
        #expect(DoorSaleDraft().level == "Intermediate")
        #expect(DoorSaleDraft.isSoldOut("Intermediate") == false)
        // A name, a role and the money away from being sellable, with nothing to
        // tap for the level — which is the point of starting it there.
        #expect(
            DoorSaleDraft(name: "Jana Novak", danceRole: .leader, method: .cash)
                .isComplete(for: fullPass)
        )
    }

    @Test("Advanced and Pro are sold out, and a sale carrying one is refused")
    func soldOutLevels() {
        #expect(DoorSaleDraft.isSoldOut("Advanced"))
        #expect(DoorSaleDraft.isSoldOut("Pro"))
        // The screen does not let them be tapped; this is the same rule where a
        // sale is decided, because recording one is a person turning up to a
        // class with no place for them.
        #expect(draft(level: "Advanced").blocker(for: fullPass) == "Advanced is sold out")
        #expect(draft(level: "Pro").blocker(for: fullPass) == "Pro is sold out")
        // Still listed, because a level that vanished would leave reception
        // explaining a gap to somebody asking for Advanced.
        #expect(DoorSaleDraft.levels.contains("Advanced"))
    }

    @Test("A full class stops nothing on a pass that has no levels")
    func soldOutDoesNotReachOtherPasses() {
        // The draft keeps whatever was typed when the operator changes pass, so
        // a Party Pass must not inherit a blocker about a class it has none of.
        #expect(draft(level: "Pro").isComplete(for: partyPass))
        #expect(DoorSaleDraft(name: "Ana", method: .cash).isComplete(for: evening))
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
        #expect(DoorSaleDraft(name: "Petar Dimitrov", method: .cash).isComplete(for: evening))
        // …while the same draft fails a Full Pass for two more reasons.
        #expect(DoorSaleDraft(name: "Petar Dimitrov", method: .cash).isComplete(for: fullPass) == false)
        // The one thing it is asked besides the name: a night at a door still
        // takes money, and it goes in the same box as a 259 € Full Pass.
        #expect(DoorSaleDraft(name: "Petar Dimitrov").blocker(for: evening) == "Choose cash or card")
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
        #expect(buyer.level == "Intermediate")
        #expect(buyer.danceRole == "follower")
        #expect(buyer.country == "")
        #expect(buyer.balance == .zero)
        #expect(buyer.source == .door)
    }

    @Test("THE CHANGE: the sale records what was taken, and it is not a balance")
    func takings() {
        let buyer = Participant.doorPass(
            fullPass, number: 7, draft: draft(method: .cash), bracelet: SampleData.braceletA
        )
        #expect(buyer.paymentMethod == .cash)
        // The price the catalogue held at the moment of sale, snapshotted: a
        // re-priced Full Pass next week must not rewrite what was taken tonight.
        #expect(buyer.pricePaid == Money(euros: 205))
        // And emphatically not on the wristband. The money went into the box;
        // `firestore.rules` refuses a door sale that starts with a balance.
        #expect(buyer.balance == .zero)
        #expect(buyer.doorSaleSummary == "205.00 € · Cash")
    }

    @Test("An evening ticket records the night's price, not the flat one")
    func eveningTakings() {
        let priced = DoorPass(
            id: "evening-ticket",
            name: TicketType.eveningTicket,
            price: Money(euros: 45),
            prices: [.saturday: Money(euros: 50)],
            kind: .evening
        )
        let saturday = Participant.eveningTicket(
            priced,
            evening: .saturday,
            number: 14,
            draft: DoorSaleDraft(name: "Petar Dimitrov", method: .card),
            bracelet: SampleData.braceletA
        )
        #expect(saturday.pricePaid == Money(euros: 50))
        #expect(saturday.paymentMethod == .card)

        // Friday has no price of its own here, so it falls back to the flat one
        // — the same fallback the screen quotes.
        let friday = Participant.eveningTicket(
            priced,
            evening: .friday,
            number: 15,
            draft: DoorSaleDraft(name: "Ana Ivanova", method: .cash),
            bracelet: SampleData.braceletA
        )
        #expect(friday.pricePaid == Money(euros: 45))
    }

    @Test("Nobody from the Sheet has takings on them")
    func rosterHasNoTakings() {
        // They paid a registration system months ago. The desk reading "no
        // method" there is the honest answer, and the screen shows nothing.
        let imported = Participant(
            id: ParticipantID("tkt-1"), ticketRef: "TKT-1", name: "Amélie Roux",
            ticketType: TicketType.fullPass, country: "France"
        )
        #expect(imported.paymentMethod == nil)
        #expect(imported.pricePaid == nil)
        #expect(imported.doorSaleSummary == nil)
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
        #expect(evening.priceLabel() == "No price set")
        #expect(fullPass.priceLabel() == "205.00 €")
        // The screens above the scan read as a sentence, which "No price set to
        // collect" is not.
        #expect(fullPass.collectLabel() == "205.00 € to collect")
        #expect(evening.collectLabel() == "No price set in the admin panel")
    }

    // MARK: A price per night

    @Test("THE CHANGE: each evening can cost a different amount")
    func nightsCanDiffer() {
        let nights = DoorPass(
            id: "evening-ticket", name: TicketType.eveningTicket, price: Money(euros: 45),
            prices: [.friday: Money(euros: 45), .saturday: Money(euros: 50), .sunday: Money(euros: 40)],
            kind: .evening
        )
        #expect(nights.price(on: .friday) == Money(euros: 45))
        #expect(nights.price(on: .saturday) == Money(euros: 50))
        #expect(nights.price(on: .sunday) == Money(euros: 40))
        #expect(nights.priceLabel(on: .saturday) == "50.00 €")
        #expect(nights.collectLabel(on: .sunday) == "40.00 € to collect")
        #expect(nights.nightsDiffer)
    }

    @Test("A night with no price of its own falls back to the flat one")
    func fallsBack() {
        // So a festival that charges the same on Friday and Saturday writes one
        // entry rather than three, and every document that predates per-night
        // prices keeps quoting what it always did.
        let sundayOnly = DoorPass(
            id: "evening-ticket", name: TicketType.eveningTicket, price: Money(euros: 45),
            prices: [.sunday: Money(euros: 40)], kind: .evening
        )
        #expect(sundayOnly.price(on: .friday) == Money(euros: 45))
        #expect(sundayOnly.price(on: .saturday) == Money(euros: 45))
        #expect(sundayOnly.price(on: .sunday) == Money(euros: 40))

        let flat = DoorPass(
            id: "evening-ticket", name: TicketType.eveningTicket,
            price: Money(euros: 45), kind: .evening
        )
        #expect(flat.price(on: .friday) == flat.price)
        #expect(flat.nightsDiffer == false)
    }

    @Test("An ordinary pass ignores the night entirely")
    func aFullPassHasOnePrice() {
        // Asked for by the shared call site rather than by anything real: the
        // buyer form passes no night, and a pass sold for a weekend should not
        // start quoting a Sunday rate if somebody ever passes one.
        #expect(fullPass.price(on: .sunday) == Money(euros: 205))
    }
}
