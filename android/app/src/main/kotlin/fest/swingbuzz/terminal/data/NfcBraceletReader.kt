package fest.swingbuzz.terminal.data

import android.app.Activity
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.util.Log
import fest.swingbuzz.terminal.domain.BraceletID
import fest.swingbuzz.terminal.domain.SimulatedBracelet
import java.lang.ref.WeakReference
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * The real bracelet reader.
 *
 * Reader mode, not the foreground-dispatch intent system. Two reasons, and the
 * second is the important one:
 *
 *   * dispatch delivers tags as Intents to the Activity, which would mean routing a
 *     scan through `onNewIntent` and back into a suspend function — a lot of
 *     indirection for a value the callback already has;
 *   * reader mode **suppresses the platform's own tag animation and sound**, so the
 *     app's Modernist scan overlay stays on screen throughout. iOS cannot do this:
 *     Core NFC always presents Apple's own sheet. The Android version of this screen
 *     is therefore closer to the design than the iOS one, which is worth knowing
 *     before somebody "fixes" the difference.
 *
 * Needs an Activity, which is why this holds a weak reference set by `MainActivity`
 * rather than taking a Context in its constructor. A strong reference here would leak
 * the Activity across a rotation.
 */
class NfcBraceletReader(private val activityRef: WeakReference<Activity>) : BraceletReader {

    private val adapter: NfcAdapter? =
        activityRef.get()?.let { NfcAdapter.getDefaultAdapter(it) }

    /**
     * False when the device has no NFC at all, and when the user has turned it off
     * in settings — in which case the app must not offer a scan it cannot perform.
     * Checked per call rather than cached: NFC can be switched off mid-shift.
     */
    override val isHardwareBacked: Boolean
        get() = adapter?.isEnabled == true

    /** Empty: a real reader has nothing to fake. */
    override val simulatedOptions: List<SimulatedBracelet> = emptyList()

    override suspend fun read(selection: BraceletID?): BraceletID {
        // `selection` is the fixture the operator tapped in the prototype panel. A
        // hardware reader ignores it by contract: the chip decides, not the UI.
        val activity = activityRef.get() ?: throw BraceletReadFailure("No screen to read from.")
        val adapter = adapter ?: throw BraceletReadFailure("This device cannot read bracelets.")
        if (!adapter.isEnabled) {
            throw BraceletReadFailure("NFC is switched off. Turn it on in Settings.")
        }

        return suspendCancellableCoroutine { continuation ->
            val callback = NfcAdapter.ReaderCallback { tag: Tag ->
                val bracelet = tag.braceletId()
                if (bracelet == null) {
                    Log.w(TAG, "tag with no usable id: ${tag.techList.joinToString()}")
                    // Not an error worth failing the scan for — keep polling, since
                    // the operator is probably still moving the wristband into place.
                    return@ReaderCallback
                }
                Log.i(TAG, "read chip ${bracelet.rawValue}")
                if (continuation.isActive) continuation.resume(bracelet)
            }

            // NFC_A covers NTAG21x and MIFARE, which is what wristbands are; B and F
            // cost nothing to accept. SKIP_NDEF_CHECK matters for speed: the identity
            // is the UID, so reading NDEF would delay every scan for data the app
            // never looks at.
            val flags = NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_NFC_F or
                NfcAdapter.FLAG_READER_NFC_V or
                NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK or
                NfcAdapter.FLAG_READER_NO_PLATFORM_SOUNDS

            try {
                adapter.enableReaderMode(activity, callback, flags, null)
            } catch (e: Exception) {
                continuation.resumeWithException(
                    BraceletReadFailure(e.message ?: "Could not start the NFC reader.")
                )
                return@suspendCancellableCoroutine
            }

            // Cancellation is the operator tapping the overlay's own Cancel, or the
            // screen going away. Either way reader mode must be released, or the next
            // scan starts with a stale callback attached.
            continuation.invokeOnCancellation {
                runCatching { adapter.disableReaderMode(activity) }
            }
        }.also {
            runCatching { adapter.disableReaderMode(activity) }
        }
    }

    private companion object {
        const val TAG = "SwingBuzz.nfc"
    }
}

/** A read that could not happen, as distinct from one the operator cancelled. */
class BraceletReadFailure(message: String) : Exception(message)

/**
 * The chip's UID as a [BraceletID], or null if the tag reports none.
 *
 * `Tag.getId()` is the UID for every technology this app polls, so there is no
 * per-technology branching to do — unlike Core NFC, where the identifier hangs off a
 * per-family associated value.
 */
internal fun Tag.braceletId(): BraceletID? = BraceletID.fromNfcId(id)
