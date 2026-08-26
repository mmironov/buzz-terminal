package fest.swingbuzz.terminal.app

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import fest.swingbuzz.terminal.data.BraceletReader
import fest.swingbuzz.terminal.data.SyncCenter
import fest.swingbuzz.terminal.designsystem.ScanFeedback
import fest.swingbuzz.terminal.domain.FailedWrite
import fest.swingbuzz.terminal.data.InMemoryTerminalRepository
import fest.swingbuzz.terminal.data.ScanCancelled
import fest.swingbuzz.terminal.data.SimulatedBraceletReader
import fest.swingbuzz.terminal.data.TerminalRepository
import fest.swingbuzz.terminal.domain.BraceletID
import fest.swingbuzz.terminal.domain.Cart
import fest.swingbuzz.terminal.domain.CartLine
import fest.swingbuzz.terminal.domain.Drink
import fest.swingbuzz.terminal.domain.Evening
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.Participant
import fest.swingbuzz.terminal.domain.PaymentDecision
import fest.swingbuzz.terminal.domain.Receipt
import fest.swingbuzz.terminal.domain.Screen
import fest.swingbuzz.terminal.domain.SimulatedBracelet
import fest.swingbuzz.terminal.domain.StaffRole
import fest.swingbuzz.terminal.domain.TopUpEntry
import kotlinx.coroutines.launch

/**
 * The whole terminal's state and every transition between screens.
 *
 * **Why one flat [Screen] state instead of a NavHost?**
 * This is a kiosk, not a browsing app. Look at the design: no back chevron
 * anywhere, no predictive-back gesture, no title bars — each screen ends in an
 * explicit "Cancel", "Done" or "Back to order", and several transitions
 * *replace* the history rather than push onto it (a receipt must not be
 * navigable back into the payment it just committed). Modelling that as a state
 * machine makes the illegal states unreachable; modelling it as a back stack
 * would mean fighting the stack to forbid what it does naturally.
 *
 * Compose's snapshot state does the same job SwiftUI's `@Observable` does: each
 * composable re-runs only for the properties it actually reads, so typing in
 * [search] does not redraw the bar menu.
 */
