import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  Regression cover for the three pieces of domain logic that were built as
//  exercises during iteration 1. All green.
//
//    TopUpEntry.press(_:)           keypad input rules
//    Participant.matches(query:)    check-in search
//    PaymentDecision.evaluate(…)    the charge decision
//
//  Run with ⌘U in Xcode, or ./scripts/test.sh
// ═══════════════════════════════════════════════════════════════════════════

// MARK: - Keypad

@Suite("Top-up keypad")
struct TopUpEntryTests {

    /// Convenience: press a run of keys, given as a string.
    private func typing(_ sequence: String) -> TopUpEntry {
        var entry = TopUpEntry()
        for character in sequence {
            switch character {
            case ".": entry.press(.decimalSeparator)
            case "<": entry.press(.backspace)
            default: entry.press(.digit(character))
            }
        }
        return entry
    }

    @Test("Digits accumulate")
    func digits() {
        #expect(typing("12").text == "12")
        #expect(typing("12").amount == Money(euros: 12))
    }

    @Test("Backspace removes the last character and is safe when empty")
    func backspace() {
        #expect(typing("12<").text == "1")
        #expect(typing("<").text == "")
        #expect(typing("1<<<").text == "")
    }

    @Test("A decimal separator on empty input yields \"0.\", not \".\"")
    func leadingSeparator() {
        #expect(typing(".").text == "0.")
    }

    @Test("Only one decimal separator is accepted")
    func singleSeparator() {
        #expect(typing("12.5.").text == "12.5")
        #expect(typing("1..").text == "1.")
    }

    @Test("At most two digits after the separator")
    func twoDecimalPlaces() {
        #expect(typing("12.50").text == "12.50")
        #expect(typing("12.567").text == "12.56")
    }

    @Test("A lone leading zero is replaced, not accumulated")
    func leadingZero() {
        #expect(typing("05").text == "5")
        // …but a zero before the separator is meaningful and must survive.
        #expect(typing("0.5").text == "0.5")
        #expect(typing("0.5").amount == Money(cents: 50))
    }

    @Test("Presets and clear bypass the keypad rules")
    func presetsAndClear() {
        var entry = TopUpEntry()
        entry.apply(preset: Money(euros: 20))
        #expect(entry.amount == Money(euros: 20))
        entry.clear()
        #expect(entry.text == "")
        #expect(entry.isConfirmable == false)
    }

    @Test("The confirm button describes what it will do")
    func confirmTitle() {
        #expect(TopUpEntry().confirmButtonTitle == "Enter an amount")
        #expect(typing("20").confirmButtonTitle == "Add 20.00 €")
    }
}

// MARK: - Search

@Suite("Check-in search")
struct ParticipantSearchTests {

    private let amelie = Participant(
        id: ParticipantID("tkt-10432"), ticketRef: "TKT-10432",
        name: "Amélie Roux", ticketType: "Full pass", country: "France"
    )
    private let nina = Participant(
        id: ParticipantID("tkt-10434"), ticketRef: "TKT-10434",
        name: "Nina Kowalski", ticketType: "Party pass", country: "Poland"
    )

    @Test("An empty or blank query matches everybody")
    func blankQuery() {
        #expect(amelie.matches(query: ""))
        #expect(amelie.matches(query: "   "))
        #expect(nina.matches(query: "\n "))
    }

    @Test("Matches on name")
    func byName() {
        #expect(amelie.matches(query: "Roux"))
        #expect(nina.matches(query: "Nina"))
        #expect(amelie.matches(query: "Nina") == false)
    }

    @Test("Matches on the ticket type")
    func byPass() {
        #expect(nina.matches(query: "party"))
        #expect(amelie.matches(query: "party") == false)
    }

    @Test("Matches a substring anywhere, not just a prefix")
    func substring() {
        #expect(amelie.matches(query: "oux"))
        #expect(nina.matches(query: "owalski"))
    }

    @Test("Ignores case, including on accented names")
    func caseInsensitive() {
        #expect(amelie.matches(query: "amélie"))
        #expect(amelie.matches(query: "AMÉLIE"))
        #expect(nina.matches(query: "KOWALSKI"))
    }

    @Test("Does not match the city — the field says participant or ticket")
    func cityIsNotSearched() {
        #expect(amelie.matches(query: "Lyon") == false)
    }
}

// MARK: - Charge decision

@Suite("Charge decision")
struct PaymentDecisionTests {

    private func participant(
        balance: Money,
        blocked: Bool = false
    ) -> Participant {
        Participant(
            id: ParticipantID("tkt-10001"),
            ticketRef: "TKT-10001",
            name: "Marta Lindqvist",
            ticketType: "Full pass",
            country: "Sweden",
            braceletId: SampleData.braceletB,
            checkedInAt: .now,
            balance: balance,
            isBlocked: blocked
        )
    }

