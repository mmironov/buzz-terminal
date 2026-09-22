import { doc, onSnapshot } from 'firebase/firestore';
import { useEffect, useState } from 'react';

import { db } from './firebase';
import { COLLECTIONS, type Participant } from './schema';

// ═══════════════════════════════════════════════════════════════════════════
//  What reception recorded about somebody sold a pass at the desk.
//
//  This panel is the only place the email can be read at all. It is not on the
//  participant document — every terminal reads those, the bar included — but in
//  `participants/{id}/contact/details`, which `firestore.rules` opens to
//  reception and the organiser claim and nobody else.
//
//  A field nobody can read is a field that should not have been collected, which
//  is why this exists rather than being left for "later".
// ═══════════════════════════════════════════════════════════════════════════

const DANCE_ROLES: Record<string, string> = {
  leader: 'Leader',
  follower: 'Follower',
};

export function DoorSaleDetails({ person }: { person: Participant }) {
  const [email, setEmail] = useState<string | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'none' | 'refused'>('loading');

  useEffect(() => {
    // Only door sales have one. Everybody from the Sheet keeps their email in
    // the Sheet, which is deliberately the one place it lives for them.
    if (person.source !== 'door') return;
    setState('loading');
    return onSnapshot(
      doc(db, COLLECTIONS.participants, person.id, COLLECTIONS.contact, 'details'),
      (snapshot) => {
        const value = snapshot.exists() ? String(snapshot.data()?.email ?? '') : '';
        setEmail(value);
        setState(snapshot.exists() ? 'ready' : 'none');
      },
      // Distinguished rather than swallowed: "they gave no address" and "this
      // panel is not allowed to read it" look identical if both render blank,
      // and the second one means something is wrong with the rules.
      () => setState('refused')
    );
  }, [person.id, person.source]);

  if (person.source !== 'door') return null;

  return (
    <div className="stack">
      <span className="kicker">Sold at the door</span>
      <table className="ledger">
        <tbody>
          <tr>
            <td>Dances as</td>
            <td className="num">{DANCE_ROLES[person.danceRole] ?? '—'}</td>
          </tr>
          <tr>
            <td>Level</td>
            <td className="num">{person.level || '—'}</td>
          </tr>
          <tr>
            <td>Email</td>
            <td className="num mono">
              {state === 'loading' ? (
                <span className="sub">Reading…</span>
              ) : state === 'refused' ? (
                <span className="field__hint field__hint--bad">Could not read it</span>
              ) : email ? (
                email
              ) : (
                <span className="sub">Not given</span>
              )}
            </td>
          </tr>
        </tbody>
      </table>
      <p className="note">
        The email is kept out of the participant document on purpose: every terminal
        reads those, and the bar has no business holding a mailing list. It lives in
        a subcollection only reception and this panel can read.
      </p>
    </div>
  );
}
