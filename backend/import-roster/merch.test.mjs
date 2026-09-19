// Runs with plain Node, no dependencies, no credentials:
//     node --test backend/import-roster/
//
// The merch import has one thing it can get catastrophically wrong, and it is
// the same thing the roster import can: overwriting festival state. A re-import
// on Saturday afternoon that reset `collectedAt` would tell the desk that forty
// people are still owed a t-shirt they are already wearing.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import { assertTouchesOnlyMerchImportFields, buildMerchPlan } from './diff.mjs';
import {
  MERCH_IMPORT_OWNED_FIELDS,
  parseMerchItem,
  parseMerchDetail,
  toMerchOrder,
} from './mapping.mjs';

// ── Parsing what the form actually contains ────────────────────────────────

test('the form values from the real Sheet map to the four items', () => {
  assert.equal(parseMerchItem('No Swing Buzz attire'), 'none');
  assert.equal(parseMerchItem('T-Shirt only: 20 €'), 'shirt');
  assert.equal(parseMerchItem('Tote bag only: 15 €'), 'tote');
  assert.equal(parseMerchItem('T-Shirt and tote bag: 25 €'), 'shirtAndTote');
});

test('a blank is the same as ordering nothing', () => {
  assert.equal(parseMerchItem(''), 'none');
  assert.equal(parseMerchItem('   '), 'none');
  assert.equal(parseMerchItem(undefined), 'none');
});

test('a changed price does not turn an order into nothing', () => {
  // Early-bird and full pricing are different strings for the same shirt, and
  // next year's prices will be different again.
  assert.equal(parseMerchItem('T-Shirt only: 24 €'), 'shirt');
  assert.equal(parseMerchItem('T-Shirt and tote bag: 30 EUR'), 'shirtAndTote');
});

test('an option nobody anticipated is recorded as unknown, not dropped', () => {
  // The desk seeing "something was ordered, ask them" beats a guest being told
  // they ordered nothing.
  assert.equal(parseMerchItem('Swing Buzz cap: 12 €'), 'unknown');
});

test('the price does not reach Firestore, exactly as with pass types', () => {
  const order = toMerchOrder({
    merchAttire: 'T-Shirt and tote bag: 25 €',
    merchSize: 'L',
    merchColour: 'Natural',
  });
  const serialised = JSON.stringify(order);
  assert.ok(!serialised.includes('25'), serialised);
  assert.ok(!serialised.includes('€'), serialised);
  assert.deepEqual(order, { item: 'shirtAndTote', size: 'L', colour: 'Natural' });
});

test('"No Swing Buzz attire" in the size and colour columns is a blank, not a size', () => {
  // It is an option in all three dropdowns, so 79 people have it as their
  // "size". Left alone, the desk reads "size: No Swing Buzz attire".
  assert.equal(parseMerchDetail('No Swing Buzz attire'), null);
  assert.equal(parseMerchDetail(''), null);
  assert.equal(parseMerchDetail('M'), 'M');
});

test('a colour keeps its name and loses the form note', () => {
  assert.equal(
    parseMerchDetail('French Navy (Available only in XS, M, L, XL)'),
    'French Navy'
  );
  // The note is stripped, not the whole value, and a colour with no note is
  // untouched.
  assert.equal(parseMerchDetail('Sky Blue'), 'Sky Blue');
});

test('ordering nothing produces no order at all', () => {
  assert.equal(
    toMerchOrder({ merchAttire: 'No Swing Buzz attire', merchSize: 'No Swing Buzz attire' }),
    null
  );
});

// ── The plan ───────────────────────────────────────────────────────────────

const row = (id, attire, size, colour) => ({
  __id: id,
  __sheetRow: 2,
  merchAttire: attire,
  merchSize: size,
  merchColour: colour,
});

test('a first import creates an order with nothing collected', () => {
  const plan = buildMerchPlan([row('a', 'T-Shirt only: 20 €', 'S', 'Natural')], new Map());
  assert.equal(plan.writes.length, 1);
  assert.equal(plan.writes[0].isNew, true);
  assert.deepEqual(plan.writes[0].initial, { collectedAt: null, collectedBy: null });
  assert.equal(plan.writes[0].data.item, 'shirt');
});

test('people who ordered nothing produce no writes at all', () => {
  const plan = buildMerchPlan(
    [row('a', 'No Swing Buzz attire', 'No Swing Buzz attire', 'No Swing Buzz attire')],
    new Map()
  );
  assert.deepEqual(plan, { writes: [], retires: [], unchanged: [] });
});

test('an unchanged order is skipped, so a re-import writes nothing', () => {
  const first = buildMerchPlan([row('a', 'T-Shirt only: 20 €', 'S', 'Natural')], new Map());
  const existing = new Map([['a', { ...first.writes[0].data, collectedAt: null }]]);
  const second = buildMerchPlan([row('a', 'T-Shirt only: 20 €', 'S', 'Natural')], existing);
  assert.equal(second.writes.length, 0);
  assert.equal(second.unchanged.length, 1);
});

test('THE TRAP: a re-import never carries collectedAt, so a handed-over shirt stays handed over', () => {
  // The guest changed size in the Sheet after collecting — the worst case,
  // because it forces a write to a document that already records a collection.
  const existing = new Map([
    ['a', {
      item: 'shirt', size: 'S', colour: 'Natural', orderHash: 'old',
      collectedAt: new Date('2026-08-21T18:00:00Z'), collectedBy: 'uid-reception',
    }],
  ]);
  const plan = buildMerchPlan([row('a', 'T-Shirt only: 20 €', 'M', 'Natural')], existing);

  assert.equal(plan.writes.length, 1);
  const write = plan.writes[0];
  assert.equal(write.isNew, false);
  // Absent from the payload, so a merge leaves what is already there.
  assert.equal('collectedAt' in write.data, false);
  assert.equal('collectedBy' in write.data, false);
  // And the initial state is not reapplied either, which would do it by the
  // back door.
  assert.equal(write.initial, null);
});

test('withdrawing an order retires it rather than deleting the record', () => {
  const existing = new Map([
    ['a', { item: 'shirt', size: 'S', colour: 'Natural', orderHash: 'old', collectedAt: null }],
  ]);
  const plan = buildMerchPlan([row('a', 'No Swing Buzz attire')], existing);
  assert.equal(plan.writes.length, 0);
  assert.equal(plan.retires.length, 1);
  assert.equal(plan.retires[0].data.item, 'none');
  assert.equal(plan.retires[0].data.size, null);
  // Deleting would also delete the record that it was handed over.
  assert.equal('collectedAt' in plan.retires[0].data, false);
});

test('a withdrawal is not repeated on the next run', () => {
  const existing = new Map([['a', { item: 'none', size: null, colour: null, orderHash: 'x' }]]);
  const plan = buildMerchPlan([row('a', 'No Swing Buzz attire')], existing);
  assert.deepEqual(plan, { writes: [], retires: [], unchanged: [] });
});

test('the guard rail refuses a payload that would touch what the terminals own', () => {
  assert.throws(
    () => assertTouchesOnlyMerchImportFields({ item: 'shirt', collectedAt: null }),
    /collectedAt/
  );
  assert.doesNotThrow(() =>
    assertTouchesOnlyMerchImportFields({ item: 'shirt', size: 'M', colour: 'Natural', orderHash: 'h' })
  );
});

test('the import-owned field list does not contain festival state', () => {
  // Pinned, because adding one here is how the guard rail above stops guarding.
  for (const owned of ['collectedAt', 'collectedBy']) {
    assert.ok(!MERCH_IMPORT_OWNED_FIELDS.includes(owned), owned);
  }
});
