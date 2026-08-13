import Foundation

/// Money as integer minor units (euro cents).
///
/// The HTML prototype used a JavaScript `Number` for balances (`balance: 23.5`).
/// That is fine for a mock but wrong for money: binary floating point cannot
/// represent 0.10 exactly, so repeated top-ups and charges accumulate error.
/// `Money` stores cents in an `Int`, which is exact for every amount this app
/// will ever see, and only converts to a decimal string at the edges.
struct Money: Hashable, Comparable, Sendable {
    /// The amount in euro cents. May be negative (used for deltas).
    var cents: Int

    init(cents: Int) {
        self.cents = cents
    }

    static let zero = Money(cents: 0)

    /// Build from a whole-and-fraction literal, e.g. `Money(euros: 2, cents: 50)`.
    init(euros: Int, cents: Int = 0) {
        self.cents = euros * 100 + cents
    }

    static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }

    static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }
    static func * (lhs: Money, rhs: Int) -> Money { Money(cents: lhs.cents * rhs) }

    static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }

    var isPositive: Bool { cents > 0 }

    /// Never below zero — used for "short by …" copy on a declined payment.
    var clampedToZero: Money { Money(cents: max(0, cents)) }
}

extension Money: CustomStringConvertible {
    /// `"23.50 €"` — matches the prototype's `n.toFixed(2) + ' €'` exactly.
    ///
    /// Deliberately locale-independent: every terminal at the festival shows the
    /// same string regardless of the phone's region, which keeps a staff member
    /// reading a balance out loud unambiguous. Localising this is a later call
    /// (see README, "Known simplifications").
    var description: String {
        let sign = cents < 0 ? "-" : ""
        let abs = Swift.abs(cents)
        return "\(sign)\(abs / 100).\(String(format: "%02d", abs % 100)) €"
    }
}

extension Money {
    /// `"5 €"` rather than `"5.00 €"` — used for the top-up preset buttons,
    /// which the design writes without the decimals.
    var compactDescription: String {
        cents % 100 == 0 ? "\(cents / 100) €" : description
    }
}

extension Money {
    /// Parse a keypad string like `"12"`, `"12."`, `"12.5"`, `"12.50"`.
    /// Returns `.zero` for empty or malformed input.
    init(keypadText: String) {
        guard !keypadText.isEmpty else { self = .zero; return }
        let parts = keypadText.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = Int(parts.first ?? "") ?? 0
        var fraction = 0
        if parts.count == 2 {
            // "5" means 50 cents, "50" means 50 cents, "" means 0
            let digits = String(parts[1].prefix(2))
            let padded = digits.padding(toLength: 2, withPad: "0", startingAt: 0)
            fraction = Int(padded) ?? 0
        }
        self = Money(euros: whole, cents: fraction)
    }
}
