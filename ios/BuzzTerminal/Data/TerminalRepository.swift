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

    /// The role this device is already signed in as, or `nil` if nobody is.
    ///
    /// Firebase keeps the session in the keychain, so a terminal that signed in
    /// on Thursday is still signed in on Saturday and through every force-quit in
    /// between. Staff sign out when they mean to and not because the app was
    /// relaunched — at a festival, most people carrying a terminal do not know
    /// the account password, and the person who does is not at the desk.
    ///
    /// Never throws. A session that cannot be restored is the same outcome as no
    /// session — the sign-in screen — and there is nobody to read an alert at
    /// launch anyway.
    func restoreSession() async -> StaffRole?

    // MARK: Connectivity
    /// Begin reporting whether the backend is reachable.
    func startMonitoringConnectivity() async

    /// Cut the backend off from the network, or restore it — the only practical way
    /// to exercise the offline queue without finding a dead spot.
    func setNetworkEnabled(_ enabled: Bool) async

    // MARK: Catalogue
    func drinks() async throws -> [Drink]

    /// Everybody on the roster who has arrived but has no bracelet yet — i.e.
    /// `braceletId == nil`. The check-in list.
    func awaitingCheckIn() async throws -> [Participant]

    /// Which colour of wristband each pass type gets, as organisers set it.
    ///
    /// Loaded with the catalogue rather than per participant: it is a handful
    /// of documents that change about twice a festival, and a point read on
    /// every check-in would be a round trip for something already in hand.
    func braceletColours() async throws -> [BraceletColour]

    /// What reception may sell at the desk, in the order organisers arranged,
    /// withdrawn ones already dropped.
    ///
    /// The price is for saying out loud. Nothing here charges it — a pass is not
    /// credit on a bracelet, so a door sale writes no ledger entry.
    func doorPasses() async throws -> [DoorPass]

    // MARK: Bracelets
    /// The account paired to this chip, or `nil` if the chip is unassigned.
    func participant(withBracelet bracelet: BraceletID) async throws -> Participant?

    /// Mint a door-sold evening ticket and pair it to a bracelet, in one write.
    ///
    /// The implementation owns the sequence number, because it also owns the
    /// retry: the participant id encodes the number (`ev-friday-14`), so two
    /// reception desks selling simultaneously collide and the loser must try the
    /// next one. That belongs here rather than in a view.
    ///
    /// `name` is the guest's, and it is the only thing asked of them. The number
    /// the night is reconciled by is still in the id and in `ticketRef`.
    func createEveningTicket(
        evening: Evening,
        name: String,
        bracelet: BraceletID
    ) async throws -> Participant

    /// Sell a catalogue pass at the door and pair it to a bracelet, in one write.
    ///
    /// Same ownership of the sequence and the retry as `createEveningTicket`, and
    /// the buyer's email goes to `participants/{id}/contact/details` in the same
    /// batch — the bar cannot read it there, which is the whole reason it is not
    /// on the participant.
    func createDoorPass(
        _ pass: DoorPass,
        draft: DoorSaleDraft,
        bracelet: BraceletID
    ) async throws -> Participant

    /// Pair a fresh bracelet to somebody already on the roster. Returns the
    /// updated participant.
    ///
    /// Permanent: re-pointing a chip at a different guest would silently
    /// transfer their balance, so the security rules forbid it outright.
    func assignBracelet(_ bracelet: BraceletID, to participant: Participant) async throws -> Participant

    // MARK: Merch

    /// What this person preordered, or nil if they ordered nothing.
    ///
    /// A separate call rather than a field on `Participant` because it lives in
    /// a subcollection the bar cannot read — see `docs/merch.md`. A bar terminal
    /// calling this gets nil rather than an error, so the bar's screens never
    /// have to know the rule exists.
    func merchOrder(for participant: Participant) async throws -> MerchOrder?

    /// The free shirt this person is owed, or nil if they are owed none.
    ///
    /// Same subcollection as the preorder and the same read rule — reception
    /// yes, the bar no — so a bar terminal gets nil rather than an error.
    func freeShirt(for participant: Participant) async throws -> FreeShirt?

    /// Record which shirt was handed over, or undo that.
    ///
    /// `size` and `colour` are written by the terminal, unlike a preordered
    /// order where the Sheet owns them: nobody chose a free shirt in advance.
    /// Passing `nil` for `handedOver` clears the handover and leaves the choice
    /// where it was, so a mis-tap does not also erase which shirt came off the
    /// pile.
    func setFreeShirt(
        size: String?,
        colour: String?,
        handedOver: Bool,
        for participant: Participant
    ) async throws -> FreeShirt

    /// Record that the merch was handed over, or undo that.
    ///
    /// Reversible, unlike a bracelet pairing: the cost of a mis-tap is a guest
    /// being told their shirt is already gone, and fixing that should not need
    /// an organiser with a database open.
    func setMerchCollected(_ collected: Bool, for participant: Participant) async throws -> MerchOrder

    /// Take money at reception and credit the account.
    /// Must be atomic server-side — two reception desks may top up at once.
    ///
    /// `method` is recorded on the ledger entry, not merely on the receipt: the
    /// cash box and the card terminal's report are both counted after the
    /// festival, and each needs a total to be counted against.
    func topUp(bracelet: BraceletID, amount: Money, method: PaymentMethod) async throws -> Participant

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
    case doorSequenceExhausted
    case braceletBlocked
    case noMerchOrdered
    case noFreeShirt
    case insufficientFunds(balance: Money, required: Money)
    case tooManyDrinksInOneRound(limit: Int)
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
        case .doorSequenceExhausted:
            "Could not allocate a door sale number. Try again."
        case .braceletBlocked:
            "This bracelet is blocked. An organiser must lift the block."
        case .noMerchOrdered:
            "There is no merch order for this participant."
        case .noFreeShirt:
            "This participant is not on the free-shirt list."
        case .insufficientFunds(let balance, let required):
            "Balance is \(balance) but the round costs \(required)."
        case .tooManyDrinksInOneRound(let limit):
            // Quantities are unlimited; it is the number of *different* drinks
            // that is capped, so the fix is to split the round rather than to
            // reduce it.
            "A round can list at most \(limit) different drinks. Split it into two."
        case .offline:
            "No connection to the festival server."
        }
    }
}
