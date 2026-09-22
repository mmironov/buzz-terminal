import Observation
import OSLog
import SwiftUI

/// The whole terminal's state and every transition between screens.
///
/// **Why one flat `screen` enum instead of a `NavigationStack` path?**
/// This is a kiosk, not a browsing app. Look at the design: no back chevron
/// anywhere, no swipe-back, no title bars — each screen ends in an explicit
/// "Cancel", "Done" or "Back to order", and several transitions *replace* the
/// history rather than push onto it (a receipt must not be swipeable back into
/// the payment it just committed). Modelling that as a state machine makes the
/// illegal states unreachable; modelling it as a nav stack would mean fighting
/// the stack to forbid what it does naturally.
///
/// The `@Observable` macro means SwiftUI tracks exactly the properties each view
/// actually reads, so touching `search` does not redraw the bar menu.
@MainActor
@Observable
final class AppModel {

    // MARK: Dependencies

    private let repository: TerminalRepository
    private let reader: BraceletReader

    /// Whether `SampleData` is what the app is actually talking to.
    ///
    /// Anything the fixtures *say* about the world is only true when this is —
    /// the demo credentials, and the descriptions beside the simulated chips.
    /// Showing them regardless is how a correct app comes to look broken: the
    /// chip labelled "fresh, not yet assigned" was a real checked-in guest on
    /// production, and the participant screen that correctly appeared read as a
    /// bug on both platforms before this was gated.
    let runsOnFixtures: Bool

    /// Whether the demo-account shortcuts mean anything.
    ///
    /// They fill fixture credentials that only `InMemoryTerminalRepository`
    /// recognises. Against Firebase they cannot succeed, so offering them there is
    /// an invitation to misread a real authentication failure as a broken app —
    /// which is exactly what happened the first time this ran on production.
    var offersDemoAccounts: Bool { runsOnFixtures }

    /// Queued writes, refused writes, and whether the backend is reachable.
    ///
    /// Shared with the repository, which is what reports into it — the model only
    /// reads. Kept out of `AppModel` itself because a refused charge has to survive
    /// the app being force-quit, and screen state does not.
    let sync: SyncCenter

    init(
        repository: TerminalRepository = InMemoryTerminalRepository(),
        reader: BraceletReader = SimulatedBraceletReader(),
        sync: SyncCenter = SyncCenter()
    ) {
        self.repository = repository
        self.reader = reader
        self.sync = sync
        self.runsOnFixtures = repository is InMemoryTerminalRepository
    }

    // MARK: Session

    let festivalName = "Swing Buzz Festival"
    var role: StaffRole?
    var screen: Screen = .signIn

    var email = ""
    var password = ""
    var loginFailed = false
    var isWorking = false

    /// Surfaced as an alert. Distinct from `loginFailed`, which the design draws
    /// inline under the password field.
    var errorMessage: String?

    #if DEBUG
    /// Set by `-sbSignIn`; performed by `RootView` once it appears.
    var autoSignInRequested = false
    /// Applied after that sign-in, so the screen shows repository data.
    var screenAfterSignIn: String?
    #endif

    // MARK: Connectivity

    /// Real, from Firestore's own opinion of whether it is talking to a server —
    /// not a manual toggle and not a guess from `NWPathMonitor`, which cannot tell
    /// a working network from a venue access point that routes nowhere.
    var isOffline: Bool { sync.state.isOffline }

    /// Writes accepted at the till and not yet acknowledged.
    var queuedTransactions: Int { sync.state.pending }

    /// Writes the server refused after the operator had already been told they
    /// worked. Money that went missing, and the reason this queue has a UI at all.
    var failedWrites: [FailedWrite] { sync.state.unsettledFailures }

    var networkLabel: String { isOffline ? "Offline" : "Online" }
    var networkDotColor: Color { isOffline ? .sbAccent : .sbNeutral600 }

    /// One line for the banner, or nil when there is nothing worth saying.
    var syncMessage: String? { sync.state.bannerMessage }
    var syncIsAlarming: Bool { sync.state.bannerIsAlarming }

    /// Kept for the views that still read it.
    var queueLabel: String { syncMessage ?? "" }

    func settleFailure(_ id: UUID) {
        sync.settle(id)
    }

    // MARK: Scanning

    struct ScanState: Equatable {
        enum Purpose: Equatable {
            /// "Whose is this?" — and nothing more. An unowned chip ends the
            /// flow rather than sliding into a check-in.
            case identify
            /// Participant-first: a guest is already chosen and this chip is
            /// about to become theirs. A chip that belongs to somebody else is
            /// refused here rather than resolved.
            case assignToSelected
            /// A door sale: mint a pass — an evening ticket or a full pass —
            /// onto a fresh chip, for the buyer already named on screen. A chip
            /// that already belongs to somebody is refused.
            case doorSale
            /// A replacement: this fresh chip takes over from the one the guest
            /// on screen has lost, which is invalidated in the same write. A
            /// chip that already belongs to somebody is refused.
            case replaceBracelet
            case payment
        }
        var purpose: Purpose
        var isReading = false
    }

    var scan: ScanState?
    var isScanning: Bool { scan != nil }
    var readerIsHardwareBacked: Bool { reader.isHardwareBacked }
    var simulatedBracelets: [SimulatedBracelet] { reader.simulatedOptions }

    // MARK: Current bracelet

    var bracelet: BraceletID?
    var participant: Participant?

    var braceletLabel: String { bracelet?.rawValue ?? "—" }

    // MARK: Reception

    /// Everybody on the roster without a bracelet yet.
    var awaitingCheckIn: [Participant] = []
    var search = ""

    /// The check-in list, filtered by whatever is in the search box.
    /// The filtering itself lives on `Participant.matches(query:)`.
    var candidates: [Participant] {
        awaitingCheckIn.filter { $0.matches(query: search) }
    }

    var topUp = TopUpEntry()

    /// Which evening a door sale is for. Preselected to tonight when tonight is
    /// one of the three — a convenience, never a validation.
    var eveningSelection: Evening = Evening.today ?? .friday

