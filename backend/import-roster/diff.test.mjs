// Runs with plain Node, no dependencies, no credentials:
//     node --test backend/import-roster/
//
// These cover the part of the importer that can lose money: the guarantee that a
// re-import updates roster fields and never touches balance, bracelet pairing or
// check-in state.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  buildPlan,
  findOrphans,
  parseRows,
  resolveColumns,
  rosterHash,
  validateIdentity,
} from './diff.mjs';
import { COLUMNS, IDENTITY_COLUMN, toDocumentId, toRosterFields } from './mapping.mjs';

// A header row matching the placeholder mapping.mjs, in a deliberately awkward
// order and with stray whitespace and casing.
const HEADER = ['  full name', 'Email', 'TICKET ID', 'City', 'Ticket type'];

const SHEET = [
  ['Amélie Roux', 'a@example.com', 'TKT-10432', 'Lyon', 'Full pass'],
  ['Tomás Herrera', 't@example.com', 'TKT-10433', 'Madrid', 'Full pass'],
];

function rowsFrom(cells, header = HEADER) {
  const resolved = resolveColumns(header);
  return validateIdentity(parseRows(cells, resolved)).usable;
}

test('resolves columns despite case and whitespace differences', () => {
  const resolved = resolveColumns(HEADER);
  assert.equal(resolved.name, 0);
  assert.equal(resolved.ticketRef, 2);
  assert.equal(resolved.city, 3);
  assert.equal(resolved.ticketType, 4);
});

test('a missing column fails loudly and lists the real headers', () => {
  assert.throws(
    () => resolveColumns(['Name', 'City']),
    (err) => {
      assert.match(err.message, /were not found in the Sheet/);
      assert.match(err.message, /Headers actually present/);
      assert.match(err.message, /\[0\] Name/);
      return true;
    }
  );
});

test('derives stable document ids from the identity column', () => {
  assert.equal(toDocumentId('TKT-10432'), 'tkt-10432');
  assert.equal(toDocumentId('  tkt/10432  '), 'tkt-10432');
  assert.throws(() => toDocumentId('///'));
});

test('blank identity values are reported, not guessed at', () => {
  const resolved = resolveColumns(HEADER);
  const rows = parseRows(
    [['No Ticket', 'x@example.com', '   ', 'Porto', 'Party pass'], ...SHEET],
    resolved
  );
  const { usable, blank } = validateIdentity(rows);
  assert.deepEqual(blank, [2]); // sheet row 2, the first data row
  assert.equal(usable.length, 2);
});

test('duplicate identity values are reported with both row numbers', () => {
  const resolved = resolveColumns(HEADER);
  const rows = parseRows([...SHEET, SHEET[0]], resolved);
  const { usable, duplicated } = validateIdentity(rows);
  assert.equal(usable.length, 2);
  assert.equal(duplicated.length, 1);
  assert.deepEqual(duplicated[0].rows, [2, 4]);
});

test('first import creates everyone with zero balance and no bracelet', () => {
  const { creates, updates, unchanged } = buildPlan(rowsFrom(SHEET), new Map());
  assert.equal(creates.length, 2);
  assert.equal(updates.length, 0);
  assert.equal(unchanged.length, 0);

  const amelie = creates.find((c) => c.id === 'tkt-10432');
  assert.equal(amelie.data.name, 'Amélie Roux');
  assert.equal(amelie.data.nameLower, 'amélie roux');
  assert.equal(amelie.data.balance, 0);
  assert.equal(amelie.data.braceletId, null);
  assert.equal(amelie.data.isBlocked, false);
});

test('email is not carried into Firestore even though it is in the Sheet', () => {
  const { creates } = buildPlan(rowsFrom(SHEET), new Map());
  const fields = Object.keys(creates[0].data);
  assert.ok(!fields.some((f) => /email|phone/i.test(f)), fields.join(','));
});

test('re-running with an unchanged Sheet writes nothing', () => {
  const rows = rowsFrom(SHEET);
  const existing = new Map(
    rows.map((r) => {
      const roster = toRosterFields(r);
      return [r.__id, { ...roster, rosterHash: rosterHash(roster), balance: 4200 }];
    })
  );
  const { creates, updates, unchanged } = buildPlan(rows, existing);
  assert.equal(creates.length, 0);
  assert.equal(updates.length, 0);
  assert.equal(unchanged.length, 2);
});

test('THE IMPORTANT ONE: a corrected name does not disturb festival state', () => {
  // Amélie is already checked in, has 42.00 € on her bracelet, and someone fixes
  // the spelling of her name in the Sheet.
  const before = toRosterFields({
    ticketRef: 'TKT-10432',
    name: 'Amelie Roux',
    ticketType: 'Full pass',
    city: 'Lyon',
  });
  const existing = new Map([
    [
      'tkt-10432',
      {
        ...before,
        rosterHash: rosterHash(before),
        balance: 4200,
        braceletId: '04:B4:2F:11',
        checkedInAt: 'Fri 17:12',
        lastTxId: 'abc-123',
        isBlocked: true,
        blockReason: 'Under review',
      },
    ],
  ]);

  const { updates } = buildPlan(rowsFrom([SHEET[0]]), existing);
  assert.equal(updates.length, 1);

  const written = Object.keys(updates[0].data);
  for (const forbidden of [
    'balance',
    'braceletId',
    'checkedInAt',
    'lastTxId',
    'isBlocked',
    'blockReason',
  ]) {
    assert.ok(
      !written.includes(forbidden),
      `import would have written ${forbidden} — that is a money bug`
    );
  }
  assert.equal(updates[0].data.name, 'Amélie Roux');
  assert.deepEqual(updates[0].changes, ['name: "Amelie Roux" → "Amélie Roux"']);
});

test('people removed from the Sheet are reported, never deleted', () => {
  const existing = new Map([
    ['tkt-10432', { name: 'Amélie Roux', balance: 0, braceletId: null }],
    ['tkt-99999', { name: 'Refunded Person', balance: 1500, braceletId: '04:AA:BB:CC' }],
  ]);
  const orphans = findOrphans(rowsFrom(SHEET), existing);
  assert.equal(orphans.length, 1);
  assert.equal(orphans[0].id, 'tkt-99999');
  assert.equal(orphans[0].checkedIn, true);
  assert.equal(orphans[0].balance, 1500);
});

test('the identity column is one of the mapped columns', () => {
  assert.ok(
    Object.keys(COLUMNS).includes(IDENTITY_COLUMN),
    `IDENTITY_COLUMN "${IDENTITY_COLUMN}" must be a key of COLUMNS`
  );
});