    @Test("An unassigned chip is not chargeable")
    func unassigned() {
        let decision = PaymentDecision.evaluate(participant: nil, total: Money(euros: 4))
        #expect(decision == .notAssigned)
        #expect(decision.isApproved == false)
    }

    @Test("A blocked bracelet is refused even when the balance would cover it")
    func blockedBeatsFunds() {
        let marta = participant(balance: Money(euros: 100), blocked: true)
        let decision = PaymentDecision.evaluate(participant: marta, total: Money(euros: 4))
        #expect(decision == .blocked(participant: marta))
    }

    @Test("Too little money is refused, and reports how much is missing")
    func insufficient() {
        let jonas = participant(balance: Money(euros: 2))
        let decision = PaymentDecision.evaluate(participant: jonas, total: Money(euros: 9))
        #expect(decision == .insufficientFunds(participant: jonas, short: Money(euros: 7)))
    }

    @Test("Enough money is approved, and reports the balance afterwards")
    func approved() {
        let marta = participant(balance: Money(euros: 23, cents: 50))
        let decision = PaymentDecision.evaluate(participant: marta, total: Money(euros: 4))
        #expect(decision == .approved(balanceAfter: Money(euros: 19, cents: 50)))
    }

    @Test("Spending the exact balance is allowed and leaves zero")
    func exactBalance() {
        let jonas = participant(balance: Money(euros: 2, cents: 50))
        let decision = PaymentDecision.evaluate(participant: jonas, total: Money(euros: 2, cents: 50))
        #expect(decision == .approved(balanceAfter: .zero))
    }

    @Test("Refusals name the guest and never imply money moved")
    func refusalCopy() {
        let elena = participant(balance: Money(euros: 14), blocked: true)
        let note = PaymentDecision
            .blocked(participant: elena)
            .note(total: Money(euros: 4))
        #expect(note.contains("Marta Lindqvist"))
        #expect(note.contains("nothing was charged"))
    }
}

// MARK: - Participant lifecycle

/// `braceletId == nil` replaced the old `WaitingGuest` type entirely, so the
/// "is this person still waiting?" question now has exactly one answer.
@Suite("Participant lifecycle")
struct ParticipantLifecycleTests {

    private func roux(bracelet: BraceletID? = nil, checkedInAt: Date? = nil) -> Participant {
        Participant(
            id: ParticipantID("tkt-10432"), ticketRef: "TKT-10432",
            name: "Amélie Roux", ticketType: "Full pass", country: "France",
            braceletId: bracelet, checkedInAt: checkedInAt
        )
    }

    @Test("No bracelet means awaiting check-in")
    func awaiting() {
        #expect(roux().isAwaitingCheckIn)
        #expect(roux().balance == .zero)
        #expect(roux().checkedInLabel == "Not checked in")
    }

    @Test("A paired bracelet means checked in")
    func pairedIsCheckedIn() {
        let paired = roux(bracelet: SampleData.braceletA, checkedInAt: .now)
        #expect(paired.isAwaitingCheckIn == false)
    }

    @Test("A just-paired bracelet reads as \"just now\", an older one as a time")
    func checkInLabel() {
        let now = roux(bracelet: SampleData.braceletA, checkedInAt: .now)
        #expect(now.checkedInLabel == "Checked in just now")

        let earlier = roux(
            bracelet: SampleData.braceletA,
            checkedInAt: Date(timeIntervalSinceNow: -3 * 3600)
        )
        #expect(earlier.checkedInLabel.hasPrefix("Checked in "))
        #expect(earlier.checkedInLabel != "Checked in just now")
    }

    @Test("The sample roster is imported plus door sales, with no overlap")
    func rosterSplit() {
        let awaiting = SampleData.roster.filter(\.isAwaitingCheckIn)
        #expect(awaiting.count == SampleData.awaitingCheckIn.count)
        #expect(
            SampleData.roster.count
                == SampleData.checkedIn.count + awaiting.count + SampleData.eveningTickets.count
        )
        // Participant ids are unique — a duplicate would mean two people sharing
        // a balance, which is the importer's whole reason for refusing to guess.
        #expect(Set(SampleData.roster.map(\.id)).count == SampleData.roster.count)
    }
}

// MARK: - Evening tickets

/// Door-sold tickets. Anonymous by design: no name, no country, and organisers
/// freeze them by hand after their evening rather than the app expiring them.
@Suite("Evening tickets")
struct EveningTicketTests {

    @Test("The id encodes the sequence, which is what makes it collision-proof")
    func identity() {
        let ticket = Participant.eveningTicket(
            evening: .friday, number: 14, bracelet: SampleData.braceletE
        )
        // Two reception desks selling at once both try `ev-friday-14`; Firestore's
        // `create` lets exactly one win, and the loser retries with 15. No counter
        // document and no coordination.
        #expect(ticket.id == ParticipantID("ev-friday-14"))
        #expect(ticket.ticketRef == "EV-FRIDAY-14")
    }

