package fest.swingbuzz.terminal.domain

/**
 * Whether the bar may charge this round to the bracelet that was just scanned.
 *
 * This is the app's one piece of real business logic, so it lives in its own
 * type rather than inside a screen. Every refusal carries the copy the design
 * shows, because "why was I declined" is the question staff get asked at the
 * bar and the wording matters.
 */
sealed interface PaymentDecision {

    /** Charge is allowed. [balanceAfter] is what the guest is left with. */
    data class Approved(val balanceAfter: Money) : PaymentDecision

    /** The chip is not paired to anybody yet. */
    data object NotAssigned : PaymentDecision

    /** An organiser froze the bracelet in the admin panel. */
    data class Blocked(val participant: Participant) : PaymentDecision

    /** Not enough money on the account. */
    data class InsufficientFunds(
        val participant: Participant,
        val short: Money,
    ) : PaymentDecision

    val isApproved: Boolean get() = this is Approved

    /** Uppercase band across the top of the pay-review screen. */
    val bandText: String
        get() = when (this) {
            is Approved -> "Checked-In"
            NotAssigned -> "Not recognised"
            is Blocked -> "Blocked"
            is InsufficientFunds -> "Declined"
        }

    val title: String
        get() = when (this) {
            is Approved -> "Ready to charge"
            NotAssigned -> "Bracelet not assigned"
            is Blocked -> "Bracelet blocked"
            is InsufficientFunds -> "Not enough balance"
        }

    /**
     * The explanatory paragraph. Note every refusal ends by making clear that
     * nothing was charged — the design is emphatic about this.
     */
    fun note(total: Money): String = when (this) {
        is Approved -> ""

        NotAssigned ->
            "This chip is not mapped to anyone yet. Send the guest to reception to " +
                "check in and load money — nothing was charged."

        is Blocked ->
            "${participant.name}’s bracelet was blocked in the admin panel. No drinks " +
                "can be served on it. Refer the guest to an organiser — nothing was charged."

        is InsufficientFunds ->
            "${participant.name} has ${participant.balance}, the round costs $total. " +
                "Short by $short. Reception can top up."
    }

    companion object {
        /**
         * Decide whether [participant] can be charged [total].
         *
         * @param participant the account behind the scanned bracelet, or `null`
         *   when the chip is not paired to anybody.
         * @param total the cost of the round.
         *
         * Checked in order, and the order is the point: a blocked bracelet is
         * refused as *blocked* even when the balance would have covered the round,
         * because "an organiser has frozen this" is what the operator needs to say
         * to the guest — not "you are short".
         *
         * A balance exactly equal to [total] is approved and leaves `0.00 €`;
         * spending your last euro on a beer is allowed.
         *
         * The client runs this so the operator gets an instant answer. It is not
         * the authority — `TerminalRepository.charge` re-checks server-side, since
         * another terminal may have spent the money in between.
         */
        fun evaluate(participant: Participant?, total: Money): PaymentDecision {
            if (participant == null) return NotAssigned
            if (participant.isBlocked) return Blocked(participant)
            if (participant.balance < total) {
                return InsufficientFunds(participant, total - participant.balance)
            }
            return Approved(participant.balance - total)
        }
    }
}
