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
