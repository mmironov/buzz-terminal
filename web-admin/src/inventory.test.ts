import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  costOf,
  litres,
  parseLitres,
  soldByDrink,
  stockReport,
  type ChargeLike,
} from './inventory.ts';

// ═══════════════════════════════════════════════════════════════════════════
//  The stock arithmetic.
//
//  Run with `npm run test:stock`. Pure functions, no Firestore, because "how
//  much gin is left" is a number somebody acts on at 2am.
// ═══════════════════════════════════════════════════════════════════════════

const charge = (at: string, items: [string, string, number][]): ChargeLike => ({
  type: 'charge',
  createdAt: new Date(at),
  items: items.map(([drinkId, name, quantity]) => ({ drinkId, name, quantity })),
});

const FRIDAY = [
  charge('2026-09-25T20:10:00Z', [['gt', 'Gin & tonic', 2], ['beer', 'Draught beer', 1]]),
  charge('2026-09-25T23:40:00Z', [['gt', 'Gin & tonic', 1]]),
];
const SATURDAY = [charge('2026-09-26T21:00:00Z', [['beer', 'Draught beer', 4]])];

test('what was sold, biggest first', () => {
  const sold = soldByDrink([...FRIDAY, ...SATURDAY]);
  assert.deepEqual(sold, [
    { drinkId: 'beer', name: 'Draught beer', quantity: 5 },
    { drinkId: 'gt', name: 'Gin & tonic', quantity: 3 },
  ]);
});

test('a top-up is not a sale', () => {
  const entries: ChargeLike[] = [
    ...FRIDAY,
    { type: 'topup', createdAt: new Date('2026-09-25T20:00:00Z'), items: [] },
  ];
  assert.equal(soldByDrink(entries).reduce((n, l) => n + l.quantity, 0), 4);
});

test('THE ONE FOR NEXT YEAR: a night is a half-open window', () => {
  // Consecutive nights must not both claim the same round, which is the whole
  // point of recording the server's clock on every charge.
  const friday = soldByDrink([...FRIDAY, ...SATURDAY], {
    from: new Date('2026-09-25T12:00:00Z'),
    to: new Date('2026-09-26T12:00:00Z'),
  });
  assert.deepEqual(friday.map((l) => [l.drinkId, l.quantity]), [['gt', 3], ['beer', 1]]);

  const saturday = soldByDrink([...FRIDAY, ...SATURDAY], {
    from: new Date('2026-09-26T12:00:00Z'),
    to: new Date('2026-09-27T12:00:00Z'),
  });
  assert.deepEqual(saturday.map((l) => [l.drinkId, l.quantity]), [['beer', 4]]);
});

test('an entry still in flight belongs to no night, but is in the total', () => {
  const pending: ChargeLike = { type: 'charge', createdAt: null, items: [{ drinkId: 'gt', name: 'Gin & tonic', quantity: 9 }] };
  assert.equal(soldByDrink([pending])[0]!.quantity, 9);
  assert.deepEqual(soldByDrink([pending], { from: new Date('2026-09-25T12:00:00Z') }), []);
});

// ── The report ─────────────────────────────────────────────────────────────

const items = [
  { id: 'gin', name: 'Gin', openingMl: 6000, isActive: true },
  { id: 'tonic', name: 'Tonic', openingMl: 12000, isActive: true },
  { id: 'keg', name: 'Draught beer', openingMl: 30000, isActive: true },
];
const drinks = [
  { id: 'gt', name: 'Gin & tonic', recipe: { gin: 50, tonic: 200 } },
  { id: 'beer', name: 'Draught beer', recipe: { keg: 400 } },
];

test('THE ONE THAT MATTERS: what is left is opening plus deliveries minus what was poured', () => {
  const report = stockReport({
    items,
    drinks,
    sold: soldByDrink([...FRIDAY, ...SATURDAY]),
    movements: { gin: 3000 },            // a new bottle carried in
  });

  const gin = report.rows.find((r) => r.id === 'gin')!;
  assert.equal(gin.consumedMl, 150);      // 3 × 50 ml
  assert.equal(gin.movedMl, 3000);
  assert.equal(gin.remainingMl, 6000 + 3000 - 150);
  assert.equal(gin.fractionLeft, 8850 / 9000);

  const keg = report.rows.find((r) => r.id === 'keg')!;
  assert.equal(keg.consumedMl, 2000);     // 5 × 400 ml
  assert.equal(keg.remainingMl, 28000);
});

test('what is drinking the gin, biggest first', () => {
  const report = stockReport({ items, drinks, sold: soldByDrink(FRIDAY), movements: {} });
  assert.deepEqual(report.rows.find((r) => r.id === 'gin')!.drawnBy, [
    { drinkId: 'gt', name: 'Gin & tonic', ml: 150 },
  ]);
});

