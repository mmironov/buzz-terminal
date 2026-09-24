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
  collection,
  collectionGroup,
  getDocs,
  orderBy,
  query,
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
 * A well-formed ledger entry. `type` decides the sign and what else it must
 * carry: a charge says what was bought, a top-up says how it was paid, and
 * neither may carry the other's field.
 *
 * Both defaults are filled in — one line priced at the whole amount, and cash —
 * so every pre-existing money test keeps testing what it was written to test
 * rather than tripping over a rule added later.
 */
function ledgerEntry({ txId, type, amount, staffUid, items, method }) {
  const entry = {
    clientTxId: txId,
    type,
    amount,
    signedAmount: type === 'topup' ? amount : -amount,
    staffUid,
    terminalId: 'terminal-01',
    createdAt: serverTimestamp(),
  };
  // A top-up must say how it was paid and a charge must not, so the default
  // carries one for a top-up only — same reasoning as `items` above: the money
  // tests written before this rule existed keep testing what they were written
  // to test rather than tripping over it.
  if (type === 'topup') return { ...entry, method: method ?? 'cash' };
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
    // The door catalogue. `isWellFormedDoorPass` reads it, so a sale cannot be
    // tested without it — which is the rule working: reception sells what the
    // organisers priced, and an empty catalogue sells nothing.
    await setDoc(doc(db, 'doorPasses', 'full-pass'), {
      name: 'Full Pass', price: 20500, sortOrder: 2, isActive: true, kind: 'pass',
    });
    await setDoc(doc(db, 'doorPasses', 'party-pass'), {
      name: 'Party Pass', price: 12000, sortOrder: 0, isActive: true, kind: 'pass',
    });
    // The extra classes, in a collection of their own: a class is not a pass,
    // admits nobody, and is never sold at the door.
    await setDoc(doc(db, 'specialSessions', 'jazz-patrik'), {
      name: 'Jazz with Patrik', price: 2500, sortOrder: 1, isActive: true,
    });
    await setDoc(doc(db, 'specialSessions', 'lindy-hop'), {
      name: 'Lindy Hop with Sakarias & Elice', price: 2500, sortOrder: 0, isActive: true,
    });
  });
});

/** Give the participant a bracelet and a balance, bypassing the rules. */
/** Fixed, so a test can copy it into the record the way the panel does. */
const PAIRED_AT = new Date('2026-09-25T19:00:00Z');

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
      pairedAt: PAIRED_AT,
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

  it('lets an admin pair a chip, since admin counts as reception', async () => {
    await assertSucceeds(pair(admin(), { uid: ADMIN_UID }));
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

// ───────────────────────────────────────────────────────────────────────────
//  Replacing a lost or broken wristband
//
//  The one way a participant's `braceletId` may move from one chip to another.
//  Both halves happen in one write: the old chip is invalidated so it stops
//  resolving for good, and a fresh one is minted. A chip still never changes
//  owner, and the balance — which lives on the person — is not touched at all.
// ───────────────────────────────────────────────────────────────────────────

describe('replacing a bracelet', () => {
  const NEW_CHIP = '04:F1:2E:88';

  /** The batch reception sends: invalidate the old chip, mint the new one. */
  function replace(
    db,
    {
      chip = NEW_CHIP,
      uid = RECEPTION_UID,
      reason = 'Lost in the venue',
      fee = null,
      method = null,
      invalidateOld = true,
      mintNew = true,
      movePerson = true,
    } = {}
  ) {
    const batch = writeBatch(db);
    if (movePerson) {
      batch.update(doc(db, 'participants', PARTICIPANT), { braceletId: chip });
    }
    if (invalidateOld) {
      batch.update(doc(db, 'bracelets', CHIP), {
        invalidatedAt: serverTimestamp(),
        invalidatedBy: uid,
        reason,
      });
    }
    if (mintNew) {
      batch.set(doc(db, 'bracelets', chip), {
        participantId: PARTICIPANT,
        staffUid: uid,
        pairedAt: serverTimestamp(),
        ...(fee === null ? {} : { replacementFee: fee, replacementMethod: method }),
      });
    }
    return batch.commit();
  }

  beforeEach(async () => {
    await seedCheckedIn(2350);
  });

  it('THE ONE THAT MATTERS: reception can replace a lost wristband', async () => {
    await assertSucceeds(replace(reception()));
  });

  it('refuses to let the bar replace one', async () => {
    await assertFails(replace(bar(), { uid: BAR_UID }));
  });

  it('refuses a replacement that leaves the old chip still working', async () => {
    // The dangerous half. A wristband that stopped being somebody's while still
    // resolving is one a finder could walk to the bar with.
    await assertFails(replace(reception(), { invalidateOld: false }));
  });

  it('refuses invalidating a chip without issuing a new one', async () => {
    // The other half alone would leave the guest with no wristband and a
    // balance they cannot reach.
    await assertFails(replace(reception(), { mintNew: false, movePerson: false }));
  });

  it('refuses a replacement with no reason written down', async () => {
    await assertFails(replace(reception(), { reason: '' }));
    await assertFails(replace(reception(), { reason: 'x'.repeat(201) }));
  });

  it('refuses moving to a chip that already belongs to somebody', async () => {
    // The property the money model rests on: a chip never changes owner. The
    // `create` on an existing document is what refuses it.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'bracelets', NEW_CHIP), {
        participantId: 'tkt-10002',
        staffUid: RECEPTION_UID,
        pairedAt: new Date(),
      });
    });
    await assertFails(replace(reception()));
  });

  it('refuses invalidating the same chip twice', async () => {
    await assertSucceeds(replace(reception()));
    await assertFails(
      updateDoc(doc(reception(), 'bracelets', CHIP), {
        invalidatedAt: serverTimestamp(),
        invalidatedBy: RECEPTION_UID,
        reason: 'Changed my mind about why',
      })
    );
  });

  it('refuses reviving an invalidated chip', async () => {
    // Once dead, dead. Reception cannot clear the invalidation, and nobody can
    // delete the document and start again.
    await assertSucceeds(replace(reception()));
    await assertFails(
      updateDoc(doc(reception(), 'bracelets', CHIP), { invalidatedAt: null })
    );
    await assertFails(deleteDoc(doc(reception(), 'bracelets', CHIP)));
    await assertFails(deleteDoc(doc(admin(), 'bracelets', CHIP)));
  });

  it('leaves the balance exactly where it was', async () => {
    // The fee is taken at the desk in cash or on the card machine. It is not on
    // the wristband, so it writes no ledger entry and moves no balance — the
    // ledger stays what is *on a bracelet*.
    await assertFails(
      (() => {
        const db = reception();
        const batch = writeBatch(db);
        batch.update(doc(db, 'participants', PARTICIPANT), {
          braceletId: NEW_CHIP,
          balance: 2250,
        });
        batch.update(doc(db, 'bracelets', CHIP), {
          invalidatedAt: serverTimestamp(), invalidatedBy: RECEPTION_UID, reason: 'Lost',
        });
        batch.set(doc(db, 'bracelets', NEW_CHIP), {
          participantId: PARTICIPANT, staffUid: RECEPTION_UID, pairedAt: serverTimestamp(),
        });
        return batch.commit();
      })()
    );
  });

  // ── What the desk took for it ────────────────────────────────────────────

  it('records the fee on the wristband it issued', async () => {
    await assertSucceeds(replace(reception(), { fee: 100, method: 'cash' }));
  });

  it('accepts a replacement with no fee, which is how one is waived', async () => {
    // A snapped clasp is the festival's fault. A waived fee is the absence of
    // the fields rather than a zero, so the totals cannot be read as "somebody
    // paid nothing".
    await assertSucceeds(replace(reception(), { fee: null }));
  });

  it('refuses a fee that does not say how it was paid', async () => {
    await assertFails(replace(reception(), { fee: 100, method: null }));
    await assertFails(replace(reception(), { fee: 100, method: 'invoice' }));
    await assertFails(replace(reception(), { fee: 0, method: 'cash' }));
    await assertFails(replace(reception(), { fee: 200001, method: 'cash' }));
    await assertFails(replace(reception(), { fee: '1.00', method: 'cash' }));
  });

  it('refuses a fee on somebody\u2019s first wristband', async () => {
    // A first wristband is part of a ticket they already paid for. Only a
    // replacement can carry a fee.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'participants', PARTICIPANT), rosterDoc());
    });
    const db = reception();
    const batch = writeBatch(db);
    batch.update(doc(db, 'participants', PARTICIPANT), {
      braceletId: CHIP,
      checkedInAt: serverTimestamp(),
    });
    batch.set(doc(db, 'bracelets', CHIP), {
      participantId: PARTICIPANT,
      staffUid: RECEPTION_UID,
      pairedAt: serverTimestamp(),
      replacementFee: 100,
      replacementMethod: 'cash',
    });
    await assertFails(batch.commit());
  });
});

