// Pure diff logic: Sheet rows + existing Firestore docs → a plan of writes.
//
// No googleapis, no firebase-admin, no I/O. This is where the "a re-import must
// never touch a balance" guarantee actually lives, so it is kept isolated and
// unit-tested (diff.test.mjs) rather than tangled into the CLI.

import { createHash } from 'node:crypto';
import {
  COLUMNS,
  IDENTITY_COLUMN,
  IMPORT_OWNED_FIELDS,
  initialFestivalState,
  isImportableStatus,
  normaliseStatus,
  toDocumentId,
  toRosterFields,
} from './mapping.mjs';

/** Stable fingerprint of the roster fields, so unchanged rows can be skipped. */
export function rosterHash(fields) {
  const canonical = JSON.stringify(
    Object.keys(fields)
      .sort()
      .map((k) => [k, fields[k]])
  );
  return createHash('sha256').update(canonical).digest('hex').slice(0, 16);
}

/** Normalise a header for tolerant matching: case and whitespace insensitive. */
function normaliseHeader(header) {
  return String(header).trim().toLowerCase().replace(/\s+/g, ' ');
}

/**
 * Resolve COLUMNS against the Sheet's real header row.
 *
 * Throws with the actual headers listed, so a typo in mapping.mjs is a two-second
 * fix rather than a mystery.
 */
export function resolveColumns(headerRow) {
  const index = new Map(headerRow.map((h, i) => [normaliseHeader(h), i]));
  const resolved = {};
  const missing = [];

  for (const [field, header] of Object.entries(COLUMNS)) {
    if (header == null) continue;
    const at = index.get(normaliseHeader(header));
    if (at === undefined) missing.push(`${field} → "${header}"`);
    else resolved[field] = at;
  }

  if (missing.length) {
    throw new Error(
      `Columns declared in mapping.mjs were not found in the Sheet:\n` +
        missing.map((m) => `  ${m}`).join('\n') +
        `\n\nHeaders actually present:\n` +
        headerRow.map((h, i) => `  [${i}] ${h}`).join('\n')
    );
  }
  if (resolved[IDENTITY_COLUMN] === undefined) {
    throw new Error(
      `IDENTITY_COLUMN is "${IDENTITY_COLUMN}" but that field is not mapped to a column. ` +
        `The importer will not run without a stable unique key.`
    );
  }
  return resolved;
}

/** Turn raw cell arrays into `{ field: value }` objects. */
export function parseRows(rows, resolved) {
  return rows.map((cells, i) => {
    const row = { __sheetRow: i + 2 }; // +2: 1-based, and row 1 is the header
    for (const [field, at] of Object.entries(resolved)) {
      row[field] = cells[at] ?? '';
    }
    return row;
  });
}

/**
 * Validate the identity column across all rows before writing anything.
 *
 * Returns `{ usable, blank, duplicated }`. The CLI refuses to proceed if either
 * problem list is non-empty — a blank or duplicated key is exactly how a
 * re-import corrupts somebody's balance.
 */
export function validateIdentity(rows) {
  const blank = [];
  const seen = new Map();
  const duplicated = [];
  const usable = [];

  for (const row of rows) {
    const raw = String(row[IDENTITY_COLUMN] ?? '').trim();
    if (!raw) {
      blank.push(row.__sheetRow);
      continue;
    }
    let id;
    try {
      id = toDocumentId(raw);
    } catch {
      blank.push(row.__sheetRow);
      continue;
    }
    if (seen.has(id)) {
      duplicated.push({ id, rows: [seen.get(id), row.__sheetRow] });
      continue;
    }
    seen.set(id, row.__sheetRow);
    usable.push({ ...row, __id: id });
  }

  return { usable, blank, duplicated };
}

/**
 * Split rows on the Status column: `Paid` in, everything else out.
 *
 * Unpaid is treated as absent during the festival. `breakdown` counts what was
 * excluded, by status, so a dry run shows exactly what is being left behind —
 * the cheap check against a status value nobody anticipated.
 */
