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
  findRevoked,
  parseRows,
  partitionByStatus,
  resolveColumns,
  rosterHash,
  validateIdentity,
} from './diff.mjs';
import {
  COLUMNS,
  IDENTITY_COLUMN,
  IMPORTABLE_STATUSES,
  toDocumentId,
  toRosterFields,
} from './mapping.mjs';

// A header row matching the placeholder mapping.mjs, in a deliberately awkward
// order and with stray whitespace and casing.
// The real registrations sheet's headers, in their real order, with the casing
// and stray whitespace a hand-maintained Google Form sheet actually has.
const HEADER = [
  'Id', 'Клеймо за време', ' Full Name', 'Email', 'Phone Number', 'Role',
  'PASS TYPE', 'Level', 'Which country are you coming from?', 'Comments', 'Status',
];

const row = ({ id, name, pass = 'Full pass', country = 'Bulgaria', status = 'Paid' }) =>
  [id, '2026-07-01 10:00:00', name, `${id}@example.com`, '+359000000', 'Follower',
   pass, 'Intermediate', country, '', status];

const SHEET = [
  row({ id: '1041', name: 'Amélie Roux', country: 'France' }),
  row({ id: '1042', name: 'Tomás Herrera', country: 'Spain' }),
];

function rowsFrom(cells, header = HEADER) {
  const resolved = resolveColumns(header);
  return validateIdentity(parseRows(cells, resolved)).usable;
}

test('resolves columns despite case and whitespace differences', () => {
  const resolved = resolveColumns(HEADER);
  assert.equal(resolved.ticketRef, 0);
  assert.equal(resolved.name, 2);
  assert.equal(resolved.ticketType, 6);
  assert.equal(resolved.country, 8);
  assert.equal(resolved.status, 10);
});

test('a missing column fails loudly and lists the real headers', () => {
  assert.throws(
    () => resolveColumns(['Name', 'Country']),
    (err) => {
      assert.match(err.message, /were not found in the Sheet/);
      assert.match(err.message, /Headers actually present/);
      assert.match(err.message, /\[0\] Name/);
      return true;
    }
  );
});

test('derives stable document ids from the identity column', () => {
  assert.equal(toDocumentId('1041'), '1041');
  assert.equal(toDocumentId('  TKT/10432  '), 'tkt-10432');
  assert.throws(() => toDocumentId('///'));
});

test('blank identity values are reported, not guessed at', () => {
  const resolved = resolveColumns(HEADER);
  const rows = parseRows([row({ id: '   ', name: 'No Id' }), ...SHEET], resolved);
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

  const amelie = creates.find((c) => c.id === '1041');
  assert.equal(amelie.data.name, 'Amélie Roux');
  assert.equal(amelie.data.nameLower, 'amélie roux');
  assert.equal(amelie.data.country, 'France');
  assert.equal(amelie.data.balance, 0);
  assert.equal(amelie.data.braceletId, null);
  assert.equal(amelie.data.isBlocked, false);
});

test('personal data in the Sheet does not reach Firestore', () => {
  const { creates } = buildPlan(rowsFrom(SHEET), new Map());
  const fields = Object.keys(creates[0].data);
  for (const forbidden of [/email/i, /phone/i, /comment/i, /level/i, /shirt/i]) {
    assert.ok(!fields.some((f) => forbidden.test(f)), `${forbidden} leaked into ${fields.join(',')}`);
  }
  // `Role` in this Sheet is the DANCE role. It must never land in a field called
  // `role`, which is what the security rules read for authorisation.
  assert.ok(!fields.includes('role'), fields.join(','));
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
    ticketRef: '1041',
    name: 'Amelie Roux',
    ticketType: 'Full pass',
    country: 'France',
  });
  const existing = new Map([
    [
      '1041',
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
    ['1041', { name: 'Amélie Roux', balance: 0, braceletId: null }],
    ['9999', { name: 'Removed From Sheet', balance: 1500, braceletId: '04:AA:BB:CC' }],
  ]);
  const orphans = findOrphans(rowsFrom(SHEET), existing);
  assert.equal(orphans.length, 1);
  assert.equal(orphans[0].id, '9999');
  assert.equal(orphans[0].checkedIn, true);
  assert.equal(orphans[0].balance, 1500);
});