test('THE ONE THAT WOULD LIE: a drink with no recipe is named, not ignored', () => {
  // A missing recipe makes the stock look healthier than it is, which is the
  // one direction this must never fail in.
  const report = stockReport({
    items,
    drinks: [drinks[0]!],                  // beer has no recipe now
    sold: soldByDrink([...FRIDAY, ...SATURDAY]),
    movements: {},
  });
  assert.deepEqual(report.uncosted.map((l) => [l.drinkId, l.quantity]), [['beer', 5]]);
  assert.equal(report.rows.find((r) => r.id === 'keg')!.consumedMl, 0);
});

test('a recipe pointing at a deleted stock item is reported', () => {
  const report = stockReport({
    items: [items[0]!],                    // tonic is gone
    drinks,
    sold: soldByDrink(FRIDAY),
    movements: {},
  });
  assert.deepEqual(report.orphanedRecipes, [
    { drinkId: 'gt', stockId: 'tonic' },
    { drinkId: 'beer', stockId: 'keg' },
  ]);
});

test('going below zero is shown, not clamped', () => {
  // It means the opening figure or a recipe is wrong. Clamping at zero hides
  // exactly the thing worth seeing.
  const report = stockReport({
    items: [{ id: 'gin', name: 'Gin', openingMl: 100, isActive: true }],
    drinks,
    sold: soldByDrink(FRIDAY),
    movements: {},
  });
  assert.equal(report.rows[0]!.remainingMl, -50);
});

test('an item nobody has sold from is untouched', () => {
  const report = stockReport({ items, drinks, sold: [], movements: {} });
  assert.deepEqual(report.rows.map((r) => r.remainingMl), [6000, 12000, 30000]);
  assert.deepEqual(report.uncosted, []);
});

// ── Reading and writing litres ─────────────────────────────────────────────

test('litres read the way somebody says them out loud', () => {
  assert.equal(litres(6000), '6.0 L');
  assert.equal(litres(30000), '30.0 L');
  // THE ONE THAT FLATTERED THE STORE: 10.8 L must not read as "11 L".
  assert.equal(litres(10800), '10.8 L');
  assert.equal(litres(250000), '250 L');
  assert.equal(litres(350), '350 ml');
  assert.equal(litres(-50), '-50 ml');
  assert.equal(litres(0), '0 ml');
});

test('typing a stock level, in litres, without floats reaching the database', () => {
  assert.equal(parseLitres('0.7'), 700);
  assert.equal(parseLitres('6'), 6000);
  assert.equal(parseLitres('1,5'), 1500);      // a comma decimal, typed by half of Europe
  assert.equal(parseLitres('30 L'), 30000);
  assert.equal(parseLitres(''), null);
  assert.equal(parseLitres('-1'), null);
  assert.equal(parseLitres('abc'), null);
  // Four decimals is a typo, not a microlitre.
  assert.equal(parseLitres('0.7001'), null);
});


// ── What it cost ───────────────────────────────────────────────────────────

test('THE ONE THAT MUST NOT ROUND TO ZERO: cents per litre, applied to millilitres', () => {
  // 18 € a litre, 50 ml of it: 90 cents.
  assert.equal(costOf(50, 1800), 90);
  assert.equal(costOf(1000, 1800), 1800);
  assert.equal(costOf(30000, 250), 7500);       // a 30 L keg at 2.50 €/L
  assert.equal(costOf(0, 1800), 0);
});

test('nobody has entered a price is not the same as free', () => {
  // Null all the way through rather than zero: a money column that silently
  // treats "unknown" as "free" is the sort of number somebody takes to a
  // supplier.
  assert.equal(costOf(50, null), null);

  const report = stockReport({
    items: [
      { id: 'gin', name: 'Gin', openingMl: 700, isActive: true, costPerLitreCents: 1800 },
      { id: 'tonic', name: 'Tonic', openingMl: 12000, isActive: true },
    ],
    drinks: [{ id: 'gt', name: 'Gin & tonic', recipe: { gin: 50, tonic: 200 } }],
    sold: [{ drinkId: 'gt', name: 'Gin & tonic', quantity: 6 }],
    movements: {},
  });

  const gin = report.rows.find((r) => r.id === 'gin')!;
  assert.equal(gin.consumedMl, 300);
  assert.equal(gin.pouredCost, 540);            // 300 ml at 18 €/L
  assert.equal(gin.remainingValue, 720);        // 400 ml still in the bottle

  const tonic = report.rows.find((r) => r.id === 'tonic')!;
  assert.equal(tonic.consumedMl, 1200);
  assert.equal(tonic.pouredCost, null);
  assert.equal(tonic.remainingValue, null);
});
