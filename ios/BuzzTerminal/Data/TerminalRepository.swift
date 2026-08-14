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

    /// Everybody on the roster who has arrived but has no bracelet yet — i.e.
    /// `braceletId == nil`. The check-in list.
    func awaitingCheckIn() async throws -> [Participant]

    // MARK: Bracelets
    /// The account paired to this chip, or `nil` if the chip is unassigned.
    func participant(withBracelet bracelet: BraceletID) async throws -> Participant?

    /// Mint a door-sold evening ticket and pair it to a bracelet, in one write.
    ///
    /// The implementation owns the sequence number, because it also owns the
    /// retry: the participant id encodes the number (`ev-friday-14`), so two
    /// reception desks selling simultaneously collide and the loser must try the
    /// next one. That belongs here rather than in a view.
    func createEveningTicket(evening: Evening, bracelet: BraceletID) async throws -> Participant

    /// Pair a fresh bracelet to somebody already on the roster. Returns the
    /// updated participant.
    ///
    /// Permanent: re-pointing a chip at a different guest would silently
    /// transfer their balance, so the security rules forbid it outright.
    func assignBracelet(_ bracelet: BraceletID, to participant: Participant) async throws -> Participant

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
    case noRoleAssigned
    case accountDisabled
    case tooManyAttempts
    case braceletNotAssigned
    case braceletAlreadyPaired
    case eveningSequenceExhausted
    case braceletBlocked
    case insufficientFunds(balance: Money, required: Money)
    case offline

    var errorDescription: String? {
        switch self {
        case .unknownAccount:
            // Deliberately ambiguous, and not only out of politeness: with email
            // enumeration protection enabled on the project, Firebase returns one
            // generic code for "no such user" and "wrong password", so naming
            // either would be a guess dressed up as a fact.
            "Unknown account or wrong password."
        case .accountDisabled:
            "This account has been disabled. An organiser must re-enable it."
        case .tooManyAttempts:
            "Too many failed attempts. Wait a minute, then try again."
        case .noRoleAssigned:
            "This account has no role yet. An organiser must grant reception or bar access."
        case .braceletNotAssigned:
            "This bracelet is not paired to anybody yet."
        case .braceletAlreadyPaired:
            "This bracelet is already paired to somebody. Use a fresh one."
        case .eveningSequenceExhausted:
            "Could not allocate an evening ticket number. Try again."
        case .braceletBlocked:
            "This bracelet is blocked. An organiser must lift the block."
        case .insufficientFunds(let balance, let required):
            "Balance is \(balance) but the round costs \(required)."
        case .offline:
            "No connection to the festival server."
        }
    }
}
