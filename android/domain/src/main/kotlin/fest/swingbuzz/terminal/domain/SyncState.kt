package fest.swingbuzz.terminal.domain

import java.time.Instant
import java.util.UUID

/**
 * A write that was accepted at the till and refused by the server afterwards.
 *
 * The Kotlin twin of the Swift `FailedWrite`, and the artefact the whole offline
 * design exists to produce. A queued charge can be rejected on replay — the rules
 * verify a balance against the ledger entry justifying it, and if anything else
 * moved that balance meanwhile the arithmetic no longer agrees. The drink is
 * already poured. Somebody has to be able to find out what happened, hours later,
 * from a phone that has since been restarted.
 *
 * Every field answers a question an organiser will actually ask: who, how much,
 * when, which till, and what did the server say.
 *
 * Deliberately free of any serialisation annotation. `:domain` is a plain JVM
 * module with no Android and no kotlinx-serialization dependency, and adding one
 * for a handful of fields would be a poor trade — the app module writes the JSON,
 * and a test pins the round trip.
 */
data class FailedWrite(
    val id: UUID = UUID.randomUUID(),
    /**
     * The client-generated transaction id, which is also the Firestore document id
     * it would have been written as. The way to check whether it somehow landed.
     */
    val transactionId: String,
    val kind: Kind,
    val participantId: String,
    /**
     * Denormalised on purpose: the participant document may be unreachable when
     * this is read, and "tkt-10042" is no use to somebody looking for a guest.
     */
    val participantName: String,
    val braceletId: String,
    val amount: Money,
    val attemptedAt: Instant,
    val terminalId: String,
    /**
     * What the server actually said, kept verbatim. A rules rejection and a network
     * fault need different responses, and paraphrasing loses that.
     */
    val reason: String,
    /** Set once an organiser has dealt with it, so the list can be worked through. */
    val settled: Boolean = false,
) {
    enum class Kind(val wire: String, val label: String) {
        TOP_UP("topUp", "Top-up"),
        CHARGE("charge", "Charge"),
        CHECK_IN("checkIn", "Check-in");

        companion object {
            fun fromWire(value: String?): Kind? = entries.firstOrNull { it.wire == value }
        }
    }

    /** One line, sayable out loud across a bar. */
    val summary: String
        get() = when (kind) {
            Kind.CHECK_IN -> "${kind.label} — $participantName, bracelet $braceletId"
            Kind.TOP_UP, Kind.CHARGE -> "${kind.label} $amount — $participantName"
        }

    /**
     * What an organiser should do about it, which differs by kind and is not
     * obvious under pressure.
     */
    val advice: String
        get() = when (kind) {
            // The cash is already in the till, so the guest is owed the credit.
            Kind.TOP_UP ->
                "The money was taken but not recorded. Top the guest up again for this amount."
            // The drink is already poured. Charging again is a decision, not a fix.
            Kind.CHARGE ->
                "The drink was served but not charged. Decide whether to charge again or write it off."
            Kind.CHECK_IN ->
                "The bracelet was handed over but not paired. Check the guest in again."
        }
}

/**
 * Everything the app has queued and not yet had confirmed, plus everything that was
 * refused.
 *
 * Immutable, unlike the Swift `struct` it mirrors: Compose recomposes on a new
 * value, so returning a copy is the idiom rather than mutating in place. The
 * arithmetic is the same, and it is tested — a pending count that drifts is worse
 * than no count at all, because staff will believe it.
 */
data class SyncState(
    val pending: Int = 0,
    val failures: List<FailedWrite> = emptyList(),
    /**
     * Whether the app can currently reach Firestore. Distinct from "has pending
     * writes": a write can be pending while online, briefly.
     */
    val isOffline: Boolean = false,
) {
    fun enqueued(): SyncState = copy(pending = pending + 1)

    /**
     * Never below zero. The count is restored from nothing on launch while
     * Firestore's own queue survives, so an acknowledgement can arrive for a write
     * this run never saw enqueued.
     */
    fun acknowledged(): SyncState = copy(pending = maxOf(0, pending - 1))

    fun failed(write: FailedWrite): SyncState =
        copy(pending = maxOf(0, pending - 1), failures = failures + write)

    fun settle(id: UUID): SyncState =
        copy(failures = failures.map { if (it.id == id) it.copy(settled = true) else it })

    fun withFailures(replacement: List<FailedWrite>): SyncState = copy(failures = replacement)

    val unsettledFailures: List<FailedWrite> get() = failures.filter { !it.settled }

    /**
     * The banner's text, or null when there is nothing worth saying — so the UI has
     * one thing to check rather than three. Not an empty string: a permanent bar of
     * whitespace across every screen is its own bug.
     */
    val bannerMessage: String?
        get() {
            val unsettled = unsettledFailures.size
            if (unsettled > 0) {
                val word = if (unsettled == 1) "transaction" else "transactions"
                return "$unsettled $word failed to sync — show an organiser"
            }
            if (pending > 0) {
                val word = if (pending == 1) "transaction" else "transactions"
                return "$pending $word waiting to sync"
            }
            return if (isOffline) "Offline — sales are being queued" else null
        }

    /** A failure is worse than a queue, and the banner should look like it. */
    val bannerIsAlarming: Boolean get() = unsettledFailures.isNotEmpty()
}