    /// What the desk may sell, as organisers priced it in the admin panel.
    ///
    /// Refreshed every time a door sale starts, not only at sign-in — see
    /// `refreshDoorPasses`. An empty list is a real state, and so is a read that
    /// failed; the picker tells those two apart rather than saying "nothing on
    /// sale" to somebody whose phone simply could not read the list.
    var doorPasses: [DoorPass] = []
    private(set) var isLoadingDoorPasses = false
    /// The read failed and there is nothing to fall back on.
    private(set) var doorPassesUnavailable = false
    /// Which pass is being sold right now.
    var selectedPass: DoorPass?

    // MARK: Replacing a wristband

    /// Everybody who has a wristband: the list to pick from when one is lost.
    ///
    /// The other list — `awaitingCheckIn` — is everybody who has none, so the
    /// two are complements and neither is a search over the whole roster.
    private(set) var checkedIn: [Participant] = []
    private(set) var isLoadingCheckedIn = false

    /// The check-in list's search box filters this one too, so one field serves
    /// both flows and neither screen has to own a second piece of state.
    var replacementCandidates: [Participant] {
        checkedIn.filter { $0.matches(query: search) }
    }

    /// The reason, the fee and how it is being paid, while the desk fills it in.
    var replacement = BraceletReplacement()

    /// What the festival charges, as an organiser set it in the panel. Nil when
    /// nobody has set one — the desk then has no fee to offer at all.
    private(set) var replacementFee: Money?

    /// The extra classes on sale, as organisers priced them.
    ///
    /// Their own collection, read on its own: a class is not a pass, so it is
    /// not in the door catalogue and cannot be offered at the door by accident.
    private(set) var specialSessions: [SpecialSession] = []

    /// True while the participant screen is showing a door sale that has not
    /// happened yet.
    ///
    /// The screen is the same one a guest off the check-in list gets, and for
    /// the same purpose: a last look at who this is before a pairing that
    /// cannot be undone. The difference is that this person does not exist yet
    /// — nothing is written until the chip is read — so the screen is drawn
    /// from the draft, the merch reads are skipped, and the button scans
    /// instead of pairing.
    private(set) var isPendingDoorSale = false
    /// What has been typed about the buyer.
    var doorSale = DoorSaleDraft()

    // MARK: Bar

    var menu: [Drink] = []
    var cart = Cart()

    var cartLines: [CartLine] { cart.lines(in: menu) }
    var cartTotal: Money { cart.total(in: menu) }
    var cartCountLabel: String { "\(cart.itemCount) items" }

    /// Recomputed whenever the pay-review screen is shown. The decision logic
    /// itself lives on `PaymentDecision` (exercise 3).
    var paymentDecision: PaymentDecision?

    // MARK: Receipt

    var receipt: Receipt?

    // MARK: - Lifecycle

    private static let log = Logger(subsystem: "fest.swingbuzz.BuzzTerminal", category: "model")

    /// Which wristband colour each pass type gets. Loaded with the catalogue.
    ///
    /// Empty until it loads, and empty is a legitimate steady state — a festival
    /// that has not coloured anything simply shows no swatches.
    private(set) var braceletColours = BraceletColourScheme()

    /// The colour for the participant on screen, if their pass type has one.
    var participantColour: BraceletColour? {
        participant.flatMap(braceletColours.colour(for:))
    }

