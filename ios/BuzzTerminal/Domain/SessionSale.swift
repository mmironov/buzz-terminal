import Foundation

/// An extra class somebody added to their weekend, and what they paid for it.
///
/// Lives in `participants/{id}/sessions/{sessionId}`, beside the merch
/// subcollection and readable by the same people: reception and the organiser
/// panel, not the bar. What somebody bought is not the bar's business, and the
/// amount makes it a takings record as well as a fact about them.
///
/// **One document per session bought, and it is written once.** The document
/// existing *is* the sale — there is no `sold: false` state, because somebody
/// who has not bought a class has no row, exactly as somebody who ordered no
/// t-shirt has no order. It is never updated: a sale is what happened, and the
/// rules refuse both an update and a delete.
///
/// The name and the price are snapshots of the catalogue at the moment of sale,
/// for the same reason a ledger line snapshots a drink's price: renaming a class
/// or changing what it costs next week must not rewrite what was taken today.
struct SessionSale: Equatable, Sendable, Identifiable {
    /// The catalogue id, which is also the document id.
    let sessionId: String
    var id: String { sessionId }
    /// What the class was called when it was sold.
    let name: String
    /// What was collected, in cents, when it was sold.
    let price: Money
    /// Cash or card — mandatory, like every other money the desk takes.
    let method: PaymentMethod
    /// The server's clock. Nil only in the moment between writing and reading
    /// back, which no screen shows.
    let soldAt: Date?
    let soldBy: String

    /// `"Sold Sat 14:03 · Cash"`, or `"Sold · Cash"` before the write lands.
    var soldLabel: String {
        guard let soldAt else { return "Sold · \(method.label)" }
        return "Sold \(Self.formatter.string(from: soldAt)) · \(method.label)"
    }

    /// 24-hour and day-of-week, matching the merch, free-shirt and check-in
    /// labels — staff read these out across a room.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()
}
