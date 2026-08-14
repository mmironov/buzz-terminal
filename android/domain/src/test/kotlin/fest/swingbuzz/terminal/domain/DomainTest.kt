package fest.swingbuzz.terminal.domain

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Nested

// ════════════════════════════════════════════════════════════════════════════
//  The Kotlin twin of `ios/BuzzTerminalTests/DomainTests.swift`: the same five
//  suites over the same rules.
//
//    TopUpEntry.press(…)            keypad input rules
//    Participant.matches(query)     check-in search
//    PaymentDecision.evaluate(…)    the charge decision
//    Participant lifecycle          bracelet == null means awaiting check-in
//    Evening tickets                anonymous, collision-proof door sales
//
//  Run with ./scripts/test.sh, or ./gradlew :domain:test
// ════════════════════════════════════════════════════════════════════════════
class DomainTest {

    // ── Keypad ──

    @Nested
    inner class TopUpKeypad {

        /** Convenience: press a run of keys, given as a string. */
        private fun typing(sequence: String): TopUpEntry =
            sequence.fold(TopUpEntry()) { entry, character ->
                entry.press(
                    when (character) {
                        '.' -> TopUpEntry.Key.DecimalSeparator
                        '<' -> TopUpEntry.Key.Backspace
                        else -> TopUpEntry.Key.Digit(character)
                    }
                )
            }

        @Test
        fun `digits accumulate`() {
            assertEquals("12", typing("12").text)
            assertEquals(Money.euros(12), typing("12").amount)
        }

        @Test
        fun `backspace removes the last character and is safe when empty`() {
            assertEquals("1", typing("12<").text)
            assertEquals("", typing("<").text)
            assertEquals("", typing("1<<<").text)
        }

        @Test
        fun `a decimal separator on empty input yields 0 dot, not a bare dot`() {
            assertEquals("0.", typing(".").text)
        }

        @Test
        fun `only one decimal separator is accepted`() {
            assertEquals("12.5", typing("12.5.").text)
            assertEquals("1.", typing("1..").text)
        }

        @Test
        fun `at most two digits after the separator`() {
            assertEquals("12.50", typing("12.50").text)
            assertEquals("12.56", typing("12.567").text)
        }

        @Test
        fun `a lone leading zero is replaced, not accumulated`() {
            assertEquals("5", typing("05").text)
            // …but a zero before the separator is meaningful and must survive.
            assertEquals("0.5", typing("0.5").text)
            assertEquals(Money(50), typing("0.5").amount)
        }

        @Test
        fun `the integer part stops at three digits`() {
            assertEquals("999", typing("9999").text)
            // The cap is on the euros only — the cents must still accept two.
            assertEquals("999.95", typing("999.95").text)
        }

        @Test
        fun `presets and clear bypass the keypad rules`() {
            val entry = TopUpEntry().applying(Money.euros(20))
            assertEquals(Money.euros(20), entry.amount)

            val cleared = entry.cleared()
            assertEquals("", cleared.text)
            assertFalse(cleared.isConfirmable)
        }

        @Test
        fun `the confirm button describes what it will do`() {
            assertEquals("Enter an amount", TopUpEntry().confirmButtonTitle)
            assertEquals("Add 20.00 €", typing("20").confirmButtonTitle)
        }
    }

    // ── Search ──

    @Nested
    inner class CheckInSearch {

        private val amelie = Participant(
            ParticipantID("tkt-10432"), "TKT-10432", "Amélie Roux", "Full pass", "France"
        )
        private val nina = Participant(
            ParticipantID("tkt-10434"), "TKT-10434", "Nina Kowalski", "Party pass", "Poland"
        )

        @Test
        fun `an empty or blank query matches everybody`() {
            assertTrue(amelie.matches(""))
            assertTrue(amelie.matches("   "))
            assertTrue(nina.matches("\n "))
        }

        @Test
        fun `matches on name`() {
            assertTrue(amelie.matches("Roux"))
            assertTrue(nina.matches("Nina"))
            assertFalse(amelie.matches("Nina"))
        }

        @Test
        fun `matches on the ticket type`() {
            assertTrue(nina.matches("party"))
            assertFalse(amelie.matches("party"))
        }

        @Test
        fun `matches a substring anywhere, not just a prefix`() {
            assertTrue(amelie.matches("oux"))
            assertTrue(nina.matches("owalski"))
        }

        @Test
        fun `ignores case, including on accented names`() {
            assertTrue(amelie.matches("amélie"))
            assertTrue(amelie.matches("AMÉLIE"))
            assertTrue(nina.matches("KOWALSKI"))
        }

        @Test
        fun `does not match the city — the field says participant or ticket`() {
            assertFalse(amelie.matches("Lyon"))
        }
    }

