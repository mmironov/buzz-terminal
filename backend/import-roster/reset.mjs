// Wipe the festival's operational data, so a real event starts from a known state
// after testing on the live project.
//
// The planning here is pure and tested. The execution is a thin layer over the
// Admin SDK, which bypasses security rules — including the rule that makes the
// ledger append-only. That is the whole point of this file and also the reason it
// is the most dangerous thing in the repository.
//
// What is NEVER touched, in any scope:
//   * Firebase Auth accounts and their role claims. Staff keep their logins.
//   * the drinks menu, unless --drinks is passed explicitly.

/** Participants the terminals created rather than the importer. */
const isDoorSale = (data) => data.source === 'evening';

/**
 * Decide what a reset does, from what is currently in Firestore.
 *
 * Pure: takes plain data, returns a plan. No SDK, no I/O, so the decision can be
 * tested without a database and read without tracing calls.
 *
 * @param participants `[{ id, data }]`
 * @param scope `'test-data'` keeps the imported roster; `'all'` deletes it too.
 */
export function planReset({ participants = [], braceletIds = [], ledgerCount = 0, scope = 'test-data' }) {
  if (!['test-data', 'all'].includes(scope)) {
    throw new Error(`Unknown scope "${scope}". Use "test-data" or "all".`);
  }

  const deleteParticipants = [];
  const resetParticipants = [];

  for (const { id, data = {} } of participants) {
    if (scope === 'all' || isDoorSale(data)) {
      // Recursive, because a participant owns a `transactions` subcollection and
      // deleting the parent document would leave it orphaned but alive.
      deleteParticipants.push(id);
    } else {
      resetParticipants.push(id);
    }
  }

  return {
    scope,
    deleteParticipants,
    resetParticipants,
    braceletIds: [...braceletIds],
    ledgerCount,
    // The fields a reset returns to their post-import values. Everything the
    // importer owns — name, ticketType, country, ticketRef — is deliberately absent:
    // a reset is not a re-import, and should not need the Sheet to run.
    resetFields: {
      braceletId: null,
      checkedInAt: null,
      balance: 0,
      lastTxId: null,
    },
  };
}

/** True when there is nothing to do, so the CLI can say so instead of "0 of 0". */
export function isNoOp(plan) {
  return (
    plan.deleteParticipants.length === 0 &&
    plan.braceletIds.length === 0 &&
    plan.ledgerCount === 0 &&
    plan.resetParticipants.length === 0
  );
}

/**
 * Guard the trigger.
 *
 * Two separate mistakes to prevent, so two separate flags: `--apply` says "yes,
 * write", and `--confirm=<project>` says "yes, THIS project". Typing the project id
 * is the part that cannot be muscle memory, because the id differs between a
 * scratch project and the festival's.
 *
 * Returns an error message, or `null` when it is safe to proceed.
 */
export function checkConfirmation({ apply, confirm, projectId }) {
  if (!apply) return null; // dry runs need no confirmation
  if (!confirm) {
    return (
      `This deletes data in "${projectId}" and cannot be undone.\n` +
      `  To go ahead, name the project:\n\n` +
      `      npm run reset -- --apply --confirm=${projectId}`
    );
  }
  if (confirm !== projectId) {
    return `--confirm=${confirm} does not match the project being reset (${projectId}).`;
  }
  return null;
}

/** Money currently recorded in the ledger, for the "are you sure" summary. */
export function summariseLedger(transactions) {
  let topUps = 0;
  let charges = 0;
  for (const tx of transactions) {
    if (tx.type === 'charge') charges += tx.amount ?? 0;
    else topUps += tx.amount ?? 0;
  }
  return { topUps, charges, net: topUps - charges, count: transactions.length };
}

// ── execution ──────────────────────────────────────────────────────────────

/**
 * Carry out a plan.
 *
 * `recursiveDelete` is used for participants because of the `transactions`
 * subcollection; a plain `delete()` on the parent leaves those documents
 * unreachable but billable, and they would reappear under a re-imported
 * participant with the same id.
 */
export async function executeReset(db, plan, { deleteDrinks = false } = {}) {
  const counts = { participantsDeleted: 0, participantsReset: 0, braceletsDeleted: 0, drinksDeleted: 0 };

  for (const id of plan.deleteParticipants) {
    await db.recursiveDelete(db.collection('participants').doc(id));
    counts.participantsDeleted += 1;
  }

  // Ledger entries under participants that are being kept: the parent survives,
  // so the subcollection has to be cleared on its own.
  for (const id of plan.resetParticipants) {
    await db.recursiveDelete(db.collection('participants').doc(id).collection('transactions'));
  }

  await inBatches(db, plan.resetParticipants, (batch, id) => {
    batch.update(db.collection('participants').doc(id), plan.resetFields);
    counts.participantsReset += 1;
  });

  await inBatches(db, plan.braceletIds, (batch, id) => {
    batch.delete(db.collection('bracelets').doc(id));
    counts.braceletsDeleted += 1;
  });

  if (deleteDrinks) {
    const drinks = await db.collection('drinks').get();
    await inBatches(db, drinks.docs.map((d) => d.id), (batch, id) => {
      batch.delete(db.collection('drinks').doc(id));
      counts.drinksDeleted += 1;
    });
  }

  return counts;
}

/** Firestore commits at most 500 writes per batch, and a festival has more. */
async function inBatches(db, ids, add, size = 400) {
  for (let i = 0; i < ids.length; i += size) {
    const batch = db.batch();
    for (const id of ids.slice(i, i + size)) add(batch, id);
    await batch.commit();
  }
}
