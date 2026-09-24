// Give staff money to spend at the bar.
//
// Staff drink on the festival, so somebody has to put the credit on their
// account. Reception could do it one wristband at a time; this does the whole
// crew in one run, before anybody has even been checked in.
//
// **This moves real money, with the Admin SDK, which bypasses the rules that
// normally protect it.** So it writes exactly the shape a terminal writes — a
// ledger entry and a balance, together — and refuses anything it cannot write
// that way. The planning below is pure and tested; the execution is a thin
// layer over Firestore.

/** Where a script's writes come from, in the ledger's own fields. */
export const SCRIPT_TERMINAL = 'import-roster';

/**
 * How the money reached the desk: it did not.
 *
 * A top-up normally says `cash` or `card`, because the question it answers is
 * what is in the cash box at the end of the night. Staff credit answers it
 * differently — nobody paid — and recording it as cash would put money in that
 * count that nobody can produce. The rules still refuse anything but cash or
 * card **from a terminal**; this value exists only on the far side of the Admin
 * SDK, which is the honest place for it.
 */
export const COMP_METHOD = 'comp';

/** A sanity ceiling, in cents. Not a policy — a typo catcher. */
export const MAX_AMOUNT = 50000;

/**
 * Parse `--amount=20` or `--amount=12.50` into cents.
 *
 * Euros, because that is what the person running it is thinking in, and the
 * festival's own prices are written that way. Rejects anything it cannot read
 * exactly rather than rounding: `--amount=20,50` is a comma-decimal typo, not
 * twenty euros.
 */
export function parseAmount(raw) {
  const text = String(raw ?? '').trim().replace(/\s*€$/, '');
  if (!/^\d+(\.\d{1,2})?$/.test(text)) {
    throw new Error(`Amount "${raw}" is not a number of euros, like 20 or 12.50.`);
  }
  const cents = Math.round(Number(text) * 100);
  if (cents <= 0) throw new Error('Amount must be more than nothing.');
  if (cents > MAX_AMOUNT) {
    throw new Error(
      `Amount ${text} € is over the ${MAX_AMOUNT / 100} € ceiling. ` +
        'If that is deliberate, run it twice or raise MAX_AMOUNT — the ceiling is here to catch a slipped decimal point.'
    );
  }
  return cents;
}

/**
 * The label that makes a run repeatable-safe, slugged for use in a document id.
 *
 * Today's date by default, so running the same command twice in one afternoon
 * credits nobody twice. A **deliberate** second top-up on the same day is a new
 * label — which is a sentence the organiser has to type, and that is the point.
 */
export function toLabel(raw, today = new Date()) {
  const fallback = today.toISOString().slice(0, 10);
  const slug = String(raw ?? fallback)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (!slug) throw new Error(`Label ${JSON.stringify(raw)} does not slugify to anything usable.`);
  return slug.slice(0, 60);
}

/** The ledger document id for one person under one label. Deterministic. */
export function transactionId(label, participantId) {
  return `staff-${label}-${participantId}`;
}

/**
 * Decide who gets credited, from what is in Firestore.
 *
 * Pure: plain data in, a plan out. Every exclusion is returned with its reason
 * rather than dropped, because "it topped up 28 people" is not a useful thing
 * to read when you believe there are 30.
 *
 * @param participants `[{ id, data }]`
 * @param target `{ all: true }` or `{ id: 'tkt-10432' }`
 * @param alreadyCredited ids that already have this label's ledger entry
 */
