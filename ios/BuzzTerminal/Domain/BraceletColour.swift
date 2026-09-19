import Foundation

/// Which colour of wristband a pass type gets.
///
/// Set by organisers in the admin panel, one document per pass type. The
/// terminals match on `passType` verbatim — the string on the participant, not
/// the document id — so a pass type the Sheet invents gets a colour the moment
/// somebody assigns one, with no code change and no list to keep in step.
struct BraceletColour: Equatable, Sendable, Identifiable {
    /// The slug of the pass type. Only ever a document key.
    let id: String
    /// The pass type exactly as it appears on a participant.
    let passType: String
    /// One of the four dance levels, or empty for "any level".
    ///
    /// Empty is the fallback every pass type gets; a named level overrides it.
    /// Only Full Pass and Full Pass Gold split in practice, but nothing here
    /// knows that — it is a fact about the festival's classes, not about code.
    var level: String = ""
    /// `#RRGGBB`, upper case. The security rules pin the format.
    let hex: String
    /// What staff call it out loud. Empty when nobody has named it.
    let name: String

    /// The red, green and blue components, 0–1, for whatever draws the swatch.
    ///
    /// Computed here rather than in the view so it is testable without SwiftUI:
    /// `Domain/` imports `Foundation` only. `Color.init(hex:)` in the design
    /// system is the thin wrapper over this.
    var components: (red: Double, green: Double, blue: Double)? {
        Self.components(hex: hex)
    }

    /// What the screen says on the swatch: the spoken name if there is one,
    /// otherwise the hex — which is at least something to read out over a radio,
    /// and makes an unnamed colour obviously unnamed rather than looking blank.
    var label: String { name.isEmpty ? hex : name }

    /// Whether text on top of this colour should be dark rather than white.
    ///
    /// The colour now fills a bar with the name written on it, so legibility is
    /// not optional: an organiser can pick `#FFE24D`, and white on that is
    /// unreadable in a bright foyer. Relative luminance per WCAG, with the
    /// threshold where dark and light text are about equally legible.
    ///
    /// Defaults to dark text for an unparseable colour, because the bar will not
    /// be drawn at all in that case and dark is the safer guess regardless.
    var prefersDarkText: Bool {
        guard let parts = components else { return true }
        // sRGB → linear, then the WCAG coefficients. Worth doing properly: a
        // naive (r+g+b)/3 calls pure blue "light" and pure green "dark".
        let linear = { (channel: Double) -> Double in
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(parts.red)
            + 0.7152 * linear(parts.green)
            + 0.0722 * linear(parts.blue)
        return luminance > 0.36
    }
}

/// The mapping as a whole: every colour an organiser has assigned.
///
/// A value type rather than a dictionary at the call site so the lookup rule
/// lives in one place with tests. It is one rule, but it is the rule that
/// decides whether somebody is handed the right wristband.
struct BraceletColourScheme: Equatable, Sendable {
    private let byCell: [String: BraceletColour]

    init(_ colours: [BraceletColour] = []) {
        // Keyed on pass type and level, not the id. Last one wins if two
        // documents claim the same cell, which the panel makes hard but not
        // impossible — two long pass types can slug to the same key.
        byCell = Dictionary(
            colours.map { (Self.key($0.passType, $0.level), $0) },
            uniquingKeysWith: { _, later in later }
        )
    }

    /// The colour for a participant, or nil when nothing covers them.
    ///
    /// **Level first, then the pass type's fallback.** An organiser colours
    /// `Full Pass` once and everybody with one gets that colour; colouring
    /// `Full Pass · Pro` as well overrides it for the people in that track.
    /// Only Full Pass and Full Pass Gold split in practice, and that stays a
    /// fact about the festival rather than a rule in here.
    ///
    /// Nil is an ordinary outcome, not an error: a festival can colour the four
    /// pass types that matter and leave the one-off upgrade strings alone. The
    /// screen shows nothing, which is the honest answer — better than a default
    /// colour somebody hands over a wristband on the strength of.
    func colour(for participant: Participant) -> BraceletColour? {
        if !participant.level.isEmpty,
           let exact = byCell[Self.key(participant.ticketType, participant.level)] {
            return exact
        }
        return byCell[Self.key(participant.ticketType, "")]
    }

    var isEmpty: Bool { byCell.isEmpty }

    /// Case- and whitespace-insensitive, because these strings come from a
    /// hand-maintained Sheet on one side and a text field on the other, and
    /// "Full Pass " failing to match "Full Pass" would be invisible.
    private static func key(_ passType: String, _ level: String) -> String {
        let clean = { (value: String) in
            value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return "\(clean(passType))\u{0}\(clean(level))"
    }
}

extension BraceletColour {
    /// `#RRGGBB`, upper or lower case, with or without the hash.
    ///
    /// Returns nil rather than a guess for anything else, and there is no
    /// fallback colour on purpose: a swatch of the wrong colour is worse than
    /// no swatch at all, because somebody hands over a wristband because of it.
    ///
    /// Accepts lower case although the rules store upper, so a document written
    /// before that rule existed still renders.
    static func components(hex: String) -> (red: Double, green: Double, blue: Double)? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
