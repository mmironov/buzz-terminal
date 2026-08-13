// ═══════════════════════════════════════════════════════════════════════════
//  THE ONE FILE YOU EDIT when the Google Sheet's columns are known.
//
//  Run `npm run headers` first — it prints the Sheet's actual header row and
//  exits. Copy the column names into COLUMNS below, set IDENTITY_COLUMN, and
//  the importer will do the rest.
//
//  Nothing here talks to Google or Firebase, so it is unit-testable and cheap
//  to get wrong safely. See diff.test.mjs.
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Map Sheet header names → the fields the schema wants.
 *
 * Left side is our field, right side is the EXACT header text in the Sheet
 * (case- and whitespace-insensitive when matched, but spell it as it appears).
 * Set a value to `null` if the Sheet has no such column.
 */
export const COLUMNS = {
  // The stable unique key. See IDENTITY_COLUMN below.
  ticketRef: 'Ticket ID',

  name: 'Full Name',
  ticketType: 'Ticket Type',
  city: 'City',
};

/**
 * Which of the above is the stable, unique, never-edited key per row.
 *
 * `participantId` is derived from it, so a re-import recognises rows it has
 * already seen. If this column is missing, blank, or duplicated, the importer
 * refuses to run rather than guess — getting this wrong either duplicates people
 * or overwrites a checked-in guest's balance.
 *
 * Do NOT point this at a row number (not stable under sorting) or at a name
 * (festivals get two Anna Kowalskis).
 */
export const IDENTITY_COLUMN = 'ticketRef';

/**
 * Columns to read but deliberately NOT copy into Firestore.
 *
 * Anything here stays in the Sheet. Every field that reaches Firestore is
 * readable by every signed-in terminal, including the bar — so email addresses,
 * phone numbers, dietary notes and accessibility needs do not belong there
 * unless a terminal actually needs them to do its job.
 *
 * List the header names you want explicitly dropped; the importer logs anything
 * it saw and ignored, so nothing leaks by being forgotten.
 */
export const EXCLUDED_COLUMNS = [
  'Email',
  'Phone',
  'Notes',
  'Dietary requirements',
  'Amount paid',
];

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
 * Lowercased, diacritic-preserving sort/search key.
 *
 * Deliberately keeps accents: the app matches with
 * `localizedCaseInsensitiveContains`, and "Amélie" should sort next to "Amelie"
 * rather than being silently rewritten.
 */
export function toSortKey(name) {
  return String(name).trim().toLowerCase();
}

/** Word tokens for the optional prefix-search index. */
export function toSearchTokens({ name, ticketType }) {
  const words = `${name} ${ticketType}`.toLowerCase().split(/\s+/).filter(Boolean);
  return [...new Set(words)];
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
    city: String(row.city ?? '').trim(),
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
  'city',
  'rosterHash',
  'importedAt',
];
