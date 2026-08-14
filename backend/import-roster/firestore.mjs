import admin from 'firebase-admin';

// The Admin SDK bypasses security rules entirely. That is why the roster fields
// are import-only in firestore.rules: no client can write them, and this script
// is the only thing that does.

export function initAdmin({ keyFile, projectId }) {
  if (admin.apps.length) return admin.app();
  return admin.initializeApp({
    credential: admin.credential.cert(keyFile),
    projectId,
  });
}

/** Every participant currently in Firestore, as `Map<id, data>`. */
export async function fetchParticipants(db) {
  const snapshot = await db.collection('participants').get();
  const existing = new Map();
  snapshot.forEach((doc) => existing.set(doc.id, doc.data()));
  return existing;
}

/**
 * Apply a plan from diff.mjs.
 *
 * Creates use `create()` rather than `set()`, so a race with another importer
 * run fails loudly instead of overwriting. Updates use `set(..., { merge: true })`
 * with roster fields only — the fields absent from the payload keep whatever
 * value the terminals put there.
 */
export async function applyPlan(db, plan, { batchSize = 400 } = {}) {
  const { FieldValue } = admin.firestore;
  const collection = db.collection('participants');
  const operations = [
    ...plan.creates.map((c) => ({ kind: 'create', ...c })),
    ...plan.updates.map((u) => ({ kind: 'update', ...u })),
  ];

  let written = 0;
  for (let i = 0; i < operations.length; i += batchSize) {
    const batch = db.batch();
    for (const op of operations.slice(i, i + batchSize)) {
      const ref = collection.doc(op.id);
      const data = { ...op.data, importedAt: FieldValue.serverTimestamp() };
      if (op.kind === 'create') batch.create(ref, data);
      else batch.set(ref, data, { merge: true });
    }
    await batch.commit();
    written += Math.min(batchSize, operations.length - i);
    process.stdout.write(`    committed ${written}/${operations.length}\n`);
  }
  return written;
}

/**
 * Set a staff member's role as a custom claim.
 *
 * Custom claims cannot be set from the Firebase console — only through the Admin
 * SDK — which is exactly why they are trustworthy: no client can grant itself a
 * role. The security rules read `request.auth.token.role`.
 *
 * The user must sign out and back in (or have their token refreshed) before a new
 * claim takes effect.
 */
export async function setRole(email, role) {
  if (!['reception', 'bar'].includes(role)) {
    throw new Error(`Role must be "reception" or "bar", got "${role}".`);
  }
  const user = await admin.auth().getUserByEmail(email);
  await admin.auth().setCustomUserClaims(user.uid, { role });
  return user.uid;
}

/** Read back what a user's claims actually are, to confirm a change landed. */
export async function describeUser(email) {
  const user = await admin.auth().getUserByEmail(email);
  return { uid: user.uid, email: user.email, claims: user.customClaims ?? {} };
}

/**
 * Make the `drinks` collection match `drinks` exactly. Prices in cents, matching
 * `Domain/Money.swift`.
 *
 * Anything already in Firestore and *not* in the list is deactivated rather than
 * deleted. Two reasons: the bar queries `isActive == true`, so deactivating takes
 * it off the menu immediately, and a deleted drink would orphan the ledger entries
 * that refer to it. A drink that stopped being sold still happened.
 *
 * Written by the Admin SDK because `firestore.rules` says `allow write: if false`
 * for this collection — prices are an organiser decision, and no terminal, however
 * compromised, can set its own.
 */
export async function seedDrinks(db, drinks) {
  const wanted = new Set(drinks.map((drink) => drink.id));
  const existing = await db.collection('drinks').get();
  const batch = db.batch();

  drinks.forEach((drink, index) => {
    batch.set(
      db.collection('drinks').doc(drink.id),
      { name: drink.name, price: drink.price, sortOrder: index, isActive: true },
      { merge: true }
    );
  });

  let retired = 0;
  existing.docs.forEach((doc) => {
    if (wanted.has(doc.id) || doc.data().isActive === false) return;
    batch.update(doc.ref, { isActive: false });
    retired += 1;
  });

  await batch.commit();
  return { written: drinks.length, retired };
}

/**
 * The menu, until the web admin panel owns it.
 *
 * Deliberately the real thing rather than the design prototype's ten invented
 * drinks — this collection is what a bartender charges people from, so a plausible
 * placeholder is worse here than an empty menu.
 */
export const DEFAULT_DRINKS = [
  { id: 'water', name: 'Water', price: 200 },
  { id: 'beer', name: 'Beer', price: 400 },
  { id: 'gt', name: 'Gin & Tonic', price: 600 },
];
