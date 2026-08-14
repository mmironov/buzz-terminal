// ═══════════════════════════════════════════════════════════════════════════
//  Executable tests for ../firestore.rules.
//
//      npm test        (starts the Firestore emulator, runs these, stops it)
//
//  These are the only thing standing between a bug in a rules file and a bar
//  terminal crediting itself money. Everything the rules claim to guarantee is
//  asserted here, from both directions: the allowed thing succeeds AND the
//  forbidden thing fails. A rule that denies everything would pass half a suite.
//
//  Note the batch writes. Rules use getAfter() to check a balance against the
//  ledger entry that justifies it, and getAfter only sees documents written in
//  the same batch or transaction — which is exactly the property that makes the
//  invariant enforceable.
// ═══════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  writeBatch,
} from 'firebase/firestore';

let testEnv;

const PARTICIPANT = 'tkt-10001';
const CHIP = '04:B4:2F:11';
const OTHER_CHIP = '04:A1:9C:7E';

const RECEPTION_UID = 'uid-reception';
const BAR_UID = 'uid-bar';
const ADMIN_UID = 'uid-admin';

const reception = () =>
  testEnv.authenticatedContext(RECEPTION_UID, { role: 'reception' }).firestore();
const bar = () => testEnv.authenticatedContext(BAR_UID, { role: 'bar' }).firestore();
/** The web admin panel. Reads everything, blocks bracelets, owns the menu. */
const admin = () => testEnv.authenticatedContext(ADMIN_UID, { role: 'admin' }).firestore();
const roleless = () => testEnv.authenticatedContext('uid-nobody', {}).firestore();
const anonymous = () => testEnv.unauthenticatedContext().firestore();

/** Roster fields as the Sheet import would have written them. */
function rosterDoc(overrides = {}) {
  return {
    ticketRef: 'TKT-10001',
    name: 'Marta Lindqvist',
    nameLower: 'marta lindqvist',
    searchTokens: ['marta', 'lindqvist', 'full', 'pass'],
    ticketType: 'Full pass',
    city: 'Stockholm',
    rosterHash: 'abc123',
    braceletId: null,
    checkedInAt: null,
    balance: 0,
    lastTxId: null,
    isBlocked: false,
    blockReason: null,
    ...overrides,
  };
}

/**
 * A well-formed ledger entry. `type` decides the sign, and whether it carries an
 * itemisation: a charge must say what was bought, a top-up must not.
 *
 * The default itemisation is one line priced at the whole amount, so every
 * pre-existing money test keeps testing what it was written to test rather than
 * tripping over the new rule.
 */
function ledgerEntry({ txId, type, amount, staffUid, items }) {
  const entry = {
    clientTxId: txId,
    type,
    amount,
    signedAmount: type === 'topup' ? amount : -amount,
    staffUid,
    terminalId: 'terminal-01',
    createdAt: serverTimestamp(),
  };
  if (type === 'topup') return entry;
  return { ...entry, items: items ?? [oneLine(amount)] };
}

/** A single itemised line worth exactly `cents`. */
function oneLine(cents, quantity = 1) {
  return { drinkId: 'beer', name: 'Draught beer', unitPrice: cents, quantity };
}

/**
 * The shape every money mutation takes: ledger entry and new balance, together.
 * Split into two writes and the rules reject it, which is the point.
 */
function moneyBatch(db, { txId, type, amount, staffUid, balanceAfter, entry, items }) {
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'participants', PARTICIPANT, 'transactions', txId),
    entry ?? ledgerEntry({ txId, type, amount, staffUid, items })
  );
  batch.update(doc(db, 'participants', PARTICIPANT), {
    balance: balanceAfter,
    lastTxId: txId,
  });
  return batch.commit();
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'swing-buzz-rules-test',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'participants', PARTICIPANT), rosterDoc());
    await setDoc(doc(db, 'drinks', 'beer'), { name: 'Draught beer', price: 400 });
  });
});

