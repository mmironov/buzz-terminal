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

    @Nested
    inner class `Staff roles from claims` {

        @Test
        fun `reception and bar map to themselves`() {
            assertEquals(StaffRole.RECEPTION, StaffRole.fromWire("reception"))
            assertEquals(StaffRole.BAR, StaffRole.fromWire("bar"))
        }

        @Test
        fun `an admin gets reception, because that is what the rules grant them`() {
            // firestore.rules puts `admin` in isReception() but never in isBar():
            // an organiser can pair, sell evening tickets and credit, and cannot
            // charge. If this ever returned BAR, an organiser could take money off
            // a bracelet.
            assertEquals(StaffRole.RECEPTION, StaffRole.fromWire("admin"))
            assertEquals(Screen.ReceptionHome, StaffRole.fromWire("admin")?.homeScreen)
        }

        @Test
        fun `an unknown or absent claim is refused rather than defaulted`() {
            // Sign-in fails on null. Defaulting to a role would be defaulting to a
            // set of money permissions.
            assertEquals(null, StaffRole.fromWire(null))
            assertEquals(null, StaffRole.fromWire(""))
            assertEquals(null, StaffRole.fromWire("Admin")) // claims are lower-case
            assertEquals(null, StaffRole.fromWire("organiser"))
        }
    }

    @Nested
    inner class `Bracelet ids from NFC chips` {

        @Test
        fun `a four-byte MIFARE uid formats like the design`() {
            assertEquals(
                "04:B4:2F:11",
                BraceletID.fromNfcId(byteArrayOf(0x04, 0xB4.toByte(), 0x2F, 0x11))?.rawValue,
            )
        }

        @Test
        fun `a seven-byte NTAG uid is accepted, not truncated`() {
            // NTAG213/215/216 — the usual wristband chip — has a 7-byte uid.
            // Truncating to four would collide two guests whose chips share a
            // prefix, and the manufacturer byte 0x04 means they all do.
            val bytes = byteArrayOf(
                0x04, 0xA2.toByte(), 0xB3.toByte(), 0xC4.toByte(),
                0xD5.toByte(), 0xE6.toByte(), 0xF7.toByte(),
            )
            assertEquals("04:A2:B3:C4:D5:E6:F7", BraceletID.fromNfcId(bytes)?.rawValue)
        }

        @Test
        fun `THE TRAP - high bytes are unsigned`() {
            // Kotlin's Byte is signed, so 0xB4 without the 0xFF mask formats as
            // "FFFFFFB4" and every id read from a real chip is wrong. This is the
            // one bug in the port that iOS could not have.
            val id = BraceletID.fromNfcId(byteArrayOf(0x00, 0x0A, 0xFF.toByte(), 0x7B))
            assertEquals("00:0A:FF:7B", id?.rawValue)
        }

        @Test
        fun `a chip reporting no uid is refused`() {
            // Otherwise this becomes a Firestore document id of "", which is a write
            // that fails deep in the repository rather than a scan that says no.
            assertEquals(null, BraceletID.fromNfcId(byteArrayOf()))
            assertEquals(null, BraceletID.fromNfcId(null))
        }

        @Test
        fun `the format matches what fresh() produces`() {
            // Both end up as Firestore document ids, so a chip read and a simulated
            // one must be the same shape or the two paths diverge silently.
            assertTrue(
                BraceletID.fromNfcId(byteArrayOf(0x99.toByte(), 0xC8.toByte(), 0x65, 0x13))!!
                    .rawValue.matches(Regex("([0-9A-F]{2}:){3}[0-9A-F]{2}"))
            )
        }
    }

    @Nested
    inner class `Sync state and failed writes` {

        private fun failure(
            kind: FailedWrite.Kind = FailedWrite.Kind.CHARGE,
            amount: Money = Money(800),
        ) = FailedWrite(
            transactionId = "tx-1",
            kind = kind,
            participantId = "tkt-1",
            participantName = "Anna Kowalski",
            braceletId = "1D:94:9D:D4:11:10:80",
            amount = amount,
            attemptedAt = Instant.ofEpochSecond(1_000_000),
            terminalId = "terminal-abc",
            reason = "PERMISSION_DENIED",
        )

        @Test
        fun `queueing and acknowledging balance out`() {
            val state = SyncState().enqueued().enqueued()
            assertEquals(2, state.pending)
            assertEquals(1, state.acknowledged().pending)
        }

        @Test
        fun `the pending count never goes negative`() {
            // Firestore's own queue survives a relaunch while this counter does not,
            // so an acknowledgement can arrive for a write this run never saw
            // enqueued. A count of -1 on a bar's screen would destroy trust in the
            // whole banner.
            assertEquals(0, SyncState().acknowledged().acknowledged().pending)
        }

        @Test
        fun `a failure decrements pending and is recorded`() {
            val state = SyncState().enqueued().failed(failure())
            assertEquals(0, state.pending)
            assertEquals(1, state.unsettledFailures.size)
        }

        @Test
        fun `settling keeps the record but takes it off the list`() {
            // Kept, not deleted: what an organiser did about missing money is part of
            // the record, and a list that erases itself cannot be audited afterwards.
            val write = failure()
            val state = SyncState().enqueued().failed(write).settle(write.id)
            assertEquals(1, state.failures.size)
            assertTrue(state.unsettledFailures.isEmpty())
            assertTrue(state.failures[0].settled)
        }

        @Test
        fun `a failure outranks a queue in the banner`() {
            val queued = SyncState().enqueued().enqueued()
            assertEquals("2 transactions waiting to sync", queued.bannerMessage)
            assertFalse(queued.bannerIsAlarming)

            val failed = queued.failed(failure())
            assertEquals("1 transaction failed to sync — show an organiser", failed.bannerMessage)
            assertTrue(failed.bannerIsAlarming)
        }

        @Test
        fun `offline alone says sales are being queued`() {
            val state = SyncState(isOffline = true)
            assertEquals("Offline — sales are being queued", state.bannerMessage)
            assertFalse(state.bannerIsAlarming)
        }

        @Test
        fun `nothing to say means no banner at all`() {
            // Not an empty string: the view checks one thing, and a permanent bar of
            // whitespace across every screen is its own bug.
            assertEquals(null, SyncState().bannerMessage)
        }

        @Test
        fun `each kind advises what to actually do about it`() {
            // A charge and a top-up fail in opposite directions: one means a drink was
            // given away, the other means a guest is owed credit.
            assertTrue(failure(FailedWrite.Kind.TOP_UP).advice.contains("Top the guest up again"))
            assertTrue(failure(FailedWrite.Kind.CHARGE).advice.contains("write it off"))
            assertTrue(failure(FailedWrite.Kind.CHECK_IN).advice.contains("Check the guest in again"))
        }

        @Test
        fun `the summary names the guest and the amount`() {
            assertEquals("Charge 8.00 € — Anna Kowalski", failure().summary)
            assertTrue(failure(FailedWrite.Kind.CHECK_IN).summary.contains("bracelet 1D:94:9D:D4:11:10:80"))
        }

        @Test
        fun `kinds survive a round trip through their wire value`() {
            // The wire strings are what SyncCenter writes to SharedPreferences, so a
            // rename would silently drop every stored failure on the next launch.
            FailedWrite.Kind.entries.forEach { kind ->
                assertEquals(kind, FailedWrite.Kind.fromWire(kind.wire))
            }
            assertEquals(null, FailedWrite.Kind.fromWire("nonsense"))
        }
    }
}
