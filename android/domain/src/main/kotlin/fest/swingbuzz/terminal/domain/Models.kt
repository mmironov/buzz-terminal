package fest.swingbuzz.terminal.domain

import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

// ─── Staff ──────────────────────────────────────────────────────────────────

/**
 * Which terminal mode a signed-in staff member gets. The festival runs the same
 * binary at reception and behind the bar; the account decides the flow.
 *
 * This comes from a Firebase Auth custom claim, not from anything the client
 * chooses — see `docs/firestore-schema.md`, "Roles".
 */
enum class StaffRole(val wire: String, val label: String) {
    RECEPTION("reception", "Reception"),
    BAR("bar", "Bar");

    /**
     * Caption under the device frame in the design; also the screen a fresh
     * sign-in lands on.
     */
    val homeScreen: Screen
        get() = when (this) {
            RECEPTION -> Screen.ReceptionHome
            BAR -> Screen.BarMenu
        }

    companion object {
        /** The claim value as Firebase hands it back, or null if it is neither. */
        fun fromWire(value: String?): StaffRole? = entries.firstOrNull { it.wire == value }
    }
}

// ─── Screens ────────────────────────────────────────────────────────────────

/**
 * Every distinct state the terminal UI can be in.
 *
 * A flat sealed hierarchy rather than a NavHost route graph, for the same
 * reason the iOS side is a flat enum rather than a `NavigationStack` — a till
 * is a state machine, not a browsing history, and "back" means different things
 * on different screens.
 */
sealed interface Screen {
    data object SignIn : Screen

    // Reception
    data object ReceptionHome : Screen
    data object Assign : Screen

    /** Selling a door ticket, reached from the check-in screen. */
    data object AssignEvening : Screen
    data object Participant : Screen
    data object Blocked : Screen
    data object TopUp : Screen

    // Bar
    data object BarMenu : Screen
    data object Cart : Screen
    data object PayReview : Screen

    // Shared
    data object Receipt : Screen
}

// ─── Identifiers ────────────────────────────────────────────────────────────

/** The NFC chip UID, as printed in the design (`04:B4:2F:11`). */
@JvmInline
value class BraceletID(val rawValue: String) {
    override fun toString() = rawValue

    companion object {
        /**
         * A chip id in the same four-byte shape a real NFC UID has, random enough
         * that the backend has certainly never seen it.
         *
         * Exists so "scan a new bracelet" stays rehearsable against a live
         * database. The fixture chips are a fixed list, and pairing is permanent
         * by design, so checking one in retires it for good.
         */
        fun fresh(random: kotlin.random.Random = kotlin.random.Random): BraceletID =
            BraceletID(
                (1..4).joinToString(":") { "%02X".format(random.nextInt(256)) }
            )
    }
}

/**
 * Identity of a person on the roster — the Firestore document id, derived from
 * the Google Sheet's stable ticket reference.
 *
 * Distinct from [BraceletID] on purpose. These were once the same thing, because
 * a participant only existed once a chip was paired to them. The roster now
 * comes from the Sheet, so a participant exists from the moment they buy a
 * ticket and the bracelet is something that happens to them later.
 */
@JvmInline
value class ParticipantID(val rawValue: String) {
    override fun toString() = rawValue
}

/**
 * A bracelet the prototype can simulate reading. Real NFC scanning lands later;
 * until then `SimulatedBraceletReader` picks from this list.
 */
data class SimulatedBracelet(
    val id: BraceletID,
    /** Human hint shown in the prototype-only simulator panel. */
    val hint: String,
)

// ─── Tickets ────────────────────────────────────────────────────────────────

/**
 * The six pass types the festival sells.
 *
 * Kept as strings rather than an enum because `ticketType` on an imported
 * participant is whatever the registrations Sheet says, and an unrecognised
 * value must still display rather than crash. These constants are the canonical
 * spellings — used to mint evening tickets and to check what the Sheet contains.
 */
object TicketType {
    const val PARTY_PASS = "Party Pass"
    const val PARTY_PASS_PLUS = "Party Pass Plus"
    const val FULL_PASS = "Full Pass"
    const val FULL_PASS_GOLD = "Full Pass Gold"
    const val JAZZ_PERFORMANCE_TRACK = "Jazz Performance Track"

    /** Sold at the door, not present in the Sheet. See [Evening]. */
    const val EVENING_TICKET = "Evening Ticket"

