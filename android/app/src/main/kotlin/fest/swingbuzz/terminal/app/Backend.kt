package fest.swingbuzz.terminal.app

import android.content.Context
import android.content.Intent
import android.util.Log
import fest.swingbuzz.terminal.BuildConfig
import fest.swingbuzz.terminal.data.FirebaseTerminalRepository
import fest.swingbuzz.terminal.data.InMemoryTerminalRepository
import fest.swingbuzz.terminal.data.TerminalIdentity
import fest.swingbuzz.terminal.data.TerminalRepository

/**
 * Debug-only launch switches, passed as intent extras.
 *
 * The iOS equivalent takes process arguments from the Xcode scheme; Android has
 * no scheme, so these arrive from `adb`:
 *
 * ```
 * adb shell am start -n fest.swingbuzz.terminal/.MainActivity \
 *   --es sbBackend memory --ez sbEmulator true
 * ```
 *
 * Ignored entirely in a release build, where the only backend is the real one.
 */
data class LaunchOverrides(
    /** `memory` opts out of Firebase. Anything else, including absent, means Firebase. */
    val usesFixtures: Boolean = false,
    /** Send Firebase at the local emulators instead of the real project. */
    val useEmulators: Boolean = false,
    /**
     * Where those emulators are. Overridable because the answer depends on how
     * the device reaches the host — see [FirebaseBootstrap.useEmulators]. A
     * phone on the same wifi wants the host's LAN address here.
     */
    val emulatorHost: String = FirebaseBootstrap.DEFAULT_EMULATOR_HOST,
) {
    companion object {
        fun from(intent: Intent?): LaunchOverrides {
            if (!BuildConfig.DEBUG || intent == null) return LaunchOverrides()
            return LaunchOverrides(
                usesFixtures = intent.getStringExtra("sbBackend")?.lowercase() == "memory",
                useEmulators = intent.getBooleanExtra("sbEmulator", false),
                emulatorHost = intent.getStringExtra("sbEmulatorHost")
                    ?: FirebaseBootstrap.DEFAULT_EMULATOR_HOST,
            )
        }
    }
}

/**
 * Decides which [TerminalRepository] the app runs on.
 *
 * Firebase is the default, in debug as well as in release, so that what gets
 * developed against is what staff run. Different defaults per build type is its
 * own bug: you exercise the fixtures all week and ship the real backend.
 */
object TerminalBackend {

    private const val TAG = "SBBackend"

    fun choose(context: Context, intent: Intent?): TerminalRepository {
        val configured = FirebaseBootstrap.isConfigured(context)
        val overrides = LaunchOverrides.from(intent)

        if (!BuildConfig.DEBUG) {
            // A release build talks to Firestore or it does nothing at all.
            //
            // The alternative — quietly falling back to the in-memory fixtures —
            // is the worst outcome available here. The app would look entirely
            // normal on a staff phone: sign in with any address beginning
            // "reception", serve invented drinks, take payments that go nowhere.
            // A till that convincingly pretends to work is worse than one that
            // refuses to start.
            //
            // This can only happen if google-services.json was missing when the
            // release was assembled, which is possible because the file is
            // gitignored — another machine, or a CI job, can build without it.
            // That is a build mistake, and failing at launch means it is found
            // during the smoke test rather than at the bar on Friday night.
            check(configured) {
                """
                No Firebase configuration in this build.

                A release build must talk to Firestore; falling back to fixtures
                would put a fake till in a bartender's hands. Put
                google-services.json in android/app/ and assemble again — see
                docs/firebase-setup.md step 6.
                """.trimIndent()
            }
            return firebase(context)
        }

        if (overrides.useEmulators && configured) {
            FirebaseBootstrap.useEmulators(overrides.emulatorHost)
        }

        // `--es sbBackend memory` opts out, for the screenshot pass and for
        // working with no network. A clone with no google-services.json also
        // lands on the fixtures, which keeps the whole app walkable for someone
        // who has not been through docs/firebase-setup.md.
        return if (overrides.usesFixtures || !configured) {
            Log.i(TAG, "Fixtures: InMemoryTerminalRepository")
            InMemoryTerminalRepository()
        } else {
            firebase(context)
        }
    }

    private fun firebase(context: Context): TerminalRepository {
        val terminalId = TerminalIdentity.current(context)
        Log.i(TAG, "Firestore, as terminal $terminalId")
        return FirebaseTerminalRepository(terminalId = terminalId)
    }
}
