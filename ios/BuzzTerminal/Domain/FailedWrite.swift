import Foundation

/// A write that was accepted at the till and refused by the server afterwards.
///
/// This is the artefact the whole offline design exists to produce. A queued charge
/// can be rejected on replay — the rules verify a balance against the ledger entry
/// justifying it, and if anything else moved that balance meanwhile the arithmetic
/// no longer agrees. The drink is already poured. Somebody has to be able to find
/// out what happened, hours later, from a phone that has since been restarted.
///
/// So every field here answers a question an organiser will actually ask: who, how
/// much, when, which till, and what did the server say.
struct FailedWrite: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// The client-generated transaction id, which is also the Firestore document id
    /// it would have been written as. The way to check whether it somehow landed
    /// after all.
    let transactionId: String
    let kind: Kind
    let participantId: String
    /// Denormalised on purpose: the participant document may be unreachable when
    /// this is read, and "tkt-10042" is no use to somebody looking for a guest.
    let participantName: String
    let braceletId: String
    let amount: Money
    let attemptedAt: Date
    let terminalId: String
    /// What the server actually said, kept verbatim. A rules rejection and a
    /// network fault need different responses, and paraphrasing loses that.
    let reason: String
    /// Set once an organiser has dealt with it, so the list can be worked through
    /// rather than merely stared at.
    var settled: Bool

    enum Kind: String, Codable, Sendable {
        case topUp
        case charge
        case checkIn

        var label: String {
            switch self {
            case .topUp: "Top-up"
            case .charge: "Charge"
            case .checkIn: "Check-in"
            }
        }
    }

    init(
        id: UUID = UUID(),
        transactionId: String,
        kind: Kind,
        participantId: String,
        participantName: String,
        braceletId: String,
        amount: Money,
        attemptedAt: Date,
        terminalId: String,
        reason: String,
        settled: Bool = false
    ) {
        self.id = id
        self.transactionId = transactionId
        self.kind = kind
        self.participantId = participantId
        self.participantName = participantName
        self.braceletId = braceletId
        self.amount = amount
        self.attemptedAt = attemptedAt
        self.terminalId = terminalId
        self.reason = reason
        self.settled = settled
    }

    /// One line, sayable out loud across a bar.
    var summary: String {
        switch kind {
        case .checkIn:
            "\(kind.label) — \(participantName), bracelet \(braceletId)"
        case .topUp, .charge:
            "\(kind.label) \(amount) — \(participantName)"
        }
    }

    /// What an organiser should do about it, which differs by kind and is not
    /// obvious under pressure.
    var advice: String {
        switch kind {
        case .topUp:
            // The cash is already in the till, so the guest is owed the credit.
            "The money was taken but not recorded. Top the guest up again for this amount."
        case .charge:
            // The drink is already poured. Charging again is a decision, not a fix.
            "The drink was served but not charged. Decide whether to charge again or write it off."
        case .checkIn:
            "The bracelet was handed over but not paired. Check the guest in again."
        }
    }
}

/// Everything the app has queued and not yet had confirmed, plus everything that
/// was refused.
///
/// Pure so the arithmetic can be tested: a pending count that drifts is worse than
/// no count at all, because staff will believe it.
struct SyncState: Equatable {
    private(set) var pending = 0
    private(set) var failures: [FailedWrite] = []
    /// Whether the app can currently reach Firestore. Distinct from "has pending
    /// writes": a write can be pending while online, briefly.
    var isOffline = false

    mutating func enqueued() {
        pending += 1
    }

    /// Never below zero. The count is restored from nothing on launch while
    /// Firestore's own queue survives, so an acknowledgement can arrive for a write
    /// this run never saw enqueued.
    mutating func acknowledged() {
        pending = max(0, pending - 1)
    }

    mutating func failed(_ write: FailedWrite) {
        pending = max(0, pending - 1)
        failures.append(write)
    }

    mutating func settle(_ id: UUID) {
        guard let index = failures.firstIndex(where: { $0.id == id }) else { return }
        failures[index].settled = true
    }

    mutating func replaceFailures(_ failures: [FailedWrite]) {
        self.failures = failures
    }

    var unsettledFailures: [FailedWrite] { failures.filter { !$0.settled } }

    /// The banner's text. Nil when there is nothing worth saying, so the UI has one
    /// thing to check rather than three.
    var bannerMessage: String? {
        let unsettled = unsettledFailures.count
        if unsettled > 0 {
            let word = unsettled == 1 ? "transaction" : "transactions"
            return "\(unsettled) \(word) failed to sync — show an organiser"
        }
        if pending > 0 {
            let word = pending == 1 ? "transaction" : "transactions"
            return "\(pending) \(word) waiting to sync"
        }
        return isOffline ? "Offline — sales are being queued" : nil
    }

    /// A failure is worse than a queue, and the banner should look like it.
    var bannerIsAlarming: Bool { !unsettledFailures.isEmpty }
}
