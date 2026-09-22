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
        /// A subcollection of a participant, holding exactly one document. See
        /// `Merch.documentId` and `docs/merch.md`.
        static let merch = "merch"
        /// Pass type → wristband colour, one document per pass type.
        static let braceletColours = "braceletColours"
        /// What reception may sell at the desk, priced in the admin panel.
        static let doorPasses = "doorPasses"
        /// The extra classes, priced in the admin panel. A collection of their
        /// own: a class is not a pass and is never sold at the door.
        static let specialSessions = "specialSessions"
        /// A subcollection of a participant holding one document: the buyer's
        /// email. Reception and the organiser panel only — see `docs/door-sales.md`.
        static let contact = "contact"
        /// A subcollection of a participant: one document per extra class they
        /// bought at the desk, keyed by the catalogue id. Reception and the
        /// panel only, like merch — what somebody bought, and what they paid.
        static let sessions = "sessions"
    }

    enum SpecialSession {
        static let name = "name"
        static let price = "price"
        static let sortOrder = "sortOrder"
        static let isActive = "isActive"
    }

    enum SessionSale {
        /// One class per person, so the sale lives at a fixed id and Firestore's
        /// create-fails-if-exists is what makes "at most one" true. Which class
        /// it was is a field.
        static let documentId = "booked"

        /// Which class was bought — a `doorPasses` id with `kind: session`.
        static let sessionId = "sessionId"
        /// The class's name and price as the catalogue held them at the moment
        /// of sale. Snapshots, like a ledger line's `unitPrice`.
        static let name = "name"
        static let price = "price"
        /// `cash` or `card`, the same two strings everywhere else money moves.
        static let method = "method"
        static let soldAt = "soldAt"
        static let soldBy = "soldBy"
    }

    enum BraceletColour {
        /// The pass type verbatim. What the apps match on — never the id.
        static let passType = "passType"
        /// One of the four dance levels, or absent for "any level".
        static let level = "level"
        /// `friday`, `saturday` or `sunday` — the three wristbands that differ
        /// by night rather than by pass type. Absent on everything else.
        static let evening = "evening"
        static let colour = "colour"
        static let name = "name"
    }

    enum DoorPass {
        static let name = "name"
        /// Cents, like every other price. For an evening ticket this is the
        /// fallback for a night with no price of its own.
        static let price = "price"
        /// `{ friday: 4500, saturday: 5000 }` — cents per night, partial.
        static let prices = "prices"
        static let sortOrder = "sortOrder"
        static let isActive = "isActive"
        /// `"pass"` or `"evening"`. Decides which flow the terminal runs.
        static let kind = "kind"

        static let kindPass = "pass"
        static let kindEvening = "evening"
    }

    enum Contact {
        /// One document per person, at a fixed path — a point read, like merch.
        static let documentId = "details"

        static let email = "email"
        static let addedBy = "addedBy"
        static let addedAt = "addedAt"
    }

    enum Merch {
        /// One order per person, at a fixed path. A known path means a point
        /// read rather than a query, which resolves from the offline cache and
        /// needs no index.
        static let documentId = "order"
        /// The other document in the same subcollection: a shirt somebody gets
        /// for nothing. `firestore.rules` branches on this id, because the two
        /// have different owners — see `FreeShirt`.
        static let freeShirtDocumentId = "freeShirt"
        /// Free shirts only: whether the Sheet says they are owed one.
        static let entitled = "entitled"

        static let item = "item"
        static let size = "size"
        static let colour = "colour"
        static let collectedAt = "collectedAt"
        static let collectedBy = "collectedBy"
        static let orderHash = "orderHash"
    }

    enum Participant {
        static let source = "source"
        static let ticketRef = "ticketRef"
        static let name = "name"
        static let nameLower = "nameLower"
        static let searchTokens = "searchTokens"
        static let ticketType = "ticketType"
        static let country = "country"
        /// The DANCE level. Never a permission — see `Participant.level`.
        static let level = "level"
        /// The DANCE role: leader or follower. Never `role`, which is the staff
        /// claim the security rules read.
        static let danceRole = "danceRole"
        static let evening = "evening"
        static let eveningNumber = "eveningNumber"
        /// Door passes: the sequence in the id, and which catalogue entry it was.
        static let doorNumber = "doorNumber"
        static let passId = "passId"
        /// How a sale at the door was paid — `cash` or `card`, the same two
        /// strings a top-up's `method` uses — and what was collected, in cents.
        /// Both absent on everybody from the Sheet.
        static let paymentMethod = "paymentMethod"
        static let pricePaid = "pricePaid"
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
        /// What a charge bought. Absent on a top-up — cash over the counter buys
        /// nothing, and the rules refuse an itemised one.
        static let items = "items"
        /// `"cash"` or `"card"`, on a top-up only — and **required** there by
        /// `firestore.rules`, not merely by this app. A top-up sent without one
        /// is denied, which is what makes the cash count reconcilable; the price
        /// is that every terminal taking money has to carry the picker. Android
        /// does not yet, so its top-ups are refused until it does.
        static let method = "method"

        static let typeTopUp = "topup"
        static let typeCharge = "charge"

        /// The most distinct drinks one charge may itemise.
        ///
        /// Not a product decision: `firestore.rules` has to verify that the lines
        /// add up to the amount charged, rules cannot loop, and the unrolled sum
        /// costs expressions against Firestore's budget of 1,000 per request. Eight
        /// is what fits inside a money batch that is already paying for the balance
        /// invariant. A ninth line is refused by the server, so the app checks
        /// first and says something useful instead.
        static let maxItems = 8
    }

    /// One line of a charge: a snapshot of what the drink was called and cost at
    /// the moment of sale, not a reference to the menu.
    ///
    /// Snapshotted so that a price change tomorrow cannot rewrite today's receipt,
    /// and so an organiser can delete a drink without orphaning the history that
    /// names it.
    enum TransactionItem {
        static let drinkId = "drinkId"
        static let name = "name"
        static let unitPrice = "unitPrice"
        static let quantity = "quantity"
    }

    enum Settings {
        /// One document, holding what is neither a price list nor a person.
        static let collection = "settings"
        static let braceletsDocumentId = "bracelets"
        static let replacementFee = "replacementFee"
    }

    enum Bracelet {
        static let participantId = "participantId"
        static let staffUid = "staffUid"
        static let pairedAt = "pairedAt"
        /// Set when a wristband is replaced: the chip stops resolving for good,
        /// and this is the record of who had it, until when, and why it ended.
        static let invalidatedAt = "invalidatedAt"
        static let invalidatedBy = "invalidatedBy"
        static let reason = "reason"
        /// What the desk took for the wristband that replaced it, on the new
        /// chip. Absent when the fee was waived — and absent on everybody's
        /// first wristband, which is part of a ticket they already paid for.
        static let replacementFee = "replacementFee"
        static let replacementMethod = "replacementMethod"
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
            level: data[Fire.Participant.level] as? String ?? "",
            danceRole: data[Fire.Participant.danceRole] as? String ?? "",
            source: (data[Fire.Participant.source] as? String).flatMap(Source.init(rawValue:)) ?? .sheet,
            evening: (data[Fire.Participant.evening] as? String).flatMap(Evening.init(rawValue:)),
            eveningNumber: data[Fire.Participant.eveningNumber] as? Int,
            doorNumber: data[Fire.Participant.doorNumber] as? Int,
            passId: data[Fire.Participant.passId] as? String,
            paymentMethod: (data[Fire.Participant.paymentMethod] as? String)
                .flatMap(PaymentMethod.init(rawValue:)),
            pricePaid: (data[Fire.Participant.pricePaid] as? Int).map(Money.init(cents:)),
            braceletId: (data[Fire.Participant.braceletId] as? String).map(BraceletID.init),
            checkedInAt: (data[Fire.Participant.checkedInAt] as? Timestamp)?.dateValue(),
            balance: Money(cents: balanceCents),
            isBlocked: data[Fire.Participant.isBlocked] as? Bool ?? false,
            blockReason: data[Fire.Participant.blockReason] as? String
        )
    }
}

