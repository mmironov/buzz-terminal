package fest.swingbuzz.terminal.data

import fest.swingbuzz.terminal.domain.BraceletID
import fest.swingbuzz.terminal.domain.CartLine
import fest.swingbuzz.terminal.domain.Evening
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.SampleData
import fest.swingbuzz.terminal.domain.StaffRole
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.jupiter.api.Nested

/**
 * Cover for the fixture backend. The iOS side has none of this — its repository
 * is exercised only by using the app — but the rules it enforces are the same
 * rules `firestore.rules` enforces in production, so having them asserted
 * somewhere fast is worth the file.
 *
 * `latencyMillis = 0`: the artificial delay exists to make loading states
 * visible during development, and has no business in a test.
 */
class InMemoryTerminalRepositoryTest {

    private fun repo() = InMemoryTerminalRepository(latencyMillis = 0)

    // ── Auth ──

    @Nested
    inner class SignIn {

        @Test
        fun `an address starting reception or bar picks the terminal mode`() = runTest {
            val repo = repo()
            assertEquals(StaffRole.RECEPTION, repo.signIn("reception@swingbuzz.fest", "x"))
            assertEquals(StaffRole.BAR, repo.signIn("bar@swingbuzz.fest", "x"))
        }

        @Test
        fun `case and surrounding whitespace do not matter`() = runTest {
            assertEquals(StaffRole.RECEPTION, repo().signIn("  RECEPTION@Swingbuzz.Fest ", ""))
        }

        @Test
        fun `anything else is refused, and the refusal names neither cause`() = runTest {
            val error = assertFailsWith<TerminalError.UnknownAccount> {
                repo().signIn("marta@example.com", "festival26")
            }
            // Enumeration protection: "no such user" and "wrong password" must
            // not be distinguishable, here or against Firebase.
            assertTrue(error.message.contains("Unknown account or wrong password"))
        }
    }

    // ── Check-in list ──

    @Nested
    inner class AwaitingCheckIn {

        @Test
        fun `lists exactly the people with no bracelet, by name`() = runTest {
            val waiting = repo().awaitingCheckIn()
            assertEquals(SampleData.awaitingCheckIn.size, waiting.size)
            assertTrue(waiting.all { it.isAwaitingCheckIn })
            assertEquals(waiting.map { it.name }.sorted(), waiting.map { it.name })
        }

        @Test
        fun `a paired bracelet drops the person off the list`() = runTest {
            val repo = repo()
            val amelie = repo.awaitingCheckIn().first { it.name == "Amélie Roux" }
            repo.assignBracelet(SampleData.braceletA, amelie)
            assertTrue(repo.awaitingCheckIn().none { it.id == amelie.id })
        }
    }

    // ── Pairing ──

    @Nested
    inner class AssignBracelet {

        @Test
        fun `pairing stamps a check-in time and keeps the balance at zero`() = runTest {
            val repo = repo()
            val amelie = repo.awaitingCheckIn().first { it.name == "Amélie Roux" }
            val paired = repo.assignBracelet(SampleData.braceletA, amelie)

            assertEquals(SampleData.braceletA, paired.braceletId)
            assertNotNull(paired.checkedInAt)
            assertEquals(Money.ZERO, paired.balance)
            assertEquals("Checked in just now", paired.checkedInLabel)
        }

        @Test
        fun `a chip already on somebody else is refused`() = runTest {
            val repo = repo()
            val amelie = repo.awaitingCheckIn().first { it.name == "Amélie Roux" }
            // braceletB is Marta's.
            assertFailsWith<TerminalError.BraceletAlreadyPaired> {
                repo.assignBracelet(SampleData.braceletB, amelie)
            }
        }

        @Test
        fun `re-pairing somebody who already has a bracelet is refused`() = runTest {
            val repo = repo()
            val amelie = repo.awaitingCheckIn().first { it.name == "Amélie Roux" }
            repo.assignBracelet(SampleData.braceletA, amelie)

            // A second chip for the same guest would strand the first one's
            // balance, which is why the security rules forbid it outright.
            assertFailsWith<TerminalError.BraceletAlreadyPaired> {
                repo.assignBracelet(BraceletID("04:FF:FF:FF"), amelie)
            }
        }
    }

    // ── Evening tickets ──

