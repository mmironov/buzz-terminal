package fest.swingbuzz.terminal.domain

/**
 * Money as integer minor units (euro cents).
 *
 * The HTML prototype used a JavaScript `Number` for balances (`balance: 23.5`).
 * That is fine for a mock but wrong for money: binary floating point cannot
 * represent 0.10 exactly, so repeated top-ups and charges accumulate error.
 * [Money] stores cents in an `Int`, which is exact for every amount this app
 * will ever see, and only converts to a decimal string at the edges.
 *
 * A value class, so the exactness costs no allocation — at runtime this is an
 * `int`, exactly like the Swift struct it is ported from.
 */
@JvmInline
value class Money(val cents: Int) : Comparable<Money> {

    override fun compareTo(other: Money): Int = cents.compareTo(other.cents)

    operator fun plus(other: Money) = Money(cents + other.cents)
    operator fun minus(other: Money) = Money(cents - other.cents)
    operator fun times(factor: Int) = Money(cents * factor)

    val isPositive: Boolean get() = cents > 0

    /** Never below zero — used for "short by …" copy on a declined payment. */
    val clampedToZero: Money get() = Money(maxOf(0, cents))

    /**
     * `"23.50 €"` — matches the prototype's `n.toFixed(2) + ' €'` exactly.
     *
     * Deliberately locale-independent: every terminal at the festival shows the
     * same string regardless of the phone's region, which keeps a staff member
     * reading a balance out loud unambiguous. Localising this is a later call
     * (see README, "Known simplifications").
     *
     * Note this is a plain string build rather than `String.format`, which would
     * quietly follow the default locale and print `23,50` on a Bulgarian phone.
     */
    override fun toString(): String {
        val sign = if (cents < 0) "-" else ""
        val abs = kotlin.math.abs(cents)
        val fraction = (abs % 100).toString().padStart(2, '0')
        return "$sign${abs / 100}.$fraction €"
    }

    /**
     * `"5 €"` rather than `"5.00 €"` — used for the top-up preset buttons,
     * which the design writes without the decimals.
     */
    val compact: String get() = if (cents % 100 == 0) "${cents / 100} €" else toString()

    companion object {
        val ZERO = Money(0)

        /** Build from a whole-and-fraction literal, e.g. `Money.euros(2, 50)`. */
        fun euros(euros: Int, cents: Int = 0) = Money(euros * 100 + cents)

        /**
         * Parse a keypad string like `"12"`, `"12."`, `"12.5"`, `"12.50"`.
         * Returns [ZERO] for empty or malformed input.
         */
        fun fromKeypad(text: String): Money {
            if (text.isEmpty()) return ZERO
            val parts = text.split(".", limit = 2)
            val whole = parts[0].toIntOrNull() ?: 0
            // "5" means 50 cents, "50" means 50 cents, "" means 0.
            val fraction =
                if (parts.size == 2) parts[1].take(2).padEnd(2, '0').toIntOrNull() ?: 0 else 0
            return euros(whole, fraction)
        }
    }
}
