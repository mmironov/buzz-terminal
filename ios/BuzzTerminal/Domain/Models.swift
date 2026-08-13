import Foundation

// MARK: - Staff

/// Which terminal mode a signed-in staff member gets. The festival runs the same
/// binary at reception and behind the bar; the account decides the flow.
///
/// From iteration 2 this comes from a Firebase Auth custom claim, not from
/// anything the client chooses — see `docs/firestore-schema.md`, "Roles".
enum StaffRole: String, Hashable, Sendable {
    case reception
    case bar

    var label: String {
        switch self {
        case .reception: "Reception"
        case .bar: "Bar"
        }
    }

    /// Caption under the device frame in the design; also the screen a fresh
    /// sign-in lands on.
    var homeScreen: Screen {
        switch self {
        case .reception: .receptionHome
        case .bar: .barMenu
        }
    }
}

// MARK: - Screens

/// Every distinct state the terminal UI can be in.
///
/// This is a flat enum rather than a `NavigationStack` path on purpose — see
/// `AppModel` for the reasoning.
enum Screen: Hashable, Sendable {
    case signIn
    // Reception
    case receptionHome
    case assign
    case participant
    case blocked
    case topUp
    // Bar
    case barMenu
    case cart
    case payReview
    // Shared
    case receipt
}

// MARK: - Identifiers

/// The NFC chip UID, as printed in the design (`04:B4:2F:11`).
struct BraceletID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    var description: String { rawValue }
}

/// Identity of a person on the roster — the Firestore document id, derived from
/// the Google Sheet's stable ticket reference.
///
/// Distinct from `BraceletID` on purpose. Until iteration 2 these were the same
/// thing, because a participant only existed once a chip was paired to them. Now
/// the roster comes from the Sheet, so a participant exists from the moment they
/// buy a ticket and the bracelet is something that happens to them later.
struct ParticipantID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    var description: String { rawValue }
}

/// A bracelet the prototype can simulate reading. Real Core NFC scanning lands
/// in iteration 3; until then `SimulatedBraceletReader` picks from this list.
struct SimulatedBracelet: Identifiable, Hashable, Sendable {
    let id: BraceletID
    /// Human hint shown in the prototype-only simulator panel.
    let hint: String
}

// MARK: - People

/// Somebody who bought a ticket.
///
/// One type for the whole lifecycle. `braceletId == nil` *is* the "arrived but
/// not checked in yet" state — there is no separate `WaitingGuest`, because the
/// roster now comes from the Sheet and everybody on it is a participant from the
/// moment they buy a ticket. This mirrors `participants/{id}` in Firestore
/// exactly, so the mapping layer has nothing to reconcile.
struct Participant: Identifiable, Hashable, Sendable {

    // ── Roster: owned by the Google Sheet import, never written by the app ──
    var id: ParticipantID
    /// As printed on their ticket. The Sheet's stable unique key.
    var ticketRef: String
    var name: String
    /// "Full pass", "Party pass", "Weekend pass". `ticketType` in Firestore.
    var ticketType: String
    var city: String

    // ── Festival state: owned by the terminals ──
    /// `nil` until reception pairs a chip. Permanent once set.
    var braceletId: BraceletID?
    var checkedInAt: Date?
    var balance: Money = .zero

    // ── Organiser state: owned by the admin panel ──
    var isBlocked: Bool = false
    /// Why an organiser froze the bracelet, shown verbatim on the blocked screen.
    var blockReason: String?

    /// The check-in list is everybody this is true for.
    var isAwaitingCheckIn: Bool { braceletId == nil }

    /// `"Checked in Fri 17:12"`, or `"Checked in just now"` immediately after
    /// pairing — the design distinguishes the two.
    var checkedInLabel: String {
        guard let checkedInAt else { return "Not checked in" }
        if Date.now.timeIntervalSince(checkedInAt) < 120 {
            return "Checked in just now"
        }
        return "Checked in \(Self.checkInFormatter.string(from: checkedInAt))"
    }

    /// `"Fri 17:12"`. 24-hour regardless of device settings, because the design
    /// shows it that way and staff read these out to each other across a room.
    private static let checkInFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()
}

extension Participant {
    /// Case- and diacritic-insensitive substring match against the guest's name
    /// or their ticket type. Deliberately *not* the city: the row displays it,
    /// but the field's placeholder only promises "participant or ticket".
    ///
    /// Note that a query of `"pass"` matches every guest, since every ticket
    /// type ends in it. Acceptable for a list this short; a real desk would
    /// probably want the ticket match to be prefix-only.
    func matches(query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return true }

        return name.localizedCaseInsensitiveContains(trimmed) || ticketType.localizedCaseInsensitiveContains(trimmed)
    }
}

// MARK: - Bar

struct Drink: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let price: Money
}

/// One line of the current round: a drink and how many of it.
struct CartLine: Identifiable, Hashable, Sendable {
    var id: String { drink.id }
    var drink: Drink
    var quantity: Int

    var total: Money { drink.price * quantity }
    /// `"2 × Draught beer"` as in the design.
    var label: String { "\(quantity) × \(drink.name)" }
    var unitLabel: String { "\(drink.price) each" }
}

/// The bar's current round, keyed by drink id.
struct Cart: Equatable, Sendable {
    private var quantities: [String: Int] = [:]

    var isEmpty: Bool { quantities.values.allSatisfy { $0 <= 0 } }
    var itemCount: Int { quantities.values.reduce(0, +) }

    func quantity(of drink: Drink) -> Int { quantities[drink.id] ?? 0 }

    /// Lines in menu order, so the cart does not reshuffle as staff tap.
    func lines(in menu: [Drink]) -> [CartLine] {
        menu.compactMap { drink in
            let qty = quantities[drink.id] ?? 0
            return qty > 0 ? CartLine(drink: drink, quantity: qty) : nil
        }
    }

    func total(in menu: [Drink]) -> Money {
        lines(in: menu).reduce(Money.zero) { $0 + $1.total }
    }

    /// Add or remove one; a line that reaches zero disappears.
    mutating func bump(_ drink: Drink, by delta: Int) {
        let next = max(0, (quantities[drink.id] ?? 0) + delta)
        if next == 0 {
            quantities.removeValue(forKey: drink.id)
        } else {
            quantities[drink.id] = next
        }
    }

    mutating func removeAll() { quantities.removeAll() }
}

// MARK: - Receipts

/// The confirmation screen shared by all three successful outcomes.
struct Receipt: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case checkIn, topUp, payment }

    var kind: Kind
    var title: String
    var note: String
    var rows: [Row]
    var balance: Money
    /// Whether the transaction went into the offline queue instead of the server.
    var queuedOffline: Bool = false

    struct Row: Hashable, Sendable, Identifiable {
        var id: String { key }
        var key: String
        var value: String
    }

    /// The band across the top of the receipt.
    var bandText: String {
        switch kind {
        case .payment: queuedOffline ? "Approved · offline" : "Payment approved"
        case .topUp: "Top-up approved"
        case .checkIn: "Check-in complete"
        }
    }

    var primaryActionLabel: String {
        switch kind {
        case .payment: "New order"
        case .topUp: "Read next bracelet"
        case .checkIn: "Top up now"
        }
    }

    var secondaryActionLabel: String {
        kind == .payment ? "Back to menu" : "Done"
    }
}