extension DoorPass {
    /// Build from `doorPasses/{slug}`.
    ///
    /// An inactive pass is dropped here rather than filtered later: a terminal
    /// that never holds a withdrawn pass cannot offer one by accident, and the
    /// rules would refuse the sale anyway — after the guest had been told a price.
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let name = data[Fire.DoorPass.name] as? String,
              !name.isEmpty,
              let priceCents = data[Fire.DoorPass.price] as? Int,
              data[Fire.DoorPass.isActive] as? Bool ?? true
        else { return nil }

        // A night with an unreadable value is simply absent, and falls back to
        // the flat price — the desk quoting last year's number is better than
        // the desk quoting nothing.
        var prices: [Evening: Money] = [:]
        if let raw = data[Fire.DoorPass.prices] as? [String: Any] {
            for evening in Evening.allCases {
                if let cents = raw[evening.rawValue] as? Int {
                    prices[evening] = Money(cents: cents)
                }
            }
        }

        self.init(
            id: document.documentID,
            name: name,
            price: Money(cents: priceCents),
            prices: prices,
            sortOrder: data[Fire.DoorPass.sortOrder] as? Int ?? 0,
            // Anything unrecognised is an ordinary pass. Refusing to sell
            // something because of a `kind` this build has not heard of would be
            // a worse failure than asking for a name that was not needed.
            // Anything unrecognised is an ordinary pass: a terminal that met a
            // `kind` it did not know and refused to sell would be worse than one
            // that asks for a name it did not strictly need.
            kind: DoorPass.Kind(wire: data[Fire.DoorPass.kind] as? String)
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

extension SpecialSession {
    /// Build from `specialSessions/{slug}`.
    ///
    /// A withdrawn class is dropped here rather than filtered later: a terminal
    /// that never holds one cannot offer it by accident, and the rules would
    /// refuse the sale anyway — after somebody had been told a price.
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let name = data[Fire.SpecialSession.name] as? String,
              !name.isEmpty,
              let cents = data[Fire.SpecialSession.price] as? Int,
              data[Fire.SpecialSession.isActive] as? Bool ?? true
        else { return nil }

        self.init(
            id: document.documentID,
            name: name,
            price: Money(cents: cents),
            sortOrder: data[Fire.SpecialSession.sortOrder] as? Int ?? 0
        )
    }
}

extension SessionSale {
    /// Build from `participants/{id}/sessions/{sessionId}`.
    ///
    /// A document with no readable method or price is dropped rather than shown
    /// as a sale with a blank beside it: the desk asking "did they pay?" of a
    /// row that cannot say is worse than the row not being there.
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let name = data[Fire.SessionSale.name] as? String,
              let cents = data[Fire.SessionSale.price] as? Int,
              let method = (data[Fire.SessionSale.method] as? String)
                  .flatMap(PaymentMethod.init(rawValue:))
        else { return nil }

