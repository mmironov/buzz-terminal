package fest.swingbuzz.terminal.data

import fest.swingbuzz.terminal.domain.BraceletID
import fest.swingbuzz.terminal.domain.CartLine
import fest.swingbuzz.terminal.domain.Drink
import fest.swingbuzz.terminal.domain.Evening
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.Participant
import fest.swingbuzz.terminal.domain.ParticipantID
import fest.swingbuzz.terminal.domain.SampleData
import fest.swingbuzz.terminal.domain.StaffRole
import java.time.Instant
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * The fixture backend: the prototype's data, held in memory.
 *
 * The Swift original is an `actor`. Kotlin has no actors, so the same two
 * guarantees are bought with a [Mutex]: mutable state is never touched
 * concurrently, and every entry point is `suspend`, so call sites already look
 * exactly like the Firebase ones will.
 *
 * The artificial [latencyMillis] makes the UI's loading states real enough to
 * notice during development. Set it to zero in tests.
 */
class InMemoryTerminalRepository(
    roster: List<Participant> = SampleData.roster,
    private val menu: List<Drink> = SampleData.drinks,
    private val latencyMillis: Long = 180L,
) : TerminalRepository {

    private val lock = Mutex()

    /** The whole roster, keyed the way Firestore keys it. */
    private val roster: MutableMap<ParticipantID, Participant> =
        roster.associateBy { it.id }.toMutableMap()

    /** Reverse lookup, standing in for the `bracelets/{chipUid}` collection. */
    private fun pairedTo(bracelet: BraceletID): Participant? =
        roster.values.firstOrNull { it.braceletId == bracelet }

    private suspend fun simulateNetwork() {
        if (latencyMillis > 0) delay(latencyMillis)
    }

    // ── Auth ──

    /**
     * Mirrors the prototype: any address starting `reception` or `bar` is
     * accepted and the password is ignored. Real credential checking is the
     * Firebase implementation's job, and this path is debug-only for exactly
     * that reason — see the iOS README, "Known simplifications".
     */
    override suspend fun signIn(email: String, password: String): StaffRole {
        simulateNetwork()
        val address = email.trim().lowercase()
        return when {
            address.startsWith("reception") -> StaffRole.RECEPTION
            address.startsWith("bar") -> StaffRole.BAR
            else -> throw TerminalError.UnknownAccount
        }
    }

    override suspend fun signOut() {
        simulateNetwork()
    }

    // ── Catalogue ──

    override suspend fun drinks(): List<Drink> {
        simulateNetwork()
        return menu
    }

    override suspend fun awaitingCheckIn(): List<Participant> {
        simulateNetwork()
        return lock.withLock {
            roster.values.filter { it.isAwaitingCheckIn }.sortedBy { it.name }
        }
    }

    // ── Bracelets ──

    override suspend fun participantWithBracelet(bracelet: BraceletID): Participant? {
        simulateNetwork()
        return lock.withLock { pairedTo(bracelet) }
    }

    override suspend fun createEveningTicket(
        evening: Evening,
        bracelet: BraceletID,
    ): Participant {
        simulateNetwork()
        return lock.withLock {
            if (pairedTo(bracelet) != null) throw TerminalError.BraceletAlreadyPaired

            // Firestore would collide on `create` and retry; here the map is the
            // whole world, so the next free number is the highest plus one.
            val highest = roster.values
                .filter { it.evening == evening }
                .mapNotNull { it.eveningNumber }
                .maxOrNull() ?: 0

            val ticket = Participant.eveningTicket(evening, highest + 1, bracelet)
            if (roster.containsKey(ticket.id)) throw TerminalError.EveningSequenceExhausted
            roster[ticket.id] = ticket
            ticket
        }
    }

    override suspend fun assignBracelet(bracelet: BraceletID, to: Participant): Participant {
        simulateNetwork()
        return lock.withLock {
            val current = roster[to.id] ?: throw TerminalError.UnknownAccount
            if (!current.isAwaitingCheckIn) throw TerminalError.BraceletAlreadyPaired
            if (pairedTo(bracelet) != null) throw TerminalError.BraceletAlreadyPaired

            val paired = current.copy(braceletId = bracelet, checkedInAt = Instant.now())
            roster[paired.id] = paired
            paired
        }
    }

    override suspend fun topUp(bracelet: BraceletID, amount: Money): Participant {
        simulateNetwork()
        return lock.withLock {
            val current = pairedTo(bracelet) ?: throw TerminalError.BraceletNotAssigned
            if (current.isBlocked) throw TerminalError.BraceletBlocked

            val updated = current.copy(balance = current.balance + amount)
            roster[updated.id] = updated
            updated
        }
    }

    override suspend fun charge(bracelet: BraceletID, lines: List<CartLine>): Participant {
        simulateNetwork()
        return lock.withLock {
            val current = pairedTo(bracelet) ?: throw TerminalError.BraceletNotAssigned
            if (current.isBlocked) throw TerminalError.BraceletBlocked

            val total = lines.fold(Money.ZERO) { running, line -> running + line.total }
            // Re-check server side. The client already ran `PaymentDecision`, but
            // a second terminal may have spent the money in between.
            if (current.balance < total) {
                throw TerminalError.InsufficientFunds(current.balance, total)
            }

            val updated = current.copy(balance = current.balance - total)
            roster[updated.id] = updated
            updated
        }
    }
}
