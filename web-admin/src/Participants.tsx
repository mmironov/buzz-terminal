import {
  collection,
  doc,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  updateDoc,
} from 'firebase/firestore';
import { useEffect, useMemo, useState } from 'react';

import { History } from './History';
import { db } from './firebase';
import {
  COLLECTIONS,
  MAX_BLOCK_REASON,
  PARTICIPANT_FIELDS,
  euros,
  shortTime,
  toParticipant,
  type Participant,
} from './schema';

type Filter = 'all' | 'checkedIn' | 'awaiting' | 'blocked';

const FILTERS: { key: Filter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'checkedIn', label: 'On a bracelet' },
  { key: 'awaiting', label: 'Awaiting check-in' },
  { key: 'blocked', label: 'Blocked' },
];

// ═══════════════════════════════════════════════════════════════════════════
//  Everybody who bought a ticket.
//
//  The whole roster is loaded once and filtered in memory, which is the strategy
//  `docs/firestore-schema.md` settles on for a few thousand people: instant to
//  type against, and it makes substring search possible at all — Firestore cannot
//  match "oux" inside "Roux", and a token query would only match from word starts.
//  Past a few thousand this needs the `searchTokens` path instead.
// ═══════════════════════════════════════════════════════════════════════════

export function Participants({ uid }: { uid: string }) {
  const [people, setPeople] = useState<Participant[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<Filter>('all');
  const [openId, setOpenId] = useState<string | null>(null);

  useEffect(() => {
    // Ordered by nameLower, which is a single field and therefore already indexed.
    // A live listener because this panel is open while the festival runs: a
    // check-in at reception should appear here without anybody reloading.
    const roster = query(
      collection(db, COLLECTIONS.participants),
      orderBy(PARTICIPANT_FIELDS.nameLower)
    );
    return onSnapshot(
      roster,
      (snapshot) => {
        setPeople(snapshot.docs.flatMap((entry) => toParticipant(entry) ?? []));
        setError(null);
      },
      (cause) => setError(cause.message)
    );
  }, []);

  const shown = useMemo(() => {
    if (!people) return [];
    const needle = search.trim().toLowerCase();
    return people.filter((person) => {
      switch (filter) {
        case 'checkedIn':
          if (!person.braceletId) return false;
          break;
        case 'awaiting':
          if (person.braceletId) return false;
          break;
        case 'blocked':
          if (!person.isBlocked) return false;
          break;
        case 'all':
          break;
      }
      if (!needle) return true;
      // Name, ticket type, ticket reference and the chip id. The chip matters
      // here in a way it does not on the terminal: an organiser holding a
      // bracelet somebody handed in has the number on it and nothing else.
      return (
        person.name.toLowerCase().includes(needle) ||
        person.ticketType.toLowerCase().includes(needle) ||
        person.ticketRef.toLowerCase().includes(needle) ||
        (person.braceletId ?? '').toLowerCase().includes(needle)
      );
    });
  }, [people, search, filter]);

  if (error) {
    return (
      <p className="empty">
        Could not read the roster: {error}
        <br />
        <span className="sub">
          A permission error here usually means the signed-in account lost its
          organiser role, or the rules have not been deployed yet.
        </span>
      </p>
    );
  }
  if (!people) return <p className="empty">Reading the roster…</p>;

  const blockedCount = people.filter((person) => person.isBlocked).length;

  return (
    <>
      <div className="toolbar">
        <input
          className="search"
          type="search"
          placeholder="Name, ticket, pass type or chip id"
          value={search}
          onChange={(event) => setSearch(event.target.value)}
        />
        <div className="filters">
          {FILTERS.map(({ key, label }) => (
            <button
              key={key}
              type="button"
              aria-pressed={filter === key}
              onClick={() => setFilter(key)}
            >
              {label}
            </button>
          ))}
        </div>
        <span className="count">
          {shown.length} of {people.length}
          {blockedCount > 0 ? ` · ${blockedCount} blocked` : ''}
        </span>
      </div>

      {shown.length === 0 ? (
        <p className="empty">Nobody matches.</p>
      ) : (
        <table className="table">
          <thead>
            <tr>
              <th>Participant</th>
              <th>Pass</th>
              <th>Bracelet</th>
              <th>Checked in</th>
              <th className="num">Balance</th>
              <th>State</th>
            </tr>
          </thead>
          <tbody>
            {shown.map((person) => (
              <Row
                key={person.id}
                person={person}
                uid={uid}
                isOpen={openId === person.id}
                onToggle={() => setOpenId(openId === person.id ? null : person.id)}
              />
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}

function Row({
  person,
  uid,
  isOpen,
  onToggle,
}: {
  person: Participant;
  uid: string;
  isOpen: boolean;
  onToggle: () => void;
}) {
  return (
    <>
      <tr className={isOpen ? 'is-open' : ''}>
        <td>
          <button className="row-button" type="button" onClick={onToggle}>
            {person.name}
          </button>
          <div className="sub mono">{person.ticketRef || person.id}</div>
        </td>
        <td>
          {person.ticketType || '—'}
          {person.country ? <div className="sub">{person.country}</div> : null}
        </td>
        <td className="mono">
          {person.braceletId ?? <span className="tag tag--quiet">Not paired</span>}
        </td>
        <td className="mono sub">{person.braceletId ? shortTime(person.checkedInAt) : '—'}</td>
        <td className="num">{euros(person.balance)}</td>
        <td>
          {person.isBlocked ? (
            <span className="tag tag--blocked">Blocked</span>
          ) : (
            <span className="tag tag--ok">Active</span>
          )}
        </td>
      </tr>

      {isOpen ? (
        <tr className="detail">
          <td colSpan={6}>
            <div className="detail__grid">
              <History participant={person} />
              <BlockPanel person={person} uid={uid} />
            </div>
          </td>
        </tr>
      ) : null}
    </>
  );
}

/**
 * Freeze a bracelet, or thaw it.
 *
 * This is the panel's whole authority over a person. It cannot adjust a balance —
 * `firestore.rules` refuses that from the admin claim, on purpose: money that
 * moved is money a ledger entry accounts for, and a correction that left no trace
 * is exactly what the ledger exists to prevent. If a guest is owed money, reception
 * tops them up and the ledger says so.
 */
function BlockPanel({ person, uid }: { person: Participant; uid: string }) {
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const trimmed = reason.trim();
  const tooLong = trimmed.length > MAX_BLOCK_REASON;

  async function apply(blocked: boolean) {
    setBusy(true);
    setError(null);
    try {
      // Exactly the four fields `isBlockChange()` permits, and nothing else — a
      // fifth key in this object is a PERMISSION_DENIED, not a stray annotation.
      // blockedBy and blockedAt are the audit trail: a block is an organiser
      // decision somebody will ask about afterwards, and `serverTimestamp()` is
      // required rather than merely preferred, because the rule pins it to
      // `request.time`.
      await updateDoc(doc(db, COLLECTIONS.participants, person.id), {
        [PARTICIPANT_FIELDS.isBlocked]: blocked,
        [PARTICIPANT_FIELDS.blockReason]: blocked ? trimmed : null,
        [PARTICIPANT_FIELDS.blockedBy]: uid,
        [PARTICIPANT_FIELDS.blockedAt]: serverTimestamp(),
      });
      setReason('');
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  if (person.isBlocked) {
    return (
      <div className="card stack">
        <p className="card__title">This bracelet is blocked</p>
        <p className="note">
          {person.blockReason ?? 'No reason recorded.'}
        </p>
        <p className="note">
          Every terminal refuses it — no top-up, no drink — and shows that reason to
          whoever is standing at the desk.
        </p>
        {error ? <p className="field__hint field__hint--bad">{error}</p> : null}
        <button className="btn btn--block" type="button" disabled={busy} onClick={() => apply(false)}>
          {busy ? 'Lifting…' : 'Lift the block'}
        </button>
      </div>
    );
  }

  return (
    <div className="card stack">
      <p className="card__title">Block this bracelet</p>
      {person.braceletId ? null : (
        <p className="note">
          Nothing is paired to this person yet, so there is nothing to present at a
          terminal. Blocking now still works and takes effect the moment a chip is
          paired.
        </p>
      )}
      <label className="field">
        <span className="kicker">Reason · shown to staff</span>
        <textarea
          value={reason}
          maxLength={MAX_BLOCK_REASON + 20}
          placeholder="Bracelet handed in at the door, Sat 01:20"
          onChange={(event) => setReason(event.target.value)}
        />
        <span className={`field__hint ${tooLong ? 'field__hint--bad' : ''}`}>
          {tooLong
            ? `${trimmed.length} characters — the limit is ${MAX_BLOCK_REASON}.`
            : 'Required. A terminal shows this verbatim, so write it for whoever is at the desk.'}
        </span>
      </label>
      {error ? <p className="field__hint field__hint--bad">{error}</p> : null}
      <button
        className="btn btn--danger btn--block"
        type="button"
        disabled={busy || trimmed.length === 0 || tooLong}
        onClick={() => apply(true)}
      >
        {busy ? 'Blocking…' : 'Block'}
      </button>
      <p className="note">
        Balances are not editable here, by design. Money that moved is accounted for
        by a ledger entry; a correction with no entry behind it is what the ledger
        exists to prevent.
      </p>
    </div>
  );
}
