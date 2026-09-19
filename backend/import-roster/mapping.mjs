// ═══════════════════════════════════════════════════════════════════════════
//  Mapping from the Swing Buzz registrations Sheet to the Firestore roster.
//
//  This is the file to edit when the Sheet changes. `npm run headers` prints the
//  Sheet's current header row and the distinct values in the status column.
//
//  Nothing here talks to Google or Firebase, so it is unit-testable and cheap to
//  get wrong safely. See diff.test.mjs.
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Our field → the EXACT header text in the Sheet.
 *
 * Matched case- and whitespace-insensitively, but spell it as it appears. A
 * header listed here that is not in the Sheet aborts the import and prints the
 * headers that actually exist.
 *
 * The Sheet is a Google Form response sheet, so the form owner can append
 * columns at any time. That is fine — anything not named here is ignored, and
 * every run logs what it ignored.
 */
export const COLUMNS = {
  /// The registration id. Unique, stable, never edited — see IDENTITY_COLUMN.
  ticketRef: 'Id',
  name: 'Full Name',
  /// A fixed set: "Full pass", "Party pass", "Weekend pass".
  ticketType: 'Pass Type',
  /// The Sheet asks for a country, not a city. Named for what it holds.
  country: 'Which country are you coming from?',
  /// Decides whether the row is importable at all. See IMPORTABLE_STATUSES.
  status: 'Status',

  // ── Merch ────────────────────────────────────────────────────────────────
  //
  // These three used to be in EXCLUDED_COLUMNS, on the rule that every field
  // reaching Firestore is readable by every terminal including the bar. That
  // rule has not been relaxed — the merch order does not go on the participant
  // document. It goes in `participants/{id}/merch/order`, which the rules let
  // reception read and the bar not. See docs/merch.md.
  merchAttire: 'Festival T-Shirt and tote bag. Choose your Swing Buzz attire.',
  merchSize: 'T-Shirt Size',
  merchColour: 'T-Shirt Color',
};

/**
 * The stable unique key. `participantId` is derived from it, so a re-import
 * recognises rows it has already seen rather than duplicating people or
 * overwriting a checked-in guest's balance.
 */
export const IDENTITY_COLUMN = 'ticketRef';

// ── Status ─────────────────────────────────────────────────────────────────

/**
 * The only status that gets imported.
 *
 * Everything else — pending, expired, cancelled, refunded, blank, anything the
 * form grows later — is treated as if the registration does not exist. That is
 * the organisers' rule, not an inference: during the festival, unpaid is the
 * same as absent.
 *
 * Compared lowercased and trimmed, so "Paid", "PAID" and " paid " all match.
 *
 * The importer does not refuse to run on an unfamiliar status, but every dry run
 * prints a breakdown of what it excluded and why. Worth actually reading: a
 * value like "Paid (bank transfer)" would be silently skipped by this rule, and
 * the guest would be missing at the door.
 */
export const IMPORTABLE_STATUSES = ['paid'];

// ── Pass types ─────────────────────────────────────────────────────────────

/**
 * The pass types the festival sells, as they should appear on a terminal.
 *
 * The Sheet's `Pass Type` column carries far more than this — the price, the
 * pricing tier, and sometimes a note:
 *
 *     "Full Pass - 185 € (EARLY BIRD pricing)"
 *     "Full Pass Gold - 130 € (First Installment 50%)"
 *     "Full Pass - 205 € (Upgrade from Party - 135€ + 70€)"
 *     "Full Pass - Dragon Swing Winner"
 *
 * 14 distinct strings for 5 actual pass types, as of the first real import. None
 * of that belongs on an 11pt row next to somebody's name, and leaving it raw would
 * split "Full Pass" across five values for any grouping or reporting.
 */
export const CANONICAL_PASS_TYPES = [
  'Party Pass',
  'Party Pass Plus',
  'Full Pass',
  'Full Pass Gold',
  'Jazz Performance Track',
  /// Never in the Sheet; minted by reception at the door.
  'Evening Ticket',
];

/**
 * Reduce a Sheet value to its canonical pass type.
 *
 * **Longest match first.** This is the whole difficulty: "Full Pass Gold - 239 €"
 * starts with "Full Pass", and a naive prefix scan would file every Gold holder as
 * a plain Full Pass. Same for "Party Pass Plus" against "Party Pass". Sorting by
 * length rather than relying on the order of the array above means reordering that
 * list cannot reintroduce the bug.
 *
 * An unrecognised value is returned unchanged rather than dropped or guessed at —
 * a new pass type should show up on a screen looking odd, not vanish. The import
 * reports how many it could not recognise.
 */
