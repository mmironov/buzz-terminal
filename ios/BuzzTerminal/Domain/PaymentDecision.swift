import Foundation

/// Whether the bar may charge this round to the bracelet that was just scanned.
///
/// This is the app's one piece of real business logic, so it lives in its own
/// type rather than inside a view. Every refusal carries the copy the design
/// shows, because "why was I declined" is the question staff get asked at the
/// bar and the wording matters.
enum PaymentDecision: Equatable, Sendable {
    /// Charge is allowed. `balanceAfter` is what the guest is left with.
    case approved(balanceAfter: Money)
    /// The chip is not paired to anybody yet.
    case notAssigned
    /// An organiser froze the bracelet in the admin panel.
    case blocked(participant: Participant)
    /// Not enough money on the account.
    case insufficientFunds(participant: Participant, short: Money)

    var isApproved: Bool {
        if case .approved = self { return true }
        return false
    }

    /// Uppercase band across the top of the pay-review screen.
    var bandText: String {
        switch self {
        case .approved: "Checked-In"
        case .notAssigned: "Not recognised"
        case .blocked: "Blocked"
        case .insufficientFunds: "Declined"
        }
    }

    var title: String {
        switch self {
        case .approved: "Ready to charge"
        case .notAssigned: "Bracelet not assigned"
        case .blocked: "Bracelet blocked"
        case .insufficientFunds: "Not enough balance"
        }
    }

    /// The explanatory paragraph. Note every refusal ends by making clear that
    /// nothing was charged — the design is emphatic about this.
    func note(total: Money) -> String {
        switch self {
        case .approved:
            return ""
        case .notAssigned:
            return "This chip is not mapped to anyone yet. Send the guest to reception to check in and load money — nothing was charged."
        case .blocked(let p):
            return "\(p.name)’s bracelet was blocked in the admin panel. No drinks can be served on it. Refer the guest to an organiser — nothing was charged."
        case .insufficientFunds(let p, let short):
            return "\(p.name) has \(p.balance), the round costs \(total). Short by \(short). Reception can top up."
        }
    }
}

extension PaymentDecision {
    /// Decide whether `participant` can be charged `total`.
    ///
    /// - Parameters:
    ///   - participant: the account behind the scanned bracelet, or `nil` when
    ///     the chip is not paired to anybody.
    ///   - total: the cost of the round.
    ///
    /// Checked in order, and the order is the point: a blocked bracelet is
    /// refused as *blocked* even when the balance would have covered the round,
    /// because "an organiser has frozen this" is what the operator needs to say
    /// to the guest — not "you are short".
    ///
    /// A balance exactly equal to `total` is approved and leaves `0.00 €`;
    /// spending your last euro on a beer is allowed.
    ///
    /// The client runs this so the operator gets an instant answer. It is not
    /// the authority — `TerminalRepository.charge` re-checks server-side, since
    /// another terminal may have spent the money in between.
    static func evaluate(participant: Participant?, total: Money) -> PaymentDecision {
        
        if let participant = participant {
            guard !participant.isBlocked else { return .blocked(participant: participant) }
            
            guard participant.balance >= total else {
                return .insufficientFunds(participant: participant, short: total - participant.balance)
            }
            
            return approved(balanceAfter: participant.balance - total)
        }
        
        return .notAssigned
    }
}
