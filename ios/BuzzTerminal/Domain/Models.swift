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
    /// Selling a door ticket, reached from the check-in screen.
    case assignEvening
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

    /// A chip id in the same four-byte shape a real NFC UID has, random enough
    /// that the backend has certainly never seen it.
    ///
    /// Exists so "scan a new bracelet" stays rehearsable against a live database.
    /// The fixture chips are a fixed list, and pairing is permanent by design, so
    /// checking one in retires it for good.
    static func fresh() -> BraceletID {
        let bytes = (0..<4).map { _ in String(format: "%02X", Int.random(in: 0...255)) }
        return BraceletID(bytes.joined(separator: ":"))
    }
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

// MARK: - Tickets

/// The six pass types the festival sells.
///
/// Kept as strings rather than an enum because `ticketType` on an imported
/// participant is whatever the registrations Sheet says, and an unrecognised
/// value must still display rather than crash. These constants are the canonical
/// spellings — used to mint evening tickets and to check what the Sheet contains.
enum TicketType {
    static let partyPass = "Party Pass"
    static let partyPassPlus = "Party Pass Plus"
    static let fullPass = "Full Pass"
    static let fullPassGold = "Full Pass Gold"
    static let jazzPerformanceTrack = "Jazz Performance Track"
    /// Sold at the door, not present in the Sheet. See `Evening`.
    static let eveningTicket = "Evening Ticket"

    static let all = [
        partyPass, partyPassPlus, fullPass, fullPassGold,
        jazzPerformanceTrack, eveningTicket,
    ]
}

/// Which evening a door-sold ticket was bought for.
///
/// Recorded for reporting and for what reception sees on screen. Deliberately
/// **not** enforced anywhere: organisers freeze an expired ticket by hand from the
/// admin panel, using the same `isBlocked` mechanism as any other bracelet. That
/// keeps the app free of date arithmetic and the rules free of a fifth refusal
/// case.
enum Evening: String, CaseIterable, Hashable, Sendable {
    case friday, saturday, sunday

    var label: String {
        switch self {
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    /// Today's evening, when today is one of the three. Used only to preselect
    /// the right button, never to validate anything.
    static var today: Evening? {
        switch Calendar.current.component(.weekday, from: .now) {
        case 6: .friday
        case 7: .saturday
        case 1: .sunday
        default: nil
        }
    }
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

    /// Where this participant came from. Decides who owns their roster fields.
    enum Source: String, Hashable, Sendable {
        /// Imported from the registrations Sheet. Roster fields are import-only.
        case sheet
        /// Sold at the door by reception. Anonymous; there is no Sheet row.
        case evening
    }

    // ── Roster ──
    var id: ParticipantID
    /// As printed on their ticket, or `EV-FRIDAY-14` for a door sale.
    var ticketRef: String
    /// For an evening ticket this is the generated label, e.g. "Evening #14" —
    /// not a person's name. Evening tickets are anonymous by design.
    var name: String
    /// One of `TicketType.all`, or whatever the Sheet said.
    var ticketType: String
    var country: String

    var source: Source = .sheet
    /// Set only on door-sold tickets.
    var evening: Evening?
    /// The nth evening ticket sold that evening. Drives `name`.
    var eveningNumber: Int?

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

    var isEveningTicket: Bool { source == .evening }

    /// `"Evening ticket · Friday"` for a door sale, otherwise the pass type.
    var ticketDescription: String {
        guard let evening else { return ticketType }
        return "Evening ticket · \(evening.label)"
    }

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
    /// Mint a door-sold evening ticket, already paired to a bracelet.
    ///
    /// The id encodes the sequence, so Firestore enforces uniqueness on `create`:
    /// two reception desks selling at the same moment collide on `ev-friday-14`
    /// and the loser retries with 15. No counter document, no coordination.
    static func eveningTicket(
        evening: Evening,
        number: Int,
        bracelet: BraceletID,
        checkedInAt: Date = .now
    ) -> Participant {
        let label = "Evening #\(number)"
        return Participant(
            id: ParticipantID("ev-\(evening.rawValue)-\(number)"),
            ticketRef: "EV-\(evening.rawValue.uppercased())-\(number)",
            name: label,
            ticketType: TicketType.eveningTicket,
            country: "",
            source: .evening,
            evening: evening,
            eveningNumber: number,
            braceletId: bracelet,
            checkedInAt: checkedInAt,
            balance: .zero
        )
    }

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
