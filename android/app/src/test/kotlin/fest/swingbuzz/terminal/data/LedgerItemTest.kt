package fest.swingbuzz.terminal.data

import fest.swingbuzz.terminal.domain.CartLine
import fest.swingbuzz.terminal.domain.Drink
import fest.swingbuzz.terminal.domain.Money
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// ═══════════════════════════════════════════════════════════════════════════
//  The itemisation a charge carries into the ledger.
//
//  `backend/firestore.rules` checks this shape exactly — four keys, no more, and
//  line totals that add up to the amount the balance moves by. A mismatch is not a
//  cosmetic bug in the admin panel's receipt: it is PERMISSION_DENIED at the bar,
//  mid-service, on a payment that has already been read out to a guest.
//
//  This is the only test in `:app`. Everything about the festival's rules lives in
//  `:domain` and is tested there without an Android SDK in sight; the Firestore
//  field names are the one contract `:domain` deliberately cannot see, and they
//  are too load-bearing to go unasserted. The mirror of this file is
//  `ios/BuzzTerminalTests/LedgerItemTests.swift`, and the server-side half is
//  `backend/rules-tests/rules.test.mjs`, "a charge says what it bought".
// ═══════════════════════════════════════════════════════════════════════════

class LedgerItemTest {

    private val beer = Drink(id = "beer", name = "Draught beer", price = Money(400))
    private val water = Drink(id = "water", name = "Water", price = Money(200))

    @Test
    fun `a line carries the drink, its unit price and how many`() {
        val item = CartLine(beer, quantity = 3).ledgerItem()

        assertEquals("beer", item[Fire.TransactionItem.DRINK_ID])
        assertEquals("Draught beer", item[Fire.TransactionItem.NAME])
        assertEquals(3, item[Fire.TransactionItem.QUANTITY])
        // The UNIT price, not the line total. Writing 1200 here would still add up
        // against a total computed the same wrong way, so the rules would accept a
        // receipt claiming beer costs 12 €. Nothing downstream catches that.
        assertEquals(400, item[Fire.TransactionItem.UNIT_PRICE])
    }

    @Test
    fun `a line carries nothing else`() {
        // `hasOnly` in the rules: an extra key is a declined payment, not a
        // harmless annotation.
        assertEquals(
            setOf("drinkId", "name", "unitPrice", "quantity"),
            CartLine(beer, quantity = 1).ledgerItem().keys,
        )
    }

    @Test
    fun `lines keep menu order`() {
        val items = listOf(CartLine(beer, 1), CartLine(water, 1)).ledgerItems()
        assertEquals(
            listOf("beer", "water"),
            items.map { it[Fire.TransactionItem.DRINK_ID] },
        )
    }

    @Test
    fun `the total is what the lines add up to`() {
        // The invariant `itemisationAddsUp` enforces server-side. Both numbers in
        // the write come from this one list, which is the only reason they cannot
        // drift apart.
        val lines = listOf(CartLine(beer, 3), CartLine(water, 2))

        val summed = lines.ledgerItems().sumOf {
            (it[Fire.TransactionItem.UNIT_PRICE] as Int) * (it[Fire.TransactionItem.QUANTITY] as Int)
        }
        assertEquals(Money(1600), lines.ledgerTotal())
        assertEquals(lines.ledgerTotal().cents, summed)
    }

    @Test
    fun `an empty round itemises to nothing`() {
        // The repository writes no `items` key at all in this case. A charge with
        // an empty array is refused by the rules, which is correct — a round that
        // bought nothing is not a round.
        assertTrue(emptyList<CartLine>().ledgerItems().isEmpty())
        assertEquals(Money.ZERO, emptyList<CartLine>().ledgerTotal())
    }

    @Test
    fun `a free drink is still a line`() {
        val tap = Drink(id = "tap", name = "Tap water", price = Money.ZERO)
        val lines = listOf(CartLine(beer, 1), CartLine(tap, 2))

        assertEquals(2, lines.ledgerItems().size)
        assertEquals(Money(400), lines.ledgerTotal())
    }

    @Test
    fun `the cap agrees with what the rules can verify`() {
        // Eight is not arbitrary — it is what fits inside Firestore's budget of
        // 1,000 expressions per request, measured by the rules tests. If this
        // number changes, `itemisationAddsUp` has to be re-measured and re-unrolled
        // on the same day, or the bar starts seeing PERMISSION_DENIED.
        assertEquals(8, Fire.Transaction.MAX_ITEMS)
    }
}