    /// Load the catalogue once a role is known.
    func loadCatalogue() async {
        do {
            menu = try await repository.drinks()
            awaitingCheckIn = try await repository.awaitingCheckIn()
            // Its own do/catch, after the two that matter. A missing swatch is
            // cosmetic; an empty roster or an empty menu stops the desk and the
            // bar. Neither should be reported as a failure because a colour
            // read went wrong, and an alert at sign-in about wristband colours
            // would be a fine way to teach staff to dismiss alerts.
            do {
                braceletColours = BraceletColourScheme(try await repository.braceletColours())
            } catch {
                Self.log.error("bracelet colours failed to load: \(error.localizedDescription, privacy: .public)")
            }
            // Same treatment, one step less cosmetic: with no catalogue the desk
            // cannot sell at the door at all, and the picker says exactly that.
            // Still not worth failing sign-in over — check-in and the bar are
            // what most of a festival is.
            await refreshDoorPasses()
            // Logged because "the list is empty" has two very different causes —
            // an empty roster, or a read the rules refused — and they look
            // identical on screen.
            Self.log.info("loaded \(self.menu.count) drinks, \(self.awaitingCheckIn.count) awaiting check-in")
        } catch {
            Self.log.error("catalogue load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    /// Re-read the door catalogue.
    ///
    /// **This is not only a sign-in concern any more.** A terminal now stays
    /// signed in for days, so a list loaded once at sign-in is a list that can be
    /// days old — and one that failed to load once stays empty until somebody
    /// force-quits the app. That is how a desk ends up being told there is
    /// nothing on sale while six passes sit in the catalogue.
    ///
    /// Six documents, read at the moment somebody starts a sale, which is also
    /// the moment a price an organiser just changed matters most.
    func refreshDoorPasses() async {
        isLoadingDoorPasses = true
        defer { isLoadingDoorPasses = false }
        do {
            doorPasses = try await repository.doorPasses()
            doorPassesUnavailable = false
        } catch {
            // A stale price list beats no price list, so whatever was there
            // stays. Only an empty one is worth admitting to.
            doorPassesUnavailable = doorPasses.isEmpty
            Self.log.error("door passes failed to load: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-read who is still awaiting check-in.
    ///
    /// Same reasoning as the catalogue, and with a sharper edge: people keep
    /// paying, the roster is re-imported during the festival, and a terminal
    /// signed in yesterday would otherwise never see somebody who bought a
    /// ticket this morning. The old list is kept on failure — a stale roster is
    /// still most of the roster.
    func refreshRoster() async {
        do {
            awaitingCheckIn = try await repository.awaitingCheckIn()
        } catch {
            Self.log.error("roster refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-read the drinks menu. Prices change mid-festival and a bar terminal is
    /// signed in all weekend.
    func refreshMenu() async {
        do {
            menu = try await repository.drinks()
        } catch {
            Self.log.error("menu refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Auth

    /// True until the app has looked for an existing session, so the sign-in
    /// screen does not flash in front of somebody who is already signed in.
    var isRestoringSession = true

    /// Pick up where this device left off, if it was signed in.
    ///
    /// Called once at launch. Signing in lasts until somebody signs out: the
    /// people carrying these phones mostly do not know the account password, and
    /// a terminal that logged itself out overnight would be a locked till at
    /// nine in the morning.
    func restoreSession() async {
        defer { isRestoringSession = false }
        guard let role = await repository.restoreSession() else { return }

        self.role = role
        screen = role.homeScreen
        // Exactly what `signIn` does after it succeeds, and in the same order —
        // the listener is refused while unauthenticated, so it cannot start any
        // earlier than this.
        await repository.startMonitoringConnectivity()
        await loadCatalogue()
    }

    func signIn() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let role = try await repository.signIn(email: email, password: password)
            self.role = role
            loginFailed = false
            password = ""
            screen = role.homeScreen
            // Only now: the rules refuse an unauthenticated listener, so starting
            // this before sign-in would report "offline" for a healthy network.
            await repository.startMonitoringConnectivity()
            await loadCatalogue()
        } catch {
            loginFailed = true
        }
    }

    /// Set while the sign-out button is waiting to be confirmed.
    ///
    /// Two taps rather than one. A mis-tap on a busy bar terminal would put a
    /// password prompt in front of somebody who does not have the password —
    /// and now that a session survives everything else, an accidental tap is the
    /// only way left to lose one.
    var isConfirmingSignOut = false

    func askToSignOut() { isConfirmingSignOut = true }
    func keepSignedIn() { isConfirmingSignOut = false }

    func signOut() async {
        isConfirmingSignOut = false
        await repository.signOut()
        role = nil
        screen = .signIn
        password = ""
        loginFailed = false
        cart.removeAll()
        bracelet = nil
        participant = nil
        merch = nil
        freeShirt = nil
        sessionSale = nil
        sessionChoice = nil
        sessionMethod = nil
        specialSessions = []
        participantActionOverride = nil
        merchUnavailable = false
        receipt = nil
        paymentDecision = nil
        search = ""
        topUp.clear()
    }

    func fillDemoAccount(_ role: StaffRole) {
        email = role == .reception ? "reception@swingbuzz.fest" : "bar@swingbuzz.fest"
        password = "festival26"
        loginFailed = false
    }

    /// Cut Firestore off from the network, or restore it.
    ///
    /// No longer a fake. It used to flip a banner and a counter; it now disables
    /// Firestore's transport, which is the only practical way to rehearse the queue
    /// — airplane mode also kills the debugger, and a venue's bad wifi cannot be
    /// summoned on demand. Writes keep being accepted while it is off and replay
    /// when it comes back, which is the behaviour under test.
    func toggleOffline() async {
        let goingOffline = !isOffline
        await repository.setNetworkEnabled(!goingOffline)
    }

    // MARK: - Scanning

    func beginScan(for purpose: ScanState.Purpose) {
        scan = ScanState(purpose: purpose)
        freshChip = .fresh()
        // Cleared, not left standing: a chip checked in a moment ago would
        // otherwise still read "Not assigned" until the fresh reads land.
        simulatedChipStatus = [:]

        // With hardware there is nothing to tap, so the read starts itself. The
        // prototype panel waits for `selectSimulatedBracelet`; a chip does not.
        if readerIsHardwareBacked {
            Task { await scanWithHardware() }
            return
        }

        guard !runsOnFixtures else { return }
        Task { await loadSimulatedChipStatuses() }
    }

    /// What Apple's scan sheet says while it waits for a chip.
    ///
    /// The sheet covers the app completely during a hardware read, so this is
    /// the operator's only reading matter at the moment of the scan. A
    /// participant-first check-in names the guest there deliberately: the
    /// pairing about to happen is permanent, and this is the last surface it
    /// appears on before it does.
    private func scanPrompt(for purpose: ScanState.Purpose) -> String? {
        switch purpose {
        case .assignToSelected:
            guard let guest = participant else { return nil }
            return "Hold a fresh bracelet to the top of the phone to pair it with \(guest.name)."
        case .doorSale:
            guard let pass = selectedPass else { return nil }
            // iOS draws this sheet over the whole app during a read, so on
            // hardware it is the last thing anybody sees before a pass becomes
            // permanent — and the last chance to notice it is the wrong one.
            let who = pass.kind == .evening
                ? "\(doorSale.trimmedName) an evening ticket for \(eveningSelection.label)"
                : "a \(pass.name) for \(doorSale.trimmedName)"
            let amount = pass.price(on: pass.kind == .evening ? eveningSelection : nil)
            let price = amount.isPositive ? " · take \(amount)" : ""
            return "Hold a fresh bracelet to the top of the phone to sell \(who)\(price)."
        case .replaceBracelet:
            guard let guest = participant else { return nil }
            return "Hold a fresh bracelet to the top of the phone to replace \(guest.name)'s. The old one stops working."
        case .identify, .payment:
            return nil
        }
    }

    /// Wait for a real chip, then resolve it exactly as a simulated read does.
    ///
    /// iOS presents its own scan sheet for the duration, so `isReading` is set for
    /// the app's own overlay underneath rather than for anything the operator sees
    /// during the read itself.
    private func scanWithHardware() async {
        guard var state = scan else { return }
        state.isReading = true
        scan = state

        do {
            let scanned = try await reader.read(selection: nil, prompt: scanPrompt(for: state.purpose))
            await resolveScan(scanned, purpose: state.purpose)
        } catch is CancellationError {
            // The operator closed the system sheet, or it timed out. Not a fault,
            // and not worth an error banner: put them back where they were.
            scan = nil
        } catch {
            scan = nil
            errorMessage = error.localizedDescription
        }
    }

    /// What the backend says about each simulated chip, keyed by chip id.
    ///
    /// Empty on the fixtures, where `SampleData`'s own hints are the truth and
    /// need no lookup.
    private(set) var simulatedChipStatus: [BraceletID: String] = [:]

    /// A chip id nothing has ever seen, regenerated every time the overlay opens.
    ///
    /// The five fixture chips are a fixed list, so against a real backend the
    /// first check-in consumes one permanently — after which "scan a new
    /// bracelet" cannot be rehearsed again without resetting the database. This
    /// row is the way back: a fresh id every time, guaranteed unassigned.
    private(set) var freshChip: BraceletID = .fresh()

    /// One point read per simulated chip, so the panel can say what is actually
    /// true rather than what `SampleData` wishes were true.
    private func loadSimulatedChipStatuses() async {
        var statuses: [BraceletID: String] = [:]
        for chip in simulatedBracelets.map(\.id) {
            do {
                guard let found = try await repository.participant(withBracelet: chip) else {
                    statuses[chip] = "Not assigned"
                    continue
                }
                statuses[chip] = found.isBlocked
                    ? "\(found.name) · blocked"
                    : "\(found.name) · \(found.balance)"
            } catch TerminalError.braceletInvalidated {
                statuses[chip] = "replaced · no longer valid"
            } catch {
                // A chip whose status could not be read is left unlabelled rather
                // than guessed at — the whole point of this panel is that it stops
                // claiming things it does not know.
                continue
            }
        }
        simulatedChipStatus = statuses
    }

    func cancelScan() {
        scan = nil
    }

    /// The operator tapped a fixture bracelet in the prototype panel.
    func selectSimulatedBracelet(_ id: BraceletID) async {
        guard var state = scan else { return }
        state.isReading = true
        scan = state

        do {
            let scanned = try await reader.read(selection: id)
            await resolveScan(scanned, purpose: state.purpose)
        } catch is CancellationError {
            scan = nil
        } catch {
            scan = nil
            errorMessage = error.localizedDescription
        }
    }

    private func resolveScan(_ scanned: BraceletID, purpose: ScanState.Purpose) async {
        do {
            let found = try await repository.participant(withBracelet: scanned)

            // Participant-first check-in resolves differently from every other
            // scan: the guest is already on screen and must survive the read, so
            // this branch runs *before* `participant` is overwritten with
            // whoever the chip belongs to.
            if case .assignToSelected = purpose {
                await pairScannedChip(scanned, existingHolder: found)
                return
            }
            // Same reason, one step further: a door sale has a pass and a buyer
            // in hand and no participant yet, so it finishes here rather than
            // falling through to "show me whoever this chip belongs to".
            if case .doorSale = purpose {
                await completeDoorSale(scanned, existingHolder: found)
                return
            }
            // And a replacement, for the same reason again: the guest whose
            // wristband is being replaced is on screen, and the chip in hand is
            // meant to belong to nobody yet.
            if case .replaceBracelet = purpose {
                await completeReplacement(scanned, existingHolder: found)
                return
            }

            bracelet = scanned
            participant = found
            scan = nil

            // Sound and haptics, so the answer arrives before anybody can look up.
            // A bartender's eyes are on the guest and a queue; reception's hands are
            // on somebody's wrist.
            switch purpose {
            case .assignToSelected:
                // Handled above, before `participant` was replaced.
                break

            case .doorSale, .replaceBracelet:
                // Handled above, before `participant` was replaced.
                break

            case .identify:
                search = ""
                if found == nil {
                    // A dead end, deliberately. Reading a bracelet asks "whose
                    // is this?" and this is the answer; it is not the opening
                    // move of a check-in. Pairing a chip to a guest is its own
                    // flow, started on purpose from the home screen, because a
                    // permanent pairing should never be something an operator
                    // fell into by scanning a wristband from the wrong pile.
                    screen = .unassignedBracelet
                    ScanFeedback.shared.problem()
                } else if found?.isBlocked == true {
                    screen = .blocked
                    ScanFeedback.shared.blocked()
                } else if let found {
                    showParticipant(found)
                    ScanFeedback.shared.success()
                }

            case .payment:
                let decision = PaymentDecision.evaluate(participant: found, total: cartTotal)
                paymentDecision = decision
                screen = .payReview
                switch decision {
                case .approved:
                    ScanFeedback.shared.success()
                case .blocked:
                    ScanFeedback.shared.blocked()
                case .notAssigned, .insufficientFunds:
                    ScanFeedback.shared.problem()
                }
            }
        } catch TerminalError.braceletInvalidated {
            // Not a failure: a wristband that was replaced is a thing people
            // find on the floor, and the answer is a screen rather than an alert
            // titled "Something went wrong" in front of a guest.
            bracelet = scanned
            participant = nil
            scan = nil
            screen = .replacedBracelet
            ScanFeedback.shared.problem()
        } catch {
            scan = nil
            errorMessage = error.localizedDescription
            ScanFeedback.shared.problem()
        }
    }

    // MARK: - Merch

    /// What the participant on screen preordered, once it has loaded.
    ///
    /// Nil covers three different situations that all look the same to the
    /// screen and should: nothing ordered, not loaded yet, and a role that may
    /// not read it. None of them is worth a distinct UI at a busy desk.
    private(set) var merch: MerchOrder?

    /// True while the merch read is in flight, so the section can hold its
    /// place rather than appearing a moment after the rest of the screen.
    private(set) var isLoadingMerch = false

    /// The merch read failed rather than came back empty.
    ///
    /// Worth a line on screen. "Nothing ordered" and "could not find out" look
    /// identical otherwise, and the difference is a guest going home without
    /// the t-shirt they paid for.
    private(set) var merchUnavailable = false

    /// The free shirt this person is owed, once it has loaded. Nil for almost
    /// everybody — five people on a roster of a hundred and ten.
    private(set) var freeShirt: FreeShirt?

    /// The extra class this person has bought, once the read lands. Nil for
    /// almost everybody, and at most one: everybody gets one session.
    private(set) var sessionSale: SessionSale?

    /// Which class the desk has picked, and how it is being paid for, before any
    /// of it is written.
    ///
    /// Held here rather than written: picking one is not a sale, and a desk that
    /// changes its mind should not have written twice. Cleared with the
    /// participant, so the next guest starts from nothing.
    private(set) var sessionChoice: String?
    private(set) var sessionMethod: PaymentMethod?

    /// Show a participant, and start loading what they are owed.
    ///
    /// One funnel for both routes to the screen — a scan and a name off the
    /// check-in list — so neither can forget either read.
    private func showParticipant(_ guest: Participant) {
        isPendingDoorSale = false
        participant = guest
        merch = nil
        freeShirt = nil
        sessionSale = nil
        sessionChoice = nil
        sessionMethod = nil
        specialSessions = []
        participantActionOverride = nil
        merchUnavailable = false
        screen = .participant
        Task { await loadMerch(for: guest) }
        Task { await loadFreeShirt(for: guest) }
        Task { await loadSessions(for: guest) }
    }

    private func loadSessions(for guest: Participant) async {
        do {
            // The catalogue rides along with the sale: two small reads on the
            // one screen that needs either, rather than a list loaded at sign-in
            // that is stale by the time an organiser adds a class.
            let classes = try await repository.specialSessions()
            let sale = try await repository.sessionSale(for: guest)
            // The operator may have moved on while this was in flight.
            guard participant?.id == guest.id else { return }
            specialSessions = classes
            sessionSale = sale
        } catch {
            // Folded into the same warning the merch read raises: both are
            // reception-only subcollections behind the same kind of rule, and
            // two sentences saying "something did not load" is one nobody reads.
            Self.log.error("session load failed: \(error.localizedDescription, privacy: .public)")
            guard participant?.id == guest.id else { return }
            merchUnavailable = true
        }
    }

    /// Pick which class is being bought. One each, so this replaces the last.
    func chooseSession(_ session: SpecialSession) {
        sessionChoice = session.id
    }

    /// Choose how it is being paid for, before it is sold.
    func chooseSessionMethod(_ method: PaymentMethod) {
        sessionMethod = method
    }

    /// The class the desk has picked, if it is still on sale.
    var chosenSession: SpecialSession? {
        specialSessions.first { $0.id == sessionChoice }
    }

    /// What the sell button says: what is missing, or what it will take.
    var sellSessionLabel: String {
        guard let chosen = chosenSession else { return "Choose a session" }
        guard sessionMethod != nil else { return "Choose cash or card" }
        return chosen.price.isPositive ? "Sell · \(chosen.price)" : "Sell"
    }

    var canSellSession: Bool {
        chosenSession != nil && sessionMethod != nil && sessionSale == nil
    }

    /// Sell an extra class to the person on screen, and take the money for it.
    ///
    /// Written once and never rewritten: the rules refuse a second write to the
    /// same document, so a double tap on a class somebody already has fails
    /// loudly rather than quietly recording a second payment method.
    func sellSession() async {
        guard let guest = participant, !isPendingDoorSale else { return }
        // One class each, and the rules enforce it by refusing a second write to
        // the same document. This is the same rule on the near side of the
        // network, where it is a hidden button rather than a red banner.
        guard sessionSale == nil, let session = chosenSession else { return }
        // Likewise for the money: a sale with no method is refused server-side.
        guard let method = sessionMethod else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            let sale = try await repository.sellSession(session, method: method, to: guest)
            guard participant?.id == guest.id else { return }
            sessionSale = sale
            sessionChoice = nil
            sessionMethod = nil
            ScanFeedback.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            ScanFeedback.shared.problem()
        }
    }

    private func loadFreeShirt(for guest: Participant) async {
        do {
            let shirt = try await repository.freeShirt(for: guest)
            // The operator may have moved on while this was in flight.
            guard participant?.id == guest.id else { return }
            freeShirt = shirt
        } catch {
            // Folded into the same warning the merch read raises rather than a
            // second line saying the same thing: both live in one subcollection
            // behind one rule, so they fail together, and one sentence about it
            // is the one somebody reads.
            Self.log.error("free-shirt load failed: \(error.localizedDescription, privacy: .public)")
            guard participant?.id == guest.id else { return }
            merchUnavailable = true
        }
    }

    /// Choose which shirt is coming off the pile, before it is handed over.
    ///
    /// Held locally until the handover is recorded: picking a size is not a
    /// write, and a desk that changed its mind three times should not have
    /// written three times.
    func chooseFreeShirt(size: String? = nil, colour: String? = nil) {
        guard var shirt = freeShirt else { return }
        if let size { shirt.size = size }
        if let colour { shirt.colour = colour }
        freeShirt = shirt
    }

    /// Hand the free shirt over, or take that back.
    func setFreeShirtHandedOver(_ handedOver: Bool) async {
        guard let guest = participant, let shirt = freeShirt, shirt.entitled else { return }
        // The rules refuse a handover with no size or colour; this is the same
        // rule on the near side of the network, where it is a disabled button
        // rather than a red banner in front of somebody holding a shirt.
        guard !handedOver || shirt.canBeHandedOver else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await repository.setFreeShirt(
                size: shirt.size,
                colour: shirt.colour,
                handedOver: handedOver,
                for: guest
            )
            guard participant?.id == guest.id else { return }
            freeShirt = updated
            ScanFeedback.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            ScanFeedback.shared.problem()
        }
    }

    private func loadMerch(for guest: Participant) async {
        isLoadingMerch = true
        defer { isLoadingMerch = false }
        do {
            let order = try await repository.merchOrder(for: guest)
            // The operator may have moved on while this was in flight. Writing
            // somebody else's t-shirt size under the name now on screen would
            // be worse than showing nothing.
            guard participant?.id == guest.id else { return }
            merch = order
            merchUnavailable = false
        } catch {
            Self.log.error("merch load failed: \(error.localizedDescription, privacy: .public)")
            guard participant?.id == guest.id else { return }
            // A line on the screen, not an alert. A t-shirt must not interrupt
            // a check-in — but silence here reads as "ordered nothing", and
            // that is how an undeployed ruleset went unnoticed once already.
            merchUnavailable = true
        }
    }

    /// Hand the merch over, or take that back.
    func setMerchCollected(_ collected: Bool) async {
        guard let guest = participant, merch?.hasSomethingToCollect == true else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await repository.setMerchCollected(collected, for: guest)
            guard participant?.id == guest.id else { return }
            merch = updated
            ScanFeedback.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            ScanFeedback.shared.problem()
        }
    }

    // MARK: - Reception: check in

    /// What the participant screen's primary button should do right now.
    ///
    /// Decided from the participant, except on the one route where the flow
    /// knows better: somebody reached from the replacement list already has a
    /// wristband, so the rule would offer a top-up, and what the desk wants is
    /// to read the chip that takes over from the lost one.
    var participantAction: CheckInAction? {
        if let override = participantActionOverride { return override }
        return participant.map(CheckInAction.decide(for:))
    }

    /// Set only by the replacement flow, and cleared with the participant.
    private(set) var participantActionOverride: CheckInAction?

    /// Somebody has lost a wristband. Start from the people who have one.
    func beginBraceletReplacement() {
        bracelet = nil
        participant = nil
        merch = nil
        freeShirt = nil
        sessionSale = nil
        sessionChoice = nil
        sessionMethod = nil
        specialSessions = []
        participantActionOverride = nil
        merchUnavailable = false
        search = ""
        replacement = BraceletReplacement()
        screen = .replaceSearch
        Task { await refreshCheckedIn() }
        Task { await refreshReplacementFee() }
    }

    /// The list is read when the flow starts rather than at sign-in: somebody
    /// checked in five minutes ago must be on it, and a terminal that has been
    /// awake since Thursday would otherwise be showing Thursday's roster.
    func refreshCheckedIn() async {
        isLoadingCheckedIn = true
        defer { isLoadingCheckedIn = false }
        do {
            checkedIn = try await repository.checkedIn()
        } catch {
            Self.log.error("checked-in list failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func refreshReplacementFee() async {
        do {
            replacementFee = try await repository.replacementFee()
        } catch {
            // A fee that cannot be read is no fee: the desk replaces the
            // wristband for nothing rather than guessing at a number to charge.
            Self.log.error("replacement fee failed: \(error.localizedDescription, privacy: .public)")
            replacementFee = nil
        }
    }

    /// Open somebody from the replacement list. Same screen a check-in uses, in
    /// the one mode that reads a chip for a person who already has one.
    func select(forReplacement guest: Participant) {
        replacement = BraceletReplacement()
        bracelet = guest.braceletId
        showParticipant(guest)
        participantActionOverride = .scanAndReplace
    }

    /// Read the fresh chip. Nothing is written until it is read, so a change of
    /// mind costs a tap rather than a wristband.
    func scanForReplacement() {
        guard participant != nil, replacement.isComplete else { return }
        beginScan(for: .replaceBracelet)
    }

    /// Mint the replacement onto the chip that has just been read.
    private func completeReplacement(_ scanned: BraceletID, existingHolder: Participant?) async {
        guard let guest = participant else {
            scan = nil
            return
        }
        if let existingHolder {
            // Nothing is lost: the reason and the fee are still on screen, so
            // the next chip out of the box finishes the same replacement.
            scan = nil
            ScanFeedback.shared.problem()
            errorMessage = "This bracelet already belongs to \(existingHolder.name). Use a fresh one."
            return
        }

        scan = nil
        isWorking = true
        defer { isWorking = false }

        do {
            let fee = replacement.fee(from: replacementFee)
            let updated = try await repository.replaceBracelet(
                scanned,
                for: guest,
                reason: replacement.trimmedReason,
                fee: fee,
                method: fee == nil ? nil : replacement.method
            )
            bracelet = scanned
            replacement = BraceletReplacement()
            participantActionOverride = nil
            showParticipant(updated)
            ScanFeedback.shared.success()
        } catch {
            errorMessage = error.localizedDescription
            ScanFeedback.shared.problem()
        }
    }

    func goToCheckInSearch() {
        bracelet = nil
        participant = nil
        merch = nil
        freeShirt = nil
        sessionSale = nil
        sessionChoice = nil
        sessionMethod = nil
        specialSessions = []
        participantActionOverride = nil
        merchUnavailable = false
        search = ""
        screen = .assign
        // The list on screen may be a day old; see `refreshRoster`.
        Task { await refreshRoster() }
    }

    /// A name was tapped on the check-in list.
    ///
    /// This no longer pairs anything. Pairing a bracelet is permanent and
    /// irreversible, and it used to happen on the first tap of a row in a
    /// scrolling list of 105 similar-looking names — one mis-tap and the wrong
    /// guest owned the chip forever, with no way back short of an organiser.
    /// Now the tap only shows who was chosen, and the pairing needs a second,
    /// deliberate action on a screen showing the name in 32pt.
    func select(candidate guest: Participant) {
        showParticipant(guest)
    }

    /// Back out of the participant screen to wherever it was reached from.
    func leaveParticipant() {
        // A door sale in progress goes back to the details it was typed into —
        // losing a name to a stray tap on "Back" would be the worst of the
        // three ways out of this screen.
        if isPendingDoorSale {
            backToDoorSaleDetails()
            return
        }
        // A guest still awaiting check-in can only have been reached from the
        // check-in list, so that is where "Back" belongs. Anyone else was
        // reached by scanning their chip, and the way out of that is home.
        if participant?.isAwaitingCheckIn == true {
            participant = nil
            merch = nil
            merchUnavailable = false
            screen = .assign
        } else {
            goHome()
        }
    }

    /// Read a chip and pair it to the participant already on screen.
    func scanToAssignBracelet() {
        guard participant?.isAwaitingCheckIn == true else { return }
        beginScan(for: .assignToSelected)
    }

    /// Pair the chip that was just read to the guest already on screen.
    ///
    /// `existingHolder` is what the reverse lookup said about the chip. Non-nil
    /// means the wristband already belongs to somebody — refuse, and say whose
    /// it is, because the operator is holding it and can put it back in the right
    /// pile. Assigning anyway is not an option: the rules allow `create` on a
    /// bracelet document and never `update`, so the server would refuse it after
    /// the desk had already said yes.
    private func pairScannedChip(_ scanned: BraceletID, existingHolder: Participant?) async {
        guard let guest = participant else {
            scan = nil
            return
        }

        if let existingHolder {
            scan = nil
            ScanFeedback.shared.problem()
            errorMessage = existingHolder.id == guest.id
                ? "\(guest.name) is already checked in with this bracelet."
                : "This bracelet already belongs to \(existingHolder.name). Use a fresh one."
            return
        }

        bracelet = scanned
        scan = nil
        ScanFeedback.shared.success()
        await assign(to: guest)
    }

    func assign(to guest: Participant) async {
        guard let bracelet else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let paired = try await repository.assignBracelet(bracelet, to: guest)
            participant = paired
            awaitingCheckIn.removeAll { $0.id == guest.id }
            receipt = Receipt(
                kind: .checkIn,
                title: "Checked in",
                note: "\(guest.name) is checked in and the bracelet is now paired to them for the whole festival.",
                rows: [
                    .init(key: "Participant", value: guest.name),
                    .init(key: "Ticket", value: guest.ticketType),
                    .init(key: "Bracelet", value: bracelet.rawValue),
                ],
                balance: paired.balance
            )
            screen = .receipt
        } catch {
            // Put the chip down. Whatever went wrong, the operator is now being
            // told about it while still holding the wristband, and leaving it
            // "in hand" would offer a one-tap retry of a pairing the server has
            // already refused — most often because the chip is a duplicate of
            // one that is paired, which retrying cannot fix.
            // `self.` because the guard above shadows the property with the
            // unwrapped chip.
            self.bracelet = nil
            errorMessage = error.localizedDescription
            ScanFeedback.shared.problem()
        }
    }

    // MARK: - Reception: door sales

    /// Start a door sale: pick the pass, take the buyer's details, then scan.
    ///
    /// The chip used to come first, on the grounds that a ticket is minted *onto*
    /// a bracelet in one write and there is nothing to sell until there is a
    /// wristband to sell it on. True of the write, wrong for the desk: it put a
    /// scan in front of a conversation that had not happened yet, and left an
    /// operator holding a wristband while somebody decided which pass they
    /// wanted and spelled their name.
    ///
    /// So the order now matches checking somebody in — decide who and what
    /// first, pair the bracelet last, as the final irreversible act. The write is
    /// still a single batch; only the order of the questions changed.
    func beginDoorSale() {
        participant = nil
        merch = nil
        freeShirt = nil
        sessionSale = nil
        sessionChoice = nil
        sessionMethod = nil
        specialSessions = []
        participantActionOverride = nil
        merchUnavailable = false
        bracelet = nil
        selectedPass = nil
        doorSale = DoorSaleDraft()
        screen = .doorPass
        Task { await refreshDoorPasses() }
    }

    /// A pass was picked from the catalogue. Where that leads depends on the
    /// pass: an evening ticket needs a night, anything else needs a buyer.
    func select(pass: DoorPass) {
        selectedPass = pass
        if pass.kind == .evening {
            eveningSelection = Evening.today ?? .friday
            screen = .assignEvening
        } else {
            // Kept rather than cleared, so picking the wrong pass and coming
            // back does not cost somebody their typing. The level is the one
            // thing that can go stale — a Party Pass has none — and
            // `DoorSaleDraft.level(for:)` drops it at the point of sale.
            screen = .doorBuyer
        }
    }

    /// Back from the buyer form, or the evening picker, to the list of passes.
    func backToPassPicker() {
        screen = .doorPass
    }

    /// Show what is about to be sold, before any wristband is touched.
    ///
    /// The provisional participant is never written and never leaves this
    /// screen: it carries a sentinel id, and every path that would use one —
    /// the merch read, the free-shirt read, a top-up — is either skipped or
    /// unreachable while `isPendingDoorSale` is true.
    func previewDoorSale() {
        guard let pass = selectedPass, doorSale.isComplete(for: pass) else { return }
        participant = Participant(
            id: Self.pendingDoorSaleId,
            ticketRef: "",
            name: doorSale.trimmedName,
            ticketType: pass.name,
            country: "",
            level: doorSale.level(for: pass),
            danceRole: doorSale.danceRole?.wire ?? "",
            source: pass.kind == .evening ? .evening : .door,
            evening: pass.kind == .evening ? eveningSelection : nil,
            // What the desk is about to collect, and how — on the last screen
            // before the money changes hands, which is the point of it.
            paymentMethod: doorSale.method,
            pricePaid: pass.kind == .evening ? pass.price(on: eveningSelection) : pass.price
        )
        merch = nil
        freeShirt = nil
        sessionSale = nil
        sessionChoice = nil
        sessionMethod = nil
        specialSessions = []
        participantActionOverride = nil
        merchUnavailable = false
        isPendingDoorSale = true
        screen = .participant
    }

    /// Not a document id anybody could have. Nothing reads it; it exists so a
    /// provisional participant cannot be mistaken for a real one in a debugger.
    private static let pendingDoorSaleId = ParticipantID("(not sold yet)")

    /// Back from the preview to the form it was built from.
    func backToDoorSaleDetails() {
        participant = nil
        isPendingDoorSale = false
        guard let pass = selectedPass else {
            screen = .doorPass
            return
        }
        screen = pass.kind == .evening ? .assignEvening : .doorBuyer
    }

    /// Everything is decided; read the wristband it is going onto.
    ///
    /// Nothing is written until that chip is read, and nothing is kept if the
    /// read is cancelled — the draft stays exactly where it was, so a wristband
    /// from the wrong pile costs one more tap rather than the buyer's details.
    func scanForDoorSale() {
        guard let pass = selectedPass else { return }
        guard doorSale.isComplete(for: pass) else { return }
        bracelet = nil
        beginScan(for: .doorSale)
    }

    /// Sell the chosen pass to the buyer on screen.
    /// Mint the sale onto the chip that has just been read.
    ///
    /// Ends on the participant screen rather than a receipt, which is what the
    /// desk wants next: a door buyer almost always loads money onto the
    /// wristband in the same conversation, and that is the screen with the
    /// button for it. The pass and the price were both on screen a moment ago,
    /// while the cash was being taken.
    private func completeDoorSale(_ scanned: BraceletID, existingHolder: Participant?) async {
        guard let pass = selectedPass else {
            scan = nil
            return
        }

        if let existingHolder {
            // Nothing is lost: the draft is untouched, so the next chip out of
            // the box finishes the same sale.
            scan = nil
            ScanFeedback.shared.problem()
            errorMessage = "This bracelet already belongs to \(existingHolder.name). Use a fresh one."
            return
        }

        bracelet = scanned
        scan = nil
        ScanFeedback.shared.success()

        isWorking = true
        defer { isWorking = false }

        do {
            let buyer: Participant
            if pass.kind == .evening {
                buyer = try await repository.createEveningTicket(
                    pass,
                    evening: eveningSelection,
                    draft: doorSale,
                    bracelet: scanned
                )
            } else {
                buyer = try await repository.createDoorPass(pass, draft: doorSale, bracelet: scanned)
            }
            selectedPass = nil
            doorSale = DoorSaleDraft()
            showParticipant(buyer)
        } catch {
            // Put the chip down, keep the sale. Whatever the server refused, it
            // refused this wristband — and the operator is still standing with
            // the buyer, whose name should not have to be typed again.
            bracelet = nil
            errorMessage = error.localizedDescription
            ScanFeedback.shared.problem()
        }
    }

    // MARK: - Reception: top up

    func confirmTopUp() async {
        guard let bracelet, let current = participant else { return }
        let amount = topUp.amount
        guard amount.isPositive else { return }
        // The button is disabled without one, so this is the second lock on the
        // same door rather than the first: `confirmTopUp` is also reachable from
        // a UI test and from LaunchOverrides, and an unmethodded top-up must not
        // be able to reach the ledger by either route.
        guard let method = topUp.method else { return }

        isWorking = true
        defer { isWorking = false }

        // One path, online or not. The repository accepts the write, gives the
        // server three seconds to object, and hands back what the local cache now
        // says — which includes the pending write. There is no separate offline
        // branch to keep in step with the real one.
        let updated: Participant
        do {
            updated = try await repository.topUp(bracelet: bracelet, amount: amount, method: method)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        participant = updated
        receipt = Receipt(
            kind: .topUp,
            title: "Balance topped up",
            note: isOffline
                ? "Saved on this device. It will sync to the festival server when the connection is back."
                : method.receiptNote,
            rows: [
                .init(key: "Participant", value: current.name),
                .init(key: "Added", value: "\(amount)"),
                .init(key: "Paid by", value: method.label),
                .init(key: "Previous balance", value: "\(current.balance)"),
            ],
            balance: updated.balance,
            queuedOffline: isOffline
        )
        topUp.clear()
        screen = .receipt
    }

    // MARK: - Bar

    func add(_ drink: Drink) {
        cart.bump(drink, by: 1)
    }

    func bump(_ drink: Drink, by delta: Int) {
        cart.bump(drink, by: delta)
        if cart.isEmpty { screen = .barMenu }
    }

    func clearCart() {
        cart.removeAll()
        screen = .barMenu
    }

    func confirmPayment() async {
        guard let bracelet, let current = participant else { return }
        guard paymentDecision?.isApproved == true else { return }
        let lines = cartLines
        let total = cartTotal

        isWorking = true
        defer { isWorking = false }

        // Same single path as a top-up. Offline the charge is accepted, queued by
        // Firestore, and shown as queued on the receipt — the drink gets served,
        // which is the decision taken deliberately: refusing sales when a venue's
        // wifi drops closes the bar mid-Saturday.
        let updated: Participant
        do {
            updated = try await repository.charge(bracelet: bracelet, lines: lines)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        participant = updated
        receipt = Receipt(
            kind: .payment,
            title: isOffline ? "Charged — queued" : "Charged",
            note: isOffline
                ? "Queued on this device and deducted locally. It syncs as soon as the bar is back online."
                : "\(current.name)’s account was debited \(total).",
            rows: lines.map { .init(key: $0.label, value: "\($0.total)") }
                + [.init(key: "Participant", value: current.name)],
            balance: updated.balance,
            queuedOffline: isOffline
        )
        cart.removeAll()
        paymentDecision = nil
        screen = .receipt
    }

    // MARK: - Navigation

    func goHome() {
        screen = role?.homeScreen ?? .signIn
        isPendingDoorSale = false
        bracelet = nil
        participant = nil
        merch = nil
        freeShirt = nil
        sessionSale = nil
        sessionChoice = nil
        sessionMethod = nil
        specialSessions = []
        participantActionOverride = nil
        merchUnavailable = false
        receipt = nil
        paymentDecision = nil
        search = ""
    }

    func goToTopUp() {
        topUp.clear()
        screen = .topUp
    }

    func backToParticipant() {
        topUp.clear()
        screen = .participant
    }

    func goToCart() { screen = .cart }

    func goToMenu() {
        screen = .barMenu
        Task { await refreshMenu() }
        bracelet = nil
        participant = nil
        merch = nil
        freeShirt = nil
        sessionSale = nil
        sessionChoice = nil
        sessionMethod = nil
        specialSessions = []
        participantActionOverride = nil
        merchUnavailable = false
        paymentDecision = nil
    }

    /// The receipt's primary button, which differs per outcome:
    /// a payment starts a new order, a top-up goes straight back to scanning,
    /// and a fresh check-in offers to load money onto the new bracelet.
    func receiptPrimaryAction() {
        guard let receipt else { return }
        switch receipt.kind {
        case .payment:
            goToMenu()
            self.receipt = nil
        case .topUp:
            // The top-up receipt's one button is Done. It used to be "Read next
            // bracelet", which began a scan from this screen.
            goHome()
        case .checkIn:
            self.receipt = nil
            goToTopUp()
        }
    }
}
