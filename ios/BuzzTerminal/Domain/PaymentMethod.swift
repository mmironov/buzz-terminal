import Foundation

/// How the money for a top-up actually reached the desk.
///
/// Recorded on the ledger entry rather than only shown on screen, because the
/// question this answers is asked after the festival, not during it: the cash
/// box has to be counted against something, and the card terminal's own report
/// has to be reconciled against something. A radio button nobody stores is
/// ceremony; the field is the feature.
///
/// Only top-ups carry one. A charge at the bar moves money that is already on a
/// bracelet, so "cash or card" is a question about the top-up that put it there
/// and was answered then.
enum PaymentMethod: String, CaseIterable, Equatable, Sendable, Identifiable {
    case cash
    case card

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: "Cash"
        case .card: "Card"
        }
    }

    /// What the receipt says once the money is in.
    var receiptNote: String {
        switch self {
        case .cash: "Cash taken at reception and added to the participant’s account."
        case .card: "Paid by card at reception and added to the participant’s account."
        }
    }

    /// The value written to `method` in the ledger. The spelling is shared with
    /// `firestore.rules`, which accepts these two strings and nothing else.
    var wire: String { rawValue }
}
