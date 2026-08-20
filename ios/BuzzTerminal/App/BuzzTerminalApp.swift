import SwiftUI

@main
struct BuzzTerminalApp: App {
    /// One model for the whole app, created once and handed down through the
    /// environment. `@State` (not `@StateObject`) is correct here because
    /// `AppModel` is `@Observable`, not `ObservableObject`.
    @State private var model: AppModel

    init() {
        let configured = FirebaseBootstrap.configureIfAvailable()
        // One SyncCenter, shared: the repository reports into it and the model reads
        // from it. Created here rather than by either of them, because a refused
        // write has to outlive both — it is persisted, and it is the record of money
        // that went missing.
        let sync = SyncCenter()

        #if DEBUG
        let overrides = LaunchOverrides.fromProcess
        if overrides.useEmulators, configured {
            FirebaseBootstrap.useEmulators()
        }
        // Firebase is the default, in DEBUG as well as in release, so that what
        // gets developed against is what staff run. Different defaults per
        // configuration is its own bug: you exercise the fixtures all week and
        // ship the real backend.
        //
        // `-sbBackend memory` opts out, for the screenshot pass and for working
        // with no network. A clone with no GoogleService-Info.plist also lands on
        // the fixtures, which keeps the whole app walkable for someone who has not
        // been through docs/firebase-setup.md.
        let repository: any TerminalRepository =
            overrides.usesFixtures || !configured
                ? InMemoryTerminalRepository()
                : FirebaseTerminalRepository(sync: sync)
        // Real chips whenever the hardware can read them. `-sbScanner simulated`
        // forces the prototype panel back on a device, which is how a flow gets
        // rehearsed without a bracelet in hand.
        let model = AppModel(
            repository: repository,
            reader: overrides.forcesSimulatedScanner ? SimulatedBraceletReader() : Self.bestReader(),
            sync: sync
        )
        model.apply(overrides)
        _model = State(initialValue: model)
        #else
        // A release build talks to Firestore or it does nothing at all.
        //
        // The alternative — quietly falling back to the in-memory fixtures — is the
        // worst outcome available here. The app would look entirely normal on a
        // staff phone: sign in with any address beginning "reception", serve
        // invented drinks, take payments that go nowhere. A till that convincingly
        // pretends to work is worse than one that refuses to start.
        //
        // This can only happen if GoogleService-Info.plist is missing from the
        // archive, which is possible because the file is gitignored — another
        // machine, or a CI job, can build without it. That is a build mistake, and
        // failing at launch means it is found during the TestFlight smoke test
        // rather than at the bar on Friday night.
        guard configured else {
            fatalError("""
                No GoogleService-Info.plist in this build.

                A release build must talk to Firestore; falling back to fixtures \
                would put a fake till in a bartender's hands. Add the file to \
                ios/BuzzTerminal/Resources/ and archive again — see \
                docs/firebase-setup.md.
                """)
        }
        _model = State(initialValue: AppModel(
            repository: FirebaseTerminalRepository(sync: sync),
            reader: Self.bestReader(),
            sync: sync
        ))
        #endif
    }

    /// Core NFC where it exists, the prototype panel where it does not.
    ///
    /// `readingAvailable` is false on the Simulator, on an iPhone 6 or earlier, and
    /// if the entitlement is missing — so this also keeps a misbuilt app walkable
    /// instead of offering a scan that cannot happen.
    private static func bestReader() -> any BraceletReader {
        #if canImport(CoreNFC)
        let nfc = CoreNFCBraceletReader()
        if nfc.isHardwareBacked { return nfc }
        #endif
        return SimulatedBraceletReader()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