export function normaliseTicketType(raw) {
  const value = String(raw ?? '').trim();
  if (!value) return '';
  const lower = value.toLowerCase();
  const byLongest = [...CANONICAL_PASS_TYPES].sort((a, b) => b.length - a.length);
  for (const canonical of byLongest) {
    if (lower.startsWith(canonical.toLowerCase())) return canonical;
  }
  return value;
}

export function isCanonicalPassType(value) {
  return CANONICAL_PASS_TYPES.includes(value);
}

// ── Privacy ────────────────────────────────────────────────────────────────

/**
 * Columns read from the Sheet and deliberately NOT copied into Firestore.
 *
 * Every field that reaches Firestore is readable by every signed-in terminal,
 * including the bar. A bartender needs a name, a ticket type and a balance. They
 * do not need somebody's phone number, dietary notes, or who they are dancing
 * with.
 *
 * Listed explicitly so the intent is on the record; the importer logs every
 * column it ignored on each run, so a newly added form question cannot leak by
 * being forgotten.
 */
export const EXCLUDED_COLUMNS = [
  'Клеймо за време',       // Google Forms timestamp
  'Email',
  'Phone Number',
  'Role',                   // DANCE role (leader/follower) — NOT StaffRole. See below.
  'Level',
  'Are you registering with a partner',
  "If you are registering with a partner, write down your partner's email.",
  'Comments',               // free text; could contain anything
  'Terms and Conditions',
  'Code of Conduct',
  'expiry_date',
  'reminder_sent',
  'expired_sent',
  'Receipt',
];

// NOTE ON `Role`. In this Sheet, "Role" is the dance role — leader or follower.
// In the app, `StaffRole` is reception or bar, and it decides who may credit a
// balance. They are unrelated concepts that share a word. Do not map one onto the
// other, and do not import this column into a field called `role`: the security
// rules read a `role` custom claim, and a collision there would be an
// authorisation bug rather than a display bug.

// ── Derivations ────────────────────────────────────────────────────────────

/** Firestore document ids: no slashes, no leading dots, reasonable length. */
export function toDocumentId(identityValue) {
  const slug = String(identityValue)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (!slug || slug === '.' || slug === '..') {
    throw new Error(`Identity value ${JSON.stringify(identityValue)} does not slugify to a usable id`);
  }
  return slug.slice(0, 200);
}

/**
 * Lowercased sort/search key.
 *
 * Deliberately keeps accents: the app matches with
 * `localizedCaseInsensitiveContains`, and "Amélie" should sort next to "Amelie"
 * rather than being silently rewritten. Names in this roster are Bulgarian,
 * Swedish, Portuguese and more, so this is not a hypothetical.
 */
export function toSortKey(name) {
  return String(name).trim().toLowerCase();
}

/** Word tokens for the optional prefix-search index. */
export function toSearchTokens({ name, ticketType }) {
  const words = `${name} ${ticketType}`.toLowerCase().split(/\s+/).filter(Boolean);
  return [...new Set(words)];
}

/** Is this row's status one we import? */
export function isImportableStatus(status) {
  return IMPORTABLE_STATUSES.includes(normaliseStatus(status));
}

export function normaliseStatus(status) {
  return String(status ?? '').trim().toLowerCase();
}

/**
 * The roster fields, and only the roster fields, that the import owns.
 * Everything absent from this object is festival state the import must not touch.
 */
export function toRosterFields(row) {
  // Normalised, and the Sheet's raw text is deliberately NOT carried across: the
  // price each person paid stays in the Sheet. Everything that reaches Firestore
  // is readable by every terminal, and a bartender has no use for it.
  const ticketType = normaliseTicketType(row.ticketType);
  return {
    ticketRef: String(row.ticketRef ?? '').trim(),
    name: String(row.name ?? '').trim(),
    nameLower: toSortKey(row.name ?? ''),
    searchTokens: toSearchTokens({ name: row.name ?? '', ticketType }),
    ticketType,
    country: String(row.country ?? '').trim(),
  };
}

// ── Merch ──────────────────────────────────────────────────────────────────

