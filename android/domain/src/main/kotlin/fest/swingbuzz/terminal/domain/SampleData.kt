package fest.swingbuzz.terminal.domain

import java.time.Instant

/**
 * The fixture data from the Claude Design prototype, reshaped to match the
 * Firestore model: one roster of participants, some of whom happen to have a
 * bracelet paired already.
 *
 * Once the Firebase repository lands, this is only used by Compose previews,
 * the debug launch overrides and the in-memory repository — never in a real
 * session. The production menu is Water 2 €, Beer 4 €, Gin & Tonic 6 €; the ten
 * drinks below are the prototype's invention and stay on the fixture path only.
 */
object SampleData {

    // ── Bar menu ──

    val drinks: List<Drink> = listOf(
        Drink("beer", "Draught beer", Money.euros(4)),
        Drink("radler", "Radler", Money.euros(4)),
        Drink("white", "White wine", Money.euros(5)),
        Drink("red", "Red wine", Money.euros(5)),
        Drink("prosecco", "Prosecco", Money.euros(6)),
        Drink("gt", "Gin & tonic", Money.euros(8)),
        Drink("sour", "Whisky sour", Money.euros(9)),
        Drink("lemonade", "Lemonade", Money.euros(3)),
        Drink("espresso", "Espresso", Money.euros(2, 50)),
        Drink("water", "Still water", Money.euros(1, 50)),
    )

    // ── Bracelet chips the simulator can present ──

    val braceletA = BraceletID("04:A1:9C:7E")
    val braceletB = BraceletID("04:B4:2F:11")
    val braceletC = BraceletID("04:C8:5D:03")
    val braceletD = BraceletID("04:D2:0B:6A")
    val braceletE = BraceletID("04:E7:3A:2C")

    val simulatedBracelets: List<SimulatedBracelet> = listOf(
        SimulatedBracelet(braceletA, "Fresh bracelet, not yet assigned"),
        SimulatedBracelet(braceletB, "Marta Lindqvist — 23.50 € on account"),
        SimulatedBracelet(braceletC, "Jonas Bergström — 2.00 € on account"),
        SimulatedBracelet(braceletD, "Elena Novak — blocked in admin panel"),
        SimulatedBracelet(braceletE, "Evening #14 (Friday) — door sale, anonymous"),
    )

    // ── Roster ──

    /**
     * A time on the Friday evening, used so the fixtures read like a real
     * festival rather than "checked in 0 seconds ago".
     */
    private fun earlier(hours: Long): Instant = Instant.now().minusSeconds(hours * 3600)

    /** Already checked in — these three have bracelets. */
    val checkedIn: List<Participant> = listOf(
        Participant(
            id = ParticipantID("tkt-10001"),
            ticketRef = "TKT-10001",
            name = "Marta Lindqvist",
            ticketType = TicketType.FULL_PASS,
            country = "Sweden",
            braceletId = braceletB,
            checkedInAt = earlier(6),
            balance = Money.euros(23, 50),
        ),
        Participant(
            id = ParticipantID("tkt-10002"),
            ticketRef = "TKT-10002",
            name = "Jonas Bergström",
            ticketType = TicketType.PARTY_PASS,
            country = "Sweden",
            braceletId = braceletC,
            checkedInAt = earlier(5),
            balance = Money.euros(2),
        ),
        Participant(
            id = ParticipantID("tkt-10003"),
            ticketRef = "TKT-10003",
            name = "Elena Novak",
            ticketType = TicketType.FULL_PASS,
            country = "Slovenia",
            braceletId = braceletD,
            checkedInAt = earlier(7),
            balance = Money.euros(14),
            isBlocked = true,
            blockReason = "Blocked in the admin panel on Sat 01:20 — no top-ups and " +
                "no payments until an organiser lifts it.",
        ),
    )

    /** Arrived, no bracelet yet. These are what the check-in list shows. */
    val awaitingCheckIn: List<Participant> = listOf(
        Participant(ParticipantID("tkt-10432"), "TKT-10432", "Amélie Roux", TicketType.FULL_PASS, "France"),
        Participant(ParticipantID("tkt-10433"), "TKT-10433", "Tomás Herrera", TicketType.FULL_PASS, "Spain"),
        Participant(ParticipantID("tkt-10434"), "TKT-10434", "Nina Kowalski", TicketType.PARTY_PASS, "Poland"),
        Participant(ParticipantID("tkt-10435"), "TKT-10435", "Sofia Ferreira", TicketType.FULL_PASS, "Portugal"),
        Participant(ParticipantID("tkt-10436"), "TKT-10436", "Dmitri Alvarez", TicketType.PARTY_PASS_PLUS, "Germany"),
        Participant(ParticipantID("tkt-10437"), "TKT-10437", "Hannah Vos", TicketType.PARTY_PASS, "Netherlands"),
    )

    /**
     * Door-sold evening tickets. Anonymous, minted at reception, never in the
     * Sheet — so [Participant.Source.EVENING], and the importer leaves them alone.
     */
    val eveningTickets: List<Participant> = listOf(
        Participant.eveningTicket(Evening.FRIDAY, 14, braceletE, checkedInAt = earlier(2)),
    )

    /** Everything in Firestore: the imported roster plus door sales. */
    val roster: List<Participant> get() = checkedIn + awaitingCheckIn + eveningTickets

    /** Convenience for previews and launch overrides. */
    fun participant(withBracelet: BraceletID): Participant? =
        roster.firstOrNull { it.braceletId == withBracelet }
}
