import Foundation

/// An extra class an organiser runs, as they priced it.
///
/// **Not a pass, and deliberately not a `DoorPass` with a different `kind`.** A
/// class admits nobody, creates no participant and is never sold at the door: it
/// is only ever added to somebody who is already here, from their own screen. It
/// shared the door catalogue for exactly one afternoon, and everything that
/// followed from that — filtering the door picker, a rule stopping a class being
/// sold as a ticket, a row in the panel's Door passes tab labelled "not a pass" —
/// was work spent keeping two different things apart in one list.
///
/// Lives in `specialSessions/{id}`, owned by organisers in the admin panel like
/// every other price list, and read by reception only: the bar neither shows the
/// classes nor sells them.
struct SpecialSession: Identifiable, Equatable, Sendable {
    /// The slug, e.g. `jazz-patrik`. Recorded on the sale as `sessionId`, and
    /// checked against this collection as the sale is written.
    let id: String
    /// Written verbatim onto the sale, and read out at the desk.
    let name: String
    let price: Money
    var sortOrder: Int = 0

    /// `"25.00 €"`, or "No price set" for a class nobody has priced yet.
    ///
    /// Zero is legal — a class thrown in for nothing is a real thing — but it is
    /// far more often a price an organiser has not typed, and reading "0.00 €"
    /// to somebody holding out a card is the failure this wording avoids.
    var priceLabel: String {
        price.isPositive ? "\(price)" : "No price set"
    }
}