    @Nested
    inner class EveningTickets {

        @Test
        fun `the number continues the evening's sequence`() = runTest {
            val repo = repo()
            // The fixtures already contain Friday #14.
            val next = repo.createEveningTicket(Evening.FRIDAY, BraceletID("04:11:11:11"))
            assertEquals("Evening #15", next.name)
            assertEquals("ev-friday-15", next.id.rawValue)
        }

        @Test
        fun `each evening counts separately, starting at one`() = runTest {
            val saturday = repo().createEveningTicket(Evening.SATURDAY, BraceletID("04:22:22:22"))
            assertEquals("Evening #1", saturday.name)
        }

        @Test
        fun `a chip that already belongs to somebody cannot be sold again`() = runTest {
            assertFailsWith<TerminalError.BraceletAlreadyPaired> {
                repo().createEveningTicket(Evening.FRIDAY, SampleData.braceletB)
            }
        }
    }

    // ── Money ──

    @Nested
    inner class TopUp {

        @Test
        fun `cash lands on the account`() = runTest {
            val updated = repo().topUp(SampleData.braceletB, Money.euros(10))
            assertEquals(Money.euros(33, 50), updated.balance)
        }

        @Test
        fun `a blocked bracelet takes no money`() = runTest {
            assertFailsWith<TerminalError.BraceletBlocked> {
                repo().topUp(SampleData.braceletD, Money.euros(10))
            }
        }

        @Test
        fun `an unpaired chip takes no money`() = runTest {
            assertFailsWith<TerminalError.BraceletNotAssigned> {
                repo().topUp(SampleData.braceletA, Money.euros(10))
            }
        }

        /**
         * The reason this repository holds a Mutex rather than a plain map. Two
         * reception desks topping up the same bracelet at the same moment must
         * not lose one of the payments — the same invariant `firestore.rules`
         * enforces with a transaction in production.
         */
        @Test
        fun `simultaneous top-ups all land`() = runTest {
            val repo = repo()
            withContext(Dispatchers.Default) {
                (1..20).map { async { repo.topUp(SampleData.braceletB, Money.euros(1)) } }.awaitAll()
            }
            val marta = repo.participantWithBracelet(SampleData.braceletB)
            assertEquals(Money.euros(43, 50), marta?.balance)
        }
    }

    @Nested
    inner class Charge {

        private val beer = SampleData.drinks.first { it.id == "beer" }   // 4.00 €
        private val sour = SampleData.drinks.first { it.id == "sour" }   // 9.00 €

        @Test
        fun `a round is debited and the new balance comes back`() = runTest {
            val updated = repo().charge(SampleData.braceletB, listOf(CartLine(beer, 2)))
            assertEquals(Money.euros(15, 50), updated.balance)
        }

        @Test
        fun `the balance is re-checked here, not trusted from the client`() = runTest {
            // Jonas has 2.00 €; the client may believe otherwise, this must not.
            val error = assertFailsWith<TerminalError.InsufficientFunds> {
                repo().charge(SampleData.braceletC, listOf(CartLine(sour, 1)))
            }
            assertEquals(Money.euros(2), error.balance)
            assertEquals(Money.euros(9), error.required)
        }

        @Test
        fun `spending the exact balance is allowed and leaves zero`() = runTest {
            val repo = repo()
            val espresso = SampleData.drinks.first { it.id == "espresso" } // 2.50 €
            repo.topUp(SampleData.braceletC, Money.euros(0, 50)) // Jonas → 2.50 €
            val updated = repo.charge(SampleData.braceletC, listOf(CartLine(espresso, 1)))
            assertEquals(Money.ZERO, updated.balance)
        }

        @Test
        fun `a blocked bracelet buys nothing, whatever the balance`() = runTest {
            // Elena has 14.00 € — plenty for a beer, and still refused.
            assertFailsWith<TerminalError.BraceletBlocked> {
                repo().charge(SampleData.braceletD, listOf(CartLine(beer, 1)))
            }
        }

        @Test
        fun `a refused charge leaves the balance untouched`() = runTest {
            val repo = repo()
            assertFailsWith<TerminalError.InsufficientFunds> {
                repo.charge(SampleData.braceletC, listOf(CartLine(sour, 1)))
            }
            assertEquals(Money.euros(2), repo.participantWithBracelet(SampleData.braceletC)?.balance)
        }
    }

    // ── Lookup ──

    @Test
    fun `an unknown chip resolves to nobody rather than failing`() = runTest {
        // The check-in flow depends on this: an unassigned chip is the *start*
        // of a pairing, not an error.
        assertNull(repo().participantWithBracelet(SampleData.braceletA))
        assertNotNull(repo().participantWithBracelet(SampleData.braceletB))
    }
}
