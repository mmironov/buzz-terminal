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
  'Festival T-Shirt and tote bag. Choose your Swing Buzz attire.',
  'T-Shirt Size',
  'T-Shirt Color',
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
  return {
    ticketRef: String(row.ticketRef ?? '').trim(),
    name: String(row.name ?? '').trim(),
    nameLower: toSortKey(row.name ?? ''),
    searchTokens: toSearchTokens({
      name: row.name ?? '',
      ticketType: row.ticketType ?? '',
    }),
    ticketType: String(row.ticketType ?? '').trim(),
    country: String(row.country ?? '').trim(),
  };
}

/** Festival state given to a person the first time they are imported. */
export function initialFestivalState() {
  return {
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
