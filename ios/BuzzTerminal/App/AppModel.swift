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
            /// A door sale: mint a pass — anonymous evening ticket or a full
            /// pass with a buyer — onto a fresh chip. A chip that already
            /// belongs to somebody is refused.
            case doorSale
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
        guard case .assignToSelected = purpose, let guest = participant else { return nil }
        return "Hold a fresh bracelet to the top of the phone to pair it with \(guest.name)."
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

            case .doorSale:
                if let found {
                    // Minting a ticket onto an owned chip would either be
                    // refused by the rules or, worse, hand a guest's balance to
                    // an anonymous door sale. Refuse it here, by name.
                    bracelet = nil
                    participant = nil
                    merch = nil
                    merchUnavailable = false
                    ScanFeedback.shared.problem()
                    errorMessage = "This bracelet already belongs to \(found.name). Use a fresh one."
                } else {
                    // Which pass comes next, because the catalogue decides
                    // whether this sale needs a buyer at all.
                    eveningSelection = Evening.today ?? .friday
                    doorSale = DoorSaleDraft()
                    selectedPass = nil
                    screen = .doorPass
                    ScanFeedback.shared.success()
                }

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

    /// Show a participant, and start loading what they preordered.
    ///
    /// One funnel for both routes to the screen — a scan and a name off the
    /// check-in list — so neither can forget the merch read.
    private func showParticipant(_ guest: Participant) {
        participant = guest
        merch = nil
        merchUnavailable = false
        screen = .participant
        Task { await loadMerch(for: guest) }
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
    /// The rule itself is pure and lives on `CheckInAction`.
    var participantAction: CheckInAction? {
        participant.map(CheckInAction.decide(for:))
    }

    /// Enter check-in from the home screen, with no chip read yet.
    ///
    /// The other way in is still a scan: an unpaired chip lands on the same list
    /// with `bracelet` already set. The list does not care which happened; the
    /// participant screen does, and asks `CheckInAction`.
    func goToCheckInSearch() {
        bracelet = nil
        participant = nil
        merch = nil
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

    /// Start a door sale: read a chip, then pick the evening.
    ///
    /// Chip first because an evening ticket is *minted onto* a bracelet in a
    /// single write — there is no ticket to sell until there is a wristband to
    /// put it on. The evening is chosen afterwards, on `AssignEveningTicketView`.
    func beginDoorSale() {
        participant = nil
        merch = nil
        merchUnavailable = false
        bracelet = nil
        selectedPass = nil
        doorSale = DoorSaleDraft()
        // Alongside the scan rather than before it: the chip read takes about a
        // second on hardware, which is plenty for six documents, and nobody
        // should wait on a price list to hold a wristband to a phone.
        Task { await refreshDoorPasses() }
        beginScan(for: .doorSale)
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

    /// Back from the buyer form to the list of passes.
    func backToPassPicker() {
        screen = .doorPass
    }

    /// Sell the chosen pass to the buyer on screen.
    func confirmDoorSale() async {
        guard let bracelet, let pass = selectedPass else { return }
        guard doorSale.isComplete(for: pass) else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            let buyer = try await repository.createDoorPass(
                pass,
                draft: doorSale,
                bracelet: bracelet
            )
            participant = buyer
            receipt = Receipt(
                kind: .checkIn,
                title: "\(pass.name) sold",
                // The price is on the receipt because the desk has to collect
                // it, and nothing else in the app will ever mention it again.
                note: pass.price.isPositive
                    ? "Take \(pass.price) at the desk. The bracelet is paired to \(buyer.name) for the whole festival."
                    : "This pass has no price set in the admin panel. The bracelet is paired to \(buyer.name).",
                rows: [
                    .init(key: "Buyer", value: buyer.name),
                    .init(key: "Pass", value: pass.name),
                    .init(key: "To collect", value: pass.priceLabel),
                    .init(key: "Dances", value: buyer.danceRoleForDisplay ?? "—"),
                ]
                + (buyer.levelForDisplay.map { [Receipt.Row(key: "Level", value: $0)] } ?? [])
                + [.init(key: "Bracelet", value: bracelet.rawValue)],
                balance: buyer.balance
            )
            selectedPass = nil
            doorSale = DoorSaleDraft()
            screen = .receipt
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sell an evening ticket on the bracelet that was just scanned.
    ///
    /// Anonymous: nothing is asked of the guest and nothing is stored about them.
    /// The receipt shows the generated label so reception has something to say and
    /// something to reconcile a cash count against.
    func assignEveningTicket() async {
        guard let bracelet else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let ticket = try await repository.createEveningTicket(
                evening: eveningSelection,
                bracelet: bracelet
            )
            participant = ticket
            receipt = Receipt(
                kind: .checkIn,
                title: "Evening ticket assigned",
                note: "\(ticket.name) is paired to this bracelet. Valid for \(eveningSelection.label) — an organiser freezes it afterwards from the admin panel.",
                rows: [
                    .init(key: "Ticket", value: ticket.ticketDescription),
                    .init(key: "Label", value: ticket.name),
                    .init(key: "Bracelet", value: bracelet.rawValue),
                ],
                balance: ticket.balance
            )
            screen = .receipt
        } catch {
            errorMessage = error.localizedDescription
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
        bracelet = nil
        participant = nil
        merch = nil
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
            self.receipt = nil
            beginScan(for: .identify)
        case .checkIn:
            self.receipt = nil
            goToTopUp()
        }
    }
}
