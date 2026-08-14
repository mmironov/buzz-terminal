import FirebaseFirestore
import Foundation

// ═══════════════════════════════════════════════════════════════════════════
//  Firestore ↔ domain mapping.
//
//  Written by hand rather than with `Codable`. These field names are not an
//  implementation detail — `backend/firestore.rules` names every one of them, and
//  49 rules tests assert on them. A property-name change that Codable would
//  silently follow is a change to a security contract, so the strings live here,
//  in one place, spelled out.
//
//  Money crosses this boundary as an integer of cents. Firestore numbers are
//  doubles; 23.50 is not representable, and a balance that drifts by a cent per
//  transaction is worse than one that is obviously wrong.
// ═══════════════════════════════════════════════════════════════════════════

enum Fire {
    enum Collection {
        static let participants = "participants"
        static let transactions = "transactions"
        static let bracelets = "bracelets"
        static let drinks = "drinks"
    }

    enum Participant {
        static let source = "source"
        static let ticketRef = "ticketRef"
        static let name = "name"
        static let nameLower = "nameLower"
        static let searchTokens = "searchTokens"
        static let ticketType = "ticketType"
        static let country = "country"
        static let evening = "evening"
        static let eveningNumber = "eveningNumber"
        static let braceletId = "braceletId"
        static let checkedInAt = "checkedInAt"
        static let balance = "balance"
        static let lastTxId = "lastTxId"
        static let isBlocked = "isBlocked"
        static let blockReason = "blockReason"
        static let createdBy = "createdBy"
        static let updatedAt = "updatedAt"
    }

    enum Transaction {
        static let clientTxId = "clientTxId"
        static let type = "type"
        static let amount = "amount"
        static let signedAmount = "signedAmount"
        static let staffUid = "staffUid"
        static let terminalId = "terminalId"
        static let createdAt = "createdAt"
        static let queuedOffline = "queuedOffline"

        static let typeTopUp = "topup"
        static let typeCharge = "charge"
    }

    enum Bracelet {
        static let participantId = "participantId"
        static let staffUid = "staffUid"
        static let pairedAt = "pairedAt"
    }

    enum Drink {
        static let name = "name"
        static let price = "price"
        static let sortOrder = "sortOrder"
        static let isActive = "isActive"
    }
}

// MARK: - Reading

extension Participant {
    /// Build from a Firestore document, or `nil` if it is missing the fields that
    /// make it a participant at all.
    ///
    /// Tolerant of absent optionals and of an unrecognised `ticketType` — the
    /// Sheet is edited by humans, and a document that is merely odd should display
    /// rather than take the terminal down mid-service. Intolerant of a missing
    /// `name` or `balance`, because there is nothing sensible to show instead.
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let name = data[Fire.Participant.name] as? String,
              let balanceCents = data[Fire.Participant.balance] as? Int
        else { return nil }

        self.init(
            id: ParticipantID(document.documentID),
            ticketRef: data[Fire.Participant.ticketRef] as? String ?? "",
            name: name,
            ticketType: data[Fire.Participant.ticketType] as? String ?? "",
            country: data[Fire.Participant.country] as? String ?? "",
            source: (data[Fire.Participant.source] as? String).flatMap(Source.init(rawValue:)) ?? .sheet,
            evening: (data[Fire.Participant.evening] as? String).flatMap(Evening.init(rawValue:)),
            eveningNumber: data[Fire.Participant.eveningNumber] as? Int,
            braceletId: (data[Fire.Participant.braceletId] as? String).map(BraceletID.init),
            checkedInAt: (data[Fire.Participant.checkedInAt] as? Timestamp)?.dateValue(),
            balance: Money(cents: balanceCents),
            isBlocked: data[Fire.Participant.isBlocked] as? Bool ?? false,
            blockReason: data[Fire.Participant.blockReason] as? String
        )
    }
}

extension Drink {
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let name = data[Fire.Drink.name] as? String,
              let priceCents = data[Fire.Drink.price] as? Int
        else { return nil }
        self.init(id: document.documentID, name: name, price: Money(cents: priceCents))
    }
}

// MARK: - Writing

extension Participant {
    /// The document a door-sold evening ticket is created as.
    ///
    /// Every field here is checked by `isWellFormedEveningTicket` in
    /// `firestore.rules`. Changing one without changing the rule means the write
    /// starts failing with `PERMISSION_DENIED`, which is the intended outcome:
    /// this shape is a contract, not a convention.
    func eveningTicketDocument(createdBy staffUid: String) -> [String: Any] {
        precondition(source == .evening, "only door sales are client-created")
        guard let evening, let eveningNumber, let braceletId else {
            preconditionFailure("an evening ticket must carry its evening, number and bracelet")
        }
        return [
            Fire.Participant.source: Source.evening.rawValue,
            Fire.Participant.ticketType: TicketType.eveningTicket,
            Fire.Participant.evening: evening.rawValue,
            Fire.Participant.eveningNumber: eveningNumber,
            Fire.Participant.ticketRef: ticketRef,
            Fire.Participant.name: name,
            Fire.Participant.nameLower: name.lowercased(),
            Fire.Participant.searchTokens: Self.searchTokens(name: name, ticketType: TicketType.eveningTicket),
            Fire.Participant.country: "",
            Fire.Participant.braceletId: braceletId.rawValue,
            Fire.Participant.checkedInAt: FieldValue.serverTimestamp(),
            Fire.Participant.balance: 0,
            Fire.Participant.lastTxId: NSNull(),
            Fire.Participant.isBlocked: false,
            Fire.Participant.blockReason: NSNull(),
            Fire.Participant.createdBy: staffUid,
        ]
    }

    /// Lowercased word tokens, matching what the importer writes so the two
    /// sources of participants are searchable the same way.
    static func searchTokens(name: String, ticketType: String) -> [String] {
        let words = "\(name) \(ticketType)".lowercased().split(separator: " ").map(String.init)
        return Array(Set(words.filter { !$0.isEmpty }))
    }
}

extension CartLine {
    var ledgerLabel: String { label }
}