/** Give the participant a bracelet and a balance, bypassing the rules. */
async function seedCheckedIn(balance = 2350, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'participants', PARTICIPANT), rosterDoc({
      braceletId: CHIP,
      checkedInAt: new Date(),
      balance,
      ...extra,
    }));
    await setDoc(doc(db, 'bracelets', CHIP), {
      participantId: PARTICIPANT,
      staffUid: RECEPTION_UID,
      pairedAt: new Date(),
    });
  });
}

// ───────────────────────────────────────────────────────────────────────────

describe('who can get in at all', () => {
  it('denies an unauthenticated reader', async () => {
    await assertFails(getDoc(doc(anonymous(), 'participants', PARTICIPANT)));
  });

  it('denies a signed-in user with no role claim', async () => {
    // The default state of a freshly created staff account. Denying it is
    // correct: a role is granted deliberately, via the Admin SDK.
    await assertFails(getDoc(doc(roleless(), 'participants', PARTICIPANT)));
  });

  it('allows both staff roles to read the roster', async () => {
    await assertSucceeds(getDoc(doc(reception(), 'participants', PARTICIPANT)));
    await assertSucceeds(getDoc(doc(bar(), 'participants', PARTICIPANT)));
  });

  it('lets staff read the menu but never write it', async () => {
    await assertSucceeds(getDoc(doc(bar(), 'drinks', 'beer')));
    await assertFails(updateDoc(doc(bar(), 'drinks', 'beer'), { price: 1 }));
    await assertFails(updateDoc(doc(reception(), 'drinks', 'beer'), { price: 1 }));
  });
});

describe('the roster belongs to the Sheet', () => {
  it('refuses to create a participant', async () => {
    await assertFails(
      setDoc(doc(reception(), 'participants', 'tkt-99999'), rosterDoc())
    );
  });

  it('refuses to delete a participant', async () => {
    await assertFails(deleteDoc(doc(reception(), 'participants', PARTICIPANT)));
  });

  // One assertion per test, so a failure names the field rather than the group.
  for (const [field, value] of [
    ['name', 'Someone Else'],
    ['ticketType', 'Weekend pass'],
    ['city', 'Malmö'],
    ['rosterHash', 'tampered'],
    ['ticketRef', 'TKT-00000'],
  ]) {
    it(`refuses to rewrite ${field} from a terminal`, async () => {
      await assertFails(
        updateDoc(doc(reception(), 'participants', PARTICIPANT), { [field]: value })
      );
      await assertFails(
        updateDoc(doc(bar(), 'participants', PARTICIPANT), { [field]: value })
      );
    });
  }

  it('tolerates a write that changes nothing', async () => {
    // Writing a field its existing value produces an empty diff, so
    // affectedKeys() is empty and hasOnly() passes. That is correct: nothing was
    // rewritten. Worth pinning down, because it is the reason the first version
    // of the test above passed when it should not have — it "rewrote"
    // ticketType to the value it already had.
    await assertSucceeds(
      updateDoc(doc(reception(), 'participants', PARTICIPANT), { ticketType: 'Full pass' })
    );
  });
});

describe('blocks are an organiser decision', () => {
  it('refuses to let a terminal lift a block', async () => {
    await seedCheckedIn(2350, { isBlocked: true });
    await assertFails(updateDoc(doc(reception(), 'participants', PARTICIPANT), { isBlocked: false }));
  });

  it('refuses to let a terminal apply a block', async () => {
    await seedCheckedIn();
    await assertFails(updateDoc(doc(reception(), 'participants', PARTICIPANT), { isBlocked: true }));
  });

  it('refuses a top-up on a blocked bracelet', async () => {
    await seedCheckedIn(2350, { isBlocked: true });
    await assertFails(
      moneyBatch(reception(), {
        txId: 'tx-1', type: 'topup', amount: 2000,
        staffUid: RECEPTION_UID, balanceAfter: 4350,
      })
    );
  });

  it('refuses a charge on a blocked bracelet', async () => {
    await seedCheckedIn(2350, { isBlocked: true });
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1950,
      })
    );
  });
});

