import Foundation

// ═══════════════════════════════════════════════════════════════════════════
//  Selling a pass at the desk.
//
//  Until now the door sold one thing: a numbered evening ticket. It now sells
//  the whole catalogue — Party Pass, Full Pass Gold, whatever organisers have
//  priced in the admin panel — and those buyers have names.
//
//  The price is **shown, never charged**. Nothing here moves money: the desk
//  takes cash or a card, and the number on screen is what they ask for. A pass
//  is not credit on a bracelet, so it writes no ledger entry and no balance.
// ═══════════════════════════════════════════════════════════════════════════

/// One thing reception may sell, as an organiser priced it.
struct DoorPass: Identifiable, Equatable, Sendable {
    /// The slug, e.g. `full-pass-gold`. Only ever a key — the apps match on
    /// `name`, and `firestore.rules` checks the two agree as the sale is written.
    let id: String
    /// Written verbatim onto the buyer as their `ticketType`.
    let name: String
    /// What it costs, and for an evening ticket what it costs on a night with
    /// no price of its own.
    let price: Money
    /// Friday, Saturday and Sunday can differ, so an evening ticket carries a
    /// price per night. Partial on purpose: only the nights that differ need an
    /// entry, and the rest fall back to `price`.
    var prices: [Evening: Money] = [:]
    var sortOrder: Int = 0
    var kind: Kind = .pass

    enum Kind: String, Equatable, Sendable {
        /// Ask for the buyer: name, dance role, level where it applies.
        case pass
        /// The numbered ticket: a name and a night, nothing else.
        case evening
    }

    /// What this costs on a given night. Nil means "not sold by the night", so
    /// the flat price applies.
    func price(on evening: Evening?) -> Money {
        guard let evening else { return price }
        return prices[evening] ?? price
    }

    /// `"205.00 €"`, or "No price set" for a row nobody has priced yet.
    ///
    /// Zero is legal — a comp is a real thing — but it is far more often a price
    /// an organiser has not typed, and reading "0.00 €" to a paying guest is the
    /// failure this wording avoids.
    func priceLabel(on evening: Evening? = nil) -> String {
        let amount = price(on: evening)
        return amount.isPositive ? "\(amount)" : "No price set"
    }

    /// What the screens above the scan say they are about to take.
    ///
    /// Separate from `priceLabel` because "No price set to collect" is not a
    /// sentence, and this one is read by somebody holding out their hand.
    func collectLabel(on evening: Evening? = nil) -> String {
        let amount = price(on: evening)
        return amount.isPositive ? "\(amount) to collect" : "No price set in the admin panel"
    }

    /// Whether the nights are priced differently from each other.
    ///
    /// Drives nothing on its own; it is here so a screen can say "45 € a night"
    /// rather than repeating the same number three times, if anybody ever wants
    /// that. The evening screen currently shows all three regardless, because
    /// the desk is reading one line per night either way.
    var nightsDiffer: Bool {
        Set(Evening.allCases.map { price(on: $0) }).count > 1
    }

    /// Whether this pass has a level worth asking for.
    ///
    /// The same two pass types `Participant.levelForDisplay` prints, and for the
    /// same reason: those are the ones whose classes split by level. Matched on
    /// the name rather than the id, so a pass renamed in the panel behaves the
    /// way its name says it should.
    var asksForLevel: Bool {
        let clean = { (value: String) in
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return [TicketType.fullPass, TicketType.fullPassGold].map(clean).contains(clean(name))
    }
}

/// Which side of the partnership somebody dances.
///
/// Named `danceRole` everywhere it is stored, never `role`. `role` is the staff
/// claim `firestore.rules` reads to decide who may take money, and the two have
/// been kept apart deliberately since the Sheet's own "Role" column turned out
/// to mean this one.
enum DanceRole: String, CaseIterable, Equatable, Sendable, Identifiable {
    case leader
    case follower

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leader: "Leader"
        case .follower: "Follower"
        }
    }

    var wire: String { rawValue }
}

/// What the desk has typed so far about a buyer.
///
/// A draft rather than a half-built `Participant`, because a `Participant` that
/// exists is somebody who has been sold a pass — and the whole point of this type
/// is the period where that is not yet true.
struct DoorSaleDraft: Equatable, Sendable {
    var name: String = ""
    var danceRole: DanceRole?
    var level: String = ""
    var email: String = ""

    /// The levels a class actually runs at — three, not the Sheet's four.
    ///
    /// `Other` is the registration form's way of saying "not applicable": it is
    /// what somebody buying a Party Pass answers, and a Party Pass has no level.
    /// Nobody standing at the desk buying a Full Pass is in a class called
    /// Other, and there is no Other wristband to hand them — the panel colours
    /// Full Pass INT, ADV and PRO. Offering it here only invited the fourth box
    /// to be tapped when somebody did not want to ask.
    ///
    /// It remains a valid value on a participant, because the Sheet produces it
    /// and the importer keeps what it is given. This is about what the desk can
    /// choose, not about what exists.
    static let levels = ["Intermediate", "Advanced", "Pro"]

    /// The longest name `firestore.rules` accepts.
    static let maxName = 80
    /// The longest email it accepts.
    static let maxEmail = 120

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Something with an `@` in the middle and no spaces.
    ///
    /// Deliberately not a real address validator. A mistyped address is a support
    /// problem; a desk that cannot complete a sale because a regex disagrees with
    /// somebody's perfectly good address is a queue. `firestore.rules` applies the
    /// same shallow check, so the two cannot disagree about what to refuse.
    var emailLooksLikeAddress: Bool {
        let value = trimmedEmail
        guard !value.isEmpty else { return true }  // blank is allowed
        guard value.count <= Self.maxEmail else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2
            && !parts[0].isEmpty && !parts[1].isEmpty
            && !value.contains(" ")
    }

    /// Whether this sale can go through, and if not, what is missing.
    ///
    /// Returns the reason rather than a bare `false` so the button can say it.
    /// A disabled button that does not explain itself is the thing somebody
    /// stands at a desk tapping.
    func blocker(for pass: DoorPass) -> String? {
        if trimmedName.isEmpty { return "Enter the guest’s name" }
        if trimmedName.count > Self.maxName { return "That name is too long" }
        // An evening ticket asks for a name and nothing else. It is one night at
        // a door with a queue behind it — no class list to build, so no dance
        // role, no level, and nowhere to send an email.
        guard pass.kind != .evening else { return nil }
        if danceRole == nil { return "Choose leader or follower" }
        if pass.asksForLevel && level.isEmpty { return "Choose a level" }
        if !emailLooksLikeAddress { return "Check the email address" }
        return nil
    }

    func isComplete(for pass: DoorPass) -> Bool { blocker(for: pass) == nil }

    /// The level actually recorded: empty for a pass that does not split by one,
    /// whatever the form happened to be holding when the operator changed pass.
    func level(for pass: DoorPass) -> String {
        pass.asksForLevel ? level : ""
    }
}
