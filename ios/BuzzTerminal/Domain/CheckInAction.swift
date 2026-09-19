import Foundation

/// What the participant screen offers, given who is on it and whether a chip is
/// already in the operator's hand.
///
/// Pure, and deliberately so. The same screen is now reached two ways — by
/// scanning a chip, and by picking a name off the check-in list — and the
/// difference between "this guest is already paired" and "this guest still needs
/// a bracelet" decides whether the primary button takes money or takes a chip.
/// Getting that wrong means offering a top-up on an account no bracelet can pay
/// from, so the rule is written down once, here, with tests, rather than as an
/// `if` inside a `ViewBuilder`.
enum CheckInAction: Equatable {

    /// Already checked in. The bracelet is theirs and the desk can load money.
    case topUp

    /// Not checked in, and the chip that was just read is unpaired — so the
    /// pairing can happen on the next tap, with no second scan.
    case assignInHand(BraceletID)

    /// Not checked in and no chip in hand: the operator has to read one.
    case scanAndAssign

    /// The one rule.
    ///
    /// Note the order. A participant who already has a bracelet gets `topUp`
    /// **even when a different chip is in hand** — pairing is permanent, the
    /// rules forbid re-pointing a chip, and a screen that offered to move
    /// somebody's bracelet would be promising something the server will refuse.
    static func decide(for participant: Participant, braceletInHand: BraceletID?) -> CheckInAction {
        guard participant.isAwaitingCheckIn else { return .topUp }
        guard let braceletInHand else { return .scanAndAssign }
        return .assignInHand(braceletInHand)
    }

    /// The primary button's label. The in-hand case names the chip, because the
    /// operator is about to pair it permanently and that is the last moment they
    /// can notice it is the wrong one.
    var label: String {
        switch self {
        case .topUp: "Add money"
        case .assignInHand(let bracelet): "Assign bracelet \(bracelet.rawValue)"
        case .scanAndAssign: "Scan and assign bracelet"
        }
    }

    /// Whether this action pairs a chip — i.e. whether it is the irreversible one.
    var isCheckIn: Bool {
        switch self {
        case .topUp: false
        case .assignInHand, .scanAndAssign: true
        }
    }
}