    val all = listOf(
        PARTY_PASS, PARTY_PASS_PLUS, FULL_PASS, FULL_PASS_GOLD,
        JAZZ_PERFORMANCE_TRACK, EVENING_TICKET,
    )
}

/**
 * Which evening a door-sold ticket was bought for.
 *
 * Recorded for reporting and for what reception sees on screen. Deliberately
 * **not** enforced anywhere: organisers freeze an expired ticket by hand from
 * the admin panel, using the same `isBlocked` mechanism as any other bracelet.
 * That keeps the app free of date arithmetic and the rules free of a fifth
 * refusal case.
 */
enum class Evening(val wire: String, val label: String) {
    FRIDAY("friday", "Friday"),
    SATURDAY("saturday", "Saturday"),
    SUNDAY("sunday", "Sunday");

    companion object {
        fun fromWire(value: String?): Evening? = entries.firstOrNull { it.wire == value }

        /**
         * Today's evening, when today is one of the three. Used only to preselect
         * the right button, never to validate anything.
         */
        fun today(clock: () -> LocalDate = { LocalDate.now() }): Evening? =
            when (clock().dayOfWeek) {
                DayOfWeek.FRIDAY -> FRIDAY
                DayOfWeek.SATURDAY -> SATURDAY
                DayOfWeek.SUNDAY -> SUNDAY
                else -> null
            }
    }
}

// ─── People ─────────────────────────────────────────────────────────────────

/**
 * Somebody who bought a ticket.
 *
 * One type for the whole lifecycle. `braceletId == null` *is* the "arrived but
 * not checked in yet" state — there is no separate `WaitingGuest`, because the
 * roster comes from the Sheet and everybody on it is a participant from the
 * moment they buy a ticket. This mirrors `participants/{id}` in Firestore
 * exactly, so the mapping layer has nothing to reconcile.
 */
data class Participant(
    // ── Roster ──
    val id: ParticipantID,
    /** As printed on their ticket, or `EV-FRIDAY-14` for a door sale. */
    val ticketRef: String,
    /**
     * For an evening ticket this is the generated label, e.g. "Evening #14" —
     * not a person's name. Evening tickets are anonymous by design.
     */
    val name: String,
    /** One of [TicketType.all], or whatever the Sheet said. */
    val ticketType: String,
    val country: String,

    val source: Source = Source.SHEET,
    /** Set only on door-sold tickets. */
    val evening: Evening? = null,
    /** The nth evening ticket sold that evening. Drives [name]. */
    val eveningNumber: Int? = null,

    // ── Festival state: owned by the terminals ──
    /** `null` until reception pairs a chip. Permanent once set. */
    val braceletId: BraceletID? = null,
    val checkedInAt: Instant? = null,
    val balance: Money = Money.ZERO,

    // ── Organiser state: owned by the admin panel ──
    val isBlocked: Boolean = false,
    /** Why an organiser froze the bracelet, shown verbatim on the blocked screen. */
    val blockReason: String? = null,
) {

    /** Where this participant came from. Decides who owns their roster fields. */
    enum class Source(val wire: String) {
        /** Imported from the registrations Sheet. Roster fields are import-only. */
        SHEET("sheet"),

        /** Sold at the door by reception. Anonymous; there is no Sheet row. */
        EVENING("evening");

        companion object {
            fun fromWire(value: String?): Source =
                entries.firstOrNull { it.wire == value } ?: SHEET
        }
    }

    /** The check-in list is everybody this is true for. */
    val isAwaitingCheckIn: Boolean get() = braceletId == null

    val isEveningTicket: Boolean get() = source == Source.EVENING

    /** `"Evening ticket · Friday"` for a door sale, otherwise the pass type. */
    val ticketDescription: String
        get() = evening?.let { "Evening ticket · ${it.label}" } ?: ticketType

    /**
     * `"Checked in Fri 17:12"`, or `"Checked in just now"` immediately after
     * pairing — the design distinguishes the two.
     */
    val checkedInLabel: String
        get() {
            val at = checkedInAt ?: return "Not checked in"
            if (Duration.between(at, Instant.now()).seconds < 120) return "Checked in just now"
            return "Checked in ${CHECK_IN_FORMATTER.format(at)}"
        }

    /**
     * Case-insensitive substring match against the guest's name or their ticket
     * type. Deliberately *not* the city: the row displays it, but the field's
     * placeholder only promises "participant or ticket".
     *
     * Note that a query of `"pass"` matches every guest, since every ticket
     * type ends in it. Acceptable for a list this short; a real desk would
     * probably want the ticket match to be prefix-only.
     */
    fun matches(query: String): Boolean {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return true
        return name.contains(trimmed, ignoreCase = true) ||
            ticketType.contains(trimmed, ignoreCase = true)
    }

    companion object {
        /**
         * `"Fri 17:12"`. 24-hour regardless of device settings, because the design
         * shows it that way and staff read these out to each other across a room.
         */
        private val CHECK_IN_FORMATTER: DateTimeFormatter =
            DateTimeFormatter.ofPattern("EEE HH:mm").withZone(ZoneId.systemDefault())

        /**
         * Mint a door-sold evening ticket, already paired to a bracelet.
         *
         * The id encodes the sequence, so Firestore enforces uniqueness on
         * `create`: two reception desks selling at the same moment collide on
         * `ev-friday-14` and the loser retries with 15. No counter document, no
         * coordination.
         */
        fun eveningTicket(
            evening: Evening,
            number: Int,
            bracelet: BraceletID,
            checkedInAt: Instant = Instant.now(),
        ) = Participant(
            id = ParticipantID("ev-${evening.wire}-$number"),
            ticketRef = "EV-${evening.wire.uppercase()}-$number",
            name = "Evening #$number",
            ticketType = TicketType.EVENING_TICKET,
            country = "",
            source = Source.EVENING,
            evening = evening,
            eveningNumber = number,
            braceletId = bracelet,
            checkedInAt = checkedInAt,
            balance = Money.ZERO,
        )
    }
}

