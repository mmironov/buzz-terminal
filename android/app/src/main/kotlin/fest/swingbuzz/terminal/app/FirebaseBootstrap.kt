package fest.swingbuzz.terminal.app

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.firestoreSettings
import com.google.firebase.firestore.memoryCacheSettings
import fest.swingbuzz.terminal.BuildConfig

/**
 * Reports whether this build has the credentials to talk to Firebase, and points
 * it at the local emulators when asked.
 *
 * There is no `configure()` here, unlike the Swift side: the `google-services`
 * plugin bakes the project into resources at build time and `FirebaseInitProvider`
 * starts the SDK before any of our code runs. So the question is not "did we
 * configure it" but "was there anything to configure with" — which is answered by
 * asking whether an app instance exists at all.
 */
object FirebaseBootstrap {

    private const val TAG = "SBFirebase"

    /**
     * True when `google-services.json` was present at build time. When false the
     * app stays on `InMemoryTerminalRepository`.
     */
    fun isConfigured(context: Context): Boolean {
        val configured = FirebaseApp.getApps(context).isNotEmpty()
        if (!configured) {
            Log.i(
                TAG,
                "No Firebase configuration in this build — staying on the in-memory " +
                    "repository. See docs/firebase-setup.md step 6.",
            )
        } else {
            Log.i(TAG, "Firebase configured for project ${FirebaseApp.getInstance().options.projectId}")
        }
        return configured
    }

    /**
     * Point the SDK at the local emulators instead of the real project.
     *
     * Must run before anything touches Firestore. This is how the app is exercised
     * against the actual security rules — the same `backend/firestore.rules` the
     * emulator loads for `backend/rules-tests` — without writing to a live
     * festival database.
     *
     * **The host defaults to `127.0.0.1` and needs `adb reverse`:**
     *
     * ```
     * adb reverse tcp:8080 tcp:8080 && adb reverse tcp:9099 tcp:9099
     * ```
     *
     * The obvious choice is `10.0.2.2`, the documented alias for the host's
     * loopback from inside the Android emulator, and it does not work for an app
     * on a current AVD. `ip route` shows why: `10.0.2.0/24` is on both `eth0`
     * (the QEMU NAT, where the alias lives) and `wlan0` (the emulated access
     * point, where it does not). App traffic binds to Wi-Fi, so packets to
     * `10.0.2.2` go to the virtual AP and are dropped — from `adb shell` the same
     * address answers, which makes this look like an app bug rather than a
     * routing one. Measured here: the shell got HTTP 200, the app's own uid timed
     * out after ten seconds, and the Auth emulator logged no request either time.
     *
     * `adb reverse` sidesteps the routing question entirely, and works unchanged
     * on a physical device over USB.
     */
    fun useEmulators(host: String = DEFAULT_EMULATOR_HOST) {
        if (!BuildConfig.DEBUG) return

        FirebaseFirestore.getInstance().apply {
            firestoreSettings = firestoreSettings {
                setHost("$host:8080")
                isSslEnabled = false
                // No disk cache: an emulator run should start from nothing rather
                // than from what a previous run, with different data, left behind.
                setLocalCacheSettings(memoryCacheSettings {})
            }
        }
        FirebaseAuth.getInstance().useEmulator(host, 9099)
        Log.i(TAG, "Emulators: Firestore $host:8080, Auth $host:9099")
    }

    /** Reachable once `adb reverse` is in place. See [useEmulators]. */
    const val DEFAULT_EMULATOR_HOST = "127.0.0.1"
}
