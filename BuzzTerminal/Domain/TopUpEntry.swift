import Foundation

/// The state of the cash-received keypad on the top-up screen.
///
/// Held as the raw text the operator typed rather than as a number, so that
/// "12." and "12.0" stay visually distinct while they are mid-entry — exactly
/// how a till behaves. `amount` is the parsed value the rest of the app uses.
struct TopUpEntry: Equatable, Sendable {
    /// Largest top-up the pad will accept: 999 €. A cash payment at a festival
    /// reception desk larger than this is a mistake, not a transaction.
    private static let maxIntegerDigits = 3
    
    /// What the operator has typed so far, e.g. `""`, `"12"`, `"12."`, `"12.50"`.
    private(set) var text: String = ""

    /// A key on the on-screen pad.
    enum Key: Hashable, Sendable {
        case digit(Character)
        case decimalSeparator
        case backspace

        var label: String {
            switch self {
            case .digit(let d): String(d)
            case .decimalSeparator: "."
            case .backspace: "⌫"
            }
        }
    }

    /// The pad layout from the design: 1-9, then `.`, `0`, `⌫`.
    static let keys: [Key] = {
        var keys: [Key] = (1...9).map { .digit(Character(String($0))) }
        keys.append(.decimalSeparator)
        keys.append(.digit("0"))
        keys.append(.backspace)
        return keys
    }()

    /// The quick-amount buttons above the pad.
    static let presets: [Money] = [
        Money(euros: 5), Money(euros: 10), Money(euros: 20), Money(euros: 50),
    ]

    /// `"0.00 €"` when nothing is typed, otherwise the raw text with the currency.
    /// Matches the prototype: mid-entry text is shown as typed, not reformatted.
    var display: String {
        text.isEmpty ? "\(Money.zero)" : "\(text) €"
    }

    var amount: Money { Money(keypadText: text) }

    var isConfirmable: Bool { amount.isPositive }

    var confirmButtonTitle: String {
        isConfirmable ? "Add \(amount)" : "Enter an amount"
    }

    mutating func apply(preset: Money) {
        text = "\(preset.cents / 100)"
    }

    mutating func clear() {
        text = ""
    }

    /// Handle one key press, applying the rules a cash keypad needs:
    ///
    ///   1. backspace removes the last character, and is a no-op when empty;
    ///   2. there is at most one decimal separator, and pressing it on empty
    ///      text produces `"0."` rather than a bare `"."`;
    ///   3. at most two digits after the separator;
    ///   4. a lone leading `"0"` is replaced rather than accumulated, so `0`
    ///      then `5` gives `"5"` — but `"0."` then `5` gives `"0.5"`;
    ///   5. the integer part stops at `maxIntegerDigits`.
    ///
    /// Rules 3 and 5 apply to opposite sides of the separator, hence the
    /// `else if` rather than a nested check — capping the euros must not also
    /// block the cents.
    ///
    /// Refused keypresses are silent: nothing tells the operator that a digit
    /// was dropped. Worth remembering if anyone ever reports "the pad stopped
    /// responding" at 999 €.
    mutating func press(_ key: Key) {
        switch key {
        case .backspace: if !text.isEmpty { text.removeLast() }
        case .decimalSeparator:
            if !text.contains(key.label) {
                if text == "" { text = "0" }
                text.append(key.label)
            }
        case .digit(let digit):
            if text == "0" {
                text = String(digit)
            } else {
                let components = text.components(separatedBy: Key.decimalSeparator.label)
                if components.count > 1 {
                    if components[1].count < 2 {
                        text.append(digit)
                    }
                } else if components[0].count < Self.maxIntegerDigits {
                    text.append(digit)
                }
            }
        }
    }
}
