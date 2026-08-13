import SwiftUI

@main
struct BuzzTerminalApp: App {
    /// One model for the whole app, created once and handed down through the
    /// environment. `@State` (not `@StateObject`) is correct here because
    /// `AppModel` is `@Observable`, not `ObservableObject`.
    @State private var model = AppModel()

    init() {
        #if DEBUG
        model.apply(LaunchOverrides.fromProcess)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
