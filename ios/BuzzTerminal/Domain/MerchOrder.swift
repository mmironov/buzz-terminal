import Foundation

/// A t-shirt or tote bag somebody paid for when they registered, and whether
/// they have been given it.
///
/// Lives in `participants/{id}/merch/order` rather than on the participant, and
/// that placement is the feature rather than an implementation detail: every
/// field on a participant document is readable by every signed-in terminal, and
/// a bartender has no business knowing what size somebody wears. The security
/// rules let reception read this and the bar not. See `docs/merch.md`.
struct MerchOrder: Equatable, Sendable {

    /// What was ordered. The Sheet sells three things; the other two cases are
    /// states rather than products.
    enum Item: String, Equatable, Sendable {
        case shirt
        case tote
        case shirtAndTote
        /// Ordered and then withdrawn in the Sheet. The document is kept rather
        /// than deleted, because the record that something was handed over
        /// outlives the order.
        case none
        /// A form option the importer did not recognise. Shown as such, because
        /// "they ordered something, ask them" is more use at a desk than
        /// silently claiming they ordered nothing.
        case unknown

        /// What a wire value that is not one of these becomes. A new option in
        /// the form reaches the desk as "something", never as "nothing".
        init(wire: String?) {
            self = Item(rawValue: wire ?? "") ?? .unknown
        }
    }

    var item: Item
    /// Nil for a tote-only order, and for any order where the guest left it
    /// blank. Never the string "No Swing Buzz attire" — the importer strips the
    /// form's own way of saying "nothing", which is an option in all three
    /// dropdowns rather than a blank.
    var size: String?
    var colour: String?

    /// When reception handed it over, and who was on the desk.
    var collectedAt: Date?
    var collectedBy: String?

    var isCollected: Bool { collectedAt != nil }

    /// Whether there is anything to hand over at all.
    ///
    /// A withdrawn order is not "nothing ordered" as far as the document is
    /// concerned, but it is as far as the desk is concerned, so both read the
    /// same here and the screen shows nothing.
    var hasSomethingToCollect: Bool { item != .none }

    /// What the desk is looking for, in the order somebody would say it out
    /// loud: the thing, then the size, then the colour.
    ///
    /// `"T-shirt · M · Sky Blue"`, or `"Tote bag"` when there is nothing more
    /// to say. Built here rather than in the view because a tote bag has no
    /// size and a blank separator hanging off the end of a label is the kind of
    /// thing nobody notices until it is on fifty screens.
    var summary: String {
        ([item.label] + [size, colour].compactMap(\.self)).joined(separator: " · ")
    }

    /// `"Collected Sat 17:12"`, or nil while it is still owed.
    var collectedLabel: String? {
        guard let collectedAt else { return nil }
        return "Collected \(Self.formatter.string(from: collectedAt))"
    }

    /// 24-hour and day-of-week, matching `Participant.checkedInLabel` — staff
    /// read these out to each other across a room.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()
}

extension MerchOrder.Item {
    var label: String {
        switch self {
        case .shirt: "T-shirt"
        case .tote: "Tote bag"
        case .shirtAndTote: "T-shirt and tote bag"
        case .none: "Nothing ordered"
        case .unknown: "Merch ordered — check the Sheet"
        }
    }
}
