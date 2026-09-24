import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  "Can you check my bracelet and tell me how much I've got?"
//
//  A question the bar answers out loud, so what is asserted here is the
//  sentences — and the one number that must never be said.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Checking a balance at the bar")
struct BalanceCheckTests {

    private func guest(
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

    @Test("A guest with money hears the amount and their own name")
    func hasMoney() {
        let check = BalanceCheck.of(guest(balance: Money(euros: 23, cents: 50)))
        #expect(check.amount == Money(euros: 23, cents: 50))
        #expect(check.headline == "23.50 €")
        // The name is on the screen because the wristband in the bartender's
        // hand is not always the one the guest thinks it is.
        #expect(check.name == "Marta Lindqvist")
        #expect(check.isProblem == false)
    }

    @Test("THE ONE THAT MATTERS: an unknown bracelet is not a balance of zero")
    func unknownChipIsNotZero() {
        // "0.00 €" would tell a guest they had spent their money. The truth is
        // that this wristband is not the one they were checked in with — or
        // nobody has been checked in with it at all.
        let check = BalanceCheck.of(nil)
        #expect(check.amount == nil)
        #expect(check.headline != Money.zero.description)
        #expect(check.headline == "Not checked in")
        #expect(check.name == nil)
        #expect(check.isProblem)
    }

    @Test("An empty bracelet says so, and says where money comes from")
    func emptyButCheckedIn() {
        // Zero IS the answer here, and it is a different sentence from the one
        // above: the guest exists, has a wristband, and has never topped up.
        let check = BalanceCheck.of(guest(balance: .zero))
        #expect(check.amount == .zero)
        #expect(check.headline == "0.00 €")
        #expect(check.note.contains("Reception"))
        // Not a fault: an evening-ticket guest who has bought nothing yet is the
        // most ordinary thing at the bar, and should not buzz like an error.
        #expect(check.isProblem == false)
    }

    @Test("A blocked bracelet still gets an honest number")
    func blocked() {
        // The money is theirs and it is still there; it is the wristband that
        // cannot be spent from. Hiding the amount would leave the bar guessing
        // and the guest arguing.
        let check = BalanceCheck.of(guest(balance: Money(euros: 12), blocked: true))
        #expect(check.amount == Money(euros: 12))
        #expect(check.note.contains("blocked"))
        #expect(check.isProblem)
    }

    @Test("THE ONE THAT READ WRONG: the band names the bracelet, not the money")
    func bandsSayWhichProblemItIs() {
        // It said "Nothing to spend" for both refusals, which over a balance of
        // 14 € is an argument with a guest about money that is still theirs.
        // Caught on the simulator, not in review.
        #expect(BalanceCheck.of(guest(balance: Money(euros: 14), blocked: true)).band == "Blocked")
        #expect(BalanceCheck.of(nil).band == "Not checked in")
        #expect(BalanceCheck.of(guest(balance: .zero)).band == "On this bracelet")
    }

    @Test("Nothing about this reads as a sale")
    func itIsAQuestionNotATransaction() {
        // The screen it feeds has no charge button, and the check is built from
        // the participant alone — no cart, no total, nothing to write. If this
        // ever needs a `Cart` parameter, something has gone wrong.
        let before = guest(balance: Money(euros: 9))
        let check = BalanceCheck.of(before)
        #expect(check.amount == before.balance)
        #expect(BalanceCheck.of(before) == check)
    }
}