        self.init(
            sessionId: data[Fire.SessionSale.sessionId] as? String ?? document.documentID,
            name: name,
            price: Money(cents: cents),
            method: method,
            soldAt: (data[Fire.SessionSale.soldAt] as? Timestamp)?.dateValue(),
            soldBy: data[Fire.SessionSale.soldBy] as? String ?? ""
        )
    }

    /// The document a sale writes. Written once and never updated.
    static func document(
        _ session: SpecialSession,
        method: PaymentMethod,
        soldBy staffUid: String
    ) -> [String: Any] {
        [
            Fire.SessionSale.sessionId: session.id,
            Fire.SessionSale.name: session.name,
            Fire.SessionSale.price: session.price.cents,
            Fire.SessionSale.method: method.wire,
            Fire.SessionSale.soldAt: FieldValue.serverTimestamp(),
            Fire.SessionSale.soldBy: staffUid,
        ]
    }
}

extension BraceletColour {
    /// Build from `braceletColours/{passTypeSlug}`.
    ///
    /// A document with a malformed colour is dropped rather than rendered. The
    /// rules pin `#RRGGBB` so this should not happen, but a swatch of the wrong
    /// colour is worse than no swatch — somebody hands over a wristband because
    /// of it.
    init?(document: DocumentSnapshot) {
        guard let data = document.data(),
              let passType = data[Fire.BraceletColour.passType] as? String,
              !passType.isEmpty,
              let hex = data[Fire.BraceletColour.colour] as? String,
              BraceletColour.components(hex: hex) != nil
        else { return nil }

        self.init(
            id: document.documentID,
            passType: passType,
            level: data[Fire.BraceletColour.level] as? String ?? "",
            evening: data[Fire.BraceletColour.evening] as? String ?? "",
            hex: hex,
            name: data[Fire.BraceletColour.name] as? String ?? ""
        )
    }
}

