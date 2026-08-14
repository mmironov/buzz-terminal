package fest.swingbuzz.terminal.data

import fest.swingbuzz.terminal.domain.BraceletID
import fest.swingbuzz.terminal.domain.CartLine
import fest.swingbuzz.terminal.domain.Drink
import fest.swingbuzz.terminal.domain.Evening
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.Participant
import fest.swingbuzz.terminal.domain.StaffRole

/**
 * Everything the terminal needs from the outside world.
 *
 * This interface is the seam the Firebase implementation slots into. It is
 * written the way a *network* API behaves, not the way an in-memory map
 * behaves:
 *
 *   • every call is `suspend` and can throw, so the UI already has loading and
 *     failure paths and nothing has to be restructured when the calls become
 *     real Firestore round trips;
 *   • mutations return the new server state ([Participant]) rather than `Unit`,
 *     which is how you want a balance change to work — the client never
 *     computes the authoritative number itself;
 *   • no implementation is assumed to be main-thread-bound, so one is free to
 *     confine its state to a dispatcher or a mutex.
 *
 * [InMemoryTerminalRepository] is the fixture implementation.
 * `FirebaseTerminalRepository` is the real one, and it lives in `:app` because
 * it needs Android; the screens will not change when it takes over.
 */
interface TerminalRepository {

    // ── Auth ──
    suspend fun signIn(email: String, password: String): StaffRole
    suspend fun signOut()

    // ── Catalogue ──
    suspend fun drinks(): List<Drink>

    /**
     * Everybody on the roster who has arrived but has no bracelet yet — i.e.
     * `braceletId == null`. The check-in list.
     */
    suspend fun awaitingCheckIn(): List<Participant>

    // ── Bracelets ──

    /** The account paired to this chip, or `null` if the chip is unassigned. */
    suspend fun participantWithBracelet(bracelet: BraceletID): Participant?

    /**
     * Mint a door-sold evening ticket and pair it to a bracelet, in one write.
     *
     * The implementation owns the sequence number, because it also owns the
     * retry: the participant id encodes the number (`ev-friday-14`), so two
     * reception desks selling simultaneously collide and the loser must try the
     * next one. That belongs here rather than in a screen.
     */
    suspend fun createEveningTicket(evening: Evening, bracelet: BraceletID): Participant

    /**
     * Pair a fresh bracelet to somebody already on the roster. Returns the
     * updated participant.
     *
     * Permanent: re-pointing a chip at a different guest would silently
     * transfer their balance, so the security rules forbid it outright.
     */
    suspend fun assignBracelet(bracelet: BraceletID, to: Participant): Participant

    /**
     * Take cash at reception and credit the account.
     * Must be atomic server-side — two reception desks may top up at once.
     */
    suspend fun topUp(bracelet: BraceletID, amount: Money): Participant

    /**
     * Debit the account for a round at the bar.
     * Must be atomic server-side, and must re-check the balance: the client's
     * `PaymentDecision` is a courtesy to the operator, not the authority.
     */
    suspend fun charge(bracelet: BraceletID, lines: List<CartLine>): Participant
}

/**
 * Failures the terminal knows how to talk about.
 *
 * A sealed exception hierarchy rather than a `Result` type, so the seam reads
 * the same as the Swift `throws` one and a screen can catch what it understands
 * and surface [message] for everything else.
 */
sealed class TerminalError(override val message: String) : Exception(message) {

    /**
     * Deliberately ambiguous, and not only out of politeness: with email
     * enumeration protection enabled on the project, Firebase returns one
     * generic code for "no such user" and "wrong password", so naming either
     * would be a guess dressed up as a fact.
     */
    data object UnknownAccount : TerminalError("Unknown account or wrong password.")

    data object NoRoleAssigned : TerminalError(
        "This account has no role yet. An organiser must grant reception or bar access."
    )

    data object AccountDisabled : TerminalError(
        "This account has been disabled. An organiser must re-enable it."
    )

    data object TooManyAttempts : TerminalError(
        "Too many failed attempts. Wait a minute, then try again."
    )

    data object BraceletNotAssigned : TerminalError(
        "This bracelet is not paired to anybody yet."
    )

    data object BraceletAlreadyPaired : TerminalError(
        "This bracelet is already paired to somebody. Use a fresh one."
    )

    data object EveningSequenceExhausted : TerminalError(
        "Could not allocate an evening ticket number. Try again."
    )

    data object BraceletBlocked : TerminalError(
        "This bracelet is blocked. An organiser must lift the block."
    )

    data class InsufficientFunds(val balance: Money, val required: Money) :
        TerminalError("Balance is $balance but the round costs $required.")

    data object Offline : TerminalError("No connection to the festival server.")
}