// ───────────────────────────────────────────────────────────────────────────
//  Handing a wristband back
//
//  An evening-ticket guest returns their wristband at the end of the night and
//  the festival reuses the chip tomorrow. The pairing ends — the participant
//  lets go and the chip document is deleted, freeing the id — so a chip still
//  never changes owner. It stops having one, and a later check-in gives it a
//  new one by ordinary `create`.
// ───────────────────────────────────────────────────────────────────────────

describe('handing a wristband back', () => {
  /** The batch the panel sends: detach, free the chip, keep the record. */
  function handBack(
    db,
    {
      chip = CHIP,
      uid = ADMIN_UID,
      participant = PARTICIPANT,
      detach = true,
      freeChip = true,
      archive = true,
      archiveOverrides = {},
    } = {}
  ) {
    const batch = writeBatch(db);
    if (detach) {
      batch.update(doc(db, 'participants', participant), { braceletId: null });
    }
    if (freeChip) {
      batch.delete(doc(db, 'bracelets', chip));
    }
    if (archive) {
      batch.set(doc(db, 'braceletHistory', `${chip}-1`), {
        chipUid: chip,
        participantId: participant,
        pairedAt: PAIRED_AT,
        returnedAt: serverTimestamp(),
        returnedBy: uid,
        ...archiveOverrides,
      });
    }
    return batch.commit();
  }

  beforeEach(async () => {
    await seedCheckedIn(750);
  });

  it('THE ONE THAT MATTERS: an organiser can free a returned wristband', async () => {
    await assertSucceeds(handBack(admin()));
  });

  it('refuses reception and the bar — it is an organiser decision', async () => {
    await assertFails(handBack(reception(), { uid: RECEPTION_UID }));
    await assertFails(handBack(bar(), { uid: BAR_UID }));
  });

  it('refuses freeing a chip while somebody still points at it', async () => {
    // The dangerous half: a chip that resolves to somebody with no wristband is
    // one the bar would happily charge.
    await assertFails(handBack(admin(), { detach: false }));
  });

  it('refuses detaching somebody while their chip still resolves', async () => {
    await assertFails(handBack(admin(), { freeChip: false }));
  });

  it('leaves the money exactly where it was', async () => {
    // The balance lives on the person, not the wristband. Handing one back does
    // not spend, refund or forget anything — and `hasOnly` is what says so.
    const db = admin();
    const batch = writeBatch(db);
    batch.update(doc(db, 'participants', PARTICIPANT), { braceletId: null, balance: 0 });
    batch.delete(doc(db, 'bracelets', CHIP));
    await assertFails(batch.commit());
  });

  it('refuses rewriting the roster on the way past', async () => {
    const db = admin();
    const batch = writeBatch(db);
    batch.update(doc(db, 'participants', PARTICIPANT), { braceletId: null, name: 'Somebody else' });
    batch.delete(doc(db, 'bracelets', CHIP));
    await assertFails(batch.commit());
  });

  it('THE OTHER ONE: a replaced wristband cannot be freed and re-issued', async () => {
    // A lost chip is dead, not returned — the festival does not have it. Without
    // this an organiser could unassign somebody's current wristband and then
    // delete the invalidated one, putting a lost chip back in the box.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(doc(db, 'bracelets', OTHER_CHIP), {
        participantId: PARTICIPANT,
        staffUid: RECEPTION_UID,
        pairedAt: PAIRED_AT,
        invalidatedAt: new Date(),
        invalidatedBy: RECEPTION_UID,
        reason: 'Lost it',
      });
    });
    // Detach them first, so the only thing standing in the way is the rule.
    await assertSucceeds(handBack(admin()));
    await assertFails(deleteDoc(doc(admin(), 'bracelets', OTHER_CHIP)));
  });

  it('frees the chip for somebody else tomorrow', async () => {
    // The point of all of it: the id is available again, and the next pairing is
    // an ordinary create by reception with no special case anywhere.
    await assertSucceeds(handBack(admin()));
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'participants', 'tkt-10002'), rosterDoc({ name: 'Somebody Else' }));
    });
    const db = reception();
    const batch = writeBatch(db);
    batch.update(doc(db, 'participants', 'tkt-10002'), {
      braceletId: CHIP,
      checkedInAt: serverTimestamp(),
    });
    batch.set(doc(db, 'bracelets', CHIP), {
      participantId: 'tkt-10002',
      staffUid: RECEPTION_UID,
      pairedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  // ── the record it leaves ─────────────────────────────────────────────────

  it('refuses a record that does not match the pairing it ends', async () => {
    await assertFails(handBack(admin(), { archiveOverrides: { participantId: 'tkt-10002' } }));
    await assertFails(handBack(admin(), { archiveOverrides: { chipUid: OTHER_CHIP } }));
    await assertFails(handBack(admin(), { archiveOverrides: { pairedAt: new Date(0) } }));
  });

  it('pins who took it back and when to the server', async () => {
    await assertFails(handBack(admin(), { archiveOverrides: { returnedBy: RECEPTION_UID } }));
    await assertFails(handBack(admin(), { archiveOverrides: { returnedAt: new Date() } }));
  });

  it('refuses extra fields, and cannot be edited afterwards', async () => {
    await assertFails(handBack(admin(), { archiveOverrides: { note: 'handed in at the bar' } }));

    await assertSucceeds(handBack(admin()));
    const record = doc(admin(), 'braceletHistory', `${CHIP}-1`);
    await assertFails(updateDoc(record, { returnedBy: RECEPTION_UID }));
    await assertFails(deleteDoc(record));
  });

  it('is the organiser\u2019s to read, and nobody else\u2019s business', async () => {
    await assertSucceeds(handBack(admin()));
    await assertSucceeds(getDoc(doc(admin(), 'braceletHistory', `${CHIP}-1`)));
    await assertFails(getDoc(doc(reception(), 'braceletHistory', `${CHIP}-1`)));
    await assertFails(getDoc(doc(bar(), 'braceletHistory', `${CHIP}-1`)));
  });
});