describe('pairing a bracelet', () => {
  function pair(db, { chip = CHIP, uid = RECEPTION_UID, withLookup = true } = {}) {
    const batch = writeBatch(db);
    batch.update(doc(db, 'participants', PARTICIPANT), {
      braceletId: chip,
      checkedInAt: serverTimestamp(),
    });
    if (withLookup) {
      batch.set(doc(db, 'bracelets', chip), {
        participantId: PARTICIPANT,
        staffUid: uid,
        pairedAt: serverTimestamp(),
      });
    }
    return batch.commit();
  }

  it('lets reception pair a fresh chip', async () => {
    await assertSucceeds(pair(reception()));
  });

  it('refuses to let the bar pair a chip', async () => {
    await assertFails(pair(bar()));
  });

  it('refuses a pairing with no matching reverse-lookup document', async () => {
    // Otherwise a scan could resolve to nobody, or to the wrong person.
    await assertFails(pair(reception(), { withLookup: false }));
  });

  it('refuses to pair a second bracelet to someone already checked in', async () => {
    await seedCheckedIn();
    await assertFails(pair(reception(), { chip: OTHER_CHIP }));
  });

  it('refuses to re-point an existing bracelet at somebody else', async () => {
    // "This bracelet is permanently paired with …" — re-pointing would silently
    // transfer their balance.
    await seedCheckedIn();
    await assertFails(
      updateDoc(doc(reception(), 'bracelets', CHIP), { participantId: 'tkt-10002' })
    );
    await assertFails(deleteDoc(doc(reception(), 'bracelets', CHIP)));
  });
});

describe('money moves only with a ledger entry behind it', () => {
  beforeEach(async () => {
    await seedCheckedIn(2350);
  });

  it('lets reception credit', async () => {
    await assertSucceeds(
      moneyBatch(reception(), {
        txId: 'tx-1', type: 'topup', amount: 2000,
        staffUid: RECEPTION_UID, balanceAfter: 4350,
      })
    );
  });

  it('lets the bar debit', async () => {
    await assertSucceeds(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1950,
      })
    );
  });

  it('THE ONE THAT MATTERS: refuses a bare balance write', async () => {
    await assertFails(
      updateDoc(doc(bar(), 'participants', PARTICIPANT), { balance: 999999 })
    );
    await assertFails(
      updateDoc(doc(reception(), 'participants', PARTICIPANT), { balance: 999999 })
    );
  });

  it('refuses a balance that disagrees with its ledger entry', async () => {
    await assertFails(
      moneyBatch(reception(), {
        txId: 'tx-1', type: 'topup', amount: 2000,
        staffUid: RECEPTION_UID,
        balanceAfter: 999999, // should be 4350
      })
    );
  });

  it('refuses the bar crediting an account', async () => {
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'topup', amount: 2000,
        staffUid: BAR_UID, balanceAfter: 4350,
      })
    );
  });

  it('refuses reception debiting an account', async () => {
    await assertFails(
      moneyBatch(reception(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: RECEPTION_UID, balanceAfter: 1950,
      })
    );
  });

  it('refuses an entry attributed to somebody else', async () => {
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: RECEPTION_UID, // not the caller
        balanceAfter: 1950,
      })
    );
  });

  it('refuses to overdraw, and allows spending to exactly zero', async () => {
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 2351,
        staffUid: BAR_UID, balanceAfter: -1,
      })
    );
    await assertSucceeds(
      moneyBatch(bar(), {
        txId: 'tx-2', type: 'charge', amount: 2350,
        staffUid: BAR_UID, balanceAfter: 0,
      })
    );
  });

  it('refuses money on a bracelet nobody has been paired to', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'participants', PARTICIPANT), rosterDoc());
    });
    await assertFails(
      moneyBatch(reception(), {
        txId: 'tx-1', type: 'topup', amount: 2000,
        staffUid: RECEPTION_UID, balanceAfter: 2000,
      })
    );
  });
});

