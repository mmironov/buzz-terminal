package fest.swingbuzz.terminal.data

import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldValue
import fest.swingbuzz.terminal.domain.BraceletID
import fest.swingbuzz.terminal.domain.Drink
import fest.swingbuzz.terminal.domain.Evening
import fest.swingbuzz.terminal.domain.Money
import fest.swingbuzz.terminal.domain.Participant
import fest.swingbuzz.terminal.domain.ParticipantID
import fest.swingbuzz.terminal.domain.TicketType

// ═══════════════════════════════════════════════════════════════════════════
//  Firestore ↔ domain mapping.
//
//  Written by hand rather than with Firestore's `toObject<T>()` reflection, for
//  the same reason the Swift side does not use Codable: these field names are not
//  an implementation detail. `backend/firestore.rules` names every one of them
//  and 49 rules tests assert on them, so a property rename that reflection would
//  silently follow is a change to a security contract. The strings live here, in
//  one place, spelled out — and they must agree with `FirestoreMapping.swift`
//  exactly, because both apps write to the same documents.
//
//  Money crosses this boundary as an integer of cents. Firestore numbers are
//  doubles; 23.50 is not representable, and a balance that drifts by a cent per
//  transaction is worse than one that is obviously wrong.
// ═══════════════════════════════════════════════════════════════════════════

object Fire {
    object Collection {
        const val PARTICIPANTS = "participants"
        const val TRANSACTIONS = "transactions"
        const val BRACELETS = "bracelets"
        const val DRINKS = "drinks"
    }

    object Participant {
        const val SOURCE = "source"
        const val TICKET_REF = "ticketRef"
        const val NAME = "name"
        const val NAME_LOWER = "nameLower"
        const val SEARCH_TOKENS = "searchTokens"
        const val TICKET_TYPE = "ticketType"
        const val COUNTRY = "country"
        const val EVENING = "evening"
        const val EVENING_NUMBER = "eveningNumber"
        const val BRACELET_ID = "braceletId"
        const val CHECKED_IN_AT = "checkedInAt"
        const val BALANCE = "balance"
        const val LAST_TX_ID = "lastTxId"
        const val IS_BLOCKED = "isBlocked"
        const val BLOCK_REASON = "blockReason"
        const val CREATED_BY = "createdBy"
        const val UPDATED_AT = "updatedAt"
    }

    object Transaction {
        const val CLIENT_TX_ID = "clientTxId"
        const val TYPE = "type"
        const val AMOUNT = "amount"
        const val SIGNED_AMOUNT = "signedAmount"
        const val STAFF_UID = "staffUid"
        const val TERMINAL_ID = "terminalId"
        const val CREATED_AT = "createdAt"
        const val QUEUED_OFFLINE = "queuedOffline"

        const val TYPE_TOP_UP = "topup"
        const val TYPE_CHARGE = "charge"
    }

    object Bracelet {
        const val PARTICIPANT_ID = "participantId"
        const val STAFF_UID = "staffUid"
        const val PAIRED_AT = "pairedAt"
    }

    object Drink {
        const val NAME = "name"
        const val PRICE = "price"
        const val SORT_ORDER = "sortOrder"
        const val IS_ACTIVE = "isActive"
    }
}

// ─── Reading ────────────────────────────────────────────────────────────────

/**
 * Build a participant from a Firestore document, or `null` if it is missing the
 * fields that make it a participant at all.
 *
 * Tolerant of absent optionals and of an unrecognised `ticketType` — the Sheet is
 * edited by humans, and a document that is merely odd should display rather than
 * take the terminal down mid-service. Intolerant of a missing `name` or
 * `balance`, because there is nothing sensible to show instead.
 */
