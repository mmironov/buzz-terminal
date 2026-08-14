import SwiftUI

@main
struct BuzzTerminalApp: App {
    /// One model for the whole app, created once and handed down through the
    /// environment. `@State` (not `@StateObject`) is correct here because
    /// `AppModel` is `@Observable`, not `ObservableObject`.
    @State private var model: AppModel

    init() {
        FirebaseBootstrap.configureIfAvailable()

        #if DEBUG
        let overrides = LaunchOverrides.fromProcess
        if overrides.useEmulators, FirebaseBootstrap.isConfigured {
            FirebaseBootstrap.useEmulators()
        }
        // Fixtures by default. Firebase is opt-in until it has been exercised
        // against the real rules — see docs/firebase-setup.md.
        let repository: any TerminalRepository =
            overrides.wantsFirebase && FirebaseBootstrap.isConfigured
                ? FirebaseTerminalRepository()
                : InMemoryTerminalRepository()
        let model = AppModel(repository: repository)
        model.apply(overrides)
        _model = State(initialValue: model)
        #else
        _model = State(initialValue: AppModel(repository: InMemoryTerminalRepository()))
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
