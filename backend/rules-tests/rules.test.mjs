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

const reception = () =>
  testEnv.authenticatedContext(RECEPTION_UID, { role: 'reception' }).firestore();
const bar = () => testEnv.authenticatedContext(BAR_UID, { role: 'bar' }).firestore();
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

/** A well-formed ledger entry. `type` decides the sign. */
function ledgerEntry({ txId, type, amount, staffUid }) {
  return {
    clientTxId: txId,
    type,
    amount,
    signedAmount: type === 'topup' ? amount : -amount,
    staffUid,
    terminalId: 'terminal-01',
    createdAt: serverTimestamp(),
  };
}

/**
 * The shape every money mutation takes: ledger entry and new balance, together.
 * Split into two writes and the rules reject it, which is the point.
 */
function moneyBatch(db, { txId, type, amount, staffUid, balanceAfter, entry }) {
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'participants', PARTICIPANT, 'transactions', txId),
    entry ?? ledgerEntry({ txId, type, amount, staffUid })
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
    for (const amount of [0, -400]) {
      await assertFails(
        moneyBatch(bar(), {
          txId: `tx-${amount}`, type: 'charge', amount,
          staffUid: BAR_UID, balanceAfter: 2350 + amount,
        })
      );
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
