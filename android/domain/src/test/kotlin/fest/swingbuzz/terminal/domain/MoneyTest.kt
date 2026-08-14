package fest.swingbuzz.terminal.domain

import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * The Kotlin twin of `ios/BuzzTerminalTests/MoneyTests.swift`. Same cases, same
 * order — when one side changes, the diff should show the other side changing
 * too.
 */
class MoneyTest {

    @Test
    fun `formats with two decimals and a euro suffix`() {
        assertEquals("23.50 €", Money.euros(23, 50).toString())
        assertEquals("2.00 €", Money.euros(2).toString())
        assertEquals("0.05 €", Money(5).toString())
        assertEquals("0.00 €", Money.ZERO.toString())
    }

    @Test
    fun `formats negatives with a leading minus, not a mangled fraction`() {
        assertEquals("-1.50 €", Money(-150).toString())
    }

    @Test
    fun `drops decimals in the compact form only when they are zero`() {
        assertEquals("5 €", Money.euros(5).compact)
        assertEquals("2.50 €", Money.euros(2, 50).compact)
    }

    @Test
    fun `arithmetic is exact where a Double would drift`() {
        // 0.10 + 0.20 == 0.30 exactly, which is not true of binary floating point.
        val total = Money(10) + Money(20)
        assertEquals(Money(30), total)

        // Ten 2.50 espressos are exactly 25.00.
        assertEquals(Money.euros(25), Money.euros(2, 50) * 10)
    }

    @Test
    fun `parses keypad text`() {
        val cases = listOf(
            "" to 0,
            "0" to 0,
            "5" to 500,
            "12" to 1200,
            "12." to 1200,
            "12.5" to 1250,
            "12.50" to 1250,
            "0.05" to 5,
        )
        for ((input, expectedCents) in cases) {
            assertEquals(expectedCents, Money.fromKeypad(input).cents, "parsing \"$input\"")
        }
    }
}
