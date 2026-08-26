package fest.swingbuzz.terminal.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import fest.swingbuzz.terminal.domain.FailedWrite
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.SyncState
import java.time.Instant
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/**
 * The app's view of what has been queued, acknowledged and refused.
 *
 * Compose state, so the UI recomposes; created once and shared between the model
 * and the repository, which is what reports into it.
 *
 * Failures are persisted, and that is the whole point of this class existing rather
 * than a couple of properties on `AppModel`. A refused charge is money that went
 * missing; it has to survive the app being force-stopped, the phone dying, and the
 * shift changing.
 *
 * The JSON is written by hand with `org.json`. `:domain` has no serialisation
 * dependency on purpose, and adding one for six fields would cost more than it
 * saves — the round trip has a test.
 */
class SyncCenter(context: Context?) {

    var state by mutableStateOf(SyncState())
        private set

    private val prefs: SharedPreferences? =
        context?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    init {
        loadFailures()
    }

    // ── Queue ──────────────────────────────────────────────────────────────

    fun enqueued() {
        state = state.enqueued()
    }

    fun acknowledged() {
        state = state.acknowledged()
    }

    fun failed(write: FailedWrite) {
        state = state.failed(write)
        saveFailures()
        // Logged as well as stored: if the phone is later unavailable, a bug report
        // still carries the record.
        Log.e(
            TAG,
            "write refused: ${write.kind.wire} ${write.amount} " +
                "participant ${write.participantId} tx ${write.transactionId} — ${write.reason}",
        )
    }

    fun settle(id: UUID) {
        state = state.settle(id)
        saveFailures()
    }

    fun setOffline(offline: Boolean) {
        if (state.isOffline == offline) return
        state = state.copy(isOffline = offline)
        Log.i(TAG, "connectivity: " + if (offline) "offline" else "online")
    }

    /**
     * Put the banner into a given state, for previews and the screenshot pass. Does
     * not touch the persisted failure list — a fake banner must never be mistaken
     * for a record of real missing money.
     */
    fun simulate(offline: Boolean, pending: Int = 0) {
        var next = state.copy(isOffline = offline)
        repeat(pending) { next = next.enqueued() }
        state = next
    }

    // ── Persistence ────────────────────────────────────────────────────────

    private fun loadFailures() {
        val raw = prefs?.getString(KEY, null) ?: return
        try {
            val array = JSONArray(raw)
            val decoded = (0 until array.length()).mapNotNull { decode(array.getJSONObject(it)) }
            state = state.withFailures(decoded)
            val unsettled = decoded.count { !it.settled }
            if (unsettled > 0) {
                Log.e(TAG, "$unsettled unsettled failed write(s) carried over from a previous run")
            }
        } catch (e: Exception) {
            // Deliberately not cleared. A decode failure means something is wrong
            // with the format, and throwing away the only record of missing money to
            // tidy up would be the worst possible response.
            Log.e(TAG, "could not decode failed writes: ${e.message}")
        }
    }

    private fun saveFailures() {
        val array = JSONArray()
        state.failures.forEach { array.put(encode(it)) }
        prefs?.edit()?.putString(KEY, array.toString())?.apply()
    }

    private fun encode(write: FailedWrite) = JSONObject().apply {
        put("id", write.id.toString())
        put("transactionId", write.transactionId)
        put("kind", write.kind.wire)
        put("participantId", write.participantId)
        put("participantName", write.participantName)
        put("braceletId", write.braceletId)
        // Cents, never a decimal: a stored amount must not become a Double on the
        // way to disk and back.
        put("amountCents", write.amount.cents)
        put("attemptedAt", write.attemptedAt.toEpochMilli())
        put("terminalId", write.terminalId)
        put("reason", write.reason)
        put("settled", write.settled)
    }

    private fun decode(json: JSONObject): FailedWrite? {
        val kind = FailedWrite.Kind.fromWire(json.optString("kind")) ?: return null
        return FailedWrite(
            id = runCatching { UUID.fromString(json.getString("id")) }.getOrElse { UUID.randomUUID() },
            transactionId = json.optString("transactionId"),
            kind = kind,
            participantId = json.optString("participantId"),
            participantName = json.optString("participantName"),
            braceletId = json.optString("braceletId"),
            amount = Money(json.optInt("amountCents")),
            attemptedAt = Instant.ofEpochMilli(json.optLong("attemptedAt")),
            terminalId = json.optString("terminalId"),
            reason = json.optString("reason"),
            settled = json.optBoolean("settled"),
        )
    }

    private companion object {
        const val TAG = "SwingBuzz.sync"
        const val PREFS = "fest.swingbuzz.sync"
        const val KEY = "failedWrites"
    }
}