test('the identity column is one of the mapped columns', () => {
  assert.ok(
    Object.keys(COLUMNS).includes(IDENTITY_COLUMN),
    `IDENTITY_COLUMN "${IDENTITY_COLUMN}" must be a key of COLUMNS`
  );
});

// ── Status ─────────────────────────────────────────────────────────────────

test('imports Paid and nothing else', () => {
  const rows = rowsFrom([
    row({ id: '1', name: 'Paid Person', status: 'Paid' }),
    row({ id: '2', name: 'Waiting Person', status: 'Pending' }),
    row({ id: '3', name: 'Gone Person', status: 'Cancelled' }),
    row({ id: '4', name: 'Shouty Person', status: 'PAID' }),
    row({ id: '5', name: 'Spaced Person', status: '  paid ' }),
    row({ id: '6', name: 'Blank Person', status: '' }),
  ]);
  const { importable, excluded } = partitionByStatus(rows);
  // Case and stray whitespace must not decide whether somebody gets in.
  assert.deepEqual(importable.map((r) => r.__id), ['1', '4', '5']);
  assert.deepEqual(excluded.map((r) => r.__id), ['2', '3', '6']);
});

test('counts what it skipped, by status', () => {
  // Not decoration: a value like "Paid (bank transfer)" is excluded by the
  // Paid-only rule, and this breakdown is the only place that shows up before
  // the guest is missing at the door.
  const rows = rowsFrom([
    row({ id: '1', name: 'A', status: 'Paid' }),
    row({ id: '2', name: 'B', status: 'Pending' }),
    row({ id: '3', name: 'C', status: 'Pending' }),
    row({ id: '4', name: 'D', status: 'Paid (bank transfer)' }),
    row({ id: '5', name: 'E', status: '' }),
  ]);
  const { breakdown } = partitionByStatus(rows);
  assert.equal(breakdown.get('pending'), 2);
  assert.equal(breakdown.get('paid (bank transfer)'), 1);
  assert.equal(breakdown.get('(blank)'), 1);
});

test('an unpaid person is never created in Firestore', () => {
  const rows = rowsFrom([row({ id: '7', name: 'Never Paid', status: 'Pending' })]);
  const { importable } = partitionByStatus(rows);
  const { creates, updates } = buildPlan(importable, new Map());
  assert.equal(creates.length, 0);
  assert.equal(updates.length, 0);
});

test('someone refunded AFTER checking in is reported with their balance intact', () => {
  const rows = rowsFrom([row({ id: '1041', name: 'Amélie Roux', status: 'Refunded' })]);
  const { importable, excluded } = partitionByStatus(rows);
  assert.equal(importable.length, 0);

  const existing = new Map([
    ['1041', { name: 'Amélie Roux', balance: 4000, braceletId: '04:B4:2F:11' }],
  ]);
  const revoked = findRevoked(excluded, existing);
  assert.equal(revoked.length, 1);
  assert.equal(revoked[0].status, 'refunded');
  assert.equal(revoked[0].checkedIn, true);
  assert.equal(revoked[0].balance, 4000);

  // And crucially the plan does not touch them: 40 € on a bracelet is real money,
  // and what happens to it is an organiser decision.
  const { creates, updates } = buildPlan(importable, existing);
  assert.equal(creates.length + updates.length, 0);
});

test('Paid is the only importable status', () => {
  // Pinned deliberately. Widening this is an organiser decision about who may be
  // checked in, not a refactor.
  assert.deepEqual(IMPORTABLE_STATUSES, ['paid']);
});