    @Test("It carries no personal data")
    func anonymous() {
        let ticket = Participant.eveningTicket(
            evening: .saturday, number: 3, bracelet: SampleData.braceletE
        )
        #expect(ticket.name == "Evening #3")   // a label, not a person
        #expect(ticket.country.isEmpty)
        #expect(ticket.source == .evening)
        #expect(ticket.isEveningTicket)
    }

    @Test("It is created already paired and with nothing on it")
    func pairedAndEmpty() {
        let ticket = Participant.eveningTicket(
            evening: .sunday, number: 1, bracelet: SampleData.braceletE
        )
        // The ticket price is cash to the festival, not credit on the bracelet.
        #expect(ticket.balance == .zero)
        #expect(ticket.isAwaitingCheckIn == false)
        #expect(ticket.braceletId == SampleData.braceletE)
        #expect(ticket.isBlocked == false)
    }

    @Test("The screen says which evening it was sold for")
    func description() {
        let evening = Participant.eveningTicket(
            evening: .friday, number: 14, bracelet: SampleData.braceletE
        )
        #expect(evening.ticketDescription == "Evening ticket · Friday")
        #expect(evening.ticketType == TicketType.eveningTicket)

        let imported = SampleData.awaitingCheckIn[0]
        #expect(imported.ticketDescription == imported.ticketType)
        #expect(imported.isEveningTicket == false)
    }

    @Test("Search finds an evening ticket by number or by evening")
    func searchable() {
        let ticket = Participant.eveningTicket(
            evening: .friday, number: 14, bracelet: SampleData.braceletE
        )
        #expect(ticket.matches(query: "evening"))
        #expect(ticket.matches(query: "#14"))
        #expect(ticket.matches(query: "Evening Ticket"))
        #expect(ticket.matches(query: "Marta") == false)
    }

    @Test("All six pass types are distinct and evening is one of them")
    func passTypes() {
        #expect(TicketType.all.count == 6)
        #expect(Set(TicketType.all).count == 6)
        #expect(TicketType.all.contains(TicketType.eveningTicket))
    }
}

@Suite("Staff roles from claims")
struct StaffRoleTests {

    @Test("Reception and bar map to themselves")
    func plainRoles() {
        #expect(StaffRole(claim: "reception") == .reception)
        #expect(StaffRole(claim: "bar") == .bar)
    }

    @Test("An admin gets reception, because that is what the rules grant them")
    func adminIsReception() {
        // firestore.rules puts `admin` in isReception() but never in isBar(): an
        // organiser can pair, sell evening tickets and credit, and cannot charge.
        // If this ever returns .bar, an organiser could take money off a bracelet.
        #expect(StaffRole(claim: "admin") == .reception)
        #expect(StaffRole(claim: "admin")?.homeScreen == .receptionHome)
    }

    @Test("An unknown or empty claim is refused rather than defaulted")
    func unknownClaim() {
        // Sign-in fails on nil. Defaulting to a role would be defaulting to a set
        // of money permissions.
        #expect(StaffRole(claim: "") == nil)
        #expect(StaffRole(claim: "Admin") == nil)      // claims are lower-case
        #expect(StaffRole(claim: "organiser") == nil)
        #expect(StaffRole(claim: "superuser") == nil)
    }
}

@Suite("Bracelet ids from NFC chips")
struct BraceletIDNFCTests {

    @Test("A four-byte MIFARE uid formats like the design")
    func fourBytes() {
        // The shape every screen, fixture and Firestore document id already uses.
        #expect(BraceletID(nfcIdentifier: Data([0x04, 0xB4, 0x2F, 0x11]))?.rawValue == "04:B4:2F:11")
    }

    @Test("A seven-byte NTAG uid is accepted, not truncated")
    func sevenBytes() {
        // NTAG213/215/216 — the usual wristband chip — has a 7-byte uid. Truncating
        // to four would collide two guests whose chips share a prefix, and the
        // manufacturer byte 0x04 means they all do.
        let data = Data([0x04, 0xA2, 0xB3, 0xC4, 0xD5, 0xE6, 0xF7])
        #expect(BraceletID(nfcIdentifier: data)?.rawValue == "04:A2:B3:C4:D5:E6:F7")
    }

    @Test("Hex is upper-case and always two digits")
    func formatting() {
        // 0x0A must be "0A", not "A": a one-digit byte shifts every colon and two
        // different chips could render to the same string.
        #expect(BraceletID(nfcIdentifier: Data([0x00, 0x0A, 0xFF, 0x7B]))?.rawValue == "00:0A:FF:7B")
    }

