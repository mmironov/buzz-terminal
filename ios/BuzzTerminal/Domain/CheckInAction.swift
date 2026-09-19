import Foundation

/// What the participant screen offers, given who is on it.
///
/// Pure, and deliberately so. The screen is reached two ways — by scanning a
/// paired chip, and by picking a name off the check-in list — and the difference
/// between "this guest is already paired" and "this guest still needs a
/// bracelet" decides whether the primary button takes money or takes a chip.
/// Getting that wrong means offering a top-up on an account no bracelet can pay
/// from, so the rule is written down once, here, with tests, rather than as an
/// `if` inside a `ViewBuilder`.
///
/// There was a third case, `assignInHand`, from when reading an unpaired chip
/// led to the check-in list: it let the pairing happen without scanning twice.
/// Reading a chip is now a dead end unless it is somebody's, so no route puts a
/// bracelet in hand before a guest is chosen, and the case was removed rather
/// than left as an unreachable state — the whole point of the flat `Screen` enum
/// is that the states in this app are the ones it can actually be in.
enum CheckInAction: Equatable {

    /// Already checked in. The bracelet is theirs and the desk can load money.
    case topUp

    /// Not checked in: the operator has to read a chip.
    case scanAndAssign

    /// The one rule.
    static func decide(for participant: Participant) -> CheckInAction {
        participant.isAwaitingCheckIn ? .scanAndAssign : .topUp
    }

    /// The primary button's label.
    var label: String {
        switch self {
        case .topUp: "Add money"
        case .scanAndAssign: "Scan and assign bracelet"
        }
    }

    /// Whether this action pairs a chip — i.e. whether it is the irreversible one.
    var isCheckIn: Bool { self == .scanAndAssign }
}
