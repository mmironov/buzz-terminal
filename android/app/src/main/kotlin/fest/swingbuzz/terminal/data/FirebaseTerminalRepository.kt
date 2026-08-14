package fest.swingbuzz.terminal.data

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import fest.swingbuzz.terminal.domain.BraceletID
import fest.swingbuzz.terminal.domain.CartLine
import fest.swingbuzz.terminal.domain.Drink
import fest.swingbuzz.terminal.domain.Evening
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.Participant
import fest.swingbuzz.terminal.domain.ParticipantID
import fest.swingbuzz.terminal.domain.StaffRole
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import java.util.UUID

/**
 * The real backend.
 *
 * **Every money write is a batch, not two writes.** `firestore.rules` verifies a
 * balance change against the ledger entry that justifies it using `getAfter()`,
 * which only sees documents written together. Splitting them is not a style
 * choice that would work slightly worse — it is rejected. The 49 tests in
 * `backend/rules-tests/` are the specification for the shapes below.
 *
 * The Swift original is an `actor`; here a [Mutex] guards the one piece of
 * mutable state, the cached evening-ticket number. Same reason: two door sales
 * running concurrently must not read the same next number.
 */
class FirebaseTerminalRepository(
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance(),
    private val auth: FirebaseAuth = FirebaseAuth.getInstance(),
    /**
     * Which physical device took the cash. Recorded on every ledger entry so a
     * till can be reconciled at the end of the night.
     */
    private val terminalId: String,
) : TerminalRepository {

    /**
     * The next evening-ticket number to try, per evening.
     *
     * Seeded once per evening by a query, then incremented locally. The id
     * encodes the number, so a collision with another desk surfaces as a failed
     * `create` and we simply try the next one — see [createEveningTicket].
     */
    private val eveningNumbers = mutableMapOf<Evening, Int>()
    private val eveningLock = Mutex()

    // ── Auth ──

    /**
     * Sign in and read the staff role from the token's custom claim.
     *
     * The role is **not** derived from the email address. Staff use their personal
     * addresses, and more importantly the client must not get to decide what it is
     * allowed to do: `firestore.rules` authorises on `request.auth.token.role`,
     * which only the Admin SDK can set. An account with no claim is refused here
     * rather than being allowed in to fail on every read.
     */
    override suspend fun signIn(email: String, password: String): StaffRole {
        val result = try {
            auth.signInWithEmailAndPassword(email, password).await()
        } catch (e: Exception) {
            throw signInFailure(e)
        }

        // Force a refresh: a role granted after this device last signed in would
        // otherwise sit behind a cached token for up to an hour.
        val token = result.user?.getIdToken(true)?.await() ?: throw TerminalError.UnknownAccount
        val role = StaffRole.fromWire(token.claims["role"] as? String)
        if (role == null) {
            auth.signOut()
            throw TerminalError.NoRoleAssigned
        }
        return role
    }

    override suspend fun signOut() {
        auth.signOut()
    }

    /**
     * Turn an Auth failure into something an operator can act on — and log the
     * underlying code, which is the part that actually matters at 2am.
     *
     * Android reports these as `errorCode` strings rather than the numeric codes
     * the iOS SDK uses, so the switch cannot be shared with Swift even though the
     * outcomes are the same. Network failure is not an error code at all here: it
     * arrives as its own exception type.
     *
     * Wrong password and unknown email are not separated, because the server
     * refuses to separate them: with email enumeration protection on, both arrive
     * as `ERROR_INVALID_CREDENTIAL`.
     */
    private fun signInFailure(error: Exception): TerminalError {
        val code = (error as? FirebaseAuthException)?.errorCode
        Log.e(LOG_TAG, "Sign-in failed: ${code ?: error.javaClass.simpleName} — ${error.message}")

        if (error is FirebaseNetworkException) return TerminalError.Offline
        return when (code) {
            "ERROR_USER_DISABLED" -> TerminalError.AccountDisabled
            "ERROR_TOO_MANY_REQUESTS" -> TerminalError.TooManyAttempts
            else -> TerminalError.UnknownAccount
        }
    }

    private fun requireStaffUid(): String =
        auth.currentUser?.uid ?: throw TerminalError.UnknownAccount

    // ── Catalogue ──

    override suspend fun drinks(): List<Drink> =
        db.collection(Fire.Collection.DRINKS)
            .whereEqualTo(Fire.Drink.IS_ACTIVE, true)
            .orderBy(Fire.Drink.SORT_ORDER)
            .get().await()
            .documents.mapNotNull { it.toDrink() }

    override suspend fun awaitingCheckIn(): List<Participant> =
        // Equality against null is a supported query, and this is the whole point
        // of `braceletId == null` being the "awaiting" state rather than a
        // separate collection. Composite index: braceletId, nameLower.
        db.collection(Fire.Collection.PARTICIPANTS)
            .whereEqualTo(Fire.Participant.BRACELET_ID, null)
            .orderBy(Fire.Participant.NAME_LOWER)
            .get().await()
            .documents.mapNotNull { it.toParticipant() }

    // ── Bracelets ──

    override suspend fun participantWithBracelet(bracelet: BraceletID): Participant? {
        // Two point reads by document id — no query, no index, and both resolve
        // from the offline cache when the wifi is out. This is why the reverse
        // lookup collection exists at all.
        val lookup = braceletDocument(bracelet).get().await()
        val participantId = lookup.getString(Fire.Bracelet.PARTICIPANT_ID) ?: return null
        return participantDocument(ParticipantID(participantId)).get().await().toParticipant()
    }

    override suspend fun assignBracelet(bracelet: BraceletID, to: Participant): Participant {
        val uid = requireStaffUid()
        val batch = db.batch()

        batch.update(
            participantDocument(to.id),
            mapOf(
                Fire.Participant.BRACELET_ID to bracelet.rawValue,
                Fire.Participant.CHECKED_IN_AT to FieldValue.serverTimestamp(),
                Fire.Participant.UPDATED_AT to FieldValue.serverTimestamp(),
            ),
        )

        // Created, never set: the rules forbid re-pointing a chip, so a bracelet
        // that already exists must fail rather than quietly move a balance.
        batch.set(braceletDocument(bracelet), braceletPairingDocument(to.id, uid))

        batch.commit().await()
        return reload(to.id)
    }

    // ── Door sales ──

    override suspend fun createEveningTicket(evening: Evening, bracelet: BraceletID): Participant {
        val uid = requireStaffUid()

        // The whole allocation is under the lock, not just the read of the cached
        // number: two sales that overlap here would otherwise both take the same
        // one, and the loser's retry would waste a round trip discovering it.
        return eveningLock.withLock {
            var number = seedEveningNumber(evening)

            // The id encodes the number, so Firestore does the deduplication: if
            // another desk already took this one, `create` fails and we try the
            // next. Bounded, because an unbounded retry against a genuine rules
            // violation would spin forever writing nothing.
            repeat(MAX_EVENING_ATTEMPTS) {
                val ticket = Participant.eveningTicket(evening, number, bracelet)
                val batch = db.batch()
                batch.set(participantDocument(ticket.id), ticket.eveningTicketDocument(uid))
                batch.set(braceletDocument(bracelet), braceletPairingDocument(ticket.id, uid))

                try {
                    batch.commit().await()
                    eveningNumbers[evening] = number + 1
                    return@withLock reload(ticket.id)
                } catch (e: Exception) {
                    // A rules rejection and a taken number are indistinguishable
                    // here: both arrive as PERMISSION_DENIED, because "already
                    // exists" is enforced by `allow create` failing. Advancing and
                    // retrying is correct for the first and harmless for the
                    // second, which the retry bound contains.
                    Log.w(LOG_TAG, "Evening ticket #$number rejected, trying the next", e)
                    number += 1
                    eveningNumbers[evening] = number
                }
            }
            throw TerminalError.EveningSequenceExhausted
        }
    }

    /**
     * One query per evening per app run, then local increments.
     *
     * A single-field equality query, so it needs no composite index. Reading the
     * whole evening once beats a counter document: no extra collection, no extra
     * rules path to secure, and no contention point.
     */
    private suspend fun seedEveningNumber(evening: Evening): Int {
        eveningNumbers[evening]?.let { return it }
        val snapshot = db.collection(Fire.Collection.PARTICIPANTS)
            .whereEqualTo(Fire.Participant.EVENING, evening.wire)
            .get().await()
        val highest = snapshot.documents
            .mapNotNull { it.getLong(Fire.Participant.EVENING_NUMBER)?.toInt() }
            .maxOrNull() ?: 0
        return (highest + 1).also { eveningNumbers[evening] = it }
    }

    // ── Money ──

    override suspend fun topUp(bracelet: BraceletID, amount: Money): Participant =
        moveMoney(bracelet, Fire.Transaction.TYPE_TOP_UP, amount)

    override suspend fun charge(bracelet: BraceletID, lines: List<CartLine>): Participant {
        val total = lines.fold(Money.ZERO) { running, line -> running + line.total }
        return moveMoney(bracelet, Fire.Transaction.TYPE_CHARGE, total)
    }

    /**
     * The one write shape that matters: a ledger entry and the new balance, in a
     * single batch, with the client-generated id doing double duty as the
     * idempotency key.
     *
     * The balance is computed from a fresh read rather than with
     * `FieldValue.increment`, because the rules must be able to verify
     * `balanceAfter == balanceBefore + signedAmount`. An increment sentinel gives
     * them nothing to compare. The cost is a lost update window — which the rules
     * close, by rejecting a balance that no longer agrees with the ledger.
     */
    private suspend fun moveMoney(
        bracelet: BraceletID,
        type: String,
        amount: Money,
    ): Participant {
        if (!amount.isPositive) {
            throw TerminalError.InsufficientFunds(Money.ZERO, amount)
        }
        val uid = requireStaffUid()

        val current = participantWithBracelet(bracelet) ?: throw TerminalError.BraceletNotAssigned
        if (current.isBlocked) throw TerminalError.BraceletBlocked

        val signed = if (type == Fire.Transaction.TYPE_CHARGE) Money(-amount.cents) else amount
        val after = current.balance + signed
        if (after.cents < 0) {
            throw TerminalError.InsufficientFunds(current.balance, amount)
        }

        val txId = UUID.randomUUID().toString()
        val batch = db.batch()

        batch.set(
            transactionDocument(current.id, txId),
            mapOf(
                Fire.Transaction.CLIENT_TX_ID to txId,
                Fire.Transaction.TYPE to type,
                Fire.Transaction.AMOUNT to amount.cents,
                Fire.Transaction.SIGNED_AMOUNT to signed.cents,
                Fire.Transaction.STAFF_UID to uid,
                Fire.Transaction.TERMINAL_ID to terminalId,
                Fire.Transaction.CREATED_AT to FieldValue.serverTimestamp(),
            ),
        )

        batch.update(
            participantDocument(current.id),
            mapOf(
                Fire.Participant.BALANCE to after.cents,
                Fire.Participant.LAST_TX_ID to txId,
                Fire.Participant.UPDATED_AT to FieldValue.serverTimestamp(),
            ),
        )

        batch.commit().await()
        return reload(current.id)
    }

    // ── Plumbing ──

    private fun participantDocument(id: ParticipantID): DocumentReference =
        db.collection(Fire.Collection.PARTICIPANTS).document(id.rawValue)

    private fun transactionDocument(id: ParticipantID, txId: String): DocumentReference =
        participantDocument(id).collection(Fire.Collection.TRANSACTIONS).document(txId)

    private fun braceletDocument(bracelet: BraceletID): DocumentReference =
        db.collection(Fire.Collection.BRACELETS).document(bracelet.rawValue)

    /**
     * Read back what the server actually stored.
     *
     * Every mutation returns this rather than the client's own arithmetic, so a
     * server-side timestamp or a rules-adjusted value is what reaches the UI.
     */
    private suspend fun reload(id: ParticipantID): Participant =
        participantDocument(id).get().await().toParticipant()
            ?: throw TerminalError.UnknownAccount

    private companion object {
        const val LOG_TAG = "SBRepository"

        /** Enough to step over a busy evening's collisions, few enough to fail fast. */
        const val MAX_EVENING_ATTEMPTS = 25
    }
}

/**
 * A stable per-device identifier for ledger entries.
 *
 * Persisted rather than generated per launch, so "which till took this cash?"
 * survives an app restart mid-shift. Not a device fingerprint and not tied to any
 * hardware id — just a UUID this install made up once. `ANDROID_ID` would have
 * been available and is deliberately not used: it is a device identifier with
 * privacy implications, and all this needs is a name for a till.
 */
object TerminalIdentity {
    private const val PREFERENCES = "fest.swingbuzz.terminal"
    private const val KEY = "terminalId"

    fun current(context: Context): String {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        preferences.getString(KEY, null)?.let { return it }
        val created = "terminal-${UUID.randomUUID().toString().take(8)}"
        preferences.edit().putString(KEY, created).apply()
        return created
    }
}