describe('the ledger is append-only and replay-safe', () => {
  beforeEach(async () => {
    await seedCheckedIn(2350);
  });

  it('requires the document id to be the idempotency key', async () => {
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1950,
        entry: ledgerEntry({ txId: 'a-different-id', type: 'charge', amount: 400, staffUid: BAR_UID }),
      })
    );
  });

  it('makes a replayed transaction collide instead of double-charging', async () => {
    // This is how iteration 3's offline queue can retry blindly.
    await assertSucceeds(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1950,
      })
    );
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1550,
      })
    );
  });

  it('refuses to edit or delete history', async () => {
    await assertSucceeds(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1950,
      })
    );
    const ref = doc(bar(), 'participants', PARTICIPANT, 'transactions', 'tx-1');
    await assertFails(updateDoc(ref, { amount: 1 }));
    await assertFails(deleteDoc(ref));
  });

  it('refuses a client-supplied timestamp', async () => {
    // An offline terminal with a wrong clock must not be able to backdate.
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1950,
        entry: {
          ...ledgerEntry({ txId: 'tx-1', type: 'charge', amount: 400, staffUid: BAR_UID }),
          createdAt: new Date('2020-01-01'),
        },
      })
    );
  });

  it('refuses a sign that disagrees with the type', async () => {
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 2750,
        entry: {
          ...ledgerEntry({ txId: 'tx-1', type: 'charge', amount: 400, staffUid: BAR_UID }),
          signedAmount: 400, // a "charge" that credits
        },
      })
    );
  });

  it('refuses a negative or zero amount', async () => {
    // Zero is itemised honestly here — one line priced at 0 — so the only thing
    // left to refuse it is `amount > 0`, which is what this test is about.
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-0', type: 'charge', amount: 0,
        staffUid: BAR_UID, balanceAfter: 2350,
      })
    );
    // A negative amount cannot be itemised at all (line prices are >= 0), so this
    // one is refused twice over. Both refusals are correct.
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-neg', type: 'charge', amount: -400,
        staffUid: BAR_UID, balanceAfter: 1950,
      })
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
//  Itemisation — the receipt and the money are one fact.
//
//  A charge carries the round it paid for, and the line totals must add up to the
//  amount the balance moved by. The rules cannot loop, so the sum is unrolled to
//  a fixed ten lines; these tests are what says the unrolling is total rather
//  than a check of the first line and a shrug at the rest.
// ═══════════════════════════════════════════════════════════════════════════