/**
 * What the form says when somebody ordered nothing.
 *
 * The same sentence appears in all three merch columns — attire, size and
 * colour — because it is an option in each dropdown rather than a blank. Treat
 * it exactly as a blank, or 79 people arrive at the desk with a t-shirt order
 * reading "No Swing Buzz attire, size No Swing Buzz attire".
 */
const NO_MERCH = 'no swing buzz attire';

/**
 * The three things the form sells, plus the two states that are not a sale:
 * `none` for an empty order, and `unknown` for an option this parser did not
 * recognise. Both apps must handle all five — the rules pin the field to this
 * list, so a sixth value cannot appear without a rules change.
 */
export const MERCH_ITEMS = ['none', 'shirt', 'tote', 'shirtAndTote', 'unknown'];

/**
 * Parse the attire column into one of `MERCH_ITEMS`.
 *
 * The Sheet's values carry a price — "T-Shirt only: 20 €" — and the price is
 * deliberately dropped, the same rule that keeps pass-type prices in the Sheet.
 * The merch is already paid for by the time anybody reads this; the desk is
 * handing over a shirt, not selling one, and a price on that screen is a number
 * somebody will eventually try to collect.
 *
 * Matched on what the option contains rather than on the exact string, because
 * the price in it changes between early-bird and full rates and a new price
 * must not silently become "ordered nothing".
 */
export function parseMerchItem(raw) {
  const text = String(raw ?? '').trim().toLowerCase();
  if (!text || text === NO_MERCH) return 'none';

  const hasShirt = text.includes('t-shirt') || text.includes('tshirt');
  const hasTote = text.includes('tote');

  if (hasShirt && hasTote) return 'shirtAndTote';
  if (hasShirt) return 'shirt';
  if (hasTote) return 'tote';

  // An option nobody anticipated. Recorded as unknown rather than guessed at or
  // silently dropped: the desk sees that something was ordered and can ask,
  // which is better than a guest being told they ordered nothing.
  return 'unknown';
}

/**
 * Size and colour, or null when there is nothing to say.
 *
 * Strips a trailing parenthetical: one colour in the Sheet reads
 * "French Navy (Available only in XS, M, L, XL)", which is a note to the person
 * filling in the form and noise to the person handing over the shirt.
 */
export function parseMerchDetail(raw) {
  const text = String(raw ?? '').trim();
  if (!text || text.toLowerCase() === NO_MERCH) return null;
  const withoutNote = text.replace(/\s*\([^)]*\)\s*$/, '').trim();
  return withoutNote || null;
}

/**
 * The merch order a row describes, or null when there is none.
 *
 * Size and colour are kept even for a tote-only order if the Sheet has them —
 * reporting what the guest actually answered is more useful at the desk than
 * second-guessing which fields "should" apply to which item.
 */
export function toMerchOrder(row) {
  const item = parseMerchItem(row.merchAttire);
  if (item === 'none') return null;
  return {
    item,
    size: parseMerchDetail(row.merchSize),
    colour: parseMerchDetail(row.merchColour),
  };
}

/**
 * Fields the importer owns on a merch document.
 *
 * `collectedAt` and `collectedBy` are absent, and that is the whole guard: a
 * re-import in the middle of Saturday must not tell forty people their shirt is
 * waiting for them when they are already wearing it. Same rule as balances.
 */
export const MERCH_IMPORT_OWNED_FIELDS = ['item', 'size', 'colour', 'orderHash', 'importedAt'];

/** Festival state given to a merch order the first time it is imported. */
export function initialMerchState() {
  return { collectedAt: null, collectedBy: null };
}

/** Festival state given to a person the first time they are imported. */
export function initialFestivalState() {
  return {
    /// Distinguishes an imported registration from a door-sold evening ticket.
    /// Written once, on create; the security rules forbid a terminal from
    /// changing it, and `findOrphans` uses it to leave door sales alone.
    source: 'sheet',
    braceletId: null,
    checkedInAt: null,
    balance: 0,
    lastTxId: null,
    isBlocked: false,
    blockReason: null,
  };
}

/**
 * Fields the importer is allowed to write on an EXISTING participant.
 * The guard rail: `balance`, `braceletId`, `checkedInAt`, `lastTxId`,
 * `isBlocked` and `blockReason` are absent, so a re-import can never move money
 * or un-check-in somebody.
 */
export const IMPORT_OWNED_FIELDS = [
  'ticketRef',
  'name',
  'nameLower',
  'searchTokens',
  'ticketType',
  'country',
  'rosterHash',
  'importedAt',
];