describe('what a replacement costs', () => {
  const ref = (db) => doc(db, 'settings', 'bracelets');

  it('is set by an organiser and read by the terminals', async () => {
    await assertSucceeds(setDoc(ref(admin()), { replacementFee: 100 }));
    await assertSucceeds(getDoc(ref(reception())));
    await assertSucceeds(getDoc(ref(bar())));
    await assertFails(setDoc(ref(reception()), { replacementFee: 100 }));
  });

  it('refuses nonsense, and anything but the one document', async () => {
    await assertFails(setDoc(ref(admin()), { replacementFee: -1 }));
    await assertFails(setDoc(ref(admin()), { replacementFee: '1.00' }));
    await assertFails(setDoc(ref(admin()), { replacementFee: 200001 }));
    await assertFails(setDoc(ref(admin()), { replacementFee: 100, currency: 'EUR' }));
    await assertFails(setDoc(doc(admin(), 'settings', 'anything-else'), { replacementFee: 100 }));
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

describe('how a top-up was paid', () => {
  beforeEach(async () => {
    await seedCheckedIn(2350);
  });

  /** A top-up carrying `method`, which the iOS terminal always sets. */
  function topUpPaid(method, { txId = 'tx-1', balanceAfter = 4350 } = {}) {
    return moneyBatch(reception(), {
      txId, type: 'topup', amount: 2000,
      staffUid: RECEPTION_UID, balanceAfter,
      entry: {
        ...ledgerEntry({ txId, type: 'topup', amount: 2000, staffUid: RECEPTION_UID }),
        method,
      },
    });
  }

  it('accepts cash and card', async () => {
    await assertSucceeds(topUpPaid('cash'));
    await assertSucceeds(topUpPaid('card', { txId: 'tx-2', balanceAfter: 6350 }));
  });

  it('refuses anything else, so the reports have two buckets and not five', async () => {
    await assertFails(topUpPaid('Cash'));
    await assertFails(topUpPaid('revolut'));
    await assertFails(topUpPaid(''));
    await assertFails(topUpPaid(2));
  });

  it('refuses a payment method on a charge', async () => {
    // The bar moves money that is already on the bracelet. How it got there is
    // a fact about the top-up, and recording it twice is how two records come
    // to disagree.
    await assertFails(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1950,
        entry: {
          ...ledgerEntry({ txId: 'tx-1', type: 'charge', amount: 400, staffUid: BAR_UID }),
          method: 'cash',
        },
      })
    );
  });

  it('THE DELIBERATE BREAK: refuses a top-up that does not say', async () => {
    // A terminal built before the picker existed — TestFlight 77 and earlier,
    // and Android — is refused here rather than writing an entry the cash count
    // can never be reconciled against. Every terminal that takes money has to
    // ship with the picker; that is the trade this rule makes on purpose.
    // Built by hand rather than through `ledgerEntry`, which now fills a method
    // in: this is the one test that needs an entry without one.
    const { method, ...noMethod } = ledgerEntry({
      txId: 'tx-1', type: 'topup', amount: 2000, staffUid: RECEPTION_UID,
    });
    await assertFails(
      moneyBatch(reception(), {
        txId: 'tx-1', type: 'topup', amount: 2000,
        staffUid: RECEPTION_UID, balanceAfter: 4350,
        entry: noMethod,
      })
    );
  });

  it('still lets the bar charge without one', async () => {
    // The mandatory half is the top-up's. Making a charge carry a method too
    // would have stopped the bar as well, which nothing about counting the cash
    // box calls for.
    await assertSucceeds(
      moneyBatch(bar(), {
        txId: 'tx-1', type: 'charge', amount: 400,
        staffUid: BAR_UID, balanceAfter: 1950,
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

  it('THE ONE THAT MATTERS: can credit, and still cannot charge', async () => {
    // An admin counts as reception, so a top-up with a matching ledger entry is
    // allowed — and is stamped with their own uid like anyone else's.
    await assertSucceeds(
      moneyBatch(admin(), {
        txId: 'tx-1', type: 'topup', amount: 2000, staffUid: ADMIN_UID, balanceAfter: 4350,
      })
    );
    // Debiting is the bar's, and only the bar's. This is the assertion that keeps
    // "who spent this?" answerable.
    await assertFails(
      moneyBatch(admin(), {
        txId: 'tx-2', type: 'charge', amount: 400, staffUid: ADMIN_UID, balanceAfter: 1950,
      })
    );
  });

  it('cannot move a balance with no ledger entry to justify it', async () => {
    // The invariant that does not care which role you are. Reception cannot do
    // this either; an admin having reception's powers does not include an
    // adjustment that leaves no trace.
    await assertFails(
      updateDoc(doc(admin(), 'participants', PARTICIPANT), { balance: 999999 })
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

  it('can sell an evening ticket, since it counts as reception', async () => {
    const db = admin();
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', 'ev-friday-14'), {
      source: 'evening', ticketType: 'Evening Ticket', evening: 'friday', eveningNumber: 14,
      ticketRef: 'EV-FRIDAY-14', name: 'Petar Dimitrov', nameLower: 'petar dimitrov',
      searchTokens: [], country: '', paymentMethod: 'cash', pricePaid: 4500,
      braceletId: '04:E7:3A:2C',
      checkedInAt: serverTimestamp(), balance: 0, lastTxId: null,
      isBlocked: false, blockReason: null, createdBy: ADMIN_UID,
    });
    batch.set(doc(db, 'bracelets', '04:E7:3A:2C'), {
      participantId: 'ev-friday-14', staffUid: ADMIN_UID, pairedAt: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
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

  it('lets a drink say what it takes out of the store', async () => {
    // Millilitres per serving, keyed by stock id. Optional: a drink nobody has
    // costed yet simply has none.
    await assertSucceeds(
      setDoc(doc(admin(), 'drinks', 'espresso'), drink({ recipe: { gin: 50, tonic: 200 } }))
    );
    await assertSucceeds(setDoc(doc(admin(), 'drinks', 'espresso'), drink()));
  });

  it('bounds the recipe, which is all a rule can do to it', async () => {
    // Rules have no loop and the keys are stock ids nobody knows in advance, so
    // "every value is a positive int" cannot be asserted here the way the charge
    // itemisation is unrolled to eight fixed terms. The size cap is the part
    // that is enforceable; the panel writes the integers.
    const tooMany = Object.fromEntries(
      Array.from({ length: 13 }, (_, i) => [`stock-${i}`, 10])
    );
    await assertFails(setDoc(doc(admin(), 'drinks', 'espresso'), drink({ recipe: tooMany })));
    await assertFails(setDoc(doc(admin(), 'drinks', 'espresso'), drink({ recipe: 'gin' })));
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
    // Named since the festival decided it wants to know who holds one. The
    // number it is reconciled by is still the id and the ticket reference.
    const pid = `ev-${evening}-${number}`;
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', pid), {
      source: 'evening',
      ticketType: 'Evening Ticket',
      evening,
      eveningNumber: number,
      ticketRef: `EV-${evening.toUpperCase()}-${number}`,
      name: 'Petar Dimitrov',
      nameLower: 'petar dimitrov',
      searchTokens: ['petar', 'dimitrov', 'evening', evening],
      country: '',
      paymentMethod: 'cash',
      pricePaid: 4500,
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

  it('THE CHANGE: an evening ticket also says how it was paid', async () => {
    // One night at a door still takes money, and it goes in the same box as a
    // 259 EUR Full Pass. The night decides the price, so the number here is
    // whatever the terminal quoted for that evening.
    await assertFails(sell(reception(), { overrides: { paymentMethod: null } }));
    await assertFails(sell(reception(), { overrides: { pricePaid: null } }));
    await assertFails(sell(reception(), { overrides: { paymentMethod: 'voucher' } }));
    await assertSucceeds(sell(reception(), { overrides: { paymentMethod: 'card', pricePaid: 5000 } }));
  });

  it('refuses an evening ticket wearing another pass type', async () => {
    // Reception CAN sell a Full Pass at the door — see the door-pass suite — but
    // not by relabelling an anonymous numbered evening ticket as one. The two
    // shapes stay separate: this one has no buyer and no price, and `ev-friday-14`
    // must mean what it has always meant.
    for (const ticketType of ['Full Pass Gold', 'Full Pass', 'Party Pass Plus', 'Jazz Performance Track']) {
      await assertFails(sell(reception(), { overrides: { ticketType } }));
    }
  });

  it('refuses a ticket that starts with money on it', async () => {
    // The ticket price is cash to the festival. A terminal that could create a
    // participant holding 500 € would be a mint.
    await assertFails(sell(reception(), { overrides: { balance: 50000 } }));
  });

  it('takes a name, and nothing else about the person', async () => {
    // These used to be anonymous: `name` was pinned to "Evening #14" and this
    // test asserted that a real one was refused. The festival changed its mind
    // about the name; it did not change its mind about anything else, and the
    // `hasOnly` list is what holds that line.
    await assertSucceeds(sell(reception(), { overrides: { name: 'Рosица Попова' } }));
    await assertFails(sell(reception(), { overrides: { country: 'Bulgaria' } }));
    await assertFails(sell(reception(), { overrides: { email: 'someone@example.com' } }));
    await assertFails(sell(reception(), { overrides: { phone: '+359000000' } }));
    await assertFails(sell(reception(), { overrides: { danceRole: 'leader' } }));
    await assertFails(sell(reception(), { overrides: { level: 'Advanced' } }));
  });

  it('refuses a nameless one, and an absurdly long name', async () => {
    await assertFails(sell(reception(), { overrides: { name: '' } }));
    await assertFails(sell(reception(), { overrides: { name: 'x'.repeat(81) } }));
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
      ticketRef: 'EV-SATURDAY-14', name: 'Petar Dimitrov', nameLower: 'petar dimitrov',
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
      ticketRef: 'EV-FRIDAY-14', name: 'Petar Dimitrov', nameLower: 'petar dimitrov',
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
      method: 'cash',
    });
    batch.update(doc(db, 'participants', pid), { balance: 2000, lastTxId: 'tx-ev-1' });
    await assertSucceeds(batch.commit());
  });
});

// ───────────────────────────────────────────────────────────────────────────
//  Selling a full pass at the door
//
//  The widest thing reception can do: create a participant who was never in the
//  Sheet, with a name on them and a 205 € pass type. What keeps it narrow is the
//  catalogue — an organiser has to have priced the pass before anybody can be
//  sold one — and the money rules, which are untouched by any of this.
// ───────────────────────────────────────────────────────────────────────────

describe('selling a pass at the door', () => {
  const DOOR_CHIP = '04:D2:0B:6A';

  /** The batch reception sends: the participant and the reverse lookup. */
  function sellPass(
    db,
    { number = 7, passId = 'full-pass', chip = DOOR_CHIP, uid = RECEPTION_UID, overrides = {} } = {}
  ) {
    const pid = `door-${number}`;
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', pid), {
      source: 'door',
      passId,
      ticketType: 'Full Pass',
      doorNumber: number,
      ticketRef: `DOOR-${number}`,
      name: 'Jana Novak',
      nameLower: 'jana novak',
      searchTokens: ['jana', 'novak', 'full', 'pass'],
      country: '',
      level: 'Advanced',
      danceRole: 'follower',
      paymentMethod: 'card',
      pricePaid: 20500,
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

  it('lets reception sell one, with a buyer on it', async () => {
    await assertSucceeds(sellPass(reception()));
  });

  it('lets an organiser sell one too, because admin counts as reception', async () => {
    await assertSucceeds(sellPass(admin(), { uid: ADMIN_UID }));
  });

  it('refuses to let the bar sell one', async () => {
    await assertFails(sellPass(bar(), { uid: BAR_UID }));
  });

  it('THE ONE THAT MATTERS: refuses a pass the organisers never priced', async () => {
    // The replacement for "reception cannot invent a pass type". It can sell
    // what is in the catalogue, at the desk, and nothing else — so a terminal
    // cannot mint a pass type that exists nowhere in the festival.
    await assertFails(
      sellPass(reception(), {
        passId: 'full-pass-platinum',
        overrides: { passId: 'full-pass-platinum', ticketType: 'Full Pass Platinum' },
      })
    );
  });

  it('THE CHANGE: a special session cannot be sold as a pass', async () => {
    // The classes are not in this catalogue at all, so a door sale pointing at
    // one fails on "that pass does not exist" — which is the protection that
    // used to need a rule of its own when the two shared a collection.
    await assertFails(
      sellPass(reception(), {
        passId: 'jazz-patrik',
        overrides: {
          passId: 'jazz-patrik',
          ticketType: 'Jazz with Patrik',
          pricePaid: 2500,
        },
      })
    );
  });

  it('refuses a pass type that disagrees with the catalogue entry', async () => {
    // `passId` says party-pass, the document claims Full Pass. Otherwise the
    // 120 € entry could be sold as a 205 € pass, or the other way round.
    await assertFails(sellPass(reception(), { overrides: { passId: 'party-pass' } }));
  });

  it('refuses a sale that starts with money on the bracelet', async () => {
    await assertFails(sellPass(reception(), { overrides: { balance: 20500 } }));
  });

  // ── What the desk took for it ────────────────────────────────────────────
  //
  // The cash box is counted against these afterwards, so they are mandatory in
  // the same way `method` is on a top-up: a takings record that some sales carry
  // and some do not cannot be counted against anything.

  it('THE CHANGE: refuses a sale that does not say how it was paid', async () => {
    await assertFails(sellPass(reception(), { overrides: { paymentMethod: null } }));
    await assertFails(
      sellPass(reception(), {
        overrides: { paymentMethod: 'invoice' },
      })
    );
    await assertFails(sellPass(reception(), { overrides: { paymentMethod: 'Cash' } }));
    await assertSucceeds(sellPass(reception(), { overrides: { paymentMethod: 'cash' } }));
  });

  it('refuses a sale that does not say what was collected', async () => {
    await assertFails(sellPass(reception(), { overrides: { pricePaid: null } }));
    await assertFails(sellPass(reception(), { overrides: { pricePaid: '205.00' } }));
    await assertFails(sellPass(reception(), { overrides: { pricePaid: 205 * 100 + 0.5 } }));
    await assertFails(sellPass(reception(), { overrides: { pricePaid: -1 } }));
    // The same typo ceiling the catalogue itself has: 2,000 EUR is a slipped
    // decimal, not a festival pass.
    await assertFails(sellPass(reception(), { overrides: { pricePaid: 200001 } }));
  });

  it('takes the price the terminal reports, not the catalogue\u2019s', async () => {
    // Deliberate. A phone holding a catalogue five minutes out of date would
    // otherwise have its sale refused in front of a queue, and the number wanted
    // here is what was actually collected \u2014 the same snapshot rule the ledger
    // follows for a round of drinks. Zero is allowed for the same reason: an
    // organiser can price something at nothing.
    // Different numbers and chips: the id is the sale, so two sales in one test
    // are two sales.
    await assertSucceeds(sellPass(reception(), { overrides: { pricePaid: 19000 } }));
    await assertSucceeds(
      sellPass(reception(), {
        number: 8,
        chip: '04:D2:0B:6B',
        overrides: { doorNumber: 8, ticketRef: 'DOOR-8', pricePaid: 0 },
      })
    );
  });

  it('THE EMAIL IS NOT ON THE PARTICIPANT', async () => {
    // Every terminal reads a participant document, the bar included. The address
    // belongs in contact/, and a terminal that tried to put it here is refused
    // rather than quietly handing the bar a mailing list.
    await assertFails(sellPass(reception(), { overrides: { email: 'jana@example.com' } }));
    await assertFails(sellPass(reception(), { overrides: { phone: '+359000000' } }));
  });

  it('refuses a document id that disagrees with its contents', async () => {
    await assertFails(sellPass(reception(), { overrides: { doorNumber: 9 } }));
    await assertFails(sellPass(reception(), { overrides: { ticketRef: 'DOOR-9' } }));
  });

  it('accepts a name the Latin alphabet alone cannot spell', async () => {
    // Half this festival is Polish, Czech or Bulgarian. `nameLower` is produced
    // by Swift's `lowercased()` and checked against the rules' `.lower()`, and
    // if those two disagree about "Ł" the sale is refused at the desk with a
    // queue behind it. Asserted rather than assumed.
    // The rules' own `.lower()` is ASCII-only, so they cannot check `nameLower`
    // against `name` — proved against the emulator, and written up in the rule
    // itself. This test is what stops somebody reinstating that check.
    const names = ['Łukasz Ćwik', 'Karol Chrząszcz', 'Анита Солари', 'Åsa Ödegård'];
    for (const [index, name] of names.entries()) {
      await assertSucceeds(
        sellPass(reception(), {
          number: 21 + index,
          chip: `04:AB:CD:2${index}`,
          overrides: { name, nameLower: name.toLowerCase(), searchTokens: ['x'] },
        })
      );
    }
  });

  it('refuses a nameless sale, and a country', async () => {
    await assertFails(sellPass(reception(), { overrides: { name: '', nameLower: '' } }));
    await assertFails(sellPass(reception(), { overrides: { country: 'Bulgaria' } }));
  });

  it('refuses a dance role that is not leader or follower', async () => {
    await assertFails(sellPass(reception(), { overrides: { danceRole: 'both' } }));
    await assertFails(sellPass(reception(), { overrides: { danceRole: '' } }));
  });

  it('refuses a level outside the four, and allows none at all', async () => {
    await assertFails(sellPass(reception(), { overrides: { level: 'Beginner' } }));
    await assertSucceeds(sellPass(reception(), { overrides: { level: '' } }));
  });

  it('refuses to start one blocked, or to arrive pre-blocked', async () => {
    await assertFails(sellPass(reception(), { overrides: { isBlocked: true } }));
  });

  it('makes two desks selling at once collide instead of both claiming #7', async () => {
    await assertSucceeds(sellPass(reception(), { number: 7 }));
    await assertFails(sellPass(reception(), { number: 7, chip: '04:FF:FF:F1' }));
    await assertSucceeds(sellPass(reception(), { number: 8, chip: '04:FF:FF:F1' }));
  });

  it('cannot be deleted afterwards, like anybody else', async () => {
    await assertSucceeds(sellPass(reception()));
    await assertFails(deleteDoc(doc(reception(), 'participants', 'door-7')));
  });

  it('behaves like any other participant once sold', async () => {
    await assertSucceeds(sellPass(reception()));
    const db = reception();
    const batch = writeBatch(db);
    batch.set(doc(db, 'participants', 'door-7', 'transactions', 'tx-d-1'), {
      clientTxId: 'tx-d-1', type: 'topup', amount: 2000, signedAmount: 2000,
      staffUid: RECEPTION_UID, terminalId: 'terminal-01', createdAt: serverTimestamp(),
      method: 'card',
    });
    batch.update(doc(db, 'participants', 'door-7'), { balance: 2000, lastTxId: 'tx-d-1' });
    await assertSucceeds(batch.commit());
  });
});

describe('the buyer’s email', () => {
  const contactRef = (db, pid = PARTICIPANT) => doc(db, 'participants', pid, 'contact', 'details');
  const details = (overrides = {}) => ({
    email: 'jana@example.com',
    addedBy: RECEPTION_UID,
    addedAt: serverTimestamp(),
    ...overrides,
  });

  it('THE ONE THAT MATTERS: the bar cannot read it', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(contactRef(context.firestore()), { email: 'jana@example.com' });
    });
    await assertFails(getDoc(contactRef(bar())));
    await assertSucceeds(getDoc(contactRef(reception())));
    // The organiser panel can, which is where anybody actually reads it.
    await assertSucceeds(getDoc(contactRef(admin())));
  });

  it('lets reception write one, and fix a typo afterwards', async () => {
    await assertSucceeds(setDoc(contactRef(reception()), details()));
    await assertSucceeds(setDoc(contactRef(reception()), details({ email: 'jana@fixed.com' })));
  });

  it('refuses the bar writing one', async () => {
    await assertFails(setDoc(contactRef(bar()), details({ addedBy: BAR_UID })));
  });

  it('refuses anything that is not an address, and allows an empty one', async () => {
    await assertFails(setDoc(contactRef(reception()), details({ email: 'not an address' })));
    await assertFails(setDoc(contactRef(reception()), details({ email: 'two@at@signs' })));
    // Empty is allowed: a buyer who does not want to give one still gets a pass.
    await assertSucceeds(setDoc(contactRef(reception()), details({ email: '' })));
  });

  it('refuses extra fields — this is an address, not a profile', async () => {
    await assertFails(setDoc(contactRef(reception()), details({ phone: '+359000000' })));
    await assertFails(setDoc(contactRef(reception()), details({ notes: 'came with Ivan' })));
  });

  it('refuses an entry attributed to somebody else, or backdated', async () => {
    await assertFails(setDoc(contactRef(reception()), details({ addedBy: ADMIN_UID })));
    await assertFails(setDoc(contactRef(reception()), details({ addedAt: new Date(0) })));
  });

  it('cannot be deleted', async () => {
    await assertSucceeds(setDoc(contactRef(reception()), details()));
    await assertFails(deleteDoc(contactRef(reception())));
  });
});

describe('the door catalogue belongs to the admin panel', () => {
  const passRef = (db, id = 'jazz-track') => doc(db, 'doorPasses', id);
  const pass = (overrides = {}) => ({
    name: 'Jazz Performance Track',
    price: 18500,
    sortOrder: 4,
    isActive: true,
    kind: 'pass',
    ...overrides,
  });

  it('lets an organiser price a pass, and every terminal read it', async () => {
    await assertSucceeds(setDoc(passRef(admin()), pass()));
    await assertSucceeds(getDoc(passRef(reception())));
    // The bar reads it too. It is a price list, not personal data — and a rule
    // narrower than the need is how a screen ends up silently showing nothing.
    await assertSucceeds(getDoc(passRef(bar())));
  });

  it('lets a terminal LIST the catalogue, which is how it actually reads it', async () => {
    // The apps do not fetch passes one id at a time — they run
    // `collection("doorPasses").order(by: "sortOrder")`. A rule can allow a get
    // and refuse a list, and the difference would show up as an empty picker
    // saying "Nothing on sale" rather than as an error anybody could act on.
    await assertSucceeds(
      getDocs(query(collection(reception(), 'doorPasses'), orderBy('sortOrder')))
    );
    await assertSucceeds(getDocs(collection(bar(), 'doorPasses')));
  });

  it('THE ONE THAT MATTERS: no terminal can set a price', async () => {
    await assertFails(setDoc(passRef(reception()), pass()));
    await assertFails(setDoc(passRef(bar()), pass()));
  });

  it('refuses a price that is not whole cents, or is a slipped decimal', async () => {
    await assertFails(setDoc(passRef(admin()), pass({ price: 185.5 })));
    await assertFails(setDoc(passRef(admin()), pass({ price: -100 })));
    await assertFails(setDoc(passRef(admin()), pass({ price: 2000000 })));
  });

  it('takes a price per night, for the evenings that differ', async () => {
    await assertSucceeds(
      setDoc(passRef(admin()), pass({
        kind: 'evening',
        prices: { friday: 4500, saturday: 5000, sunday: 4000 },
      }))
    );
    // A night left out falls back to the flat price, so a festival that charges
    // the same on Friday and Saturday writes one entry, not three.
    await assertSucceeds(
      setDoc(passRef(admin()), pass({ kind: 'evening', prices: { sunday: 4000 } }))
    );
    await assertSucceeds(setDoc(passRef(admin()), pass({ kind: 'evening', prices: {} })));
  });

  it('refuses a night that is not one of the three, or a slipped decimal', async () => {
    await assertFails(setDoc(passRef(admin()), pass({ prices: { monday: 4500 } })));
    await assertFails(setDoc(passRef(admin()), pass({ prices: { friday: 45.5 } })));
    await assertFails(setDoc(passRef(admin()), pass({ prices: { friday: -100 } })));
    await assertFails(setDoc(passRef(admin()), pass({ prices: { friday: 2000000 } })));
    await assertFails(setDoc(passRef(admin()), pass({ prices: 4500 })));
  });

  it('still lets no terminal touch the per-night prices', async () => {
    await assertFails(
      setDoc(passRef(reception()), pass({ kind: 'evening', prices: { friday: 1 } }))
    );
  });

  it('refuses a kind the terminals would not know how to sell', async () => {
    await assertFails(setDoc(passRef(admin()), pass({ kind: 'weekend' })));
    await assertSucceeds(setDoc(passRef(admin()), pass({ kind: 'evening' })));
  });

  it('refuses a nameless pass and extra fields', async () => {
    await assertFails(setDoc(passRef(admin()), pass({ name: '' })));
    await assertFails(setDoc(passRef(admin()), pass({ colour: '#FF0000' })));
  });

  it('lets an organiser take one off sale, and delete one', async () => {
    await assertSucceeds(setDoc(passRef(admin()), pass()));
    await assertSucceeds(setDoc(passRef(admin()), pass({ isActive: false })));
    await assertSucceeds(deleteDoc(passRef(admin())));
    await assertFails(deleteDoc(passRef(reception())));
  });
});

// ───────────────────────────────────────────────────────────────────────────
//  Preordered merch
//
//  The reason this lives in a subcollection at all: a participant document is
//  readable by every signed-in terminal, and a bartender has no business
//  knowing what size somebody wears. The first test here is the feature.
// ───────────────────────────────────────────────────────────────────────────

describe('preordered merch', () => {
  const merchRef = (db, pid = PARTICIPANT) => doc(db, 'participants', pid, 'merch', 'order');

  /** An imported order, written the way the Admin SDK writes it. */
  async function seedOrder(overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(merchRef(context.firestore()), {
        item: 'shirt',
        size: 'M',
        colour: 'Sky Blue',
        orderHash: 'hash1',
        collectedAt: null,
        collectedBy: null,
        ...overrides,
      });
    });
  }

  it('is readable by reception, who hand it over', async () => {
    await seedOrder();
    await assertSucceeds(getDoc(merchRef(reception())));
  });

  it('is readable by an admin, who is reception when the desk is busy', async () => {
    await seedOrder();
    await assertSucceeds(getDoc(merchRef(admin())));
  });

  it('THE POINT: the bar cannot read it, though it can read the participant', async () => {
    await seedOrder();
    // The bar needs the person — name, balance, whether they are blocked.
    await assertSucceeds(getDoc(doc(bar(), 'participants', PARTICIPANT)));
    // It does not need their t-shirt size, and cannot have it.
    await assertFails(getDoc(merchRef(bar())));
  });

  it('is unreadable without a role at all', async () => {
    await seedOrder();
    await assertFails(getDoc(merchRef(roleless())));
    await assertFails(getDoc(merchRef(anonymous())));
  });

  it('lets reception mark it collected, stamped by the server and the staff uid', async () => {
    await seedOrder();
    await assertSucceeds(
      updateDoc(merchRef(reception()), {
        collectedAt: serverTimestamp(),
        collectedBy: RECEPTION_UID,
      })
    );
  });

  it('lets reception undo a collection, unlike a bracelet pairing', async () => {
    await seedOrder({ collectedAt: new Date(), collectedBy: RECEPTION_UID });
    await assertSucceeds(
      updateDoc(merchRef(reception()), { collectedAt: null, collectedBy: null })
    );
  });

  it('refuses a collection stamped with anybody else, or with the phone clock', async () => {
    await seedOrder();
    await assertFails(
      updateDoc(merchRef(reception()), {
        collectedAt: serverTimestamp(),
        collectedBy: BAR_UID,
      })
    );
    await assertFails(
      updateDoc(merchRef(reception()), {
        collectedAt: new Date('2020-01-01'),
        collectedBy: RECEPTION_UID,
      })
    );
  });

  it('refuses the bar handing merch over', async () => {
    await seedOrder();
    await assertFails(
      updateDoc(merchRef(bar()), {
        collectedAt: serverTimestamp(),
        collectedBy: BAR_UID,
      })
    );
  });

  it('keeps what was ordered in the Sheet: a terminal cannot edit the order', async () => {
    await seedOrder();
    for (const change of [
      { item: 'shirtAndTote' },
      { size: 'XL' },
      { colour: 'French Navy' },
      { orderHash: 'forged' },
    ]) {
      await assertFails(updateDoc(merchRef(reception()), change));
    }
  });

  it('refuses collecting something that was never ordered', async () => {
    await seedOrder({ item: 'none', size: null, colour: null });
    await assertFails(
      updateDoc(merchRef(reception()), {
        collectedAt: serverTimestamp(),
        collectedBy: RECEPTION_UID,
      })
    );
  });

  it('is never created or deleted by a terminal — the Sheet owns it', async () => {
    await assertFails(
      setDoc(merchRef(reception()), {
        item: 'shirt', size: 'S', colour: 'Natural',
        orderHash: 'x', collectedAt: null, collectedBy: null,
      })
    );
    await seedOrder();
    await assertFails(deleteDoc(merchRef(reception())));
  });
});

// ───────────────────────────────────────────────────────────────────────────
//  Bracelet colours
//
//  Which colour wristband a pass type gets. Organisers set it, everybody reads
//  it — including the bar, deliberately: the colour is a function of a field
//  every terminal already reads, so restricting it would protect nothing and
//  would produce a terminal that silently shows no colour.
// ───────────────────────────────────────────────────────────────────────────

describe('the free shirt', () => {
  const shirtRef = (db, pid = PARTICIPANT) => doc(db, 'participants', pid, 'merch', 'freeShirt');

  /** As the importer writes it: on the list, nothing chosen yet. */
  async function seedShirt(extra = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(shirtRef(context.firestore()), {
        entitled: true,
        size: null,
        colour: null,
        collectedAt: null,
        collectedBy: null,
        ...extra,
      });
    });
  }

  /** What the terminal sends when the shirt goes over the counter. */
  const handover = (overrides = {}) => ({
    size: 'M',
    colour: 'Sky Blue',
    collectedAt: serverTimestamp(),
    collectedBy: RECEPTION_UID,
    ...overrides,
  });

  it('THE ONE THAT MATTERS: the bar cannot read who gets a free shirt', async () => {
    await seedShirt();
    await assertFails(getDoc(shirtRef(bar())));
    await assertSucceeds(getDoc(shirtRef(reception())));
  });

  it('lets reception record the size and colour it was handed over in', async () => {
    // The difference from a preordered order: there, the Sheet decided the size
    // and the terminal may not touch it. Here nobody chose in advance, so the
    // desk writes what came off the pile.
    await seedShirt();
    await assertSucceeds(updateDoc(shirtRef(reception()), handover()));
  });

  it('lets reception undo a handover, and keeps the shirt on the list', async () => {
    await seedShirt();
    await assertSucceeds(updateDoc(shirtRef(reception()), handover()));
    await assertSucceeds(
      updateDoc(shirtRef(reception()), { collectedAt: null, collectedBy: null })
    );
  });

  it('refuses the bar handing one over', async () => {
    await seedShirt();
    await assertFails(updateDoc(shirtRef(bar()), handover({ collectedBy: BAR_UID })));
  });

  it('refuses a handover with no size or no colour', async () => {
    // "A shirt, size unknown, handed over" is how somebody ends up with two.
    await seedShirt();
    await assertFails(updateDoc(shirtRef(reception()), handover({ size: null })));
    await assertFails(updateDoc(shirtRef(reception()), handover({ colour: null })));
  });

  it('refuses one for somebody who is not on the list', async () => {
    await seedShirt({ entitled: false });
    await assertFails(updateDoc(shirtRef(reception()), handover()));
  });

  it('THE OTHER ONE: a terminal cannot put itself on the list', async () => {
    await seedShirt({ entitled: false });
    await assertFails(updateDoc(shirtRef(reception()), { entitled: true }));
    // Nor alongside a handover, which is the shape somebody would actually try.
    await assertFails(updateDoc(shirtRef(reception()), { ...handover(), entitled: true }));
  });

  it('refuses a backdated handover and one attributed to somebody else', async () => {
    await seedShirt();
    await assertFails(updateDoc(shirtRef(reception()), handover({ collectedAt: new Date(0) })));
    await assertFails(updateDoc(shirtRef(reception()), handover({ collectedBy: ADMIN_UID })));
  });

  it('refuses nonsense in the size or the colour', async () => {
    await seedShirt();
    await assertFails(updateDoc(shirtRef(reception()), handover({ size: '' })));
    await assertFails(updateDoc(shirtRef(reception()), handover({ size: 'x'.repeat(9) })));
    await assertFails(updateDoc(shirtRef(reception()), handover({ colour: 'x'.repeat(41) })));
    await assertFails(updateDoc(shirtRef(reception()), handover({ size: 42 })));
  });

  it('refuses extra fields — this is a shirt, not a profile', async () => {
    await seedShirt();
    await assertFails(updateDoc(shirtRef(reception()), { ...handover(), note: 'nice one' }));
  });

  it('cannot be created or deleted by a terminal', async () => {
    await assertFails(setDoc(shirtRef(reception()), { entitled: true }));
    await seedShirt();
    await assertFails(deleteDoc(shirtRef(reception())));
  });

  it('leaves the preordered order rule alone', async () => {
    // Both documents live in the same subcollection and the rule branches on the
    // id. This is the check that the branch did not loosen the older half: an
    // `order` still refuses a size change, which a free shirt allows.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'participants', PARTICIPANT, 'merch', 'order'), {
        item: 'shirt', size: 'M', colour: 'Natural', collectedAt: null, collectedBy: null,
      });
    });
    await assertFails(
      updateDoc(doc(reception(), 'participants', PARTICIPANT, 'merch', 'order'), { size: 'L' })
    );
  });
});

describe('the special-session catalogue', () => {
  const ref = (db, id = 'jazz-patrik') => doc(db, 'specialSessions', id);
  const session = (overrides = {}) => ({
    name: 'Jazz with Patrik', price: 2500, sortOrder: 1, isActive: true, ...overrides,
  });

  it('is read by the terminals and written by an organiser', async () => {
    await assertSucceeds(getDoc(ref(reception())));
    await assertSucceeds(setDoc(ref(admin()), session({ price: 3000 })));
    await assertFails(setDoc(ref(reception()), session({ price: 3000 })));
  });

  it('is not the bar\u2019s business — it neither shows nor sells a class', async () => {
    await assertFails(getDoc(ref(bar())));
    await assertFails(setDoc(ref(bar()), session()));
  });

  it('refuses nonsense in a name or a price', async () => {
    await assertFails(setDoc(ref(admin()), session({ name: '' })));
    await assertFails(setDoc(ref(admin()), session({ name: 'x'.repeat(101) })));
    await assertFails(setDoc(ref(admin()), session({ price: '25.00' })));
    await assertFails(setDoc(ref(admin()), session({ price: -1 })));
    await assertFails(setDoc(ref(admin()), session({ price: 200001 })));
    await assertFails(setDoc(ref(admin()), { ...session(), kind: 'session' }));
  });

  it('THE SPLIT: a class is not a door pass, and cannot be written as one', async () => {
    // They shared `doorPasses` behind a `kind` for one afternoon. The catalogue
    // refuses that kind now, so the two cannot drift back together.
    await assertFails(
      setDoc(doc(admin(), 'doorPasses', 'jazz-patrik'), {
        name: 'Jazz with Patrik', price: 2500, sortOrder: 9, isActive: true, kind: 'session',
      })
    );
  });

  it('lets an organiser withdraw one and delete it', async () => {
    await assertSucceeds(setDoc(ref(admin()), session({ isActive: false })));
    await assertSucceeds(deleteDoc(ref(admin())));
    await assertFails(deleteDoc(ref(reception())));
  });
});

// ───────────────────────────────────────────────────────────────────────────
//  Special sessions
//
//  An extra class bought at the desk by somebody who is already here. The
//  document existing IS the sale, it is written once, and it says what was paid
//  — so it is a takings record as much as a fact about a person.
// ───────────────────────────────────────────────────────────────────────────

describe('special sessions', () => {
  // One class each, so the sale lives at a fixed document id and which class it
  // was is a field. `create` failing on an existing document is the enforcement.
  const ref = (db, docId = 'booked') =>
    doc(db, 'participants', PARTICIPANT, 'sessions', docId);

  const sale = (overrides = {}) => ({
    sessionId: 'jazz-patrik',
    name: 'Jazz with Patrik',
    price: 2500,
    method: 'cash',
    soldAt: serverTimestamp(),
    soldBy: RECEPTION_UID,
    ...overrides,
  });

  async function seedSale(overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(ref(context.firestore()), {
        ...sale(overrides),
        soldAt: new Date(),
      });
    });
  }

  it('lets reception sell one', async () => {
    await assertSucceeds(setDoc(ref(reception()), sale()));
  });

  it('lets an organiser sell one too, since admin counts as reception', async () => {
    await assertSucceeds(setDoc(ref(admin()), sale({ soldBy: ADMIN_UID })));
  });

  it('THE ONE THAT MATTERS: the bar can neither read nor sell one', async () => {
    // What somebody bought and what they paid is not the bar's business — the
    // same line merch holds, and the reason this is a subcollection at all.
    await seedSale();
    await assertFails(getDoc(ref(bar())));
    await assertSucceeds(getDoc(ref(reception())));
    await assertFails(setDoc(ref(bar()), sale()));
  });

  it('refuses a class the organisers never put on sale', async () => {
    // The same protection a door pass gets: reception sells what the festival
    // sells, at the price list's own names, and cannot invent a private lesson.
    await assertFails(
      setDoc(ref(reception()), sale({ sessionId: 'private-lesson', name: 'Private lesson' }))
    );
  });

  it('THE CHANGE: one class each — a second sale is refused', async () => {
    // Enforced by the path rather than by the screen: the sale is at a fixed id,
    // so `create` on an existing one fails. Somebody who bought Jazz cannot also
    // be sold Lindy Hop, whatever a terminal sends.
    await assertSucceeds(setDoc(ref(reception()), sale()));
    await assertFails(
      setDoc(ref(reception()), sale({ sessionId: 'lindy-hop', name: 'Lindy Hop with Sakarias & Elice' }))
    );
  });

  it('refuses a sale written anywhere but the one document', async () => {
    // Two documents under one person would be two classes, which is the thing
    // the fixed id exists to prevent.
    await assertFails(setDoc(ref(reception(), 'jazz-patrik'), sale()));
    await assertFails(setDoc(ref(reception(), 'second'), sale()));
  });

  it('refuses a name that disagrees with the catalogue', async () => {
    await assertFails(setDoc(ref(reception()), sale({ name: 'Jazz with somebody else' })));
  });

  it('refuses selling an ordinary pass as a session', async () => {
    // `full-pass` is a door pass, and the classes are a different collection
    // entirely — so this fails on "no such class" rather than on a kind check.
    await assertFails(
      setDoc(ref(reception()), sale({ sessionId: 'full-pass', name: 'Full Pass', price: 20500 }))
    );
  });

  it('refuses a sale that does not say how it was paid', async () => {
    await assertFails(setDoc(ref(reception()), sale({ method: null })));
    await assertFails(setDoc(ref(reception()), sale({ method: 'invoice' })));
    await assertFails(setDoc(ref(reception()), sale({ method: 'Cash' })));
  });

  it('refuses nonsense in the price, and takes what the terminal reports', async () => {
    await assertFails(setDoc(ref(reception()), sale({ price: '25.00' })));
    await assertFails(setDoc(ref(reception()), sale({ price: -1 })));
    await assertFails(setDoc(ref(reception()), sale({ price: 200001 })));
    // Deliberately not pinned to the catalogue: a phone holding a five-minute-old
    // price must not have the sale refused with money already on the desk.
    await assertSucceeds(setDoc(ref(reception()), sale({ price: 2000 })));
  });

  it('pins who sold it and when to the server, not to the client', async () => {
    await assertFails(setDoc(ref(reception()), sale({ soldBy: ADMIN_UID })));
    await assertFails(setDoc(ref(reception()), sale({ soldAt: new Date() })));
  });

  it('refuses extra fields', async () => {
    await assertFails(setDoc(ref(reception()), { ...sale(), refunded: true }));
  });

  it('THE PANEL: the totals are a collection-group read, which needs its own rule', async () => {
    // A nested `match` does not authorise a collection-group query, and the
    // admin panel adds these up across everybody. Asserted because the failure
    // is silent: the table simply never appears.
    await seedSale();
    await assertSucceeds(getDocs(collectionGroup(reception(), 'sessions')));
    await assertSucceeds(getDocs(collectionGroup(admin(), 'sessions')));
    await assertFails(getDocs(collectionGroup(bar(), 'sessions')));
  });

  it('THE OTHER ONE: a sale is written once and never rewritten', async () => {
    // A second tap on a class somebody already bought must fail rather than
    // quietly replace the method the first sale recorded — a sale that can be
    // rewritten is one nobody can count a cash box against.
    await seedSale();
    await assertFails(updateDoc(ref(reception()), { method: 'card' }));
    await assertFails(setDoc(ref(reception()), sale({ method: 'card' })));
    await assertFails(deleteDoc(ref(reception())));
    await assertFails(deleteDoc(ref(admin())));
  });
});

