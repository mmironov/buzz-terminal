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
 * Every existing merch order, keyed by participant id.
 *
 * A collection-group read rather than one get per participant: 105 point reads
 * to find 28 documents is a slow dry run for no reason. The parent's id is the
 * key, which is why the document is always called `order` — one merch order per
 * person, at a known path, readable offline from cache on a terminal.
 */
export async function fetchMerchOrders(db) {
  return fetchMerchDocuments(db, 'order');
}

/** The same collection, the other document id. See `fetchMerchDocuments`. */
export async function fetchFreeShirts(db) {
  return fetchMerchDocuments(db, 'freeShirt');
}

/**
 * One document id out of the `merch` subcollection, keyed by participant.
 *
 * **The id filter is load-bearing.** A collection-group query over `merch`
 * returns every document in it, and there are two per person now — the
 * preordered `order` and the `freeShirt`. Keying a map by the parent id without
 * filtering would let one silently overwrite the other, and the importer would
 * then compare a free shirt against a t-shirt order and rewrite both.
 */
async function fetchMerchDocuments(db, documentId) {
  const snapshot = await db.collectionGroup('merch').get();
  const existing = new Map();
  snapshot.forEach((doc) => {
    if (doc.id !== documentId) return;
    const participantId = doc.ref.parent.parent?.id;
    if (participantId) existing.set(participantId, doc.data());
  });
  return existing;
}

/**
 * Apply a merch plan from diff.mjs.
 *
 * Always `set(..., { merge: true })`, never `create`: the payload deliberately
 * omits `collectedAt`, so a merge leaves a handed-over shirt handed over. On a
 * first write the initial state is included so the fields exist rather than
 * being absent, which keeps the security rules' shape check simple.
 */
export async function applyFreeShirtPlan(db, plan, { batchSize = 400 } = {}) {
  return applyMerchPlan(db, plan, { batchSize, documentId: 'freeShirt', label: 'free shirts' });
}

export async function applyMerchPlan(db, plan, { batchSize = 400, documentId = 'order', label = 'merch' } = {}) {
  const { FieldValue } = admin.firestore;
  const operations = [
    ...plan.writes.map((w) => ({ ...w, data: { ...(w.initial ?? {}), ...w.data } })),
    ...plan.retires,
  ];

  let written = 0;
  for (let i = 0; i < operations.length; i += batchSize) {
    const batch = db.batch();
    for (const op of operations.slice(i, i + batchSize)) {
      const ref = db.collection('participants').doc(op.id).collection('merch').doc(documentId);
      batch.set(ref, { ...op.data, importedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
    await batch.commit();
    written += Math.min(batchSize, operations.length - i);
    process.stdout.write(`    committed ${written}/${operations.length} ${label}\n`);
  }
  return written;
}

/** The three roles `firestore.rules` knows about. Nothing else is a role. */
export const ROLES = ['reception', 'bar', 'admin'];

/**
 * Set a staff member's role as a custom claim.
 *
 * Custom claims cannot be set from the Firebase console — only through the Admin
 * SDK — which is exactly why they are trustworthy: no client can grant itself a
 * role. The security rules read `request.auth.token.role`.
 *
 * `admin` is the web panel in `web-admin/`: it can block bracelets and edit the
 * menu, and it deliberately cannot move money. Grant it to organisers, not to
 * whoever is standing behind the bar — an admin token in a terminal's hands is
 * a menu nobody meant to change.
 *
 * The user must sign out and back in (or have their token refreshed) before a new
 * claim takes effect.
 */
export async function setRole(email, role) {
  if (!ROLES.includes(role)) {
    throw new Error(`Role must be one of ${ROLES.join(', ')} — got "${role}".`);
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
 * The menu now belongs to the web admin panel, so this is a bootstrap rather than
 * the way prices get set: it puts something on the bar's screen on a fresh
 * project, before anyone has signed into `web-admin/`. Editing it afterwards from
 * here would silently overwrite whatever an organiser has since done — including
 * reactivating a drink they took off the menu tonight.
 *
 * Still the Admin SDK rather than a client, because `firestore.rules` grants
 * `drinks` writes to the `admin` claim alone, and no terminal, however
 * compromised, can set its own prices.
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
 * The menu a fresh project starts with. The admin panel takes it from here.
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

/**
 * Write the door-sale catalogue, the same way `seedDrinks` writes the menu:
 * merged, so re-running it never clears a price an organiser has since edited
 * on purpose — it only puts the row back if somebody deleted it.
 *
 * Nothing is retired here. A pass missing from this list is one an organiser
 * added in the panel, and a seed script is the wrong thing to be withdrawing it.
 */
export async function seedDoorPasses(db, passes) {
  const batch = db.batch();
  passes.forEach((pass, index) => {
    batch.set(
      db.collection('doorPasses').doc(pass.id),
      {
        name: pass.name,
        price: pass.price,
        sortOrder: index,
        isActive: true,
        kind: pass.kind ?? 'pass',
      },
      { merge: true }
    );
  });
  await batch.commit();
  return { written: passes.length };
}

/**
 * What the festival sells at the door, at the prices the organisers gave.
 *
 * The evening ticket is in the list because it IS a door sale — it is the one
 * the terminals have always sold — but its price is deliberately left at zero
 * rather than guessed. The panel shows "No price set" beside it, which is the
 * honest state until somebody types the number.
 */
export const DEFAULT_DOOR_PASSES = [
  { id: 'evening-ticket', name: 'Evening Ticket', price: 0, kind: 'evening' },
  { id: 'party-pass', name: 'Party Pass', price: 12000 },
  { id: 'party-pass-plus', name: 'Party Pass Plus', price: 15500 },
  { id: 'full-pass', name: 'Full Pass', price: 20500 },
  { id: 'full-pass-gold', name: 'Full Pass Gold', price: 25900 },
  { id: 'jazz-performance-track', name: 'Jazz Performance Track', price: 18500 },
];

/**
 * The extra classes, which are **not** passes.
 *
 * A collection of their own because a class admits nobody, creates no
 * participant and is never sold at the door: it is added to somebody who is
 * already here, from their own screen.
 */
export const DEFAULT_SPECIAL_SESSIONS = [
  { id: 'lindy-sakarias-elice', name: 'Lindy Hop with Sakarias & Elice', price: 2500 },
  { id: 'jazz-patrik', name: 'Jazz with Patrik', price: 2500 },
];

/** Write the class list, leaving anything an organiser added alone. */
export async function seedSpecialSessions(db, sessions) {
  const batch = db.batch();
  sessions.forEach((session, index) => {
    batch.set(
      db.collection('specialSessions').doc(session.id),
      {
        name: session.name,
        price: session.price,
        sortOrder: index,
        isActive: true,
      },
      { merge: true }
    );
  });
  await batch.commit();
  return { written: sessions.length };
}
