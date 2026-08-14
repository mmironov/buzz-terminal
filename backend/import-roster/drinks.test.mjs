import { test } from 'node:test';
import assert from 'node:assert/strict';
import { seedDrinks, DEFAULT_DRINKS } from './firestore.mjs';

// A fake Firestore, just enough to record what `seedDrinks` would send. The real
// thing is exercised against the live project by `npm run seed-drinks`; what needs
// covering here is the decision about which existing drinks get retired, because
// getting it wrong either leaves a withdrawn drink on sale or takes the whole menu
// down mid-service.
function fakeDb(existing = {}) {
  const writes = { set: [], update: [] };
  const docs = Object.entries(existing).map(([id, data]) => ({
    id,
    data: () => data,
    ref: { id },
  }));

  return {
    writes,
    collection(name) {
      assert.equal(name, 'drinks');
      return {
        doc: (id) => ({ id }),
        get: async () => ({ docs, size: docs.length }),
      };
    },
    batch() {
      return {
        set: (ref, data, options) => writes.set.push({ id: ref.id, data, options }),
        update: (ref, data) => writes.update.push({ id: ref.id, data }),
        commit: async () => {},
      };
    },
  };
}

test('writes each drink with its list position as sortOrder', async () => {
  const db = fakeDb();
  const result = await seedDrinks(db, [
    { id: 'water', name: 'Water', price: 200 },
    { id: 'beer', name: 'Beer', price: 400 },
  ]);

  assert.deepEqual(result, { written: 2, retired: 0 });
  assert.deepEqual(
    db.writes.set.map((w) => [w.id, w.data.sortOrder, w.data.isActive]),
    [
      ['water', 0, true],
      ['beer', 1, true],
    ]
  );
});

test('merges, so a price change never clears fields the admin panel may add later', async () => {
  const db = fakeDb();
  await seedDrinks(db, [{ id: 'beer', name: 'Beer', price: 450 }]);
  assert.deepEqual(db.writes.set[0].options, { merge: true });
});

test('a drink dropped from the list is deactivated, not deleted', async () => {
  const db = fakeDb({
    water: { name: 'Water', price: 200, sortOrder: 0, isActive: true },
    prosecco: { name: 'Prosecco', price: 600, sortOrder: 1, isActive: true },
  });

  const result = await seedDrinks(db, [{ id: 'water', name: 'Water', price: 200 }]);

  assert.deepEqual(result, { written: 1, retired: 1 });
  assert.deepEqual(db.writes.update, [{ id: 'prosecco', data: { isActive: false } }]);
  // Deleting it would orphan every ledger line that names it. A drink that
  // stopped being sold still happened.
  assert.equal(db.writes.update.length, 1);
});

test('an already-retired drink is left alone rather than rewritten every run', async () => {
  const db = fakeDb({
    prosecco: { name: 'Prosecco', price: 600, sortOrder: 1, isActive: false },
  });
  const result = await seedDrinks(db, [{ id: 'water', name: 'Water', price: 200 }]);
  assert.equal(result.retired, 0);
  assert.deepEqual(db.writes.update, []);
});

test('re-seeding the same list is idempotent and retires nothing', async () => {
  const existing = Object.fromEntries(
    DEFAULT_DRINKS.map((d, i) => [d.id, { ...d, sortOrder: i, isActive: true }])
  );
  const result = await seedDrinks(fakeDb(existing), DEFAULT_DRINKS);
  assert.deepEqual(result, { written: DEFAULT_DRINKS.length, retired: 0 });
});

test('the menu is priced in whole cents, and nothing is free', () => {
  for (const drink of DEFAULT_DRINKS) {
    assert.ok(Number.isInteger(drink.price), `${drink.id} price must be integer cents`);
    assert.ok(drink.price > 0, `${drink.id} must cost something`);
    assert.ok(drink.name.trim().length > 0, `${drink.id} needs a name`);
  }
  assert.equal(new Set(DEFAULT_DRINKS.map((d) => d.id)).size, DEFAULT_DRINKS.length);
});
