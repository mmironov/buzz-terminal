import Foundation
import Testing

@testable import BuzzTerminal

// ═══════════════════════════════════════════════════════════════════════════
//  Replacing a lost or broken wristband.
//
//  The one place a participant's bracelet may change, and the rules only allow
//  it as a single write that invalidates the old chip and mints a new one. What
//  is asserted here is the near side of that: what the desk has to fill in, and
//  the one thing this does NOT do — move money.
// ═══════════════════════════════════════════════════════════════════════════

@Suite("Replacing a bracelet")
struct BraceletReplacementTests {

    private let fee = Money(euros: 1)

    @Test("THE ONE THAT MATTERS: nothing is replaced without a reason")
    func reasonIsRequired() {
        // `firestore.rules` refuses a replacement with no reason, so the same
        // rule lives here and arrives as a button that says what is missing
        // rather than as a red banner in front of a guest.
        #expect(BraceletReplacement().blocker == "Say why it is being replaced")
        #expect(BraceletReplacement(reason: "   ").blocker == "Say why it is being replaced")
        #expect(BraceletReplacement(reason: "Lost in the venue").isComplete)
    }

    @Test("A reason longer than the rules accept is refused here first")
    func reasonIsBounded() {
        let long = String(repeating: "a", count: BraceletReplacement.maxReason + 1)
        #expect(BraceletReplacement(reason: long).blocker == "That reason is too long")
        #expect(BraceletReplacement(reason: String(repeating: "a", count: 200)).isComplete)
    }

    @Test("A fee has to say how it was paid")
    func feeNeedsAMethod() {
        var charged = BraceletReplacement(reason: "Lost it", chargesFee: true)
        #expect(charged.blocker == "Choose cash or card")
        charged.method = .card
        #expect(charged.isComplete)
    }

    @Test("Waiving is the absence of a fee, not a zero")
    func waiving() {
        // A snapped clasp is the festival's fault. Recording 0 € paid in cash
        // would make the takings read as though somebody had paid nothing.
        let waived = BraceletReplacement(reason: "Clasp broke")
        #expect(waived.isComplete)
        #expect(waived.fee(from: fee) == nil)

        let charged = BraceletReplacement(reason: "Lost it", chargesFee: true, method: .cash)
        #expect(charged.fee(from: fee) == Money(euros: 1))
    }

    @Test("With no fee configured there is nothing to charge")
    func noFeeConfigured() {
        // An organiser who has set no fee gets a desk that replaces wristbands
        // for nothing, rather than one that invents a number.
        let charged = BraceletReplacement(reason: "Lost it", chargesFee: true, method: .cash)
        #expect(charged.fee(from: nil) == nil)
        #expect(charged.fee(from: .zero) == nil)
    }

    @Test("The reason is trimmed, the way the write sends it")
    func trimming() {
        #expect(BraceletReplacement(reason: "  Lost it  ").trimmedReason == "Lost it")
    }

    @Test("THE OTHER ONE: the screen offers a scan, not a top-up")
    func theActionIsAScan() {
        // Somebody reached this way already has a wristband, so the ordinary
        // rule would offer to add money. The flow overrides it, and the label is
        // what tells the desk which of the two irreversible things is about to
        // happen.
        #expect(CheckInAction.scanAndReplace.label == "Scan and replace")
        #expect(CheckInAction.scanAndReplace.isReplacement)
        #expect(CheckInAction.topUp.isReplacement == false)
        // And it is not a check-in: the guest is already checked in, which is
        // what the identity card at the top of the screen keeps saying.
        #expect(CheckInAction.scanAndReplace.isCheckIn == false)
    }
}