    // ── Charge decision ──

    @Nested
    inner class ChargeDecision {

        private fun participant(balance: Money, blocked: Boolean = false) = Participant(
            id = ParticipantID("tkt-10001"),
            ticketRef = "TKT-10001",
            name = "Marta Lindqvist",
            ticketType = "Full pass",
            country = "Sweden",
            braceletId = SampleData.braceletB,
            checkedInAt = Instant.now(),
            balance = balance,
            isBlocked = blocked,
        )

        @Test
        fun `an unassigned chip is not chargeable`() {
            val decision = PaymentDecision.evaluate(null, Money.euros(4))
            assertEquals(PaymentDecision.NotAssigned, decision)
            assertFalse(decision.isApproved)
        }

        @Test
        fun `a blocked bracelet is refused even when the balance would cover it`() {
            val marta = participant(Money.euros(100), blocked = true)
            assertEquals(
                PaymentDecision.Blocked(marta),
                PaymentDecision.evaluate(marta, Money.euros(4)),
            )
        }

        @Test
        fun `too little money is refused, and reports how much is missing`() {
            val jonas = participant(Money.euros(2))
            assertEquals(
                PaymentDecision.InsufficientFunds(jonas, Money.euros(7)),
                PaymentDecision.evaluate(jonas, Money.euros(9)),
            )
        }

        @Test
        fun `enough money is approved, and reports the balance afterwards`() {
            val marta = participant(Money.euros(23, 50))
            assertEquals(
                PaymentDecision.Approved(Money.euros(19, 50)),
                PaymentDecision.evaluate(marta, Money.euros(4)),
            )
        }

        @Test
        fun `spending the exact balance is allowed and leaves zero`() {
            val jonas = participant(Money.euros(2, 50))
            assertEquals(
                PaymentDecision.Approved(Money.ZERO),
                PaymentDecision.evaluate(jonas, Money.euros(2, 50)),
            )
        }

        @Test
        fun `refusals name the guest and never imply money moved`() {
            val elena = participant(Money.euros(14), blocked = true)
            val note = PaymentDecision.Blocked(elena).note(Money.euros(4))
            assertTrue(note.contains("Marta Lindqvist"))
            assertTrue(note.contains("nothing was charged"))
        }
    }

    // ── Participant lifecycle ──

    /**
     * `braceletId == null` replaced the old `WaitingGuest` type entirely, so the
     * "is this person still waiting?" question now has exactly one answer.
     */
    @Nested
    inner class ParticipantLifecycle {

        private fun roux(bracelet: BraceletID? = null, checkedInAt: Instant? = null) = Participant(
            id = ParticipantID("tkt-10432"),
            ticketRef = "TKT-10432",
            name = "Amélie Roux",
            ticketType = "Full pass",
            country = "France",
            braceletId = bracelet,
            checkedInAt = checkedInAt,
        )

        @Test
        fun `no bracelet means awaiting check-in`() {
            assertTrue(roux().isAwaitingCheckIn)
            assertEquals(Money.ZERO, roux().balance)
            assertEquals("Not checked in", roux().checkedInLabel)
        }

        @Test
        fun `a paired bracelet means checked in`() {
            assertFalse(roux(SampleData.braceletA, Instant.now()).isAwaitingCheckIn)
        }

        @Test
        fun `a just-paired bracelet reads as just now, an older one as a time`() {
            assertEquals("Checked in just now", roux(SampleData.braceletA, Instant.now()).checkedInLabel)

            val earlier = roux(SampleData.braceletA, Instant.now().minusSeconds(3 * 3600))
            assertTrue(earlier.checkedInLabel.startsWith("Checked in "))
            assertTrue(earlier.checkedInLabel != "Checked in just now")
        }

        @Test
        fun `the sample roster is imported plus door sales, with no overlap`() {
            val roster = SampleData.roster
            val awaiting = roster.filter { it.isAwaitingCheckIn }
            assertEquals(SampleData.awaitingCheckIn.size, awaiting.size)
            assertEquals(
                SampleData.checkedIn.size + awaiting.size + SampleData.eveningTickets.size,
                roster.size,
            )
            // Participant ids are unique — a duplicate would mean two people sharing
            // a balance, which is the importer's whole reason for refusing to guess.
            assertEquals(roster.size, roster.map { it.id }.toSet().size)
        }
    }

