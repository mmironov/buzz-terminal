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

/** Seed or update the drinks menu. Prices in cents, matching `Domain/Money.swift`. */
export async function seedDrinks(db, drinks) {
  const batch = db.batch();
  drinks.forEach((drink, index) => {
    batch.set(
      db.collection('drinks').doc(drink.id),
      { name: drink.name, price: drink.price, sortOrder: index, isActive: true },
      { merge: true }
    );
  });
  await batch.commit();
  return drinks.length;
}

/** The menu from the design prototype, as a starting point. */
export const DEFAULT_DRINKS = [
  { id: 'beer', name: 'Draught beer', price: 400 },
  { id: 'radler', name: 'Radler', price: 400 },
  { id: 'white', name: 'White wine', price: 500 },
  { id: 'red', name: 'Red wine', price: 500 },
  { id: 'prosecco', name: 'Prosecco', price: 600 },
  { id: 'gt', name: 'Gin & tonic', price: 800 },
  { id: 'sour', name: 'Whisky sour', price: 900 },
  { id: 'lemonade', name: 'Lemonade', price: 300 },
  { id: 'espresso', name: 'Espresso', price: 250 },
  { id: 'water', name: 'Still water', price: 150 },
];
