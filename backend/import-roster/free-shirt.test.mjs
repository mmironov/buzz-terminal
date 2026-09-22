// The free shirt: who is owed one, and what the importer must never touch.
//
// Its shape differs from a preordered order in exactly one way, and the whole
// file is about that difference: the Sheet decides WHETHER somebody gets a
// shirt, and the desk decides WHICH one, at the moment of handing it over. So
// `size` and `colour` are festival state here, where on an order they are
// import-owned — and an import that wrote them would erase the record of what
// somebody was actually given.

import assert from 'node:assert/strict';
import test from 'node:test';

import { buildFreeShirtPlan, assertTouchesOnlyFreeShirtImportFields } from './diff.mjs';
import { parseFreeShirt, initialFreeShirtState } from './mapping.mjs';

const rows = (...specs) =>
  specs.map((spec, index) => ({ __id: spec.id, __sheetRow: index + 2, freeShirt: spec.value }));

test('TRUE means a shirt, blank means none', () => {
  assert.equal(parseFreeShirt('TRUE'), true);
  assert.equal(parseFreeShirt('true'), true);
  assert.equal(parseFreeShirt(''), false);
  assert.equal(parseFreeShirt(undefined), false);
  assert.equal(parseFreeShirt('FALSE'), false);
});

test('read tolerantly — a hand-maintained checkbox column is not one spelling', () => {
  // The cost of a false negative is somebody being told at the desk that they
  // are not on the list, which is a conversation nobody at reception can settle.
  for (const yes of ['Yes', 'y', '1', ' TRUE ', 'да']) {
    assert.equal(parseFreeShirt(yes), true, `expected "${yes}" to count as a free shirt`);
  }
});

test('somebody new on the list gets a document with nothing chosen yet', () => {
  const plan = buildFreeShirtPlan(rows({ id: 'tkt-1', value: 'TRUE' }), new Map());
  assert.equal(plan.writes.length, 1);
  assert.equal(plan.writes[0].isNew, true);
  assert.deepEqual(plan.writes[0].data, { entitled: true });
  // Size and colour start empty because nobody has chosen them — that happens at
  // the desk, in front of the pile of shirts.
  assert.deepEqual(plan.writes[0].initial, {
    size: null, colour: null, collectedAt: null, collectedBy: null,
  });
});

test('nobody else gets one, and no document is written for them', () => {
  const plan = buildFreeShirtPlan(rows({ id: 'tkt-1', value: '' }), new Map());
  assert.equal(plan.writes.length, 0);
  assert.equal(plan.retires.length, 0);
});

test('a second import changes nothing for somebody already on the list', () => {
  const existing = new Map([['tkt-1', { entitled: true, size: 'M', colour: 'Natural' }]]);
  const plan = buildFreeShirtPlan(rows({ id: 'tkt-1', value: 'TRUE' }), existing);
  assert.equal(plan.writes.length, 0);
  assert.equal(plan.unchanged.length, 1);
});

test('THE TRAP: a re-import never rewrites the shirt somebody was handed', () => {
  // The failure this prevents: a shirt is handed over as L · Sky Blue, the
  // roster is re-imported an hour later, and the record becomes "entitled, size
  // unknown, never collected". The desk hands them a second shirt.
  const handedOver = {
    entitled: true,
    size: 'L',
    colour: 'Sky Blue',
    collectedAt: 'a real timestamp',
    collectedBy: 'uid-reception',
  };
  const plan = buildFreeShirtPlan(
    rows({ id: 'tkt-1', value: 'TRUE' }),
    new Map([['tkt-1', handedOver]])
  );
  // Unchanged, so nothing is written at all.
  assert.equal(plan.writes.length, 0);
  assert.equal(plan.unchanged.length, 1);

  // And even when something IS written — the entitlement coming back after being
  // withdrawn — the payload carries no size, colour or collection.
  const restored = buildFreeShirtPlan(
    rows({ id: 'tkt-1', value: 'TRUE' }),
    new Map([['tkt-1', { ...handedOver, entitled: false }]])
  );
  assert.equal(restored.writes.length, 1);
  assert.deepEqual(restored.writes[0].data, { entitled: true });
  // No initial state either: the document exists, so re-seeding it would be the
  // very overwrite this test is about.
  assert.equal(restored.writes[0].initial, null);
});

test('taken off the list: withdrawn, never deleted', () => {
  // Deleting would take the record of the handover with it, and the shirt is
  // already on somebody's back.
  const plan = buildFreeShirtPlan(
    rows({ id: 'tkt-1', value: '' }),
    new Map([['tkt-1', { entitled: true, size: 'M', colour: 'Natural' }]])
  );
  assert.equal(plan.writes.length, 0);
  assert.equal(plan.retires.length, 1);
  assert.deepEqual(plan.retires[0].data, { entitled: false });
});

test('withdrawing twice is not an update', () => {
  const plan = buildFreeShirtPlan(
    rows({ id: 'tkt-1', value: '' }),
    new Map([['tkt-1', { entitled: false }]])
  );
  assert.equal(plan.retires.length, 0);
});

test('the guard refuses a payload carrying the desk’s fields', () => {
  assert.doesNotThrow(() => assertTouchesOnlyFreeShirtImportFields({ entitled: true }));
  for (const field of ['size', 'colour', 'collectedAt', 'collectedBy']) {
    assert.throws(
      () => assertTouchesOnlyFreeShirtImportFields({ entitled: true, [field]: 'x' }),
      (error) => {
        assert.match(error.message, /belong to the terminals/);
        assert.match(error.message, new RegExp(field));
        return true;
      },
      `expected ${field} to be refused`
    );
  }
});

test('the initial state names every field the rules expect to exist', () => {
  assert.deepEqual(Object.keys(initialFreeShirtState()).sort(), [
    'collectedAt', 'collectedBy', 'colour', 'size',
  ]);
});
