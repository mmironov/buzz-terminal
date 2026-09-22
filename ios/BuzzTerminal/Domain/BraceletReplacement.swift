import Foundation

/// Replacing a wristband somebody has lost or broken.
///
/// **The old chip is invalidated and a fresh one takes its place, in one write.**
/// The balance does not move: it lives on the person, not the wristband, so a
/// lost chip loses nobody any money and the ledger is not involved at all.
///
/// The fee is the other half of that. It is paid at the desk, in cash or on the
/// card machine, exactly like a pass sold at the door — **not** taken off the
/// balance, which would put a festival charge into the record of what somebody
/// spent at the bar. It is optional, because a snapped clasp is the festival's
/// fault and the desk waives it; a waived fee is recorded as no fee rather than
/// as zero paid, so the takings cannot be read as "somebody paid nothing".
struct BraceletReplacement: Equatable, Sendable {

    /// Why it is being replaced, in the operator's words. Required: "there is a
    /// new wristband and nobody wrote down why" is the state this prevents, and
    /// `firestore.rules` refuses a replacement without one.
    var reason: String = ""

    /// Whether the guest is being charged for it.
    var chargesFee: Bool = false

    /// How they paid, once they are being charged. Nothing is pre-selected, for
    /// the same reason as everywhere else money is taken: a default is a wrong
    /// answer nobody has to touch.
    var method: PaymentMethod?

    /// The longest reason `firestore.rules` accepts.
    static let maxReason = 200

    var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether this replacement can go through, and if not, what is missing.
    ///
    /// Returns the reason rather than a bare `false` so the button can say it —
    /// a disabled button that does not explain itself is the thing somebody
    /// stands at a desk tapping.
    var blocker: String? {
        if trimmedReason.isEmpty { return "Say why it is being replaced" }
        if trimmedReason.count > Self.maxReason { return "That reason is too long" }
        if chargesFee && method == nil { return "Choose cash or card" }
        return nil
    }

    var isComplete: Bool { blocker == nil }

    /// What to record as taken, given what the festival charges. Nil when the
    /// fee is waived, which is what the absence of a fee means everywhere else.
    func fee(from configured: Money?) -> Money? {
        guard chargesFee, let configured, configured.isPositive else { return nil }
        return configured
    }
}