export function planTopUps({
  participants = [],
  amount,
  target = { all: true },
  label,
  alreadyCredited = [],
}) {
  if (!Number.isInteger(amount) || amount <= 0) {
    throw new Error('Amount must be a positive whole number of cents.');
  }
  if (!label) throw new Error('A label is required — it is what makes a re-run safe.');
  if (!target.all && !target.id) throw new Error('Choose --all or --id=<participant>.');

  const done = new Set(alreadyCredited);
  const credits = [];
  const skipped = [];

  const wanted = target.all
    ? participants
    : participants.filter(({ id }) => id === target.id);

  if (!target.all && wanted.length === 0) {
    throw new Error(`No participant with id "${target.id}".`);
  }

  for (const { id, data = {} } of wanted) {
    const name = data.name ?? id;

    // Staff only, including when an id was named: "top up this person" is a
    // different request from "give somebody money", and the second one is
    // reception's job at the desk, where it is written down as cash.
    if (data.admission !== 'staff') {
      skipped.push({ id, name, reason: 'not staff' });
      continue;
    }
    if (data.isBlocked) {
      skipped.push({ id, name, reason: 'blocked' });
      continue;
    }
    if (done.has(id)) {
      skipped.push({ id, name, reason: `already credited under "${label}"` });
      continue;
    }

    const balance = Number.isInteger(data.balance) ? data.balance : 0;
    credits.push({
      id,
      name,
      transactionId: transactionId(label, id),
      amount,
      balanceBefore: balance,
      balanceAfter: balance + amount,
    });
  }

  return { label, amount, credits, skipped, total: credits.length * amount };
}

/**
 * The ledger entry, in the shape `FirebaseTerminalRepository.moveMoney` writes.
 *
 * Deliberately the same document as a top-up taken at the desk, so the panel's
 * history, the balance invariant and any future audit all see one kind of fact.
 * The two additions are `method: "comp"` and `grant`, which say where it came
 * from — a script, under a named run — rather than leaving it to be guessed
 * from a staff uid nobody recognises.
 */
export function ledgerEntry({ transactionId: txId, amount, label, serverTimestamp }) {
  return {
    clientTxId: txId,
    type: 'topup',
    amount,
    signedAmount: amount,
    staffUid: SCRIPT_TERMINAL,
    terminalId: SCRIPT_TERMINAL,
    createdAt: serverTimestamp,
    method: COMP_METHOD,
    grant: label,
  };
}

// ── execution ──────────────────────────────────────────────────────────────

/**
 * Which of these people already have this label's entry.
 *
 * One point read each, at a fixed document id — no query, no index. It is what
 * makes the dry run tell the truth about a second run rather than promising to
 * credit everybody again.
 */
export async function findAlreadyCredited(db, { participants, label }) {
  const found = [];
  for (const { id } of participants) {
    const ref = db
      .collection('participants')
      .doc(id)
      .collection('transactions')
      .doc(transactionId(label, id));
    if ((await ref.get()).exists) found.push(id);
  }
  return found;
}

/**
 * Carry out a plan, one transaction per person.
 *
 * A transaction rather than a batch, and one person at a time, because the
 * balance has to be read and written together: the bar may be charging somebody
 * at the same moment, and a stale read would quietly undo their round. The same
 * reasoning as the app's, for the same invariant.
 *
 * `create` on the ledger entry is the idempotency: a second run at the same
 * label fails on the document rather than crediting twice. That is structural,
 * not a check somebody has to remember.
 */
export async function executeTopUps(db, plan, { serverTimestamp }) {
  const results = { credited: 0, cents: 0, failures: [] };

  for (const credit of plan.credits) {
    const participantRef = db.collection('participants').doc(credit.id);
    const txRef = participantRef.collection('transactions').doc(credit.transactionId);

    try {
      await db.runTransaction(async (tx) => {
        const snapshot = await tx.get(participantRef);
        if (!snapshot.exists) throw new Error('participant disappeared mid-run');

        // Read now, not from the plan: the plan may be a minute old, and a
        // balance is the one field on this document that moves on its own.
        const before = Number.isInteger(snapshot.get('balance')) ? snapshot.get('balance') : 0;

        tx.create(txRef, ledgerEntry({
          transactionId: credit.transactionId,
          amount: credit.amount,
          label: plan.label,
          serverTimestamp,
        }));
        tx.update(participantRef, {
          balance: before + credit.amount,
          lastTxId: credit.transactionId,
          updatedAt: serverTimestamp,
        });
      });
      results.credited += 1;
      results.cents += credit.amount;
    } catch (error) {
      // Recorded and carried on: one person's failure must not leave the rest
      // of the crew unpaid, and the summary names everybody who missed out.
      results.failures.push({ id: credit.id, name: credit.name, reason: error.message });
    }
  }

  return results;
}
