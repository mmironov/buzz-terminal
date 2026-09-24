import { test } from 'node:test';
import assert from 'node:assert/strict';

import { normaliseAdmission, bracketedNotes, toRosterFields } from './mapping.mjs';
import {
  COMP_METHOD,
  ledgerEntry,
  parseAmount,
  planTopUps,
  toLabel,
  transactionId,
} from './topup.mjs';

// ── Reading staff and the guest list out of the Sheet ──────────────────────

test('the two markers are recognised, and nothing else is', () => {
  // Every one of these is a real value from the festival's Sheet.
  assert.equal(normaliseAdmission('Full Pass - 0 € (Staff member - Taster Teacher)'), 'staff');
  assert.equal(normaliseAdmission('Party Pass - 0 € (Staff member - Musician)'), 'staff');
  assert.equal(normaliseAdmission('Full Pass Gold - 0 € (Staff member - Main Teacher)'), 'staff');
  assert.equal(normaliseAdmission('Saturday Evening - 0 € (Guest list)'), 'guest');
  assert.equal(normaliseAdmission("Party Pass - 0 € (Guest list - Sakarias' friend)"), 'guest');

  // Brackets that are about money, not about who somebody is.
  assert.equal(normaliseAdmission('Full Pass - 185 € (EARLY BIRD pricing)'), '');
  assert.equal(normaliseAdmission('Full Pass Gold - 130 € (First Installment 50%)'), '');
  assert.equal(normaliseAdmission('Full Pass - 205 € (Upgrade from Party - 135€ + 70€)'), '');
  assert.equal(normaliseAdmission("Party Pass - 0 € (Discount from last year's competition)"), '');
  assert.equal(normaliseAdmission('Full Pass - 205 €'), '');
  assert.equal(normaliseAdmission(''), '');
  assert.equal(normaliseAdmission(undefined), '');
});

test('THE ONE IN THE REAL SHEET: an unclosed bracket still counts', () => {
  // "Party Pass - 0 € (Staff member - DJ" — no closing bracket, twice over.
  // A plain \(([^)]*)\) misses it, the two DJs are not staff, and the first
  // anybody hears about it is a DJ who was not topped up.
  assert.equal(normaliseAdmission('Party Pass - 0 € (Staff member - DJ'), 'staff');
  assert.equal(normaliseAdmission('Saturday Evening - 0 € (Guest list'), 'guest');
});

test('every bracket is checked, not only the first', () => {
  // One row already carries a pricing bracket and then more text. A scan that
  // stopped at the first bracket is one form edit away from missing somebody.
  assert.equal(
    normaliseAdmission('Full Pass - 0 € (EARLY BIRD pricing) (Staff member - Venue)'),
    'staff'
  );
  assert.deepEqual(bracketedNotes('A (one) B (two'), ['one', 'two']);
  assert.deepEqual(bracketedNotes('nothing here'), []);
});

test('case and spacing in the Sheet do not matter', () => {
  assert.equal(normaliseAdmission('Full Pass - 0 € (STAFF MEMBER - Bar)'), 'staff');
  assert.equal(normaliseAdmission('Full Pass - 0 € (  guest list  )'), 'guest');
});

test('the marking rides on the roster fields, so a re-import maintains it', () => {
  const fields = toRosterFields({
    ticketRef: '42',
    name: 'Sakarias',
    ticketType: 'Full Pass Gold - 0 € (Staff member - Main Teacher)',
    country: 'Sweden',
    level: 'Pro - you teach it',
  });
  assert.equal(fields.admission, 'staff');
  // And the pass type itself is unchanged by any of this: a staff member holds
  // a Full Pass Gold like anybody else.
  assert.equal(fields.ticketType, 'Full Pass Gold');
});

test('somebody who simply bought a ticket is marked as nothing', () => {
  const fields = toRosterFields({ ticketRef: '43', name: 'Someone', ticketType: 'Party Pass - 120 €' });
  assert.equal(fields.admission, '');
});

// ── Planning a top-up ──────────────────────────────────────────────────────

const staff = (id, over = {}) => ({ id, data: { name: `Staff ${id}`, admission: 'staff', balance: 0, ...over } });
const guest = (id) => ({ id, data: { name: `Guest ${id}`, admission: 'guest', balance: 0 } });
const payer = (id) => ({ id, data: { name: `Payer ${id}`, admission: '', balance: 0 } });

test('--all credits every staff member and nobody else', () => {
  const plan = planTopUps({
    participants: [staff('a'), guest('b'), payer('c'), staff('d')],
    amount: 2000,
    label: 'friday',
  });

  assert.deepEqual(plan.credits.map((c) => c.id), ['a', 'd']);
  assert.equal(plan.total, 4000);
  // The guest list is not staff. They got in free; they do not drink free.
  assert.deepEqual(
    plan.skipped.map((s) => [s.id, s.reason]),
    [['b', 'not staff'], ['c', 'not staff']]
  );
});

test('a balance is added to, never replaced', () => {
  // Somebody halfway through the festival has spent some of Thursday's credit.
  const plan = planTopUps({ participants: [staff('a', { balance: 750 })], amount: 2000, label: 'sat' });
  assert.equal(plan.credits[0].balanceBefore, 750);
  assert.equal(plan.credits[0].balanceAfter, 2750);
});

