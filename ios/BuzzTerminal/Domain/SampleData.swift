import Foundation

/// The fixture data from the Claude Design prototype, reshaped to match the
/// Firestore model: one roster of participants, some of whom happen to have a
/// bracelet paired already.
///
/// Once `FirebaseTerminalRepository` lands, this is only used by SwiftUI previews,
/// `LaunchOverrides` and the in-memory repository — never in a real session.
enum SampleData {

    // MARK: Bar menu

    static let drinks: [Drink] = [
        Drink(id: "beer", name: "Draught beer", price: Money(euros: 4)),
        Drink(id: "radler", name: "Radler", price: Money(euros: 4)),
        Drink(id: "white", name: "White wine", price: Money(euros: 5)),
        Drink(id: "red", name: "Red wine", price: Money(euros: 5)),
        Drink(id: "prosecco", name: "Prosecco", price: Money(euros: 6)),
        Drink(id: "gt", name: "Gin & tonic", price: Money(euros: 8)),
        Drink(id: "sour", name: "Whisky sour", price: Money(euros: 9)),
        Drink(id: "lemonade", name: "Lemonade", price: Money(euros: 3)),
        Drink(id: "espresso", name: "Espresso", price: Money(euros: 2, cents: 50)),
        Drink(id: "water", name: "Still water", price: Money(euros: 1, cents: 50)),
    ]

    // MARK: Bracelet chips the simulator can present

    static let braceletA = BraceletID("04:A1:9C:7E")
    static let braceletB = BraceletID("04:B4:2F:11")
    static let braceletC = BraceletID("04:C8:5D:03")
    static let braceletD = BraceletID("04:D2:0B:6A")

    static let simulatedBracelets: [SimulatedBracelet] = [
        SimulatedBracelet(id: braceletA, hint: "Fresh bracelet, not yet assigned"),
        SimulatedBracelet(id: braceletB, hint: "Marta Lindqvist — 23.50 € on account"),
        SimulatedBracelet(id: braceletC, hint: "Jonas Bergström — 2.00 € on account"),
        SimulatedBracelet(id: braceletD, hint: "Elena Novak — blocked in admin panel"),
    ]

    // MARK: Roster

    /// A time on the Friday evening, used so the fixtures read like a real
    /// festival rather than "checked in 0 seconds ago".
    private static func earlier(_ hours: Double) -> Date {
        Date(timeIntervalSinceNow: -hours * 3600)
    }

    /// Already checked in — these three have bracelets.
    static let checkedIn: [Participant] = [
        Participant(
            id: ParticipantID("tkt-10001"),
            ticketRef: "TKT-10001",
            name: "Marta Lindqvist",
            ticketType: "Full pass",
            city: "Stockholm",
            braceletId: braceletB,
            checkedInAt: earlier(6),
            balance: Money(euros: 23, cents: 50)
        ),
        Participant(
            id: ParticipantID("tkt-10002"),
            ticketRef: "TKT-10002",
            name: "Jonas Bergström",
            ticketType: "Party pass",
            city: "Göteborg",
            braceletId: braceletC,
            checkedInAt: earlier(5),
            balance: Money(euros: 2)
        ),
        Participant(
            id: ParticipantID("tkt-10003"),
            ticketRef: "TKT-10003",
            name: "Elena Novak",
            ticketType: "Full pass",
            city: "Ljubljana",
            braceletId: braceletD,
            checkedInAt: earlier(7),
            balance: Money(euros: 14),
            isBlocked: true,
            blockReason: "Blocked in the admin panel on Sat 01:20 — no top-ups and no payments until an organiser lifts it."
        ),
    ]

    /// Arrived, no bracelet yet. These are what the check-in list shows.
    static let awaitingCheckIn: [Participant] = [
        Participant(id: ParticipantID("tkt-10432"), ticketRef: "TKT-10432", name: "Amélie Roux", ticketType: "Full pass", city: "Lyon"),
        Participant(id: ParticipantID("tkt-10433"), ticketRef: "TKT-10433", name: "Tomás Herrera", ticketType: "Full pass", city: "Madrid"),
        Participant(id: ParticipantID("tkt-10434"), ticketRef: "TKT-10434", name: "Nina Kowalski", ticketType: "Party pass", city: "Kraków"),
        Participant(id: ParticipantID("tkt-10435"), ticketRef: "TKT-10435", name: "Sofia Ferreira", ticketType: "Full pass", city: "Porto"),
        Participant(id: ParticipantID("tkt-10436"), ticketRef: "TKT-10436", name: "Dmitri Alvarez", ticketType: "Weekend pass", city: "Berlin"),
        Participant(id: ParticipantID("tkt-10437"), ticketRef: "TKT-10437", name: "Hannah Vos", ticketType: "Party pass", city: "Utrecht"),
    ]

    /// The whole roster, as the Sheet import would have left it.
    static var roster: [Participant] { checkedIn + awaitingCheckIn }

    /// Convenience for previews and launch overrides.
    static func participant(withBracelet bracelet: BraceletID) -> Participant? {
        checkedIn.first { $0.braceletId == bracelet }
    }
}
