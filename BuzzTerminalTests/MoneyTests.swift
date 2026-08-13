import Testing

@testable import BuzzTerminal

/// These cover code that is already written — they should be green from the
/// start, and they are here as worked examples of the style the exercise tests
/// are written in.
@Suite("Money")
struct MoneyTests {

    @Test("Formats with two decimals and a euro suffix")
    func formatting() {
        #expect("\(Money(euros: 23, cents: 50))" == "23.50 €")
        #expect("\(Money(euros: 2))" == "2.00 €")
        #expect("\(Money(cents: 5))" == "0.05 €")
        #expect("\(Money.zero)" == "0.00 €")
    }

    @Test("Formats negatives with a leading minus, not a mangled fraction")
    func negativeFormatting() {
        #expect("\(Money(cents: -150))" == "-1.50 €")
    }

    @Test("Drops decimals in the compact form only when they are zero")
    func compactFormatting() {
        #expect(Money(euros: 5).compactDescription == "5 €")
        #expect(Money(euros: 2, cents: 50).compactDescription == "2.50 €")
    }

    @Test("Arithmetic is exact where a Double would drift")
    func exactArithmetic() {
        // 0.10 + 0.20 == 0.30 exactly, which is not true of binary floating point.
        var total = Money(cents: 10)
        total += Money(cents: 20)
        #expect(total == Money(cents: 30))

        // Ten 2.50 espressos are exactly 25.00.
        let ten = Money(euros: 2, cents: 50) * 10
        #expect(ten == Money(euros: 25))
    }

    @Test("Parses keypad text", arguments: [
        ("", 0),
        ("0", 0),
        ("5", 500),
        ("12", 1200),
        ("12.", 1200),
        ("12.5", 1250),
        ("12.50", 1250),
        ("0.05", 5),
    ])
    func keypadParsing(input: String, expectedCents: Int) {
        #expect(Money(keypadText: input).cents == expectedCents)
    }
}