describe('bracelet colours', () => {
  const ref = (db, id = 'full-pass') => doc(db, 'braceletColours', id);
  const colour = (overrides = {}) => ({
    passType: 'Full Pass',
    colour: '#1E6BB8',
    name: 'Sky Blue',
    ...overrides,
  });

  async function seed(overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(ref(context.firestore()), colour(overrides));
    });
  }

  it('is readable by every role, the bar included', async () => {
    await seed();
    await assertSucceeds(getDoc(ref(reception())));
    await assertSucceeds(getDoc(ref(bar())));
    await assertSucceeds(getDoc(ref(admin())));
  });

  it('is not readable without a role', async () => {
    await seed();
    await assertFails(getDoc(ref(roleless())));
    await assertFails(getDoc(ref(anonymous())));
  });

  it('is written by an organiser and nobody else', async () => {
    await assertSucceeds(setDoc(ref(admin()), colour()));
    await assertFails(setDoc(ref(reception(), 'party-pass'), colour({ passType: 'Party Pass' })));
    await assertFails(setDoc(ref(bar(), 'party-pass'), colour({ passType: 'Party Pass' })));
  });

  it('accepts a colour with no name — a swatch is enough', async () => {
    await assertSucceeds(
      setDoc(ref(admin()), { passType: 'Full Pass', colour: '#1E6BB8' })
    );
  });

  /// Pinned because both apps parse this string, and Swift has no forgiving
  /// colour parser: "red" would reach a phone as no colour at all.
  it('refuses anything that is not #RRGGBB in upper case', async () => {
    for (const bad of ['red', '#f00', '#1e6bb8', '1E6BB8', '#1E6BB', '#1E6BB8F', '']) {
      await assertFails(setDoc(ref(admin()), colour({ colour: bad })));
    }
    await assertSucceeds(setDoc(ref(admin()), colour({ colour: '#00FF00' })));
  });

  it('refuses a blank pass type, which could never match anybody', async () => {
    await assertFails(setDoc(ref(admin()), colour({ passType: '' })));
  });

  it('refuses extra fields', async () => {
    await assertFails(
      setDoc(ref(admin()), { ...colour(), sortOrder: 2 })
    );
  });

  it('accepts a level, so Full Pass Advanced can differ from Full Pass Pro', async () => {
    for (const level of ['Intermediate', 'Advanced', 'Pro', 'Other']) {
      await assertSucceeds(
        setDoc(ref(admin(), `full-pass-${level.toLowerCase()}`), colour({ level }))
      );
    }
  });

  it('treats an absent or empty level as "any level"', async () => {
    await assertSucceeds(setDoc(ref(admin()), colour()));
    await assertSucceeds(setDoc(ref(admin()), colour({ level: '' })));
  });

  /// A fifth level would match nobody, so a mapping using one would look like a
  /// colour that silently does nothing.
  it('refuses a level that is not one of the four', async () => {
    for (const bad of ['Beginner', 'advanced', 'Pro - fixed partner track', 'Expert']) {
      await assertFails(setDoc(ref(admin()), colour({ level: bad })));
    }
  });

  it('accepts a night, for the three wristbands that differ by night', async () => {
    // All three evenings carry the same `ticketType`, so the night is the only
    // thing that tells a Friday wristband from a Sunday one.
    for (const evening of ['friday', 'saturday', 'sunday']) {
      await assertSucceeds(
        setDoc(ref(admin(), `evening-${evening}`), colour({ passType: 'Evening Ticket', evening }))
      );
    }
    await assertSucceeds(setDoc(ref(admin()), colour({ evening: '' })));
  });

  it('refuses a night that is not one of the three', async () => {
    for (const bad of ['monday', 'Friday', 'fri', 'friday evening']) {
      await assertFails(setDoc(ref(admin()), colour({ evening: bad })));
    }
  });

  /// A level says which class somebody is in and a night says which door they
  /// came through. One document claiming both matches nobody.
  it('refuses a document claiming both a level and a night', async () => {
    await assertFails(setDoc(ref(admin()), colour({ level: 'Pro', evening: 'friday' })));
    // Either one alone, with the other empty, is the ordinary case.
    await assertSucceeds(setDoc(ref(admin()), colour({ level: 'Pro', evening: '' })));
    await assertSucceeds(setDoc(ref(admin()), colour({ level: '', evening: 'friday' })));
  });

  it('lets an organiser recolour and remove a mapping', async () => {
    await seed();
    await assertSucceeds(updateDoc(ref(admin()), { colour: '#C8A64B' }));
    await assertSucceeds(deleteDoc(ref(admin())));
  });

  it('refuses a terminal deleting one', async () => {
    await seed();
    await assertFails(deleteDoc(ref(reception())));
    await assertFails(deleteDoc(ref(bar())));
  });
});


