import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  onSnapshot,
  orderBy,
  query,
  setDoc,
  updateDoc,
} from 'firebase/firestore';
import { useEffect, useState } from 'react';

import { db } from './firebase';
import {
  COLLECTIONS,
  MAX_PASS_NAME,
  MAX_PASS_PRICE,
  PAYMENT_METHOD_LABELS,
  SPECIAL_SESSION_FIELDS,
  euros,
  parseEuros,
  slugify,
  toSessionSale,
  toSpecialSession,
  type SessionSale,
  type SpecialSession,
} from './schema';

// ═══════════════════════════════════════════════════════════════════════════
//  The extra classes: Lindy Hop with Sakarias & Elice, Jazz with Patrik.
//
//  **Not passes**, which is why they are not in the Door passes tab. A class
//  admits nobody, creates no participant and is never sold at the door — it is
//  added to somebody who is already here, from their own screen, and everybody
//  gets at most one.
//
//  They lived in `doorPasses` behind a `kind` for one afternoon, and everything
//  that followed from it — filtering them out of the door picker, a rule
//  stopping a class being sold as a ticket, a row labelled "not a pass" in a
//  list of passes — was work spent keeping two different things apart in one
//  place. This tab is the cheaper answer.
// ═══════════════════════════════════════════════════════════════════════════

export function Sessions() {
  const [sessions, setSessions] = useState<SpecialSession[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const catalogue = query(
      collection(db, COLLECTIONS.specialSessions),
      orderBy(SPECIAL_SESSION_FIELDS.sortOrder)
    );
    return onSnapshot(
      catalogue,
      (snapshot) => {
        setSessions(snapshot.docs.flatMap((entry) => toSpecialSession(entry) ?? []));
        setError(null);
      },
      (cause) => setError(cause.message)
    );
  }, []);

  if (error) return <p className="empty">Could not read the sessions: {error}</p>;
  if (!sessions) return <p className="empty">Reading the sessions…</p>;

  const onSale = sessions.filter((session) => session.isActive);

  return (
    <div className="stack">
      <AddSession existing={sessions} onError={setError} />

      <div className="toolbar">
        <span className="count">
          {onSale.length} on sale
          {sessions.length > onSale.length
            ? ` · ${sessions.length - onSale.length} withdrawn`
            : ''}
        </span>
      </div>

      {sessions.length === 0 ? (
        <p className="empty">
          No classes yet, so the participant screen shows nothing. Add the first
          one above — reception can then add it to somebody who is already here.
        </p>
      ) : (
        <table className="table table--drinks">
          <colgroup>
            <col />
            <col style={{ width: '120px' }} />
            <col style={{ width: '110px' }} />
            <col style={{ width: '260px' }} />
          </colgroup>
          <thead>
            <tr>
              <th>Class</th>
              <th className="num">Price</th>
              <th>On sale</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {sessions.map((session) => (
              <SessionRow key={session.id} session={session} onError={setError} />
            ))}
          </tbody>
        </table>
      )}

      <Takings onError={setError} />

      <p className="note">
        A class is added to a participant from their own screen, never sold at the
        door — it admits nobody and creates nobody. Everybody gets at most one:
        the sale lives at a fixed path, so a second one is refused by
        <code> firestore.rules</code> rather than by the screen. The price here is
        what the desk collects and says out loud; what it actually took is
        recorded on each sale and totalled below.
      </p>
    </div>
  );
}

