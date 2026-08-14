import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import OSLog

/// Starts the Firebase SDK, if this build has the credentials to do so.
///
/// `@MainActor` because `isConfigured` is mutable state shared across the app, and
/// Swift 6 will not allow that without isolation. The main actor is the honest
/// home for it: `FirebaseApp.configure()` is called once from `App.init`, which
/// is already main-actor isolated.
@MainActor
enum FirebaseBootstrap {

    private static let log = Logger(subsystem: "fest.swingbuzz.BuzzTerminal", category: "firebase")

    /// Whether `FirebaseApp.configure()` ran. When false the app stays on
    /// `InMemoryTerminalRepository`.
    private(set) static var isConfigured = false

    /// Configure Firebase only if `GoogleService-Info.plist` is in the bundle.
    ///
    /// The plist is gitignored — it identifies the project and pins its API keys —
    /// so a fresh clone does not have one. `FirebaseApp.configure()` raises a
    /// fatal error in that situation, which would mean the app could not launch at
    /// all for anyone who has not been through `docs/firebase-setup.md`. Falling
    /// back to the in-memory repository keeps the whole app walkable instead.
    @discardableResult
    static func configureIfAvailable() -> Bool {
        guard !isConfigured else { return true }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            log.notice("""
                No GoogleService-Info.plist in the bundle — staying on the in-memory \
                repository. See docs/firebase-setup.md step 5.
                """)
            return false
        }
        FirebaseApp.configure()
        isConfigured = true
        log.info("Firebase configured for project \(FirebaseApp.app()?.options.projectID ?? "?", privacy: .public)")
        return true
    }

    #if DEBUG
    /// Point the SDK at the local emulators instead of the real project.
    ///
    /// Must run before anything touches Firestore, hence immediately after
    /// `configure()`. This is how the app is exercised against the actual security
    /// rules — the same `backend/firestore.rules` the emulator loads for
    /// `backend/rules-tests` — without writing to a live festival database.
    static func useEmulators() {
        let settings = Firestore.firestore().settings
        settings.host = "127.0.0.1:8080"
        settings.isSSLEnabled = false
        // No disk cache: an emulator run should start from nothing, not from
        // whatever a previous run left behind.
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings

        Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
        log.notice("Using local emulators: Firestore :8080, Auth :9099")
    }
    #endif
}
