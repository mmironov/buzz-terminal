import Observation
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

    init(
        repository: TerminalRepository = InMemoryTerminalRepository(),
        reader: BraceletReader = SimulatedBraceletReader()
    ) {
        self.repository = repository
        self.reader = reader
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

    // MARK: Connectivity (prototype affordance — see `toggleOffline`)

    var isOffline = false
    var queuedTransactions = 0

    var networkLabel: String { isOffline ? "Offline" : "Online" }
    var networkDotColor: Color { isOffline ? .sbAccent : .sbNeutral600 }
    var queueLabel: String {
        queuedTransactions == 1
            ? "1 transaction waiting to sync"
            : "\(queuedTransactions) transactions waiting to sync"
    }

    // MARK: Scanning

    struct ScanState: Equatable {
        enum Purpose: Equatable { case checkInOrTopUp, payment }
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

    var waitingGuests: [WaitingGuest] = []
    var search = ""

    /// The check-in list, filtered by whatever is in the search box.
    /// The filtering itself lives on `WaitingGuest` (exercise 2).
    var candidates: [WaitingGuest] {
        waitingGuests.filter { $0.matches(query: search) }
    }

    var topUp = TopUpEntry()

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

    /// Load the catalogue once a role is known.
    func loadCatalogue() async {
        do {
            menu = try await repository.drinks()
            waitingGuests = try await repository.waitingGuests()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Auth

    func signIn() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let role = try await repository.signIn(email: email, password: password)
            self.role = role
            loginFailed = false
            password = ""
            screen = role.homeScreen
            await loadCatalogue()
        } catch {
            loginFailed = true
        }
    }

    func signOut() async {
        await repository.signOut()
        role = nil
        screen = .signIn
        password = ""
        loginFailed = false
        cart.removeAll()
        bracelet = nil
        participant = nil
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

    /// Flips the offline banner from the design.
    ///
    /// Iteration 1 fakes this: there is no reachability monitoring and no real
    /// queue, because there is no server to be disconnected from yet. What it
    /// does do is exercise every piece of offline *UI* — the banner, the queue
    /// count, the "Approved · offline" receipt band — so those are already built
    /// and reviewed when iteration 3 adds a real write-behind queue.
    func toggleOffline() {
        isOffline.toggle()
        if !isOffline { queuedTransactions = 0 }
    }

    // MARK: - Scanning

    func beginScan(for purpose: ScanState.Purpose) {
        scan = ScanState(purpose: purpose)
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
            bracelet = scanned
            participant = found
            scan = nil

            switch purpose {
            case .checkInOrTopUp:
                search = ""
                if found == nil {
                    screen = .assign
                } else if found?.isBlocked == true {
                    screen = .blocked
                } else {
                    screen = .participant
                }

            case .payment:
                paymentDecision = PaymentDecision.evaluate(participant: found, total: cartTotal)
                screen = .payReview
            }
        } catch {
            scan = nil
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Reception: check in

    func assign(to guest: WaitingGuest) async {
        guard let bracelet else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let created = try await repository.assignBracelet(bracelet, to: guest)
            participant = created
            waitingGuests.removeAll { $0.id == guest.id }
            receipt = Receipt(
                kind: .checkIn,
                title: "Checked in",
                note: "\(guest.name) is checked in and the bracelet is now paired to them for the whole festival.",
                rows: [
                    .init(key: "Participant", value: guest.name),
                    .init(key: "Ticket", value: guest.pass),
                    .init(key: "Bracelet", value: bracelet.rawValue),
                ],
                balance: created.balance
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

        isWorking = true
        defer { isWorking = false }

        let updated: Participant
        if isOffline {
            // Applied locally and counted into the queue, matching the design.
            // A real write-behind queue is iteration 3.
            var local = current
            local.balance += amount
            updated = local
            queuedTransactions += 1
        } else {
            do {
                updated = try await repository.topUp(bracelet: bracelet, amount: amount)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        participant = updated
        receipt = Receipt(
            kind: .topUp,
            title: "Balance topped up",
            note: isOffline
                ? "Saved on this device. It will sync to the festival server when the connection is back."
                : "Cash taken at reception and added to the participant’s account.",
            rows: [
                .init(key: "Participant", value: current.name),
                .init(key: "Added", value: "\(amount)"),
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

        let updated: Participant
        if isOffline {
            var local = current
            local.balance -= total
            updated = local
            queuedTransactions += 1
        } else {
            do {
                updated = try await repository.charge(bracelet: bracelet, lines: lines)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        participant = updated
        receipt = Receipt(
            kind: .payment,
            title: isOffline ? "Charged — queued" : "Charged",
            note: isOffline
                ? "Held on this device and deducted locally. It syncs as soon as the bar is back online."
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
        bracelet = nil
        participant = nil
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
            beginScan(for: .checkInOrTopUp)
        case .checkIn:
            self.receipt = nil
            goToTopUp()
        }
    }
}
