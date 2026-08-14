import { collection, onSnapshot, orderBy, query } from 'firebase/firestore';
import { useEffect, useState } from 'react';

import { db } from './firebase';
import {
  COLLECTIONS,
  euros,
  shortTime,
  toTransaction,
  type Participant,
  type Transaction,
} from './schema';

// ═══════════════════════════════════════════════════════════════════════════
//  One bracelet's history.
//
//  This is the screen a dispute at the bar is settled from, so it shows the
//  ledger and nothing derived from anywhere else. It is also read-only in the
//  strongest sense available: `firestore.rules` makes the transactions
//  subcollection append-only for everybody, including the admin claim this panel
//  signs in with. The organiser sees history and cannot edit history.
// ═══════════════════════════════════════════════════════════════════════════

export function History({ participant }: { participant: Participant }) {
  const [entries, setEntries] = useState<Transaction[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // A listener rather than a one-off read: an organiser looking at a bracelet
    // while it is being used at the bar should watch the round land, not wonder
    // whether the screen is stale.
    const ledger = query(
      collection(db, COLLECTIONS.participants, participant.id, COLLECTIONS.transactions),
      orderBy('createdAt', 'desc')
    );
    return onSnapshot(
      ledger,
      (snapshot) => {
        setEntries(snapshot.docs.flatMap((doc) => toTransaction(doc) ?? []));
        setError(null);
      },
      (cause) => setError(cause.message)
    );
  }, [participant.id]);

  if (error) return <p className="field__hint field__hint--bad">Could not read history: {error}</p>;
  if (!entries) return <p className="sub">Reading history…</p>;
  if (entries.length === 0) {
    return (
      <p className="sub">
        Nothing yet. No top-up and no drink has been charged to this bracelet.
      </p>
    );
  }

  // The ledger has to add up to the balance. It is the same arithmetic
  // `firestore.rules` enforces one entry at a time, done here across all of them:
  // if these two ever disagree, something wrote a balance the rules should have
  // refused, and that is worth seeing on the screen rather than in a report nobody
  // runs.
  const ledgerSum = entries.reduce((total, entry) => total + entry.signedAmount, 0);
  const reconciles = ledgerSum === participant.balance;

  return (
    <div className="stack">
      <span className="kicker">History · {entries.length} entries</span>

      <table className="ledger">
        <thead>
          <tr>
            <th>When</th>
            <th>What</th>
            <th className="num">Amount</th>
            <th>Terminal</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((entry) => (
            <tr key={entry.id}>
              <td className="mono">{shortTime(entry.createdAt)}</td>
              <td>
                {entry.type === 'topup' ? 'Top-up' : 'Bar'}
                {entry.type === 'charge' ? <Lines entry={entry} /> : null}
              </td>
              <td className={`num ${entry.signedAmount < 0 ? 'signed--out' : 'signed--in'}`}>
                {entry.signedAmount > 0 ? '+' : ''}
                {euros(entry.signedAmount)}
              </td>
              <td className="mono sub" title={`staff ${entry.staffUid}`}>
                {entry.terminalId || '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className={`reconcile ${reconciles ? '' : 'reconcile--off'}`}>
        <span>{reconciles ? 'Ledger reconciles' : 'Ledger does NOT match the balance'}</span>
        <span className="mono">
          {euros(ledgerSum)}
          {reconciles ? '' : ` vs ${euros(participant.balance)} on the bracelet`}
        </span>
      </div>
    </div>
  );
}

/**
 * The round a charge paid for.
 *
 * A charge written before the terminals recorded this has no lines, and says so
 * rather than rendering an empty list that reads like "bought nothing". Every
 * charge from an app carrying this change has them, and the rules require the
 * lines to add up to the amount — see `itemisationAddsUp` in `firestore.rules`.
 */
function Lines({ entry }: { entry: Transaction }) {
  if (entry.items.length === 0) {
    return <p className="lines">Itemisation not recorded</p>;
  }
  return (
    <ul className="lines">
      {entry.items.map((line, index) => (
        <li key={`${line.drinkId}-${index}`}>
          {line.quantity} × {line.name}
          {line.quantity > 1 ? ` (${euros(line.unitPrice)} each)` : ''}
        </li>
      ))}
    </ul>
  );
}