export function partitionByStatus(rows) {
  const importable = [];
  const excluded = [];
  const breakdown = new Map();

  for (const row of rows) {
    const status = normaliseStatus(row.status);
    if (isImportableStatus(status)) {
      importable.push(row);
      continue;
    }
    excluded.push({ ...row, __status: status });
    const key = status || '(blank)';
    breakdown.set(key, (breakdown.get(key) ?? 0) + 1);
  }

  return { importable, excluded, breakdown };
}

/**
 * People whose status says "do not import" but who are already in Firestore.
 *
 * Someone who paid, checked in, loaded 40 € onto a bracelet and was then marked
 * refunded is not a row to silently skip. Reported, never deleted — the money is
 * real and what happens to it is an organiser decision.
 */
export function findRevoked(excluded, existing) {
  return excluded
    .filter((row) => existing.has(row.__id))
    .map((row) => {
      const doc = existing.get(row.__id);
      return {
        id: row.__id,
        name: doc.name ?? row.name,
        status: row.__status,
        checkedIn: doc.braceletId != null,
        balance: doc.balance ?? 0,
      };
    });
}

/**
 * Build the write plan.
 *
 * @param rows      output of validateIdentity().usable
 * @param existing  Map of participantId → current document data
 * @returns { creates, updates, unchanged }
 */
export function buildPlan(rows, existing) {
  const creates = [];
  const updates = [];
  const unchanged = [];

  for (const row of rows) {
    const id = row.__id;
    const roster = toRosterFields(row);
    const hash = rosterHash(roster);
    const current = existing.get(id);

    if (!current) {
      creates.push({
        id,
        sheetRow: row.__sheetRow,
        data: { ...roster, rosterHash: hash, ...initialFestivalState() },
      });
      continue;
    }

    if (current.rosterHash === hash) {
      unchanged.push({ id, sheetRow: row.__sheetRow });
      continue;
    }

    // Only roster fields. Festival state is deliberately absent — see
    // IMPORT_OWNED_FIELDS in mapping.mjs.
    const data = { ...roster, rosterHash: hash };
    assertTouchesOnlyImportOwnedFields(data);

    updates.push({
      id,
      sheetRow: row.__sheetRow,
      data,
      changes: describeChanges(current, roster),
    });
  }

  return { creates, updates, unchanged };
}

/**
 * Belt and braces. If someone later adds a field to toRosterFields() that is
 * actually festival state, this throws instead of quietly overwriting balances.
 */
export function assertTouchesOnlyImportOwnedFields(data) {
  const offending = Object.keys(data).filter(
    (k) => !IMPORT_OWNED_FIELDS.includes(k)
  );
  if (offending.length) {
    throw new Error(
      `Refusing to build an update touching non-roster fields: ${offending.join(', ')}. ` +
        `Festival state (balance, braceletId, checkedInAt, isBlocked) is never import-owned.`
    );
  }
}

/** Human-readable field changes for the dry-run output. */
function describeChanges(current, roster) {
  const interesting = ['name', 'ticketType', 'country', 'ticketRef'];
  return interesting
    .filter((k) => current[k] !== roster[k])
    .map((k) => `${k}: ${JSON.stringify(current[k] ?? null)} → ${JSON.stringify(roster[k])}`);
}

/**
 * People in Firestore who are no longer in the Sheet.
 *
 * Reported, never deleted. A refund or a cancelled ticket is an organiser
 * decision, and somebody may already be checked in with money on their bracelet.
 */
export function findOrphans(rows, existing) {
  const inSheet = new Set(rows.map((r) => r.__id));
  const orphans = [];
  for (const [id, doc] of existing) {
    if (inSheet.has(id)) continue;
    orphans.push({
      id,
      name: doc.name ?? '(unnamed)',
      checkedIn: doc.braceletId != null,
      balance: doc.balance ?? 0,
    });
  }
  return orphans;
}
