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
        name: "Amélie Roux", ticketType: "Full pass", city: "Lyon"
    )
    private let nina = Participant(
        id: ParticipantID("tkt-10434"), ticketRef: "TKT-10434",
        name: "Nina Kowalski", ticketType: "Party pass", city: "Kraków"
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
            city: "Stockholm",
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
            name: "Amélie Roux", ticketType: "Full pass", city: "Lyon",
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

    @Test("The sample roster splits into checked-in and awaiting, with no overlap")
    func rosterSplit() {
        let awaiting = SampleData.roster.filter(\.isAwaitingCheckIn)
        #expect(awaiting.count == SampleData.awaitingCheckIn.count)
        #expect(SampleData.roster.count == SampleData.checkedIn.count + awaiting.count)
        // Participant ids are unique — a duplicate would mean two people sharing
        // a balance, which is the importer's whole reason for refusing to guess.
        #expect(Set(SampleData.roster.map(\.id)).count == SampleData.roster.count)
    }
}