// ─── Bar ────────────────────────────────────────────────────────────────────

data class Drink(
    val id: String,
    val name: String,
    val price: Money,
)

/** One line of the current round: a drink and how many of it. */
data class CartLine(
    val drink: Drink,
    val quantity: Int,
) {
    val id: String get() = drink.id
    val total: Money get() = drink.price * quantity

    /** `"2 × Draught beer"` as in the design. */
    val label: String get() = "$quantity × ${drink.name}"
    val unitLabel: String get() = "${drink.price} each"
}

/**
 * The bar's current round, keyed by drink id.
 *
 * Immutable, unlike the Swift struct's `mutating func bump` — [bump] returns the
 * next cart. Same semantics, and it is what a Compose state holder wants.
 */
data class Cart(private val quantities: Map<String, Int> = emptyMap()) {

    val isEmpty: Boolean get() = quantities.values.all { it <= 0 }
    val itemCount: Int get() = quantities.values.sum()

    fun quantity(of: Drink): Int = quantities[of.id] ?: 0

    /** Lines in menu order, so the cart does not reshuffle as staff tap. */
    fun lines(menu: List<Drink>): List<CartLine> =
        menu.mapNotNull { drink ->
            val quantity = quantities[drink.id] ?: 0
            if (quantity > 0) CartLine(drink, quantity) else null
        }

    fun total(menu: List<Drink>): Money =
        lines(menu).fold(Money.ZERO) { running, line -> running + line.total }

    /** Add or remove one; a line that reaches zero disappears. */
    fun bump(drink: Drink, by: Int): Cart {
        val next = maxOf(0, (quantities[drink.id] ?: 0) + by)
        return Cart(
            if (next == 0) quantities - drink.id else quantities + (drink.id to next)
        )
    }

    fun cleared() = Cart()
}

// ─── Receipts ───────────────────────────────────────────────────────────────

/** The confirmation screen shared by all three successful outcomes. */
data class Receipt(
    val kind: Kind,
    val title: String,
    val note: String,
    val rows: List<Row>,
    val balance: Money,
    /** Whether the transaction went into the offline queue instead of the server. */
    val queuedOffline: Boolean = false,
) {
    enum class Kind { CHECK_IN, TOP_UP, PAYMENT }

    data class Row(val key: String, val value: String) {
        val id: String get() = key
    }

    /** The band across the top of the receipt. */
    val bandText: String
        get() = when (kind) {
            Kind.PAYMENT -> if (queuedOffline) "Approved · offline" else "Payment approved"
            Kind.TOP_UP -> "Top-up approved"
            Kind.CHECK_IN -> "Check-in complete"
        }

    val primaryActionLabel: String
        get() = when (kind) {
            Kind.PAYMENT -> "New order"
            Kind.TOP_UP -> "Read next bracelet"
            Kind.CHECK_IN -> "Top up now"
        }

    val secondaryActionLabel: String
        get() = if (kind == Kind.PAYMENT) "Back to menu" else "Done"
}
