import Foundation

/// What the bar reads off a wristband when somebody asks "how much have I got?"
///
/// A question, not a transaction. Nothing is written, nothing is reserved, and
/// no round is involved — which is why it is only offered when the order is
/// empty: a bartender halfway through building a round has a different button
/// under their thumb, and the two must not be confused.
///
/// The whole point is the answer said out loud, so the sentences are the type.
struct BalanceCheck: Equatable, Sendable {

    /// The number to say. **Nil when the chip answers for nobody** — an unknown
    /// wristband is not a balance of zero, and showing "0.00 €" would tell a
    /// guest they had spent their money when the truth is that this is not the
    /// wristband they were checked in with.
    var amount: Money?

    /// Who it belongs to, so the bar can say "is that you?" to a guest holding
    /// somebody else's wristband.
    var name: String?
    var ticket: String?

    /// The band across the top, which is the only part read from two metres
    /// away. It names the *wristband's* state, never the amount: "Nothing to
    /// spend" over a balance of 14 € is how a blocked guest ends up arguing
    /// about money that is still theirs.
    var band: String

    /// The line under the number.
    var note: String

    /// Something is wrong with the wristband rather than with the balance: the
    /// screen says so in the alert tone and the scan buzzes rather than chimes.
    var isProblem: Bool

    var headline: String {
        amount?.description ?? "Not checked in"
    }

    static func of(_ participant: Participant?) -> BalanceCheck {
        guard let participant else {
            return BalanceCheck(
                amount: nil,
                name: nil,
                ticket: nil,
                band: "Not checked in",
                note: "Nobody has this bracelet. It has not been checked in, so there is nothing on it — reception can do that.",
                isProblem: true
            )
        }

        if participant.isBlocked {
            // The money is still theirs and still there; it is the wristband
            // that cannot be spent from. Saying the amount anyway is the honest
            // answer to what was asked, and it stops the bar guessing.
            return BalanceCheck(
                amount: participant.balance,
                name: participant.name,
                ticket: participant.ticketDescription,
                band: "Blocked",
                note: "This bracelet is blocked, so nothing can be bought with it. Reception can sort it out.",
                isProblem: true
            )
        }

        return BalanceCheck(
            amount: participant.balance,
            name: participant.name,
            ticket: participant.ticketDescription,
            band: "On this bracelet",
            note: participant.balance.isPositive
                ? "Reception can add more to it."
                : "Nothing on it yet. Reception tops up bracelets.",
            isProblem: false
        )
    }
}
