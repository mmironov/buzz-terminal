import SwiftUI

/// Assembles the chrome, the current screen and the scan overlay.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.sbBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                if model.screen != .signIn {
                    StatusHeaderView()
                }
                currentScreen
            }

            if let scan = model.scan {
                ScanOverlayView(state: scan)
                    // Covers the status bar and home indicator too: the operator
                    // needs the whole slab dark while the phone is on a wrist.
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        // Modernist is a light system. See the note in `Tokens.swift`.
        .preferredColorScheme(.light)
        #if DEBUG
        .task {
            guard model.autoSignInRequested else { return }
            model.autoSignInRequested = false
            await model.signIn()
            switch model.screenAfterSignIn {
            case "assign": model.bracelet = SampleData.braceletA; model.screen = .assign
            case "bar": model.screen = .barMenu
            default: break
            }
        }
        #endif
        .animation(.easeOut(duration: 0.25), value: model.screen)
        .animation(.easeOut(duration: 0.25), value: model.isScanning)
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            presenting: model.errorMessage
        ) { _ in
            Button("OK") { model.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch model.screen {
        case .signIn:
            SignInView()
        case .receptionHome:
            ReceptionHomeView()
        case .assign:
            AssignBraceletView()
        case .assignEvening:
            AssignEveningTicketView()
        case .participant:
            ParticipantView()
        case .blocked:
            BlockedBraceletView()
        case .topUp:
            TopUpView()
        case .barMenu:
            BarMenuView()
        case .cart:
            CartView()
        case .payReview:
            PayReviewView()
        case .receipt:
            ReceiptView()
        }
    }
}

#Preview("Sign in") {
    RootView().environment(AppModel())
}

#Preview("Reception") {
    let model = AppModel()
    model.role = .reception
    model.screen = .receptionHome
    return RootView().environment(model)
}

#Preview("Bar") {
    let model = AppModel()
    model.role = .bar
    model.screen = .barMenu
    model.menu = SampleData.drinks
    return RootView().environment(model)
}