fun DocumentSnapshot.toParticipant(): Participant? {
    val name = getString(Fire.Participant.NAME) ?: return null
    // Firestore hands back every number as Long. `toInt()` is safe for cents:
    // a balance would have to exceed 21 million euros to overflow.
    val balanceCents = getLong(Fire.Participant.BALANCE)?.toInt() ?: return null

    return Participant(
        id = ParticipantID(id),
        ticketRef = getString(Fire.Participant.TICKET_REF).orEmpty(),
        name = name,
        ticketType = getString(Fire.Participant.TICKET_TYPE).orEmpty(),
        country = getString(Fire.Participant.COUNTRY).orEmpty(),
        source = Participant.Source.fromWire(getString(Fire.Participant.SOURCE)),
        evening = Evening.fromWire(getString(Fire.Participant.EVENING)),
        eveningNumber = getLong(Fire.Participant.EVENING_NUMBER)?.toInt(),
        braceletId = getString(Fire.Participant.BRACELET_ID)?.let(::BraceletID),
        checkedInAt = getTimestamp(Fire.Participant.CHECKED_IN_AT)?.toInstant(),
        balance = Money(balanceCents),
        isBlocked = getBoolean(Fire.Participant.IS_BLOCKED) ?: false,
        blockReason = getString(Fire.Participant.BLOCK_REASON),
    )
}

fun DocumentSnapshot.toDrink(): Drink? {
    val name = getString(Fire.Drink.NAME) ?: return null
    val priceCents = getLong(Fire.Drink.PRICE)?.toInt() ?: return null
    return Drink(id = id, name = name, price = Money(priceCents))
}

// ─── Writing ────────────────────────────────────────────────────────────────

/**
 * The document a door-sold evening ticket is created as.
 *
 * Every field here is checked by `isWellFormedEveningTicket` in
 * `firestore.rules`. Changing one without changing the rule means the write
 * starts failing with PERMISSION_DENIED, which is the intended outcome: this
 * shape is a contract, not a convention.
 */
fun Participant.eveningTicketDocument(createdBy: String): Map<String, Any?> {
    require(source == Participant.Source.EVENING) { "only door sales are client-created" }
    val evening = requireNotNull(evening) { "an evening ticket must carry its evening" }
    val number = requireNotNull(eveningNumber) { "an evening ticket must carry its number" }
    val bracelet = requireNotNull(braceletId) { "an evening ticket must carry its bracelet" }

    return mapOf(
        Fire.Participant.SOURCE to Participant.Source.EVENING.wire,
        Fire.Participant.TICKET_TYPE to TicketType.EVENING_TICKET,
        Fire.Participant.EVENING to evening.wire,
        Fire.Participant.EVENING_NUMBER to number,
        Fire.Participant.TICKET_REF to ticketRef,
        Fire.Participant.NAME to name,
        Fire.Participant.NAME_LOWER to name.lowercase(),
        Fire.Participant.SEARCH_TOKENS to searchTokens(name, TicketType.EVENING_TICKET),
        Fire.Participant.COUNTRY to "",
        Fire.Participant.BRACELET_ID to bracelet.rawValue,
        Fire.Participant.CHECKED_IN_AT to FieldValue.serverTimestamp(),
        Fire.Participant.BALANCE to 0,
        Fire.Participant.LAST_TX_ID to null,
        Fire.Participant.IS_BLOCKED to false,
        Fire.Participant.BLOCK_REASON to null,
        Fire.Participant.CREATED_BY to createdBy,
    )
}

/**
 * Lowercased word tokens, matching what the importer writes so the two sources of
 * participants are searchable the same way.
 */
private fun searchTokens(name: String, ticketType: String): List<String> =
    "$name $ticketType".lowercase().split(" ").filter { it.isNotEmpty() }.distinct()

/** The reverse-lookup document that pairs a chip to an account. */
fun braceletPairingDocument(participantId: ParticipantID, staffUid: String): Map<String, Any?> = mapOf(
    Fire.Bracelet.PARTICIPANT_ID to participantId.rawValue,
    Fire.Bracelet.STAFF_UID to staffUid,
    Fire.Bracelet.PAIRED_AT to FieldValue.serverTimestamp(),
)