extension FreeShirt {
    /// Build from `participants/{id}/merch/freeShirt`.
    ///
    /// Nil only when the document does not exist, which is the common case —
    /// five people on a roster of a hundred and ten are owed one.
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(
            // Absent reads as not entitled: a document with no `entitled` field
            // is not one this importer wrote, and offering a free shirt on the
            // strength of a malformed document is the wrong way to be wrong.
            entitled: data[Fire.Merch.entitled] as? Bool ?? false,
            size: data[Fire.Merch.size] as? String,
            colour: data[Fire.Merch.colour] as? String,
            collectedAt: (data[Fire.Merch.collectedAt] as? Timestamp)?.dateValue(),
            collectedBy: data[Fire.Merch.collectedBy] as? String
        )
    }
}

extension MerchOrder {
    /// Build from `participants/{id}/merch/order`.
    ///
    /// Returns nil only when the document does not exist. An order whose `item`
    /// the importer never heard of still builds, as `.unknown`, because the
    /// desk being told "something was ordered, check the Sheet" is better than
    /// a guest being told they ordered nothing.
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        self.init(
            item: Item(wire: data[Fire.Merch.item] as? String),
            size: data[Fire.Merch.size] as? String,
            colour: data[Fire.Merch.colour] as? String,
            collectedAt: (data[Fire.Merch.collectedAt] as? Timestamp)?.dateValue(),
            collectedBy: data[Fire.Merch.collectedBy] as? String
        )
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
        guard let paymentMethod, let pricePaid else {
            preconditionFailure("a door sale must say how it was paid, and how much")
        }
        return [
            Fire.Participant.paymentMethod: paymentMethod.wire,
            Fire.Participant.pricePaid: pricePaid.cents,
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

    /// The document for a pass sold at the door, with a buyer on it.
    ///
    /// The email is **not** here. It goes to `contact/details`, which the bar
    /// cannot read — see `isWellFormedDoorPass` in `firestore.rules`, which
    /// refuses this document outright if an address is attached to it.
    func doorPassDocument(createdBy staffUid: String) -> [String: Any] {
        precondition(source == .door, "only door sales are client-created")
        guard let doorNumber, let passId, let braceletId else {
            preconditionFailure("a door pass must carry its number, catalogue id and bracelet")
        }
        guard let paymentMethod, let pricePaid else {
            preconditionFailure("a door sale must say how it was paid, and how much")
        }
        return [
            Fire.Participant.paymentMethod: paymentMethod.wire,
            Fire.Participant.pricePaid: pricePaid.cents,
            Fire.Participant.source: Source.door.rawValue,
            Fire.Participant.passId: passId,
            Fire.Participant.ticketType: ticketType,
            Fire.Participant.doorNumber: doorNumber,
            Fire.Participant.ticketRef: ticketRef,
            Fire.Participant.name: name,
            Fire.Participant.nameLower: name.lowercased(),
            // Capped at the twelve the rules accept. A long name with a long
            // pass type can produce more, and the refusal would arrive as a
            // failed sale rather than as anything anybody could act on.
            Fire.Participant.searchTokens: Array(
                Self.searchTokens(name: name, ticketType: ticketType).prefix(12)
            ),
            Fire.Participant.country: "",
            Fire.Participant.level: level,
            Fire.Participant.danceRole: danceRole,
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

    /// This line as the ledger stores it.
    ///
    /// The shape is checked by `itemisationAddsUp` in `firestore.rules`, including
    /// that no other key rides along: `hasOnly` means an extra field here is a
    /// PERMISSION_DENIED at the bar, not a harmless annotation.
    var ledgerItem: [String: Any] {
        [
            Fire.TransactionItem.drinkId: drink.id,
            Fire.TransactionItem.name: drink.name,
            Fire.TransactionItem.unitPrice: drink.price.cents,
            Fire.TransactionItem.quantity: quantity,
        ]
    }
}

extension Array where Element == CartLine {
    /// The `items` array for a charge, or `nil` when there is nothing to itemise.
    ///
    /// Pure, so it is testable without a network: the rules are unforgiving about
    /// this shape and the failure mode is a declined payment mid-service, which is
    /// the worst possible place to discover a typo in a field name.
    var ledgerItems: [[String: Any]] {
        map(\.ledgerItem)
    }

    /// What the lines add up to. The rules require this to equal the amount the
    /// balance moves by, so both must come from here rather than be computed twice.
    var ledgerTotal: Money {
        reduce(Money.zero) { $0 + $1.total }
    }
}
