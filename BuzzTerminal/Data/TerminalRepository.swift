import Foundation

/// Everything the terminal needs from the outside world.
///
/// This protocol is the seam that iteration 2 slots Firebase into. It is written
/// the way a *network* API behaves, not the way an in-memory dictionary behaves:
///
///   • every call is `async` and can `throw`, so the UI already has loading and
///     failure paths and nothing has to be restructured when the calls become
///     real Firestore round trips;
///   • mutations return the new server state (`Participant`) rather than `Void`,
///     which is how you want a balance change to work — the client never
///     computes the authoritative number itself;
///   • `Sendable`, so an implementation is free to be an `actor` off the main
///     thread.
///
/// `InMemoryTerminalRepository` is the iteration-1 implementation.
/// `FirebaseTerminalRepository` will be the iteration-2 one, and the views will
/// not change at all.
protocol TerminalRepository: Sendable {

    // MARK: Auth
    func signIn(email: String, password: String) async throws -> StaffRole
    func signOut() async

    // MARK: Catalogue
    func drinks() async throws -> [Drink]
    func waitingGuests() async throws -> [WaitingGuest]

    // MARK: Bracelets
    /// The account paired to this chip, or `nil` if the chip is unassigned.
    func participant(withBracelet bracelet: BraceletID) async throws -> Participant?

    /// Pair a fresh bracelet to a guest who has arrived. Returns the newly
    /// created account, which starts at a zero balance.
    func assignBracelet(_ bracelet: BraceletID, to guest: WaitingGuest) async throws -> Participant

    /// Take cash at reception and credit the account.
    /// Must be atomic server-side — two reception desks may top up at once.
    func topUp(bracelet: BraceletID, amount: Money) async throws -> Participant

    /// Debit the account for a round at the bar.
    /// Must be atomic server-side, and must re-check the balance: the client's
    /// `PaymentDecision` is a courtesy to the operator, not the authority.
    func charge(bracelet: BraceletID, lines: [CartLine]) async throws -> Participant
}

/// Failures the terminal knows how to talk about.
enum TerminalError: Error, Equatable, LocalizedError {
    case unknownAccount
    case braceletNotAssigned
    case braceletBlocked
    case insufficientFunds(balance: Money, required: Money)
    case offline

    var errorDescription: String? {
        switch self {
        case .unknownAccount:
            "Unknown account. Use one of the staff logins below."
        case .braceletNotAssigned:
            "This bracelet is not paired to anybody yet."
        case .braceletBlocked:
            "This bracelet is blocked. An organiser must lift the block."
        case .insufficientFunds(let balance, let required):
            "Balance is \(balance) but the round costs \(required)."
        case .offline:
            "No connection to the festival server."
        }
    }
}
