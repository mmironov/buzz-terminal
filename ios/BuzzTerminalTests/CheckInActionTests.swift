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
//      the security rules refuse, after the desk has said yes — and pairing is
//      permanent, so there is no undo at the desk either way.
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

    @Test("No bracelet: the desk has to read a chip")
    func awaiting() {
        #expect(CheckInAction.decide(for: guest()) == .scanAndAssign)
    }

    @Test("Already paired: the only thing left to do is add money")
    func checkedIn() {
        #expect(CheckInAction.decide(for: guest(bracelet: chip)) == .topUp)
    }

    /// An evening ticket is a participant like any other once it exists: door
    /// sales are anonymous, but the wristband is theirs and it takes money.
    @Test("A door-sold evening ticket behaves like any other paired guest")
    func eveningTicket() {
        var sold = guest(bracelet: otherChip)
        sold.source = .evening
        sold.evening = .friday
        #expect(CheckInAction.decide(for: sold) == .topUp)
    }

    @Test("Only the pairing action is irreversible")
    func irreversibility() {
        #expect(CheckInAction.topUp.isCheckIn == false)
        #expect(CheckInAction.scanAndAssign.isCheckIn)
    }

    @Test("Each action carries its own button label")
    func labels() {
        #expect(CheckInAction.topUp.label == "Add money")
        #expect(CheckInAction.scanAndAssign.label == "Scan and assign bracelet")
    }
}
