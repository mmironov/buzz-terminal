package fest.swingbuzz.terminal.domain

/**
 * The state of the cash-received keypad on the top-up screen.
 *
 * Held as the raw text the operator typed rather than as a number, so that
 * "12." and "12.0" stay visually distinct while they are mid-entry — exactly
 * how a till behaves. [amount] is the parsed value the rest of the app uses.
 *
 * Immutable: [press] returns the next state rather than mutating in place. The
 * Swift original is a `mutating func` on a struct, which is the same thing —
 * and on this side it is what lets the screen hold one `by mutableStateOf`
 * value and have Compose recompose when it is replaced.
 */
data class TopUpEntry(
    /** What the operator has typed so far, e.g. `""`, `"12"`, `"12."`, `"12.50"`. */
    val text: String = "",
) {

    /** A key on the on-screen pad. */
    sealed interface Key {
        val label: String

        data class Digit(val digit: Char) : Key {
            override val label: String get() = digit.toString()
        }

        data object DecimalSeparator : Key {
            override val label: String get() = "."
        }

        data object Backspace : Key {
            override val label: String get() = "⌫"
        }
    }

    /**
     * `"0.00 €"` when nothing is typed, otherwise the raw text with the currency.
     * Matches the prototype: mid-entry text is shown as typed, not reformatted.
     */
    val display: String get() = if (text.isEmpty()) Money.ZERO.toString() else "$text €"

    val amount: Money get() = Money.fromKeypad(text)

    val isConfirmable: Boolean get() = amount.isPositive

    val confirmButtonTitle: String
        get() = if (isConfirmable) "Add $amount" else "Enter an amount"

    fun applying(preset: Money) = TopUpEntry("${preset.cents / 100}")

    fun cleared() = TopUpEntry("")

    /**
     * Handle one key press, applying the rules a cash keypad needs:
     *
     *   1. backspace removes the last character, and is a no-op when empty;
     *   2. there is at most one decimal separator, and pressing it on empty
     *      text produces `"0."` rather than a bare `"."`;
     *   3. at most two digits after the separator;
     *   4. a lone leading `"0"` is replaced rather than accumulated, so `0`
     *      then `5` gives `"5"` — but `"0."` then `5` gives `"0.5"`;
     *   5. the integer part stops at [MAX_INTEGER_DIGITS].
     *
     * Rules 3 and 5 apply to opposite sides of the separator, hence the
     * `else if` rather than a nested check — capping the euros must not also
     * block the cents.
     *
     * Refused keypresses are silent: nothing tells the operator that a digit
     * was dropped. Worth remembering if anyone ever reports "the pad stopped
     * responding" at 999 €.
     */
    fun press(key: Key): TopUpEntry = when (key) {
        Key.Backspace -> TopUpEntry(text.dropLast(1))

        Key.DecimalSeparator ->
            if (text.contains(key.label)) this
            else TopUpEntry((text.ifEmpty { "0" }) + key.label)

        is Key.Digit -> {
            if (text == "0") {
                TopUpEntry(key.digit.toString())
            } else {
                val components = text.split(Key.DecimalSeparator.label)
                if (components.size > 1) {
                    if (components[1].length < 2) TopUpEntry(text + key.digit) else this
                } else if (components[0].length < MAX_INTEGER_DIGITS) {
                    TopUpEntry(text + key.digit)
                } else {
                    this
                }
            }
        }
    }

    companion object {
        /**
         * Largest top-up the pad will accept: 999 €. A cash payment at a festival
         * reception desk larger than this is a mistake, not a transaction.
         */
        private const val MAX_INTEGER_DIGITS = 3

        /** The pad layout from the design: 1-9, then `.`, `0`, `⌫`. */
        val keys: List<Key> = buildList {
            ('1'..'9').forEach { add(Key.Digit(it)) }
            add(Key.DecimalSeparator)
            add(Key.Digit('0'))
            add(Key.Backspace)
        }

        /** The quick-amount buttons above the pad. */
        val presets: List<Money> =
            listOf(Money.euros(5), Money.euros(10), Money.euros(20), Money.euros(50))
    }
}