// ── What is behind the bar ───────────────────────────────────────────────────

describe('reading every ledger at once', () => {
  it('THE SILENT ONE: the panel can run the collection-group query, and only the panel', async () => {
    // A nested match does not authorise a collection-group query, and the
    // failure is invisible — the table simply never appears. That is exactly
    // how the special-session takings shipped broken once already.
    await assertSucceeds(getDocs(collectionGroup(admin(), 'transactions')));
    // Narrower than the per-participant rule on purpose: a terminal may read
    // the ledger of whoever is in front of it, not everybody's at once.
    await assertFails(getDocs(collectionGroup(bar(), 'transactions')));
    await assertFails(getDocs(collectionGroup(reception(), 'transactions')));
    await assertFails(getDocs(collectionGroup(anonymous(), 'transactions')));
  });

  it('and every delivery at once, for the stock report', async () => {
    await assertSucceeds(getDocs(collectionGroup(admin(), 'movements')));
    await assertFails(getDocs(collectionGroup(bar(), 'movements')));
    await assertFails(getDocs(collectionGroup(reception(), 'movements')));
  });
});

describe('the stock behind the bar', () => {
  const item = (overrides = {}) => ({
    name: 'Gin', openingMl: 6000, sortOrder: 0, isActive: true, ...overrides,
  });
  const movement = (overrides = {}) => ({
    deltaMl: 3000, reason: 'A new box carried in', at: serverTimestamp(), by: ADMIN_UID, ...overrides,
  });

  it('an organiser sets up what is in the store', async () => {
    await assertSucceeds(setDoc(doc(admin(), 'stock', 'gin'), item()));
    await assertSucceeds(setDoc(doc(admin(), 'stock', 'gin'), item({ openingMl: 9000 })));
    await assertSucceeds(deleteDoc(doc(admin(), 'stock', 'gin')));
  });

  it('refuses a malformed item', async () => {
    for (const bad of [
      item({ openingMl: 6.5 }),               // litres as a float — the whole point of ml
      item({ openingMl: -1 }),
      item({ openingMl: 1000001 }),           // past the typo ceiling
      item({ name: '' }),
      item({ name: 'x'.repeat(61) }),
      item({ isActive: 'yes' }),
      { ...item(), supplier: 'Ivan' },        // an extra field
      { name: 'Gin', openingMl: 6000 },       // missing sortOrder and isActive
    ]) {
      await assertFails(setDoc(doc(admin(), 'stock', 'gin'), bad));
    }
  });

  it('THE ONE THAT MATTERS: no terminal writes stock, and the bar does not read it to sell', async () => {
    // It is a planning tool, not a till: the bar's screen must never depend on
    // it, and a bartender must never be able to change it.
    await setDoc(doc(admin(), 'stock', 'gin'), item());
    for (const db of [bar(), reception(), roleless(), anonymous()]) {
      await assertFails(setDoc(doc(db, 'stock', 'gin'), item()));
      await assertFails(updateDoc(doc(db, 'stock', 'gin'), { openingMl: 1 }));
      await assertFails(deleteDoc(doc(db, 'stock', 'gin')));
    }
    // Reading is open to staff, the same as the menu and the colours: it costs
    // nothing and a future screen may want it.
    await assertSucceeds(getDoc(doc(bar(), 'stock', 'gin')));
    await assertFails(getDoc(doc(anonymous(), 'stock', 'gin')));
  });

  it('records a new box, and cannot rewrite one', async () => {
    await setDoc(doc(admin(), 'stock', 'gin'), item());
    await assertSucceeds(setDoc(doc(admin(), 'stock/gin/movements', 'm1'), movement()));
    // Append-only, like the ledger: "how did we get to four litres" is a
    // question somebody asks next year.
    await assertFails(updateDoc(doc(admin(), 'stock/gin/movements', 'm1'), { deltaMl: 9000 }));
    await assertFails(deleteDoc(doc(admin(), 'stock/gin/movements', 'm1')));
  });

  it('a recount that found less is a negative movement, and zero is not a movement', async () => {
    await setDoc(doc(admin(), 'stock', 'gin'), item());
    await assertSucceeds(
      setDoc(doc(admin(), 'stock/gin/movements', 'm2'), movement({ deltaMl: -400, reason: 'Recount at 2am' }))
    );
    await assertFails(setDoc(doc(admin(), 'stock/gin/movements', 'm3'), movement({ deltaMl: 0 })));
    await assertFails(setDoc(doc(admin(), 'stock/gin/movements', 'm4'), movement({ deltaMl: 500.5 })));
    await assertFails(setDoc(doc(admin(), 'stock/gin/movements', 'm5'), movement({ reason: '' })));
  });

  it('a movement carries the server clock and the organiser who made it', async () => {
    await setDoc(doc(admin(), 'stock', 'gin'), item());
    await assertFails(
      setDoc(doc(admin(), 'stock/gin/movements', 'm6'), movement({ at: new Date('2020-01-01') }))
    );
    await assertFails(
      setDoc(doc(admin(), 'stock/gin/movements', 'm7'), movement({ by: 'uid-somebody-else' }))
    );
    for (const db of [bar(), reception()]) {
      await assertFails(setDoc(doc(db, 'stock/gin/movements', 'm8'), movement({ by: 'uid-bar' })));
    }
  });
});
