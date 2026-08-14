package fest.swingbuzz.terminal.app

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import fest.swingbuzz.terminal.data.BraceletReader
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
    val offersDemoAccounts: Boolean = repository is InMemoryTerminalRepository

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

    // ── Connectivity (prototype affordance — see [toggleOffline]) ──

    var isOffline by mutableStateOf(false)
        private set
    var queuedTransactions by mutableStateOf(0)
        private set

    val networkLabel: String get() = if (isOffline) "Offline" else "Online"
    val queueLabel: String
        get() = if (queuedTransactions == 1) {
            "1 transaction waiting to sync"
        } else {
            "$queuedTransactions transactions waiting to sync"
        }

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
    fun toggleOffline() {
        isOffline = !isOffline
        if (!isOffline) queuedTransactions = 0
    }

    // ── Scanning ──

    fun beginScan(purpose: ScanState.Purpose) {
        scan = ScanState(purpose)
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

            when (purpose) {
                ScanState.Purpose.CHECK_IN_OR_TOP_UP -> {
                    search = ""
                    screen = when {
                        found == null -> Screen.Assign
                        found.isBlocked -> Screen.Blocked
                        else -> Screen.Participant
                    }
                }

                ScanState.Purpose.PAYMENT -> {
                    paymentDecision = PaymentDecision.evaluate(found, cartTotal)
                    screen = Screen.PayReview
                }
            }
        } catch (error: Exception) {
            scan = null
            errorMessage = error.message
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
                val updated = if (isOffline) {
                    // Applied locally and counted into the queue, matching the
                    // design. A real write-behind queue comes later.
                    queuedTransactions += 1
                    current.copy(balance = current.balance + amount)
                } else {
                    repository.topUp(chip, amount)
                }

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
                val updated = if (isOffline) {
                    queuedTransactions += 1
                    current.copy(balance = current.balance - total)
                } else {
                    repository.charge(chip, lines)
                }

                participant = updated
                receipt = Receipt(
                    kind = Receipt.Kind.PAYMENT,
                    title = if (isOffline) "Charged — queued" else "Charged",
                    note = if (isOffline) {
                        "Held on this device and deducted locally. It syncs as soon as " +
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