function SessionRow({
  session,
  onError,
}: {
  session: SpecialSession;
  onError: (message: string) => void;
}) {
  const [name, setName] = useState(session.name);
  const [price, setPrice] = useState((session.price / 100).toFixed(2));
  const [busy, setBusy] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  useEffect(() => {
    setName(session.name);
    setPrice((session.price / 100).toFixed(2));
  }, [session.name, session.price]);

  const cents = parseEuros(price);
  const trimmed = name.trim();
  const valid = trimmed.length > 0 && trimmed.length <= MAX_PASS_NAME;
  const priceOK = cents !== null && cents <= MAX_PASS_PRICE;
  const dirty = trimmed !== session.name || cents !== session.price;

  async function run(work: () => Promise<void>) {
    setBusy(true);
    try {
      await work();
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  const ref = doc(db, COLLECTIONS.specialSessions, session.id);

  return (
    <tr className={session.isActive ? '' : 'is-off'}>
      <td>
        <input
          aria-label={`Name of ${session.name}`}
          value={name}
          maxLength={MAX_PASS_NAME}
          onChange={(event) => setName(event.target.value)}
        />
        {/* The name is written onto every sale as it happens, so renaming a
            class changes what the next sale records and nothing that already
            happened. The panel's totals group by the recorded name. */}
        <div className="sub mono">{session.id}</div>
      </td>
      <td className="num">
        <input
          className="price"
          aria-label={`Price of ${session.name}`}
          value={price}
          inputMode="decimal"
          onChange={(event) => setPrice(event.target.value)}
        />
      </td>
      <td>
        <span className={session.isActive ? 'tag tag--ok' : 'tag tag--quiet'}>
          {session.isActive ? 'On sale' : 'Withdrawn'}
        </span>
      </td>
      <td>
        <div className="actions">
          <button
            className="btn btn--primary"
            type="button"
            disabled={busy || !valid || !priceOK || !dirty}
            onClick={() =>
              run(async () => {
                if (cents === null) return;
                await updateDoc(ref, {
                  [SPECIAL_SESSION_FIELDS.name]: trimmed,
                  [SPECIAL_SESSION_FIELDS.price]: cents,
                });
              })
            }
          >
            Save
          </button>
          <button
            className="btn"
            type="button"
            disabled={busy}
            title={
              session.isActive
                ? 'Reception stops being offered it; sales already recorded stay'
                : 'Offer it again'
            }
            onClick={() =>
              run(() =>
                updateDoc(ref, { [SPECIAL_SESSION_FIELDS.isActive]: !session.isActive })
              )
            }
          >
            {session.isActive ? 'Withdraw' : 'Put back on sale'}
          </button>
          {confirmingDelete ? (
            <>
              <div className="field__hint">
                Deleting removes the class itself. Sales already recorded keep the
                name and price they were sold at — withdrawing is the reversible one.
              </div>
              <button
                className="btn btn--danger"
                type="button"
                disabled={busy}
                onClick={() => run(() => deleteDoc(ref))}
              >
                Delete for good
              </button>
              <button className="btn" type="button" onClick={() => setConfirmingDelete(false)}>
                Keep it
              </button>
            </>
          ) : (
            <button className="btn" type="button" onClick={() => setConfirmingDelete(true)}>
              Delete
            </button>
          )}
        </div>
      </td>
    </tr>
  );
}

function AddSession({
  existing,
  onError,
}: {
  existing: SpecialSession[];
  onError: (message: string) => void;
}) {
  const [name, setName] = useState('');
  const [price, setPrice] = useState('');
  const [busy, setBusy] = useState(false);

  const trimmed = name.trim();
  const cents = parseEuros(price);
  const id = slugify(trimmed);
  const clashes = existing.some((session) => session.id === id);
  const valid =
    trimmed.length > 0 && trimmed.length <= MAX_PASS_NAME && cents !== null && cents <= MAX_PASS_PRICE;

  return (
    <div className="card">
      <h2 className="card__title">A class reception can add</h2>
      <div className="drink-form">
        <label className="field">
          <span>Name</span>
          <input
            value={name}
            maxLength={MAX_PASS_NAME}
            placeholder="Jazz with Patrik"
            onChange={(event) => setName(event.target.value)}
          />
        </label>
        <label className="field">
          <span>Price</span>
          <input
            value={price}
            inputMode="decimal"
            placeholder="25.00"
            onChange={(event) => setPrice(event.target.value)}
          />
        </label>
        <button
          className="btn btn--primary"
          type="button"
          disabled={busy || !valid || clashes}
          onClick={async () => {
            if (cents === null) return;
            setBusy(true);
            try {
              await setDoc(doc(db, COLLECTIONS.specialSessions, id), {
                [SPECIAL_SESSION_FIELDS.name]: trimmed,
                [SPECIAL_SESSION_FIELDS.price]: cents,
                [SPECIAL_SESSION_FIELDS.sortOrder]: existing.length,
                [SPECIAL_SESSION_FIELDS.isActive]: true,
              });
              setName('');
              setPrice('');
            } catch (cause) {
              onError(cause instanceof Error ? cause.message : String(cause));
            } finally {
              setBusy(false);
            }
          }}
        >
          Add the class
        </button>
      </div>
      {clashes ? (
        <p className="field__hint field__hint--bad">
          There is already a class with that name.
        </p>
      ) : null}
    </div>
  );
}

/**
 * What the desk has taken for classes.
 *
 * A collection-group read, because a class bought lives under the person who
 * bought it — `participants/{id}/sessions/booked` — and there is no other place
 * it could sensibly live: it is as much a fact about them as their merch. The
 * panel reads across all of them to total the money.
 */
function Takings({ onError }: { onError: (message: string) => void }) {
  const [sales, setSales] = useState<SessionSale[] | null>(null);

  useEffect(() => {
    return onSnapshot(
      collectionGroup(db, COLLECTIONS.sessions),
      (snapshot) => setSales(snapshot.docs.flatMap((entry) => toSessionSale(entry) ?? [])),
      (cause) => onError(cause.message)
    );
  }, [onError]);

  if (!sales || sales.length === 0) return null;

  const byClass = new Map<string, { count: number; cash: number; card: number }>();
  for (const sale of sales) {
    const row = byClass.get(sale.name) ?? { count: 0, cash: 0, card: 0 };
    row.count += 1;
    row[sale.method] += sale.price;
    byClass.set(sale.name, row);
  }
  const rows = [...byClass.entries()].sort((a, b) => b[1].count - a[1].count);
  const total = rows.reduce(
    (sum, [, row]) => ({
      count: sum.count + row.count,
      cash: sum.cash + row.cash,
      card: sum.card + row.card,
    }),
    { count: 0, cash: 0, card: 0 }
  );

  return (
    <div className="stack">
      <h2 className="card__title">Sold so far</h2>
      <table className="table">
        <colgroup>
          <col />
          <col style={{ width: '80px' }} />
          <col style={{ width: '120px' }} />
          <col style={{ width: '120px' }} />
          <col style={{ width: '120px' }} />
        </colgroup>
        <thead>
          <tr>
            <th>Class</th>
            <th className="num">Sold</th>
            <th className="num">{PAYMENT_METHOD_LABELS.cash}</th>
            <th className="num">{PAYMENT_METHOD_LABELS.card}</th>
            <th className="num">Total</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(([name, row]) => (
            <tr key={name}>
              {/* The name each sale recorded, not the catalogue's current one:
                  renaming a class does not rewrite what was sold under the old
                  name, so a rename shows up here as two rows rather than as
                  history quietly changing. */}
              <td>{name}</td>
              <td className="num">{row.count}</td>
              <td className="num">{euros(row.cash)}</td>
              <td className="num">{euros(row.card)}</td>
              <td className="num">{euros(row.cash + row.card)}</td>
            </tr>
          ))}
          <tr>
            <td className="name">All classes</td>
            <td className="num name">{total.count}</td>
            <td className="num name">{euros(total.cash)}</td>
            <td className="num name">{euros(total.card)}</td>
            <td className="num name">{euros(total.cash + total.card)}</td>
          </tr>
        </tbody>
      </table>
      <p className="note">
        The cash column is what should be in the box; the card column is what the
        reader's own report should say. Each sale is written once and cannot be
        edited — the rules refuse an update — so what is here is what the desk
        recorded at the time.
      </p>
    </div>
  );
}
