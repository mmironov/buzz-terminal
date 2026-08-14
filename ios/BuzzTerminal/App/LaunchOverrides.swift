#if DEBUG
import Foundation

/// Debug-only equivalent of the Claude Design prototype's props panel, which had
/// `startScreen`, `startOffline` and `showSimulator` knobs.
///
/// Pass them as launch arguments — in Xcode via Product ▸ Scheme ▸ Edit Scheme ▸
/// Run ▸ Arguments, or from the command line:
///
///     xcrun simctl launch <udid> fest.swingbuzz.BuzzTerminal -sbScreen participant
///
/// Available screens: `reception`, `bar`, `assign`, `participant`, `blocked`,
/// `topup`, `receipt`, `cart`, `payreview`, `payreview-short`,
/// `payreview-blocked`, `payreview-unassigned`, `assign-evening`,
/// `evening-participant`.
/// Add `-sbOffline` for the offline banner, `-sbScanning` for the scan sheet,
/// `-sbBackend memory` to use the in-memory fixtures rather than Firestore, and
/// `-sbEmulator` to point Firebase at the local emulators.
///
/// Wrapped in `#if DEBUG` so none of it exists in a release build. Useful beyond
/// screenshots: it is how you get to a deep screen without walking the flow every
/// time you tweak one label on it.
struct LaunchOverrides {
    var screen: String?
    var offline = false
    var scanning = false
    /// `-sbBackend memory` for the in-memory fixtures; anything else, including
    /// the default, talks to Firestore.
    ///
    /// It used to be the other way round. Firebase became the default once it was
    /// the real backend, because a debug build that behaves differently from the
    /// release build is a trap — you exercise the fixtures all week and ship
    /// Firestore. The screenshot pass opts out explicitly.
    var backend = "firebase"
    /// `-sbEmulator` sends Firebase at localhost instead of the real project.
    var useEmulators = false
    /// `-sbSignIn <email> <password>` signs in on launch. For driving an emulator
    /// run without a human at the keyboard; DEBUG only, like everything here.
    var signInEmail: String?
    var signInPassword: String?

    static var fromProcess: LaunchOverrides {
        let arguments = ProcessInfo.processInfo.arguments
        var overrides = LaunchOverrides()

        if let index = arguments.firstIndex(of: "-sbScreen"), index + 1 < arguments.count {
            overrides.screen = arguments[index + 1].lowercased()
        }
        if let index = arguments.firstIndex(of: "-sbBackend"), index + 1 < arguments.count {
            overrides.backend = arguments[index + 1].lowercased()
        }
        overrides.offline = arguments.contains("-sbOffline")
        overrides.scanning = arguments.contains("-sbScanning")
        overrides.useEmulators = arguments.contains("-sbEmulator")
        if let index = arguments.firstIndex(of: "-sbSignIn"), index + 2 < arguments.count {
            overrides.signInEmail = arguments[index + 1]
            overrides.signInPassword = arguments[index + 2]
        }
        return overrides
    }

    var isActive: Bool { screen != nil || offline || scanning || signInEmail != nil }
    var usesFixtures: Bool { backend == "memory" }
}

extension AppModel {
    /// Jump straight into a screen with plausible state behind it.
    func apply(_ overrides: LaunchOverrides) {
        guard overrides.isActive else { return }

        if overrides.offline {
            isOffline = true
            queuedTransactions = 3
        }

        if let email = overrides.signInEmail, let password = overrides.signInPassword {
            self.email = email
            self.password = password
            autoSignInRequested = true
            // Any -sbScreen is applied AFTER signing in, so the screen shows data
            // that came from the repository rather than from these fixtures.
            screenAfterSignIn = overrides.screen
            return
        }

        menu = SampleData.drinks
        awaitingCheckIn = SampleData.awaitingCheckIn

        let marta = SampleData.participant(withBracelet: SampleData.braceletB)
        let jonas = SampleData.participant(withBracelet: SampleData.braceletC)
        let elena = SampleData.participant(withBracelet: SampleData.braceletD)

        switch overrides.screen {
        case "reception":
            role = .reception
            screen = .receptionHome

        case "bar":
            role = .bar
            screen = .barMenu
            seedCart()

        case "assign":
            role = .reception
            bracelet = SampleData.braceletA
            screen = .assign

        case "assign-evening":
            role = .reception
            bracelet = SampleData.braceletA
            screen = .assignEvening

        case "evening-participant":
            role = .reception
            bracelet = SampleData.braceletE
            participant = SampleData.participant(withBracelet: SampleData.braceletE)
            screen = .participant

        case "participant":
            role = .reception
            bracelet = SampleData.braceletB
            participant = marta
            screen = .participant

        case "blocked":
            role = .reception
            bracelet = SampleData.braceletD
            participant = elena
            screen = .blocked

        case "topup":
            role = .reception
            bracelet = SampleData.braceletB
            participant = marta
            topUp.apply(preset: Money(euros: 20))
            screen = .topUp

        case "receipt":
            role = .reception
            bracelet = SampleData.braceletB
            participant = marta
            receipt = Receipt(
                kind: .topUp,
                title: "Balance topped up",
                note: "Cash taken at reception and added to the participant’s account.",
                rows: [
                    .init(key: "Participant", value: "Marta Lindqvist"),
                    .init(key: "Added", value: "20.00 €"),
                    .init(key: "Previous balance", value: "23.50 €"),
                ],
                balance: Money(euros: 43, cents: 50)
            )
            screen = .receipt

        case "cart":
            role = .bar
            seedCart()
            screen = .cart

        // The three pay-review outcomes. All of them run the real
        // `PaymentDecision.evaluate` against the seeded cart rather than
        // hard-coding a result, so these screens show what the logic actually
        // decides — a wrong rule shows up here, not just in a test.
        case "payreview":
            role = .bar
            seedCart()
            bracelet = SampleData.braceletB
            participant = marta
            paymentDecision = .evaluate(participant: marta, total: cartTotal)
            screen = .payReview

        case "payreview-short":
            role = .bar
            seedCart()
            bracelet = SampleData.braceletC
            participant = jonas
            paymentDecision = .evaluate(participant: jonas, total: cartTotal)
            screen = .payReview

        case "payreview-blocked":
            role = .bar
            seedCart()
            bracelet = SampleData.braceletD
            participant = elena
            paymentDecision = .evaluate(participant: elena, total: cartTotal)
            screen = .payReview

        case "payreview-unassigned":
            role = .bar
            seedCart()
            bracelet = SampleData.braceletA
            participant = nil
            paymentDecision = .evaluate(participant: nil, total: cartTotal)
            screen = .payReview

        default:
            break
        }

        if overrides.scanning {
            beginScan(for: role == .bar ? .payment : .checkInOrTopUp)
        }
    }

    private func seedCart() {
        add(SampleData.drinks[0])   // Draught beer
        add(SampleData.drinks[0])
        add(SampleData.drinks[5])   // Gin & tonic
    }
}
#endif
