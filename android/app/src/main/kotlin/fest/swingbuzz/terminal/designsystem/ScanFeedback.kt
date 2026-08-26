package fest.swingbuzz.terminal.designsystem

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.CombinedVibration
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

/**
 * Sound and haptics for a scan. The Kotlin twin of the Swift `ScanFeedback`, at the
 * same frequencies, so the two apps behave alike behind the same bar.
 *
 * Tones are generated rather than borrowed from `ToneGenerator`, whose palette is
 * telephony signalling and whose stream choice is not ours. Three signals, chosen to
 * be told apart across a noisy room rather than to be pleasant:
 *
 *   success   rising    880 → 1318 Hz
 *   blocked   falling   1046 → 659 → 415 Hz
 *   problem   low buzz  196 / 165 Hz
 *
 * Blocked falls where success rises: melodic shape carries further than pitch, so
 * the two separate before either is consciously heard — which matters at a bar,
 * where the answer is needed before the operator can look up.
 */
class ScanFeedback(context: Context) {

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    private val successTone by lazy {
        render(listOf(Tone(880.0, 0.065), Tone(1318.5, 0.085)))
    }

    private val blockedTone by lazy {
        render(listOf(Tone(1046.5, 0.08), Tone(659.25, 0.075), Tone(415.3, 0.16)))
    }

    private val problemTone by lazy {
        // Longer than success on purpose: the one sound an operator must not miss
        // should occupy more time than the one they will hear hundreds of times.
        render(listOf(Tone(196.0, 0.13), Tone(0.0, 0.05), Tone(165.0, 0.2)))
    }

    /** A chip that read cleanly, or a payment the server will accept. */
    fun success() {
        vibrate(longArrayOf(0, 18))
        play(successTone)
    }

    /**
     * A bracelet an organiser has frozen.
     *
     * Its own sound because it is its own situation: nothing is broken, the read
     * worked, and no amount of retrying will change the answer. Somebody has to
     * fetch an organiser.
     */
    fun blocked() {
        vibrate(longArrayOf(0, 30, 80, 30))
        play(blockedTone)
    }

    /**
     * A duplicate, a chip nobody is paired to, not enough money, or a read that
     * failed. One signal for all of them: the operator has to look at the screen,
     * and which of the four it is cannot be usefully conveyed by a tone.
     */
    fun problem() {
        vibrate(longArrayOf(0, 60, 90, 120))
        play(problemTone)
    }

    // ── Playback ──

    private fun play(samples: ShortArray?) {
        if (samples == null || samples.isEmpty()) return
        try {
            // USAGE_MEDIA, not a notification usage. A staff phone lives on silent,
            // and Android's ringer mode silences notification audio while leaving
            // media alone — so a notification stream would be the Android version
            // of "sometimes audible", which is not worth shipping for a till.
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(samples.size * 2)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            track.write(samples, 0, samples.size)
            // Released when it finishes, so a fast operator scanning three bracelets
            // a second does not accumulate tracks. A new one per tone costs less
            // than the bookkeeping of reusing one across overlapping plays.
            track.setNotificationMarkerPosition(samples.size)
            track.setPlaybackPositionUpdateListener(
                object : AudioTrack.OnPlaybackPositionUpdateListener {
                    override fun onMarkerReached(t: AudioTrack?) {
                        runCatching { t?.release() }
                    }

                    override fun onPeriodicNotification(t: AudioTrack?) = Unit
                }
            )
            track.play()
        } catch (e: Exception) {
            // Audio is a courtesy here, not the feature. A phone that refuses to
            // play must not stop a check-in.
            Log.w(TAG, "scan feedback unavailable: ${e.message}")
        }
    }

    private fun vibrate(pattern: LongArray) {
        val vibrator = vibrator ?: return
        runCatching {
            val effect = VibrationEffect.createWaveform(pattern, -1)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Nothing gained from CombinedVibration here, but it is the
                // non-deprecated path on S and later.
                (vibrator as Vibrator).vibrate(effect)
            } else {
                vibrator.vibrate(effect)
            }
        }.onFailure { Log.w(TAG, "haptics unavailable: ${it.message}") }
    }

    // ── Tone rendering ──

    private class Tone(val frequency: Double, val duration: Double)

    /**
     * Render notes into one PCM buffer, with a short ramp on each edge.
     *
     * The ramp is not polish: a sine wave cut off mid-cycle produces an audible
     * click, and a click on every scan is exactly the kind of small ugliness that
     * makes staff stop using a tool.
     */
    private fun render(notes: List<Tone>): ShortArray? {
        val total = notes.sumOf { it.duration }
        val frames = (total * SAMPLE_RATE).toInt()
        if (frames <= 0) return null
        val out = ShortArray(frames)

        var index = 0
        for (note in notes) {
            val count = (note.duration * SAMPLE_RATE).toInt()
            val ramp = min((0.006 * SAMPLE_RATE).toInt(), count / 2)
            for (offset in 0 until count) {
                if (index >= frames) break
                var value = 0.0
                if (note.frequency > 0) {
                    val phase = 2 * PI * note.frequency * offset / SAMPLE_RATE
                    value = sin(phase) * 0.28
                    if (offset < ramp && ramp > 0) {
                        value *= offset.toDouble() / ramp
                    } else if (offset > count - ramp && ramp > 0) {
                        value *= (count - offset).toDouble() / ramp
                    }
                }
                out[index] = (value * Short.MAX_VALUE).toInt().toShort()
                index += 1
            }
        }
        return out
    }

    private companion object {
        const val TAG = "SwingBuzz.feedback"
        const val SAMPLE_RATE = 44_100
    }
}