class AppModel(
    private val repository: TerminalRepository = InMemoryTerminalRepository(),
    private val reader: BraceletReader = SimulatedBraceletReader(),
    /**
     * Queued writes, refused writes, and whether the backend is reachable.
     *
     * Shared with the repository, which is what reports into it — the model only
     * reads. Kept out of [AppModel] because a refused charge has to survive the app
     * being force-stopped, and screen state does not.
     */
    val sync: SyncCenter = SyncCenter(null),
    /** Sound and haptics for a scan. Null in tests and previews. */
    private val feedback: ScanFeedback? = null,
) : ViewModel() {

    /**
     * Whether the demo-account shortcuts mean anything.
     *
     * They fill fixture credentials that only [InMemoryTerminalRepository]
     * recognises. Against Firebase they cannot succeed, so offering them there
     * is an invitation to misread a real authentication failure as a broken app
     * — which is exactly what happened the first time the iOS app ran against
     * production.
     */
    val offersDemoAccounts: Boolean get() = runsOnFixtures

    /**
     * Whether `SampleData` is what the app is actually talking to.
     *
     * Anything the fixtures *say* about the world — the demo credentials, the
     * descriptions beside the simulated chips — is only true when this is true.
     * Displaying it regardless is how a correct app comes to look broken: the
     * chip labelled "fresh, not yet assigned" is a real, checked-in guest on
     * Firestore, and the screen that says so reads as a bug.
     */
    val runsOnFixtures: Boolean = repository is InMemoryTerminalRepository

    // ── Session ──

    val festivalName = "Swing Buzz Festival"
    var role by mutableStateOf<StaffRole?>(null)
        private set
    var screen by mutableStateOf<Screen>(Screen.SignIn)
        private set

    var email by mutableStateOf("")
    var password by mutableStateOf("")
    var loginFailed by mutableStateOf(false)
        private set
    var isWorking by mutableStateOf(false)
        private set

    /**
     * Surfaced as a dialog. Distinct from [loginFailed], which the design draws
     * inline under the password field.
     */
    var errorMessage by mutableStateOf<String?>(null)

    /** What the inline sign-in error says. Whatever actually failed, verbatim. */
    var signInErrorText by mutableStateOf<String?>(null)
        private set

    // ── Connectivity ──

    /**
     * Real, from Firestore's own opinion of whether it is talking to a server — not
     * a manual toggle, and not a guess from a connectivity callback, which cannot
     * tell a working network from a venue access point that routes nowhere.
     */
    val isOffline: Boolean get() = sync.state.isOffline

    /** Writes accepted at the till and not yet acknowledged. */
    val queuedTransactions: Int get() = sync.state.pending

    /**
     * Writes the server refused after the operator had already been told they
     * worked. Money that went missing, and the reason this queue has a UI at all.
     */
    val failedWrites: List<FailedWrite> get() = sync.state.unsettledFailures

    val networkLabel: String get() = if (isOffline) "Offline" else "Online"

    /** One line for the banner, or null when there is nothing worth saying. */
    val syncMessage: String? get() = sync.state.bannerMessage
    val syncIsAlarming: Boolean get() = sync.state.bannerIsAlarming

    /** Kept for the views that still read it. */
    val queueLabel: String get() = syncMessage ?: ""

    fun settleFailure(id: java.util.UUID) = sync.settle(id)

    // ── Scanning ──

    data class ScanState(val purpose: Purpose, val isReading: Boolean = false) {
        enum class Purpose { CHECK_IN_OR_TOP_UP, PAYMENT }
    }

    var scan by mutableStateOf<ScanState?>(null)
        private set

    val isScanning: Boolean get() = scan != null
    val readerIsHardwareBacked: Boolean get() = reader.isHardwareBacked
    val simulatedBracelets: List<SimulatedBracelet> get() = reader.simulatedOptions

    // ── Current bracelet ──

    var bracelet by mutableStateOf<BraceletID?>(null)
        private set
    var participant by mutableStateOf<Participant?>(null)
        private set

    val braceletLabel: String get() = bracelet?.rawValue ?: "—"

    // ── Reception ──

    /** Everybody on the roster without a bracelet yet. */
    var awaitingCheckIn by mutableStateOf<List<Participant>>(emptyList())
        private set
    var search by mutableStateOf("")

    /**
     * The check-in list, filtered by whatever is in the search box.
     * The filtering itself lives on `Participant.matches(query)`.
     */
    val candidates: List<Participant> get() = awaitingCheckIn.filter { it.matches(search) }

    var topUp by mutableStateOf(TopUpEntry())
        private set

    /**
     * Which evening a door sale is for. Preselected to tonight when tonight is
     * one of the three — a convenience, never a validation.
     */
    var eveningSelection by mutableStateOf(Evening.today() ?: Evening.FRIDAY)

    // ── Bar ──

    var menu by mutableStateOf<List<Drink>>(emptyList())
        private set
    var cart by mutableStateOf(Cart())
        private set

    val cartLines: List<CartLine> get() = cart.lines(menu)
    val cartTotal: Money get() = cart.total(menu)
    val cartCountLabel: String get() = "${cart.itemCount} items"

    /**
     * Recomputed whenever the pay-review screen is shown. The decision logic
     * itself lives on [PaymentDecision].
     */
    var paymentDecision by mutableStateOf<PaymentDecision?>(null)
        private set

    // ── Receipt ──

    var receipt by mutableStateOf<Receipt?>(null)
        private set

    // ── Lifecycle ──

    /** Load the catalogue once a role is known. */
    private suspend fun loadCatalogue() {
        try {
            menu = repository.drinks()
            awaitingCheckIn = repository.awaitingCheckIn()
            // Logged because "the list is empty" has two very different causes —
            // an empty roster, or a read the rules refused — and they look
            // identical on screen.
            Log.i(TAG, "loaded ${menu.size} drinks, ${awaitingCheckIn.size} awaiting check-in")
        } catch (error: Exception) {
            Log.e(TAG, "catalogue load failed", error)
            errorMessage = error.message
        }
    }

    // ── Auth ──

    fun signIn() {
        if (isWorking) return
        viewModelScope.launch {
            isWorking = true
            try {
                val signedIn = repository.signIn(email, password)
                role = signedIn
                loginFailed = false
                signInErrorText = null
                password = ""
                screen = signedIn.homeScreen
                // Only now: the rules refuse an unauthenticated listener, so
                // starting this before sign-in would report "offline" for a
                // perfectly healthy network.
                repository.startMonitoringConnectivity()
                loadCatalogue()
            } catch (error: Exception) {
                // Report what actually failed rather than a house error: at the
                // desk, "no role assigned" and "wrong password" need different
                // people to fix them.
                loginFailed = true
                signInErrorText = error.message ?: "Sign-in failed."
            } finally {
                isWorking = false
            }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            repository.signOut()
            role = null
            screen = Screen.SignIn
            password = ""
            loginFailed = false
            signInErrorText = null
            cart = cart.cleared()
            bracelet = null
            participant = null
            receipt = null
            paymentDecision = null
            search = ""
            topUp = topUp.cleared()
        }
    }

    fun fillDemoAccount(role: StaffRole) {
        email = if (role == StaffRole.RECEPTION) {
            "reception@swingbuzz.fest"
        } else {
            "bar@swingbuzz.fest"
        }
        password = "festival26"
        loginFailed = false
        signInErrorText = null
    }

    /**
     * Flips the offline banner from the design.
     *
     * Faked for now: there is no reachability monitoring and no real queue. What
     * it does do is exercise every piece of offline *UI* — the banner, the queue
     * count, the "Approved · offline" receipt band — so those are already built
     * and reviewed when a real write-behind queue lands.
     */
    /**
     * Cut Firestore off from the network, or restore it.
     *
     * No longer a fake. It used to flip a banner and a counter; it now disables
     * Firestore's transport, which is the only practical way to rehearse the queue —
     * aeroplane mode also drops adb, and a venue's bad wifi cannot be summoned on
     * demand. Writes keep being accepted while it is off and replay when it returns.
     */
    fun toggleOffline() {
        val goingOffline = !isOffline
        viewModelScope.launch { repository.setNetworkEnabled(!goingOffline) }
    }

    // ── Scanning ──

    fun beginScan(purpose: ScanState.Purpose) {
        scan = ScanState(purpose)
        freshChip = BraceletID.fresh()
        // Cleared, not left standing: a chip checked in a moment ago would
        // otherwise still read "Not assigned" until the fresh reads land.
        simulatedChipStatus = emptyMap()

        // With hardware there is nothing to tap, so the read starts itself. The
        // prototype panel waits for `selectSimulatedBracelet`; a chip does not.
        if (readerIsHardwareBacked) {
            viewModelScope.launch { scanWithHardware() }
            return
        }

        if (!runsOnFixtures) viewModelScope.launch { loadSimulatedChipStatuses() }
    }

    /**
     * Wait for a real chip, then resolve it exactly as a simulated read does.
     *
     * Unlike iOS there is no system sheet over the top: reader mode suppresses the
     * platform's own animation, so the app's overlay is what the operator sees for
     * the whole scan.
     */
    private suspend fun scanWithHardware() {
        val state = scan ?: return
        scan = state.copy(isReading = true)
        try {
            resolveScan(reader.read(null), state.purpose)
        } catch (e: ScanCancelled) {
            // The operator cancelled. Not a fault, and not worth an error dialog.
            scan = null
        } catch (e: Exception) {
            scan = null
            errorMessage = e.message
            feedback?.problem()
        }
    }

    /**
     * What the backend says about each simulated chip, keyed by chip id.
     *
     * Empty on the fixtures, where `SampleData`'s own hints are the truth and
     * need no lookup.
     */
    var simulatedChipStatus by mutableStateOf<Map<BraceletID, String>>(emptyMap())
        private set

    /**
     * A chip id nothing has ever seen, regenerated every time the overlay opens.
     *
     * The five fixture chips are a fixed list, so against a real backend the
     * first check-in consumes one permanently — after which "scan a new
     * bracelet" cannot be rehearsed again without resetting the database. This
     * row is the way back: a fresh id every time, guaranteed unassigned.
     */
    var freshChip by mutableStateOf(BraceletID.fresh())
        private set

    /**
     * One point read per simulated chip, so the panel can say what is actually
     * true rather than what `SampleData` wishes were true.
     */
    private suspend fun loadSimulatedChipStatuses() {
        val statuses = mutableMapOf<BraceletID, String>()
        for (chip in simulatedBracelets.map { it.id }) {
            try {
                val found = repository.participantWithBracelet(chip)
                statuses[chip] = when {
                    found == null -> "Not assigned"
                    found.isBlocked -> "${found.name} · blocked"
                    else -> "${found.name} · ${found.balance}"
                }
            } catch (_: Exception) {
                // A chip whose status could not be read is left unlabelled rather
                // than guessed at — the whole point of this panel is that it stops
                // claiming things it does not know.
            }
        }
        simulatedChipStatus = statuses
    }

    fun cancelScan() {
        scan = null
    }

    /** The operator tapped a fixture bracelet in the prototype panel. */
    fun selectSimulatedBracelet(id: BraceletID) {
        val state = scan ?: return
        scan = state.copy(isReading = true)

        viewModelScope.launch {
            try {
                resolveScan(reader.read(id), state.purpose)
            } catch (_: ScanCancelled) {
                scan = null
            } catch (error: Exception) {
                scan = null
                errorMessage = error.message
            }
        }
    }

    private suspend fun resolveScan(scanned: BraceletID, purpose: ScanState.Purpose) {
        try {
            val found = repository.participantWithBracelet(scanned)
            bracelet = scanned
            participant = found
            scan = null

            // Sound and haptics, so the answer arrives before anybody can look up.
            // A bartender's eyes are on the guest and a queue; reception's hands are
            // on somebody's wrist.
            when (purpose) {
                ScanState.Purpose.CHECK_IN_OR_TOP_UP -> {
                    search = ""
                    screen = when {
                        // Not an error: an unpaired chip at reception is a check-in
                        // about to happen, which is the desk's whole job.
                        found == null -> Screen.Assign
                        found.isBlocked -> Screen.Blocked
                        else -> Screen.Participant
                    }
                    if (found?.isBlocked == true) feedback?.blocked() else feedback?.success()
                }

                ScanState.Purpose.PAYMENT -> {
                    val decision = PaymentDecision.evaluate(found, cartTotal)
                    paymentDecision = decision
                    screen = Screen.PayReview
                    when (decision) {
                        is PaymentDecision.Approved -> feedback?.success()
                        is PaymentDecision.Blocked -> feedback?.blocked()
                        PaymentDecision.NotAssigned,
                        is PaymentDecision.InsufficientFunds -> feedback?.problem()
                    }
                }
            }
        } catch (error: Exception) {
            scan = null
            errorMessage = error.message
            feedback?.problem()
        }
    }

    // ── Reception: check in ──

    fun assign(guest: Participant) {
        val chip = bracelet ?: return
        if (isWorking) return
        viewModelScope.launch {
            isWorking = true
            try {
                val paired = repository.assignBracelet(chip, guest)
                participant = paired
                awaitingCheckIn = awaitingCheckIn.filterNot { it.id == guest.id }
                receipt = Receipt(
                    kind = Receipt.Kind.CHECK_IN,
                    title = "Checked in",
                    note = "${guest.name} is checked in and the bracelet is now paired to " +
                        "them for the whole festival.",
                    rows = listOf(
                        Receipt.Row("Participant", guest.name),
                        Receipt.Row("Ticket", guest.ticketType),
                        Receipt.Row("Bracelet", chip.rawValue),
                    ),
                    balance = paired.balance,
                )
                screen = Screen.Receipt
            } catch (error: Exception) {
                errorMessage = error.message
            } finally {
                isWorking = false
            }
        }
    }

    // ── Reception: door sales ──

    fun goToAssignEvening() {
        eveningSelection = Evening.today() ?: Evening.FRIDAY
        screen = Screen.AssignEvening
    }

    /**
     * Cancelling a door sale. Back to the check-in list rather than home,
     * because the bracelet on the desk has still been scanned and is still the
     * thing being dealt with.
     */
    fun backToAssign() {
        screen = Screen.Assign
    }

    /**
     * Sell an evening ticket on the bracelet that was just scanned.
     *
     * Anonymous: nothing is asked of the guest and nothing is stored about them.
     * The receipt shows the generated label so reception has something to say
     * and something to reconcile a cash count against.
     */
    fun assignEveningTicket() {
        val chip = bracelet ?: return
        if (isWorking) return
        viewModelScope.launch {
            isWorking = true
            try {
                val ticket = repository.createEveningTicket(eveningSelection, chip)
                participant = ticket
                receipt = Receipt(
                    kind = Receipt.Kind.CHECK_IN,
                    title = "Evening ticket assigned",
                    note = "${ticket.name} is paired to this bracelet. Valid for " +
                        "${eveningSelection.label} — an organiser freezes it afterwards " +
                        "from the admin panel.",
                    rows = listOf(
                        Receipt.Row("Ticket", ticket.ticketDescription),
                        Receipt.Row("Label", ticket.name),
                        Receipt.Row("Bracelet", chip.rawValue),
                    ),
                    balance = ticket.balance,
                )
                screen = Screen.Receipt
            } catch (error: Exception) {
                errorMessage = error.message
            } finally {
                isWorking = false
            }
        }
    }

    // ── Reception: top up ──

    fun pressTopUp(key: TopUpEntry.Key) {
        topUp = topUp.press(key)
    }

    fun applyTopUpPreset(preset: Money) {
        topUp = topUp.applying(preset)
    }

    fun confirmTopUp() {
        val chip = bracelet ?: return
        val current = participant ?: return
        val amount = topUp.amount
        if (!amount.isPositive || isWorking) return

        viewModelScope.launch {
            isWorking = true
            try {
                // One path, online or not. The repository accepts the write, gives
                // the server three seconds to object, and hands back what the local
                // cache now says — which includes the pending write. There is no
                // separate offline branch to keep in step with the real one.
                val updated = repository.topUp(chip, amount)

                participant = updated
                receipt = Receipt(
                    kind = Receipt.Kind.TOP_UP,
                    title = "Balance topped up",
                    note = if (isOffline) {
                        "Saved on this device. It will sync to the festival server when " +
                            "the connection is back."
                    } else {
                        "Cash taken at reception and added to the participant’s account."
                    },
                    rows = listOf(
                        Receipt.Row("Participant", current.name),
                        Receipt.Row("Added", "$amount"),
                        Receipt.Row("Previous balance", "${current.balance}"),
                    ),
                    balance = updated.balance,
                    queuedOffline = isOffline,
                )
                topUp = topUp.cleared()
                screen = Screen.Receipt
            } catch (error: Exception) {
                errorMessage = error.message
            } finally {
                isWorking = false
            }
        }
    }

    // ── Bar ──

    fun add(drink: Drink) {
        cart = cart.bump(drink, 1)
    }

    fun bump(drink: Drink, by: Int) {
        cart = cart.bump(drink, by)
        if (cart.isEmpty) screen = Screen.BarMenu
    }

    fun clearCart() {
        cart = cart.cleared()
        screen = Screen.BarMenu
    }

    fun confirmPayment() {
        val chip = bracelet ?: return
        val current = participant ?: return
        if (paymentDecision?.isApproved != true || isWorking) return

        val lines = cartLines
        val total = cartTotal

        viewModelScope.launch {
            isWorking = true
            try {
                // Same single path as a top-up. Offline the charge is accepted,
                // queued by Firestore, and shown as queued on the receipt — the
                // drink gets served, which is the decision taken deliberately:
                // refusing sales when a venue's wifi drops closes the bar
                // mid-Saturday.
                val updated = repository.charge(chip, lines)

                participant = updated
                receipt = Receipt(
                    kind = Receipt.Kind.PAYMENT,
                    title = if (isOffline) "Charged — queued" else "Charged",
                    note = if (isOffline) {
                        "Queued on this device and deducted locally. It syncs as soon as " +
                            "the bar is back online."
                    } else {
                        "${current.name}’s account was debited $total."
                    },
                    rows = lines.map { Receipt.Row(it.label, "${it.total}") } +
                        Receipt.Row("Participant", current.name),
                    balance = updated.balance,
                    queuedOffline = isOffline,
                )
                cart = cart.cleared()
                paymentDecision = null
                screen = Screen.Receipt
            } catch (error: Exception) {
                errorMessage = error.message
            } finally {
                isWorking = false
            }
        }
    }

    // ── Navigation ──

    fun goHome() {
        screen = role?.homeScreen ?: Screen.SignIn
        bracelet = null
        participant = null
        receipt = null
        paymentDecision = null
        search = ""
    }

    fun goToTopUp() {
        topUp = topUp.cleared()
        screen = Screen.TopUp
    }

    fun backToParticipant() {
        topUp = topUp.cleared()
        screen = Screen.Participant
    }

    fun goToCart() {
        screen = Screen.Cart
    }

    fun goToMenu() {
        screen = Screen.BarMenu
        bracelet = null
        participant = null
        paymentDecision = null
    }

    /**
     * The receipt's primary button, which differs per outcome: a payment starts
     * a new order, a top-up goes straight back to scanning, and a fresh check-in
     * offers to load money onto the new bracelet.
     */
    fun receiptPrimaryAction() {
        when (receipt?.kind ?: return) {
            Receipt.Kind.PAYMENT -> {
                goToMenu()
                receipt = null
            }

            Receipt.Kind.TOP_UP -> {
                receipt = null
                beginScan(ScanState.Purpose.CHECK_IN_OR_TOP_UP)
            }

            Receipt.Kind.CHECK_IN -> {
                receipt = null
                goToTopUp()
            }
        }
    }

    private companion object {
        const val TAG = "BuzzTerminal"
    }
}
