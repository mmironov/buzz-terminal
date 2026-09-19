import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  The participant screen is now reached two ways — by scanning a paired
//  bracelet, and by picking a name off the check-in list — and it offers a
//  different primary action in each case. These pin that rule, because getting
//  it wrong in either direction is expensive:
//
//    • offering "Add money" to somebody with no bracelet takes cash for an
//      account nothing can spend from;
//    • offering "Assign bracelet" to somebody already paired promises a write
//      the security rules refuse, after the desk has said yes.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Check-in action")
struct CheckInActionTests {

    private let chip = BraceletID("04:B4:2F:11")
    private let otherChip = BraceletID("1D:94:9D:D4:11:10:80")

    private func guest(bracelet: BraceletID? = nil) -> Participant {
        Participant(
            id: ParticipantID("101"),
            ticketRef: "SB-101",
            name: "Nina Kowalski",
            ticketType: TicketType.fullPass,
            country: "PL",
            braceletId: bracelet
        )
    }

    @Test("No bracelet and nothing scanned: the desk has to read a chip")
    func awaitingWithNothingInHand() {
        #expect(CheckInAction.decide(for: guest(), braceletInHand: nil) == .scanAndAssign)
    }

    @Test("No bracelet but a chip was already read: pair it without scanning twice")
    func awaitingWithChipInHand() {
        #expect(
            CheckInAction.decide(for: guest(), braceletInHand: chip) == .assignInHand(chip)
        )
    }

    @Test("Already paired: the only thing left to do is add money")
    func checkedIn() {
        #expect(CheckInAction.decide(for: guest(bracelet: chip), braceletInHand: chip) == .topUp)
    }

    /// The case that would quietly lose money. A guest is checked in, reception
    /// picks up somebody else's wristband, and the screen must not offer to
    /// re-point it: pairing is permanent, the rules allow `create` and never
    /// `update`, and a button promising otherwise is a refusal waiting to happen
    /// at the desk.
    @Test("Paired guest with a different chip in hand still gets a top-up, never a re-pairing")
    func checkedInWithForeignChip() {
        #expect(
            CheckInAction.decide(for: guest(bracelet: chip), braceletInHand: otherChip) == .topUp
        )
    }

    @Test("Only the pairing actions are irreversible")
    func irreversibility() {
        #expect(CheckInAction.topUp.isCheckIn == false)
        #expect(CheckInAction.scanAndAssign.isCheckIn)
        #expect(CheckInAction.assignInHand(chip).isCheckIn)
    }

    /// The in-hand label names the chip. This is the operator's last chance to
    /// notice they are holding the wrong wristband, so the id has to be on the
    /// button rather than only in the small print.
    @Test("The in-hand label names the bracelet")
    func labels() {
        #expect(CheckInAction.topUp.label == "Add money")
        #expect(CheckInAction.scanAndAssign.label == "Scan and assign bracelet")
        #expect(CheckInAction.assignInHand(chip).label == "Assign bracelet 04:B4:2F:11")
    }
}