    // ── Evening tickets ──

    /**
     * Door-sold tickets. Anonymous by design: no name, no country, and organisers
     * freeze them by hand after their evening rather than the app expiring them.
     */
    @Nested
    inner class EveningTickets {

        @Test
        fun `the id encodes the sequence, which is what makes it collision-proof`() {
            val ticket = Participant.eveningTicket(Evening.FRIDAY, 14, SampleData.braceletE)
            // Two reception desks selling at once both try `ev-friday-14`; Firestore's
            // `create` lets exactly one win, and the loser retries with 15. No counter
            // document and no coordination.
            assertEquals(ParticipantID("ev-friday-14"), ticket.id)
            assertEquals("EV-FRIDAY-14", ticket.ticketRef)
        }

        @Test
        fun `it carries no personal data`() {
            val ticket = Participant.eveningTicket(Evening.SATURDAY, 3, SampleData.braceletE)
            assertEquals("Evening #3", ticket.name) // a label, not a person
            assertTrue(ticket.country.isEmpty())
            assertEquals(Participant.Source.EVENING, ticket.source)
            assertTrue(ticket.isEveningTicket)
        }

        @Test
        fun `it is created already paired and with nothing on it`() {
            val ticket = Participant.eveningTicket(Evening.SUNDAY, 1, SampleData.braceletE)
            // The ticket price is cash to the festival, not credit on the bracelet.
            assertEquals(Money.ZERO, ticket.balance)
            assertFalse(ticket.isAwaitingCheckIn)
            assertEquals(SampleData.braceletE, ticket.braceletId)
            assertFalse(ticket.isBlocked)
        }

        @Test
        fun `the screen says which evening it was sold for`() {
            val evening = Participant.eveningTicket(Evening.FRIDAY, 14, SampleData.braceletE)
            assertEquals("Evening ticket · Friday", evening.ticketDescription)
            assertEquals(TicketType.EVENING_TICKET, evening.ticketType)

            val imported = SampleData.awaitingCheckIn[0]
            assertEquals(imported.ticketType, imported.ticketDescription)
            assertFalse(imported.isEveningTicket)
        }

        @Test
        fun `search finds an evening ticket by number or by evening`() {
            val ticket = Participant.eveningTicket(Evening.FRIDAY, 14, SampleData.braceletE)
            assertTrue(ticket.matches("evening"))
            assertTrue(ticket.matches("#14"))
            assertTrue(ticket.matches("Evening Ticket"))
            assertFalse(ticket.matches("Marta"))
        }

        @Test
        fun `all six pass types are distinct and evening is one of them`() {
            assertEquals(6, TicketType.all.size)
            assertEquals(6, TicketType.all.toSet().size)
            assertTrue(TicketType.all.contains(TicketType.EVENING_TICKET))
        }
    }

    /**
     * The generator behind the simulator panel's "new chip" row. Its entire job
     * is to produce something the backend has never seen, so both properties
     * below are the feature rather than incidental detail.
     */
    @Nested
    inner class FreshChipIds {

        @Test
        fun `looks like a four-byte NFC uid`() {
            repeat(50) {
                assertTrue(
                    BraceletID.fresh().rawValue.matches(Regex("([0-9A-F]{2}:){3}[0-9A-F]{2}")),
                    "unexpected shape: ${BraceletID.fresh()}",
                )
            }
        }

        @Test
        fun `does not collide with the fixture chips`() {
            val fixtures = SampleData.simulatedBracelets.map { it.id }.toSet()
            val generated = List(500) { BraceletID.fresh() }
            assertTrue(generated.none { it in fixtures })
        }

        @Test
        fun `is different every time`() {
            // 500 draws from 2^32; a duplicate is possible but a *run* of them is
            // not, so this pins randomness without being flaky about it.
            val generated = List(500) { BraceletID.fresh() }
            assertTrue(generated.toSet().size > 490)
        }
    }
}
