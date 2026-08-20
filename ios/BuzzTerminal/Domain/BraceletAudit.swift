import Foundation

/// Walking a box of wristbands, checking every UID is unique.
///
/// Exists because a duplicate UID is undetectable once bracelets are on wrists: two
/// chips reporting the same id are the same chip as far as any phone is concerned,
/// so the two guests silently share one balance and the bar charges the wrong
/// person. Nothing downstream can catch it. Checking the box is the whole defence.
///
/// Pure, and separate from the NFC session on purpose — the decision "is this a new
/// bracelet, the same one still in the field, or a genuine duplicate?" is the part
/// worth being sure about, and it needs no hardware to test.
struct BraceletAudit: Equatable {

    /// Every distinct chip, in the order first seen. The index is what an operator
    /// counts against the pile.
    private(set) var seen: [BraceletID] = []

    /// Repeats worth a human's attention, newest first.
    private(set) var repeats: [Repeat] = []

    /// Total reads, including ones ignored as the same tag still being held.
    private(set) var reads = 0

    /// A struct rather than a tuple: Swift cannot synthesise `Equatable` for a
    /// stored tuple, and `Equatable` is what lets a test assert `audit == .init()`
    /// after a reset.
    private struct LastRead: Equatable {
        let id: BraceletID
        let at: Date
    }
    private var lastRead: LastRead?

    /// How long the same chip is assumed to be the same physical wristband still
    /// sitting in the reader's field. Core NFC will happily re-detect a tag that
    /// has not moved, and reporting that as a duplicate would make the tool cry
    /// wolf on its first bracelet.
    static let sameTagWindow: TimeInterval = 3

    struct Repeat: Equatable, Identifiable {
        let id: BraceletID
        /// 1-based position of the first sighting, so it can be said out loud:
        /// "this is the same id as number 12".
        let firstSeenAt: Int
        let secondSeenAt: Int
    }

    enum Outcome: Equatable {
        /// A chip not seen before. The normal case.
        case new(position: Int)
        /// The same chip, immediately again — almost certainly still in the field.
        /// Not reported to the operator at all.
        case stillHolding
        /// A chip seen earlier in this run. Either a wristband scanned twice, or
        /// two wristbands sharing a UID, and this cannot tell which.
        case repeated(Repeat)
    }

    /// Record a read and say what it was.
    @discardableResult
    mutating func record(_ id: BraceletID, at now: Date) -> Outcome {
        reads += 1

        if let last = lastRead,
           last.id == id,
           now.timeIntervalSince(last.at) < Self.sameTagWindow {
            lastRead = LastRead(id: id, at: now)
            return .stillHolding
        }
        lastRead = LastRead(id: id, at: now)

        if let index = seen.firstIndex(of: id) {
            let event = Repeat(
                id: id,
                firstSeenAt: index + 1,
                secondSeenAt: seen.count + repeats.count + 1
            )
            repeats.insert(event, at: 0)
            return .repeated(event)
        }

        seen.append(id)
        return .new(position: seen.count)
    }

    mutating func reset() {
        self = BraceletAudit()
    }

    /// A one-line verdict, for the top of the screen.
    var summary: String {
        if seen.isEmpty { return "Nothing scanned yet." }
        let bracelets = seen.count == 1 ? "1 bracelet" : "\(seen.count) bracelets"
        guard !repeats.isEmpty else { return "\(bracelets), all unique." }
        let word = repeats.count == 1 ? "repeat" : "repeats"
        return "\(bracelets), \(repeats.count) \(word) to check."
    }

    /// Plain text, so a run can be pasted into a message to a vendor.
    var transcript: String {
        var lines = ["\(seen.count) unique, \(reads) reads"]
        for (index, id) in seen.enumerated() {
            lines.append("\(index + 1). \(id.rawValue)")
        }
        if !repeats.isEmpty {
            lines.append("")
            lines.append("Repeats:")
            for event in repeats.reversed() {
                lines.append("  \(event.id.rawValue) — also seen as #\(event.firstSeenAt)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