test('one person by id', () => {
  const plan = planTopUps({
    participants: [staff('a'), staff('b')],
    amount: 1000,
    target: { id: 'b' },
    label: 'extra',
  });
  assert.deepEqual(plan.credits.map((c) => c.id), ['b']);
  assert.equal(plan.skipped.length, 0);
});

test('an id that is not staff is refused rather than quietly credited', () => {
  // "Top up a staff member" is a different request from "give somebody money",
  // and the second one is reception's job — where it is written down as cash.
  const plan = planTopUps({
    participants: [payer('c')],
    amount: 1000,
    target: { id: 'c' },
    label: 'extra',
  });
  assert.equal(plan.credits.length, 0);
  assert.deepEqual(plan.skipped, [{ id: 'c', name: 'Payer c', reason: 'not staff' }]);
});

test('an id nobody has is an error, not an empty plan', () => {
  assert.throws(
    () => planTopUps({ participants: [staff('a')], amount: 1000, target: { id: 'nope' }, label: 'x' }),
    /No participant with id "nope"/
  );
});

test('a blocked account is skipped and said out loud', () => {
  const plan = planTopUps({ participants: [staff('a', { isBlocked: true })], amount: 1000, label: 'x' });
  assert.equal(plan.credits.length, 0);
  assert.equal(plan.skipped[0].reason, 'blocked');
});

test('THE ONE THAT MATTERS: the same label credits nobody twice', () => {
  // The protection against the obvious disaster — running it again because the
  // first run's output scrolled past, and paying the whole crew twice.
  const plan = planTopUps({
    participants: [staff('a'), staff('b')],
    amount: 2000,
    label: 'friday',
    alreadyCredited: ['a'],
  });
  assert.deepEqual(plan.credits.map((c) => c.id), ['b']);
  assert.match(plan.skipped[0].reason, /already credited under "friday"/);
});

test('the ledger id is derived, which is what makes that possible', () => {
  // Not a UUID: the id has to be the same on the second run for the write to
  // collide. `create` then refuses it at the database, not in this file.
  assert.equal(transactionId('friday', 'tkt-42'), 'staff-friday-tkt-42');
});

test('a label defaults to the date, so two runs in one afternoon are one run', () => {
  assert.equal(toLabel(undefined, new Date('2026-09-25T10:00:00Z')), '2026-09-25');
  assert.equal(toLabel('Friday Crew'), 'friday-crew');
  assert.throws(() => toLabel('!!!'), /does not slugify/);
});

// ── The money itself ───────────────────────────────────────────────────────

test('amounts are euros, and a slipped decimal point is caught', () => {
  assert.equal(parseAmount('20'), 2000);
  assert.equal(parseAmount('12.50'), 1250);
  assert.equal(parseAmount('0.05'), 5);
  assert.equal(parseAmount('20 €'), 2000);

  assert.throws(() => parseAmount('20,50'), /not a number of euros/);
  assert.throws(() => parseAmount('-5'), /not a number of euros/);
  assert.throws(() => parseAmount('abc'), /not a number of euros/);
  assert.throws(() => parseAmount('0'), /more than nothing/);
  // 2000 € instead of 20 €, which is the whole reason for a ceiling.
  assert.throws(() => parseAmount('2000'), /ceiling/);
});

test('the ledger entry is the same document a terminal writes', () => {
  // It has to be: the panel reads this history, and the balance invariant is
  // "money moved, and here is the entry that says why". A different shape here
  // would be a balance with a gap behind it.
  const entry = ledgerEntry({
    transactionId: 'staff-friday-a',
    amount: 2000,
    label: 'friday',
    serverTimestamp: 'TIMESTAMP',
  });

  assert.equal(entry.clientTxId, 'staff-friday-a');
  assert.equal(entry.type, 'topup');
  assert.equal(entry.amount, 2000);
  assert.equal(entry.signedAmount, 2000);      // a credit, so positive
  assert.equal(entry.createdAt, 'TIMESTAMP');  // the server's clock, never ours
  assert.equal(entry.grant, 'friday');
  // A top-up carries no items; the rules refuse them, and so does the meaning —
  // cash over the counter buys nothing.
  assert.equal('items' in entry, false);
});

test("the method says nobody paid, because nobody did", () => {
  // Recording staff credit as cash would put money in the end-of-night count
  // that nobody can produce from the box.
  assert.equal(ledgerEntry({ transactionId: 'x', amount: 1, label: 'l' }).method, COMP_METHOD);
  assert.equal(COMP_METHOD, 'comp');
  assert.equal(['cash', 'card'].includes(COMP_METHOD), false);
});

test('planning refuses money it cannot write honestly', () => {
  assert.throws(() => planTopUps({ participants: [], amount: 0, label: 'x' }), /positive whole number/);
  assert.throws(() => planTopUps({ participants: [], amount: 12.5, label: 'x' }), /positive whole number/);
  assert.throws(() => planTopUps({ participants: [], amount: 100 }), /label is required/);
});
