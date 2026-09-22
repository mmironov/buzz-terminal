import Foundation

/// A shirt somebody gets for nothing — a teacher, a volunteer, whoever the
/// organisers put on the list — and whether they have been given it.
///
/// Lives beside the preordered order, in `participants/{id}/merch/freeShirt`,
/// and is readable by reception and not by the bar for the same reason: every
/// field on a participant document is readable by every terminal, and what
/// somebody was given is not the bar's business.
///
/// **It differs from `MerchOrder` in exactly one way, and everything here
/// follows from it.** A preorder was chosen months ago, so the Sheet knows the
/// item, the size and the colour, and the desk may only say it was handed over.
/// Nobody chose a free shirt in advance: the Sheet knows only *that* somebody
/// gets one, and the size and colour are picked at the desk, off whatever is in
/// the box. So those two are festival state here, written by the terminal, and
/// the importer is forbidden from touching them.
struct FreeShirt: Equatable, Sendable {

    /// Whether the Sheet says this person is owed one.
    ///
    /// False is a real state rather than an absent document: somebody taken off
    /// the list keeps whatever record already exists, because the shirt may
    /// already be on their back.
    var entitled: Bool

    /// Chosen at the desk, not imported. Nil until the shirt is handed over.
    var size: String?
    var colour: String?

    /// When reception handed it over, and who was on the desk.
    var collectedAt: Date?
    var collectedBy: String?

    var isCollected: Bool { collectedAt != nil }

    /// The sizes the festival printed. Offered in full: the notes in the Sheet
    /// say some colours came in fewer sizes, but by the festival the truth is
    /// whatever is in the box in front of the desk, and a picker that refuses a
    /// shirt somebody is physically holding is worse than no picker.
    static let sizes = ["XS", "S", "M", "L", "XL"]

    /// The four the festival printed, in the Sheet's own spelling — the same
    /// words a preordered shirt displays, so the desk reads one vocabulary.
    static let colours = ["Sky Blue", "Natural", "French Navy", "Pale Pink"]

    /// Whether a handover can be recorded: both halves chosen.
    ///
    /// The rules refuse a collection without them, so this is the same rule on
    /// the near side of the network — a refusal arrives as a red banner in
    /// front of somebody holding a shirt.
    var canBeHandedOver: Bool { size != nil && colour != nil }

    /// `"M · Sky Blue"`, or what is still missing.
    var choiceSummary: String {
        switch (size, colour) {
        case let (size?, colour?): "\(size) · \(colour)"
        case let (size?, nil): "\(size) · pick a colour"
        case let (nil, colour?): "\(colour) · pick a size"
        case (nil, nil): "Pick a size and a colour"
        }
    }

    /// `"Handed over Sat 17:12"`, or nil while it is still owed.
    var collectedLabel: String? {
        guard let collectedAt else { return nil }
        return "Handed over \(Self.formatter.string(from: collectedAt))"
    }

    /// 24-hour and day-of-week, matching `MerchOrder` and
    /// `Participant.checkedInLabel` — staff read these out across a room.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()
}
