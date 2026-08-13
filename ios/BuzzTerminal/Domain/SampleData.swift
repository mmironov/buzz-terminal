import Foundation

/// The fixture data from the Claude Design prototype, kept verbatim so the app
/// and the design can be compared side by side.
///
/// In iteration 2 the drinks list and the guest list move to Firestore and this
/// file shrinks to whatever the offline cache needs to seed itself with.
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

    // MARK: Already checked in

    static let participants: [BraceletID: Participant] = [
        braceletB: Participant(
            id: braceletB,
            name: "Marta Lindqvist",
            pass: "Full pass",
            balance: Money(euros: 23, cents: 50),
            checkedInAt: "Fri 17:12"
        ),
        braceletC: Participant(
            id: braceletC,
            name: "Jonas Bergström",
            pass: "Party pass",
            balance: Money(euros: 2),
            checkedInAt: "Fri 18:04"
        ),
        braceletD: Participant(
            id: braceletD,
            name: "Elena Novak",
            pass: "Full pass",
            balance: Money(euros: 14),
            checkedInAt: "Fri 16:40",
            isBlocked: true,
            blockReason: "Blocked in the admin panel on Sat 01:20 — no top-ups and no payments until an organiser lifts it."
        ),
    ]

    // MARK: Arrived, waiting for a bracelet

    static let waitingGuests: [WaitingGuest] = [
        WaitingGuest(id: "w1", name: "Amélie Roux", pass: "Full pass", city: "Lyon"),
        WaitingGuest(id: "w2", name: "Tomás Herrera", pass: "Full pass", city: "Madrid"),
        WaitingGuest(id: "w3", name: "Nina Kowalski", pass: "Party pass", city: "Kraków"),
        WaitingGuest(id: "w4", name: "Sofia Ferreira", pass: "Full pass", city: "Porto"),
        WaitingGuest(id: "w5", name: "Dmitri Alvarez", pass: "Weekend pass", city: "Berlin"),
        WaitingGuest(id: "w6", name: "Hannah Vos", pass: "Party pass", city: "Utrecht"),
    ]
}
