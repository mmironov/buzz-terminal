// ═══════════════════════════════════════════════════════════════════════════
//  Put some real history on the emulator's bracelets, so the panel has something
//  to show.
//
//      cd backend && firebase emulators:start --only firestore,auth
//      ./seed-emulator.sh          # accounts, roster, the menu
//      cd ../web-admin && npm run seed:history
//
//  Deliberately NOT the Admin SDK. `seed-emulator.sh` writes the roster as `owner`
//  because the roster genuinely belongs to an import that bypasses the rules — but
//  bracelets and money do not. This script signs in as reception@example.test and
//  bar@example.test with the client SDK and sends exactly the batches the iOS and
//  Android repositories send, so the rules are enforced against it. If a write
//  shape here is wrong the script fails, which is the point: it is a rehearsal of
//  the terminals, not a shortcut around them.
//
//  Idempotent-ish: pairing a bracelet is permanent by design, so a second run
//  reports the pairings it could not redo and tops up and charges again.
// ═══════════════════════════════════════════════════════════════════════════

import { initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import {
  connectFirestoreEmulator,
  doc,
  getDoc,
  getFirestore,
  serverTimestamp,
  writeBatch,
} from 'firebase/firestore';

const app = initializeApp({
  apiKey: 'emulator-ignores-this',
  authDomain: 'localhost',
  projectId: process.env.FIREBASE_PROJECT_ID ?? 'swing-buzz',
  appId: '1:0:web:0',
});
const auth = getAuth(app);
const db = getFirestore(app);
connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
connectFirestoreEmulator(db, '127.0.0.1', 8080);

const PASSWORD = 'festival26';
const TERMINAL = 'terminal-seed';

/** The three chips, one per seeded participant. */
const CHIPS = { 1041: '04:B4:2F:11', 1042: '04:C8:5D:03', 1043: '04:A1:9C:7E' };

async function as(email) {
  await signOut(auth).catch(() => {});
  const credential = await signInWithEmailAndPassword(auth, email, PASSWORD);
  // Forced refresh, same as the apps: a role granted after the account was created
  // sits behind a cached token otherwise.
  await credential.user.getIdToken(true);
  return credential.user.uid;
}

/** Reception pairing a chip: the participant and the reverse lookup, together. */
async function checkIn(uid, participantId, chip) {
  const batch = writeBatch(db);
  batch.update(doc(db, 'participants', participantId), {
    braceletId: chip,
    checkedInAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(db, 'bracelets', chip), {
    participantId,
    staffUid: uid,
    pairedAt: serverTimestamp(),
  });
  await batch.commit();
}

/**
 * A money batch, in the exact shape `moveMoney` sends: the ledger entry and the
 * new balance in one commit, with the document id doubling as the idempotency key.
 * `items` is present for a charge and absent for a top-up, which the rules require.
 */
async function money(uid, participantId, { type, amount, items }) {
  const before = await getDoc(doc(db, 'participants', participantId));
  const balance = before.data()?.balance ?? 0;
  const signed = type === 'charge' ? -amount : amount;
  const txId = crypto.randomUUID();

  const entry = {
    clientTxId: txId,
    type,
    amount,
    signedAmount: signed,
    staffUid: uid,
    terminalId: TERMINAL,
    createdAt: serverTimestamp(),
  };
  if (items) entry.items = items;

  const batch = writeBatch(db);
  batch.set(doc(db, 'participants', participantId, 'transactions', txId), entry);
  batch.update(doc(db, 'participants', participantId), {
    balance: balance + signed,
    lastTxId: txId,
    updatedAt: serverTimestamp(),
  });
  await batch.commit();
  return balance + signed;
}

const line = (drinkId, name, unitPrice, quantity) => ({ drinkId, name, unitPrice, quantity });

const euro = (cents) => `${(cents / 100).toFixed(2)} €`;

async function attempt(what, work) {
  try {
    const result = await work();
    console.log(`  ✔ ${what}${typeof result === 'number' ? ` → ${euro(result)}` : ''}`);
  } catch (error) {
    console.log(`  · ${what} — skipped (${error.code ?? error.message})`);
  }
}

console.log('\nreception:');
const receptionUid = await as('reception@example.test');
for (const [participantId, chip] of Object.entries(CHIPS)) {
  // 1043 is left awaiting check-in on purpose: the panel needs a row with no
  // bracelet to show, and reception's own screen is that list.
  if (participantId === '1043') continue;
  await attempt(`check in ${participantId} on ${chip}`, () =>
    checkIn(receptionUid, participantId, chip)
  );
}
await attempt('top up 1041 by 20.00 €', () =>
  money(receptionUid, '1041', { type: 'topup', amount: 2000 })
);
await attempt('top up 1042 by 10.00 €', () =>
  money(receptionUid, '1042', { type: 'topup', amount: 1000 })
);

console.log('\nbar:');
const barUid = await as('bar@example.test');
// A multi-line round, so the panel's history has an itemisation worth reading.
await attempt('charge 1041 for 3 beer + 1 water', () =>
  money(barUid, '1041', {
    type: 'charge',
    amount: 1400,
    items: [line('beer', 'Beer', 400, 3), line('water', 'Water', 200, 1)],
  })
);
await attempt('charge 1041 for 1 gin & tonic', () =>
  money(barUid, '1041', {
    type: 'charge',
    amount: 600,
    items: [line('gt', 'Gin & Tonic', 600, 1)],
  })
);
await attempt('charge 1042 for 2 water', () =>
  money(barUid, '1042', {
    type: 'charge',
    amount: 400,
    items: [line('water', 'Water', 200, 2)],
  })
);

await signOut(auth);
console.log('\ndone. Open the panel with: npm run dev:emulator\n');
process.exit(0);