    @Test("A chip reporting no uid is refused")
    func empty() {
        // Otherwise this becomes a Firestore document id of "", which is a write
        // that fails deep in the repository rather than a scan that says no.
        #expect(BraceletID(nfcIdentifier: Data()) == nil)
    }

    @Test("A round trip through the fixture chips is stable")
    func roundTrip() {
        // Whatever the formatter does, it must agree with the ids already stored in
        // Firestore — a re-scan of a paired bracelet has to resolve to the same
        // document, or the guest reads as unknown at the bar.
        let bytes = Data([0x99, 0xC8, 0x65, 0x13])
        #expect(BraceletID(nfcIdentifier: bytes) == BraceletID("99:C8:65:13"))
    }
}

@Suite("Bracelet batch audit")
struct BraceletAuditTests {

    private let a = BraceletID("1D:94:9D:D4:11:10:80")
    private let b = BraceletID("1D:94:9D:D4:11:10:81")
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("Distinct chips are counted in the order they were seen")
    func distinct() {
        var audit = BraceletAudit()
        #expect(audit.record(a, at: t0) == .new(position: 1))
        #expect(audit.record(b, at: t0.addingTimeInterval(5)) == .new(position: 2))
        #expect(audit.seen == [a, b])
        #expect(audit.repeats.isEmpty)
        #expect(audit.summary == "2 bracelets, all unique.")
    }

    @Test("A chip still sitting in the field is ignored, not reported")
    func stillHolding() {
        // Core NFC re-detects a tag that has not moved. Calling that a duplicate
        // would make the tool cry wolf on its very first bracelet, and an operator
        // who learns to ignore it has lost the only warning that matters.
        var audit = BraceletAudit()
        audit.record(a, at: t0)
        #expect(audit.record(a, at: t0.addingTimeInterval(0.4)) == .stillHolding)
        #expect(audit.record(a, at: t0.addingTimeInterval(2.9)) == .stillHolding)
        #expect(audit.repeats.isEmpty)
        #expect(audit.seen.count == 1)
        // Reads still count, so the discrepancy is visible if anybody looks.
        #expect(audit.reads == 3)
    }

    @Test("The same chip after the window is a repeat worth checking")
    func repeatAfterWindow() {
        var audit = BraceletAudit()
        audit.record(a, at: t0)
        let outcome = audit.record(a, at: t0.addingTimeInterval(4))
        #expect(outcome == .repeated(.init(id: a, firstSeenAt: 1, secondSeenAt: 2)))
        #expect(audit.repeats.count == 1)
        // Not added twice: the point of the list is one row per physical bracelet.
        #expect(audit.seen == [a])
        #expect(audit.summary == "1 bracelet, 1 repeat to check.")
    }

    @Test("A chip interleaved with another still counts as a repeat")
    func interleaved() {
        // The window only forgives the *immediately* preceding chip. Scanning a,
        // then b, then a again means bracelet a came back — which is the shape a
        // genuine duplicate takes when working through a pile.
        var audit = BraceletAudit()
        audit.record(a, at: t0)
        audit.record(b, at: t0.addingTimeInterval(0.2))
        let outcome = audit.record(a, at: t0.addingTimeInterval(0.4))
        #expect(outcome == .repeated(.init(id: a, firstSeenAt: 1, secondSeenAt: 3)))
    }

    @Test("Repeats are newest-first, so the last one found is on top")
    func repeatOrder() {
        var audit = BraceletAudit()
        audit.record(a, at: t0)
        audit.record(b, at: t0.addingTimeInterval(4))
        audit.record(a, at: t0.addingTimeInterval(8))
        audit.record(b, at: t0.addingTimeInterval(12))
        #expect(audit.repeats.map(\.id) == [b, a])
    }

    @Test("An empty audit says so rather than claiming success")
    func empty() {
        // "0 bracelets, all unique" would read as a clean bill of health for a box
        // nobody has scanned.
        #expect(BraceletAudit().summary == "Nothing scanned yet.")
    }

    @Test("The transcript is pasteable, and names the repeats")
    func transcript() {
        var audit = BraceletAudit()
        audit.record(a, at: t0)
        audit.record(b, at: t0.addingTimeInterval(4))
        audit.record(a, at: t0.addingTimeInterval(8))
        let text = audit.transcript
        #expect(text.contains("2 unique, 3 reads"))
        #expect(text.contains("1. \(a.rawValue)"))
        #expect(text.contains("also seen as #1"))
    }

    @Test("Reset clears everything")
    func reset() {
        var audit = BraceletAudit()
        audit.record(a, at: t0)
        audit.record(a, at: t0.addingTimeInterval(4))
        audit.reset()
        #expect(audit == BraceletAudit())
        #expect(audit.reads == 0)
    }
}