describe('a charge says what it bought', () => {
  beforeEach(async () => {
    await seedCheckedIn(2350);
  });

  const charge = (items, amount = 1400) =>
    moneyBatch(bar(), {
      txId: 'tx-1', type: 'charge', amount,
      staffUid: BAR_UID, balanceAfter: 2350 - amount,
      items,
    });

  it('accepts a round whose lines add up', async () => {
    await assertSucceeds(
      charge([
        { drinkId: 'beer', name: 'Draught beer', unitPrice: 400, quantity: 3 },
        { drinkId: 'water', name: 'Water', unitPrice: 200, quantity: 1 },
      ])
    );
  });

  it('THE ONE THAT MATTERS: refuses a round whose lines do not add up', async () => {
    // The failure this exists to stop: a receipt saying "1 × Water" against 14 €
    // off the bracelet. Off by one cent is still off.
    await assertFails(charge([{ drinkId: 'water', name: 'Water', unitPrice: 200, quantity: 1 }]));
    await assertFails(charge([{ drinkId: 'beer', name: 'Draught beer', unitPrice: 400, quantity: 3 }]));
    await assertFails(charge([{ drinkId: 'beer', name: 'Draught beer', unitPrice: 1399, quantity: 1 }]));
  });

  it('refuses a charge with no itemisation at all', async () => {
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400, staffUid: BAR_UID, balanceAfter: 1950,
        entry: {
          clientTxId: 'tx-1', type: 'charge', amount: 400, signedAmount: -400,
          staffUid: BAR_UID, terminalId: 'terminal-01', createdAt: serverTimestamp(),
        },
      })
    );
    await assertFails(charge([], 400));
  });

  it('refuses an itemised top-up', async () => {
    // Cash over the counter buys nothing, so there is no round to describe. A
    // top-up that claimed one would be a receipt for something that never
    // happened.
    await assertFails(
      moneyBatch(reception(), {
        txId: 'tx-1', type: 'topup', amount: 2000, staffUid: RECEPTION_UID, balanceAfter: 4350,
        entry: {
          ...ledgerEntry({ txId: 'tx-1', type: 'topup', amount: 2000, staffUid: RECEPTION_UID }),
          items: [oneLine(2000)],
        },
      })
    );
  });

  /** `n` distinct drinks at `unitPrice` each, one of every one. */
  const distinctLines = (n, unitPrice) =>
    Array.from({ length: n }, (_, i) => ({
      drinkId: `d${i}`, name: `Drink ${i}`, unitPrice, quantity: 1,
    }));

  it('counts every line, not just the first few', async () => {
    // Eight lines of 175 is the cap exactly, and the eighth has to be counted for
    // the sum to reach 1400. If the unrolled chain were short by one term this
    // would be rejected — which is the point of testing at the boundary rather
    // than in the middle.
    //
    // This is also the expensive case. A cap of ten failed here with "maximum of
    // 1000 expressions to evaluate has been reached", which is a production
    // failure that no amount of reading the rule would have shown.
    await assertSucceeds(charge(distinctLines(8, 175)));
  });

  it('refuses a ninth line rather than ignoring it', async () => {
    // Past the cap the unrolled sum would stop counting, and a silently
    // uncounted line is exactly the thing the sum exists to prevent. Refused
    // loudly instead.
    await assertFails(charge(distinctLines(9, 100), 900));
  });

  it('refuses a malformed line', async () => {
    for (const line of [
      { drinkId: 'beer', name: 'Draught beer', unitPrice: 1400 },              // no quantity
      { drinkId: 'beer', name: 'Draught beer', quantity: 1 },                  // no price
      { drinkId: 'beer', unitPrice: 1400, quantity: 1 },                       // no name
      { name: 'Draught beer', unitPrice: 1400, quantity: 1 },                  // no drinkId
      // Note 400.5 rather than 14.0: JavaScript has one number type, so a whole
      // number reaches Firestore as an integer however it was written. Only a
      // genuine fraction exercises `is int`.
      { drinkId: 'beer', name: 'Draught beer', unitPrice: 400.5, quantity: 1 },
      { drinkId: 'beer', name: 'Draught beer', unitPrice: 1400, quantity: 0 },
      { drinkId: 'beer', name: 'Draught beer', unitPrice: -1400, quantity: -1 },
      { drinkId: 'beer', name: 'Draught beer', unitPrice: 1400, quantity: 1, note: 'extra' },
    ]) {
      await assertFails(charge([line]));
    }
  });

  it('allows a free line inside a paid round', async () => {
    // Tap water alongside the beer. The round still costs something, which is
    // what `amount > 0` cares about.
    await assertSucceeds(
      charge([
        { drinkId: 'beer', name: 'Draught beer', unitPrice: 1400, quantity: 1 },
        { drinkId: 'tap', name: 'Tap water', unitPrice: 0, quantity: 2 },
      ])
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
//  The admin panel — `web-admin/`, role `admin`.
//
//  Two powers, and the tests below are mostly about everything it does NOT get.
//  An organiser freezes a bracelet and edits the menu. An organiser does not
//  move money: an adjustment that left no ledger entry behind is precisely what
//  the ledger exists to make impossible, and giving the panel a balance write
//  would reopen that hole from the other side.
// ═══════════════════════════════════════════════════════════════════════════

describe('the admin panel', () => {
  const blockFields = (reason) => ({
    isBlocked: true,
    blockReason: reason,
    blockedBy: ADMIN_UID,
    blockedAt: serverTimestamp(),
  });

  beforeEach(async () => {
    await seedCheckedIn(2350);
  });

  it('reads everything it has to display', async () => {
    await assertSucceeds(getDoc(doc(admin(), 'participants', PARTICIPANT)));
    await assertSucceeds(getDoc(doc(admin(), 'bracelets', CHIP)));
    await assertSucceeds(getDoc(doc(admin(), 'drinks', 'beer')));
  });

  it('reads a bracelet history', async () => {
    await assertSucceeds(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400, staffUid: BAR_UID, balanceAfter: 1950,
      })
    );
    await assertSucceeds(
      getDoc(doc(admin(), 'participants', PARTICIPANT, 'transactions', 'tx-1'))
    );
  });

  it('blocks a bracelet, and unblocks it again', async () => {
    await assertSucceeds(
      updateDoc(doc(admin(), 'participants', PARTICIPANT), blockFields('Lost at the door'))
    );
    await assertSucceeds(
      updateDoc(doc(admin(), 'participants', PARTICIPANT), {
        isBlocked: false, blockReason: null, blockedBy: ADMIN_UID, blockedAt: serverTimestamp(),
      })
    );
  });

  it('requires a block to say why', async () => {
    // The reason is shown verbatim on the terminal's blocked screen. An empty one
    // leaves whoever is standing at the desk with nothing to act on.
    await assertFails(updateDoc(doc(admin(), 'participants', PARTICIPANT), blockFields('')));
    await assertFails(
      updateDoc(doc(admin(), 'participants', PARTICIPANT), {
        isBlocked: true, blockedBy: ADMIN_UID, blockedAt: serverTimestamp(),
      })
    );
    await assertFails(updateDoc(doc(admin(), 'participants', PARTICIPANT), blockFields('x'.repeat(301))));
  });

  it('records who blocked it, on the server clock', async () => {
    await assertFails(
      updateDoc(doc(admin(), 'participants', PARTICIPANT), {
        ...blockFields('Lost'), blockedBy: BAR_UID,          // somebody else
      })
    );
    await assertFails(
      updateDoc(doc(admin(), 'participants', PARTICIPANT), {
        ...blockFields('Lost'), blockedAt: new Date('2020-01-01'),
      })
    );
  });

  it('THE ONE THAT MATTERS: cannot move money', async () => {
    await assertFails(
      updateDoc(doc(admin(), 'participants', PARTICIPANT), { balance: 999999 })
    );
    // Not even with a ledger entry to justify it — `admin` is not staff, so the
    // create is refused before the arithmetic is ever reached.
    await assertFails(
      moneyBatch(admin(), {
        txId: 'tx-1', type: 'topup', amount: 2000, staffUid: ADMIN_UID, balanceAfter: 4350,
      })
    );
    await assertFails(
      moneyBatch(admin(), {
        txId: 'tx-2', type: 'charge', amount: 400, staffUid: ADMIN_UID, balanceAfter: 1950,
      })
    );
  });

  it('cannot rewrite the roster, the pairing, or history', async () => {
    await assertFails(updateDoc(doc(admin(), 'participants', PARTICIPANT), { name: 'Someone Else' }));
    await assertFails(updateDoc(doc(admin(), 'participants', PARTICIPANT), { braceletId: OTHER_CHIP }));
    await assertFails(deleteDoc(doc(admin(), 'participants', PARTICIPANT)));
    await assertFails(updateDoc(doc(admin(), 'bracelets', CHIP), { participantId: 'tkt-10002' }));
    await assertFails(deleteDoc(doc(admin(), 'bracelets', CHIP)));
  });

  it('cannot smuggle another field alongside a block', async () => {
    await assertFails(
      updateDoc(doc(admin(), 'participants', PARTICIPANT), {
        ...blockFields('Lost'), balance: 999999,
      })
    );
  });

  it('cannot sell an evening ticket', async () => {
    // Minting participants is reception's hole, not the organiser's.
    const db = admin();
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', 'ev-friday-14'), {
      source: 'evening', ticketType: 'Evening Ticket', evening: 'friday', eveningNumber: 14,
      ticketRef: 'EV-FRIDAY-14', name: 'Evening #14', nameLower: 'evening #14',
      searchTokens: [], country: '', braceletId: '04:E7:3A:2C',
      checkedInAt: serverTimestamp(), balance: 0, lastTxId: null,
      isBlocked: false, blockReason: null, createdBy: ADMIN_UID,
    });
    batch.set(doc(db, 'bracelets', '04:E7:3A:2C'), {
      participantId: 'ev-friday-14', staffUid: ADMIN_UID, pairedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });
});

describe('the drinks menu belongs to the admin panel', () => {
  const drink = (overrides = {}) => ({
    name: 'Espresso Martini', price: 900, sortOrder: 3, isActive: true, ...overrides,
  });

  it('lets an admin add, edit, retire and delete a drink', async () => {
    await assertSucceeds(setDoc(doc(admin(), 'drinks', 'espresso'), drink()));
    await assertSucceeds(
      setDoc(doc(admin(), 'drinks', 'espresso'), drink({ price: 950 }))
    );
    await assertSucceeds(
      setDoc(doc(admin(), 'drinks', 'espresso'), drink({ isActive: false }))
    );
    await assertSucceeds(deleteDoc(doc(admin(), 'drinks', 'espresso')));
  });

  it('refuses a malformed drink', async () => {
    for (const bad of [
      drink({ price: 9.5 }),                    // euros, not cents
      drink({ price: -100 }),
      drink({ price: 100001 }),                 // past the typo ceiling
      drink({ name: '' }),
      drink({ name: 'x'.repeat(61) }),
      drink({ sortOrder: -1 }),
      drink({ isActive: 'yes' }),
      { ...drink(), tagline: 'the good one' },  // an extra field
      { name: 'Espresso Martini', price: 900 }, // missing sortOrder and isActive
    ]) {
      await assertFails(setDoc(doc(admin(), 'drinks', 'espresso'), bad));
    }
  });

  it('refuses every write from a terminal, still', async () => {
    // This is the rule that used to be `allow write: if false`. The authority
    // moved to the admin panel; it did not widen.
    for (const db of [bar(), reception(), roleless(), anonymous()]) {
      await assertFails(setDoc(doc(db, 'drinks', 'espresso'), drink()));
      await assertFails(updateDoc(doc(db, 'drinks', 'beer'), { price: 1 }));
      await assertFails(deleteDoc(doc(db, 'drinks', 'beer')));
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════
//  Evening tickets — the one thing a terminal may create.
//
//  Passes are sold at the door each evening and those buyers have no Sheet row,
//  so reception must be able to create a participant. Every test below exists to
//  keep that hole the size of an anonymous evening ticket and no larger.
// ═══════════════════════════════════════════════════════════════════════════

describe('selling an evening ticket at the door', () => {
  const EV_CHIP = '04:E7:3A:2C';

  /** The batch reception sends: the ticket and its reverse lookup, together. */
  function sell(db, { evening = 'friday', number = 14, chip = EV_CHIP, uid = RECEPTION_UID, overrides = {} } = {}) {
    const pid = `ev-${evening}-${number}`;
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', pid), {
      source: 'evening',
      ticketType: 'Evening Ticket',
      evening,
      eveningNumber: number,
      ticketRef: `EV-${evening.toUpperCase()}-${number}`,
      name: `Evening #${number}`,
      nameLower: `evening #${number}`,
      searchTokens: ['evening', `#${number}`, evening],
      country: '',
      braceletId: chip,
      checkedInAt: serverTimestamp(),
      balance: 0,
      lastTxId: null,
      isBlocked: false,
      blockReason: null,
      createdBy: uid,
      ...overrides,
    });
    batch.set(doc(db, 'bracelets', chip), {
      participantId: pid,
      staffUid: uid,
      pairedAt: serverTimestamp(),
    });
    return batch.commit();
  }

  it('lets reception sell one', async () => {
    await assertSucceeds(sell(reception()));
  });

  it('refuses to let the bar sell one', async () => {
    await assertFails(sell(bar()));
  });

  it('THE ONE THAT MATTERS: refuses to mint any other pass type', async () => {
    for (const ticketType of ['Full Pass Gold', 'Full Pass', 'Party Pass Plus', 'Jazz Performance Track']) {
      await assertFails(sell(reception(), { overrides: { ticketType } }));
    }
  });

  it('refuses a ticket that starts with money on it', async () => {
    // The ticket price is cash to the festival. A terminal that could create a
    // participant holding 500 € would be a mint.
    await assertFails(sell(reception(), { overrides: { balance: 50000 } }));
  });

  it('refuses to attach personal data', async () => {
    await assertFails(sell(reception(), { overrides: { country: 'Bulgaria' } }));
    await assertFails(sell(reception(), { overrides: { name: 'Rossitsa Popova' } }));
    await assertFails(sell(reception(), { overrides: { email: 'someone@example.com' } }));
    await assertFails(sell(reception(), { overrides: { phone: '+359000000' } }));
  });

  it('refuses a document id that disagrees with its contents', async () => {
    // Otherwise the id stops being a reliable sequence and two tickets could
    // claim to be #14.
    const db = reception();
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', 'ev-friday-14'), {
      source: 'evening', ticketType: 'Evening Ticket',
      evening: 'saturday',              // ← disagrees with the id
      eveningNumber: 14,
      ticketRef: 'EV-SATURDAY-14', name: 'Evening #14', nameLower: 'evening #14',
      searchTokens: [], country: '', braceletId: EV_CHIP,
      checkedInAt: serverTimestamp(), balance: 0, lastTxId: null,
      isBlocked: false, blockReason: null, createdBy: RECEPTION_UID,
    });
    batch.set(doc(db, 'bracelets', EV_CHIP), {
      participantId: 'ev-friday-14', staffUid: RECEPTION_UID, pairedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  it('refuses an invented evening', async () => {
    await assertFails(sell(reception(), { evening: 'monday' }));
  });

  it('refuses a source of "sheet"', async () => {
    // A door sale must never masquerade as an imported registration; the importer
    // would then treat it as an orphan, or overwrite it.
    await assertFails(sell(reception(), { overrides: { source: 'sheet' } }));
  });

  it('refuses one that is pre-blocked, or attributed to somebody else', async () => {
    await assertFails(sell(reception(), { overrides: { isBlocked: true } }));
    await assertFails(sell(reception(), { overrides: { createdBy: BAR_UID } }));
  });

  it('refuses one with no reverse-lookup document', async () => {
    const db = reception();
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', 'ev-friday-14'), {
      source: 'evening', ticketType: 'Evening Ticket', evening: 'friday', eveningNumber: 14,
      ticketRef: 'EV-FRIDAY-14', name: 'Evening #14', nameLower: 'evening #14',
      searchTokens: [], country: '', braceletId: EV_CHIP,
      checkedInAt: serverTimestamp(), balance: 0, lastTxId: null,
      isBlocked: false, blockReason: null, createdBy: RECEPTION_UID,
    });
    await assertFails(batch.commit());
  });

  it('makes two desks selling at once collide instead of both claiming #14', async () => {
    await assertSucceeds(sell(reception(), { number: 14 }));
    // Same id, different chip: the second desk loses and must retry with 15.
    await assertFails(sell(reception(), { number: 14, chip: '04:FF:FF:FF' }));
    await assertSucceeds(sell(reception(), { number: 15, chip: '04:FF:FF:FF' }));
  });

  it('still refuses to delete one', async () => {
    await assertSucceeds(sell(reception()));
    await assertFails(deleteDoc(doc(reception(), 'participants', 'ev-friday-14')));
  });

  it('behaves like any other participant once sold', async () => {
    await assertSucceeds(sell(reception()));
    const pid = 'ev-friday-14';
    const db = reception();
    // A top-up works exactly as it does for an imported participant.
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', pid, 'transactions', 'tx-ev-1'), {
      clientTxId: 'tx-ev-1', type: 'topup', amount: 2000, signedAmount: 2000,
      staffUid: RECEPTION_UID, terminalId: 'terminal-01', createdAt: serverTimestamp(),
    });
    batch.update(doc(db, 'participants', pid), { balance: 2000, lastTxId: 'tx-ev-1' });
    await assertSucceeds(batch.commit());
  });
});
