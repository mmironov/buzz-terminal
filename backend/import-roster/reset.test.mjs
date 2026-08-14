import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planReset, isNoOp, checkConfirmation, summariseLedger } from './reset.mjs';

const sheetPerson = (id) => ({ id, data: { source: 'sheet', name: 'Someone', balance: 1200 } });
const doorSale = (id) => ({ id, data: { source: 'evening', name: 'Evening #3', balance: 500 } });

test('test-data scope keeps the imported roster and deletes the door sales', () => {
  const plan = planReset({
    participants: [sheetPerson('a'), doorSale('ev-friday-1'), sheetPerson('b')],
    braceletIds: ['04:A1'],
    ledgerCount: 7,
  });

  assert.deepEqual(plan.deleteParticipants, ['ev-friday-1']);
  assert.deepEqual(plan.resetParticipants, ['a', 'b']);
  // Re-importing 83 people to undo a test is a needless dependency on the Sheet
  // being reachable at the moment you want a clean database.
  assert.equal(plan.scope, 'test-data');
});

test('all scope deletes every participant and resets none', () => {
  const plan = planReset({
    participants: [sheetPerson('a'), doorSale('ev-friday-1')],
    scope: 'all',
  });
  assert.deepEqual(plan.deleteParticipants, ['a', 'ev-friday-1']);
  assert.deepEqual(plan.resetParticipants, []);
});

test('a reset returns exactly the four fields the terminals own', () => {
  const { resetFields } = planReset({ participants: [] });
  assert.deepEqual(resetFields, {
    braceletId: null,
    checkedInAt: null,
    balance: 0,
    lastTxId: null,
  });
  // Roster fields must be absent: a reset is not a re-import, and silently
  // blanking somebody's name would make the roster unrecoverable without the Sheet.
  for (const owned of ['name', 'ticketType', 'country', 'ticketRef', 'source']) {
    assert.equal(owned in resetFields, false, `${owned} belongs to the importer`);
  }
});

test('an unknown scope is refused rather than guessed at', () => {
  assert.throws(() => planReset({ participants: [], scope: 'everything' }), /Unknown scope/);
});

test('a clean database is recognised as a no-op', () => {
  assert.equal(isNoOp(planReset({ participants: [] })), true);
  assert.equal(isNoOp(planReset({ participants: [sheetPerson('a')] })), false);
});

// ── the rails ──────────────────────────────────────────────────────────────

test('a dry run needs no confirmation', () => {
  assert.equal(checkConfirmation({ apply: false, projectId: 'swing-buzz' }), null);
});

test('--apply without --confirm is refused, and the message names the project', () => {
  const refusal = checkConfirmation({ apply: true, projectId: 'swing-buzz' });
  assert.match(refusal, /cannot be undone/);
  assert.match(refusal, /--confirm=swing-buzz/);
});

test('THE TRAP: a confirmation for a different project is refused', () => {
  // The reason --confirm exists. Wiping a scratch project is a shrug; wiping the
  // festival's is unrecoverable, and the two commands differ by one word.
  const refusal = checkConfirmation({ apply: true, confirm: 'swing-buzz-test', projectId: 'swing-buzz' });
  assert.match(refusal, /does not match/);
});

test('a matching confirmation proceeds', () => {
  assert.equal(checkConfirmation({ apply: true, confirm: 'swing-buzz', projectId: 'swing-buzz' }), null);
});

test('the ledger summary separates top-ups from charges', () => {
  const money = summariseLedger([
    { type: 'topup', amount: 2000 },
    { type: 'charge', amount: 800 },
    { type: 'topup', amount: 500 },
  ]);
  assert.deepEqual(money, { topUps: 2500, charges: 800, net: 1700, count: 3 });
});

test('the summary tolerates a malformed entry rather than reporting NaN money', () => {
  const money = summariseLedger([{ type: 'topup' }, { type: 'charge', amount: 400 }]);
  assert.equal(money.topUps, 0);
  assert.equal(money.net, -400);
  assert.ok(Number.isFinite(money.net));
});
