import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
} from 'firebase/firestore';
import { useEffect, useMemo, useState } from 'react';

import { db } from './firebase';
import {
  COLLECTIONS,
  DRINK_FIELDS,
  euros,
  parseEuros,
  MAX_MOVEMENT_REASON,
  MAX_STOCK_ML,
  MAX_STOCK_NAME,
  STOCK_FIELDS,
  STOCK_MOVEMENT_FIELDS,
  slugify,
  toDrink,
  toStockItem,
  toStockMovement,
  toTransaction,
  type Drink,
  type StockItem,
} from './schema';
import { litres, parseLitres, soldByDrink, stockReport, type SoldLine } from './inventory';

// ═══════════════════════════════════════════════════════════════════════════
//  What is left behind the bar.
//
//  **Nothing on this screen is recorded by anybody.** The bar has always written
//  what it sold — itemised, timestamped, append-only — so the only new facts are
//  what was in the store to begin with and what a serving takes out of it.
//  Everything else is derived, which means last night can be recomputed
//  differently next year without the bar having had to remember anything extra.
//
//  Millilitres as integers end to end; litres only on the way to the screen.
//  The arithmetic lives in inventory.ts, where it is tested without a database.
// ═══════════════════════════════════════════════════════════════════════════

export function Stock({ uid }: { uid: string }) {
  const [items, setItems] = useState<StockItem[] | null>(null);
  const [drinks, setDrinks] = useState<Drink[]>([]);
  const [sold, setSold] = useState<SoldLine[]>([]);
  const [moved, setMoved] = useState<Record<string, number>>({});
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const store = query(collection(db, COLLECTIONS.stock), orderBy(STOCK_FIELDS.sortOrder));
    return onSnapshot(
      store,
      (snap) => setItems(snap.docs.flatMap((entry) => toStockItem(entry) ?? [])),
      (cause) => setError(cause.message)
    );
  }, []);

  useEffect(() => {
    const menu = query(collection(db, COLLECTIONS.drinks), orderBy(DRINK_FIELDS.sortOrder));
    return onSnapshot(menu, (snap) => setDrinks(snap.docs.flatMap((entry) => toDrink(entry) ?? [])));
  }, []);

  useEffect(() => {
    // Every charge ever written. A collection-group query needs a rule of its
    // own — a nested match does not authorise one, and the failure is silent.
    return onSnapshot(
      collectionGroup(db, COLLECTIONS.transactions),
      (snap) => setSold(soldByDrink(snap.docs.flatMap((entry) => toTransaction(entry) ?? []))),
      (cause) => setError(cause.message)
    );
  }, []);

  useEffect(() => {
    return onSnapshot(collectionGroup(db, COLLECTIONS.movements), (snap) => {
      const totals: Record<string, number> = {};
      for (const entry of snap.docs) {
        const movement = toStockMovement(entry);
        // `stock/{id}/movements/{mid}` — the item is the grandparent.
        const stockId = entry.ref.parent.parent?.id;
        if (movement && stockId) totals[stockId] = (totals[stockId] ?? 0) + movement.deltaMl;
      }
      setMoved(totals);
    });
  }, []);

  const report = useMemo(
    () => stockReport({ items: items ?? [], drinks, sold, movements: moved }),
    [items, drinks, sold, moved]
  );

  if (error) return <p className="empty">Could not read the store: {error}</p>;
  if (!items) return <p className="empty">Reading the store…</p>;

  return (
    <div className="stack">
      <AddItem existing={items} onError={setError} />

      {items.length === 0 ? (
        <p className="empty">
          Nothing in the store yet. Add what is behind the bar — a keg, a bottle of gin, a
          box of tonic — then give each drink on the menu a recipe in the Bar tab, and this
          page will say what is left.
        </p>
      ) : (
        <table className="table">
          <thead>
            <tr>
              <th>Item</th>
              <th className="num">Started with</th>
              <th className="num">Since</th>
              <th className="num">Poured</th>
              <th className="num">Left</th>
              <th className="num">€ / litre</th>
              <th className="num">Value left</th>
              <th>What is drinking it</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {report.rows.map((row) => {
              const item = items.find((entry) => entry.id === row.id);
              const low = row.fractionLeft !== null && row.fractionLeft <= 0.2;
              return (
                <tr key={row.id}>
                  <td>
                    {row.name}
                    {item && !item.isActive ? <span className="tag tag--quiet">Retired</span> : null}
                  </td>
                  <td className="num mono">{litres(row.openingMl)}</td>
                  <td className="num mono sub">
                    {row.movedMl === 0
                      ? '—'
                      : `${row.movedMl > 0 ? '+' : ''}${litres(row.movedMl)}`}
                  </td>
                  <td className="num mono">{litres(row.consumedMl)}</td>
                  <td className={`num mono ${low || row.remainingMl < 0 ? 'signed--out' : ''}`}>
                    <strong>{litres(row.remainingMl)}</strong>
                    {row.fractionLeft !== null ? (
                      <div className="sub">{Math.round(row.fractionLeft * 100)}% left</div>
                    ) : null}
                  </td>
                  <td className="num">
                    {item ? <CostPerLitre item={item} onError={setError} /> : null}
                  </td>
                  <td className="num mono">
                    {row.remainingValue === null ? (
                      <span className="sub">—</span>
                    ) : (
                      <>
                        {euros(row.remainingValue)}
                        {row.pouredCost !== null && row.pouredCost > 0 ? (
                          <div className="sub">{euros(row.pouredCost)} poured</div>
                        ) : null}
                      </>
                    )}
                  </td>
                  <td className="sub">
                    {row.drawnBy.length === 0
                      ? '—'
                      : row.drawnBy.map((drink) => `${drink.name} ${litres(drink.ml)}`).join(' · ')}
                  </td>
                  <td>{item ? <RowActions item={item} uid={uid} onError={setError} /> : null}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      )}

      <Warnings uncosted={report.uncosted} orphaned={report.orphanedRecipes} drinks={drinks} />
      <Sold sold={sold} />
    </div>
  );
}

/**
 * The two ways this page can lie, said out loud.
 *
 * A drink with no recipe pours nothing, so the store looks healthier than it is
 * — the one direction this must never fail in silently.
 */
function Warnings({
  uncosted,
  orphaned,
  drinks,
}: {
  uncosted: SoldLine[];
  orphaned: { drinkId: string; stockId: string }[];
  drinks: Drink[];
}) {
  if (uncosted.length === 0 && orphaned.length === 0) return null;
  const nameOf = (id: string) => drinks.find((drink) => drink.id === id)?.name ?? id;

  return (
    <div className="card">
      <h2 className="card__title">Not counted against the store</h2>
      {uncosted.length > 0 ? (
        <>
          <p className="sub">
            These sold but have no recipe, so nothing was taken off the store for them. Until
            they have one, everything above reads higher than it really is.
          </p>
          <ul className="lines">
            {uncosted.map((line) => (
              <li key={line.drinkId}>
                <strong>{line.name}</strong> — {line.quantity} sold
              </li>
            ))}
          </ul>
        </>
      ) : null}
      {orphaned.length > 0 ? (
        <p className="sub">
          {orphaned.map((entry) => `${nameOf(entry.drinkId)} → ${entry.stockId}`).join(', ')} —
          a recipe points at something no longer in the store.
        </p>
      ) : null}
    </div>
  );
}

function AddItem({
  existing,
  onError,
}: {
  existing: StockItem[];
  onError: (message: string | null) => void;
}) {
  const [name, setName] = useState('');
  const [amount, setAmount] = useState('');
  const [busy, setBusy] = useState(false);

  const ml = parseLitres(amount);
  const id = slugify(name);
  const clash = existing.some((item) => item.id === id);
  const blocker = !name.trim()
    ? 'Name it'
    : clash
      ? 'Already in the store'
      : ml === null
        ? 'Litres, like 0.7 or 30'
        : ml > MAX_STOCK_ML
          ? 'Over a thousand litres — check that'
          : null;

  async function add() {
    if (blocker || ml === null) return;
    setBusy(true);
    try {
      await setDoc(doc(db, COLLECTIONS.stock, id), {
        [STOCK_FIELDS.name]: name.trim().slice(0, MAX_STOCK_NAME),
        [STOCK_FIELDS.openingMl]: ml,
        [STOCK_FIELDS.sortOrder]: existing.length,
        [STOCK_FIELDS.isActive]: true,
      });
      setName('');
      setAmount('');
      onError(null);
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card">
      <h2 className="card__title">What is behind the bar</h2>
      <div className="drink-form">
        <label className="field">
          <span>Item</span>
          <input
            value={name}
            maxLength={MAX_STOCK_NAME}
            placeholder="Gin"
            onChange={(event) => setName(event.target.value)}
          />
        </label>
        <label className="field">
          <span>Litres to start</span>
          <input
            value={amount}
            inputMode="decimal"
            placeholder="0.7"
            onChange={(event) => setAmount(event.target.value)}
          />
        </label>
        <button className="btn btn--primary" type="button" disabled={!!blocker || busy} onClick={add}>
          {blocker ?? 'Add'}
        </button>
      </div>
    </div>
  );
}

/**
 * A delivery, or a recount. Append-only: "how did we get to four litres" is a
 * question somebody asks next year, and an edited number cannot answer it.
 */
function RowActions({
  item,
  uid,
  onError,
}: {
  item: StockItem;
  uid: string;
  onError: (message: string | null) => void;
}) {
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);

  const ml = parseLitres(amount);

  async function record(sign: 1 | -1) {
    if (ml === null || ml === 0) return;
    setBusy(true);
    try {
      await setDoc(doc(db, COLLECTIONS.stock, item.id, COLLECTIONS.movements, `${Date.now()}`), {
        [STOCK_MOVEMENT_FIELDS.deltaMl]: sign * ml,
        [STOCK_MOVEMENT_FIELDS.reason]: (
          reason.trim() || (sign > 0 ? 'Carried in' : 'Recount found less')
        ).slice(0, MAX_MOVEMENT_REASON),
        [STOCK_MOVEMENT_FIELDS.at]: serverTimestamp(),
        [STOCK_MOVEMENT_FIELDS.by]: uid,
      });
      setAmount('');
      setReason('');
      setOpen(false);
      onError(null);
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  if (confirming) {
    // In the row rather than a native dialog, the same as deleting a drink: a
    // window.confirm cannot be driven by anything automated, and it has nowhere
    // to say what survives.
    return (
      <div className="actions">
        <span className="field__hint">
          Take <strong>{item.name}</strong> out of the store? What was sold stays in the
          ledger, and its deliveries stay recorded.
        </span>
        <button
          className="btn btn--danger"
          type="button"
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            try {
              await deleteDoc(doc(db, COLLECTIONS.stock, item.id));
            } catch (cause) {
              onError(cause instanceof Error ? cause.message : String(cause));
            } finally {
              setBusy(false);
            }
          }}
        >
          Yes, remove
        </button>
        <button className="btn btn--ghost" type="button" onClick={() => setConfirming(false)}>
          Keep it
        </button>
      </div>
    );
  }

  if (!open) {
    return (
      <div className="actions">
        <button className="btn" type="button" onClick={() => setOpen(true)}>
          Carried in
        </button>
        <button className="btn btn--ghost" type="button" onClick={() => setConfirming(true)}>
          Remove
        </button>
      </div>
    );
  }

  return (
    <div className="drink-form">
      <label className="field">
        <span>Litres</span>
        <input
          value={amount}
          inputMode="decimal"
          placeholder="30"
          autoFocus
          onChange={(event) => setAmount(event.target.value)}
        />
      </label>
      <label className="field">
        <span>Why</span>
        <input
          value={reason}
          maxLength={MAX_MOVEMENT_REASON}
          placeholder="A new keg"
          onChange={(event) => setReason(event.target.value)}
        />
      </label>
      <div className="actions">
        <button
          className="btn btn--primary"
          type="button"
          disabled={ml === null || busy}
          onClick={() => record(1)}
        >
          Carried in
        </button>
        <button className="btn" type="button" disabled={ml === null || busy} onClick={() => record(-1)}>
          Found less
        </button>
        <button className="btn btn--ghost" type="button" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </div>
  );
}

function Sold({ sold }: { sold: SoldLine[] }) {
  if (sold.length === 0) return null;
  const total = sold.reduce((count, line) => count + line.quantity, 0);
  return (
    <div className="card">
      <h2 className="card__title">Sold so far</h2>
      <p className="sub">
        Every round the bar has charged — {total} drinks. This is the record the after-festival
        numbers are built from, so it is here rather than only in the history.
      </p>
      <table className="table">
        <thead>
          <tr>
            <th>Drink</th>
            <th className="num">Sold</th>
          </tr>
        </thead>
        <tbody>
          {sold.map((line) => (
            <tr key={line.drinkId}>
              <td>{line.name}</td>
              <td className="num mono">{line.quantity}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * What a litre of it cost, filled in whenever somebody gets to it.
 *
 * Deliberately editable in place and deliberately optional: during the festival
 * the levels are what matter, and the money is a job for the week after. A blank
 * here is "nobody has said", which is why the value column shows a dash rather
 * than zero — a total that quietly counts unknown as free is the sort of number
 * somebody takes to a supplier.
 */
function CostPerLitre({
  item,
  onError,
}: {
  item: StockItem;
  onError: (message: string | null) => void;
}) {
  const asInput = item.costPerLitreCents === null ? '' : (item.costPerLitreCents / 100).toFixed(2);
  const [value, setValue] = useState(asInput);
  const [busy, setBusy] = useState(false);

  // Re-sync when the document changes underneath — another organiser, or this
  // field's own write coming back through the listener.
  useEffect(() => setValue(asInput), [asInput]);

  const trimmed = value.trim();
  const cents = trimmed === '' ? null : parseEuros(trimmed);
  const bad = trimmed !== '' && cents === null;
  const dirty = cents !== item.costPerLitreCents;

  async function save() {
    if (bad || !dirty) return;
    setBusy(true);
    try {
      await setDoc(
        doc(db, COLLECTIONS.stock, item.id),
        {
          [STOCK_FIELDS.name]: item.name,
          [STOCK_FIELDS.openingMl]: item.openingMl,
          [STOCK_FIELDS.sortOrder]: item.sortOrder,
          [STOCK_FIELDS.isActive]: item.isActive,
          // Left out entirely rather than written as null: the rules take the
          // field or its absence, and absence is what "nobody has said" is.
          ...(cents === null ? {} : { [STOCK_FIELDS.costPerLitreCents]: cents }),
        }
      );
      onError(null);
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  return (
    <input
      aria-label={`Cost per litre of ${item.name}`}
      className="price"
      inputMode="decimal"
      placeholder="—"
      value={value}
      disabled={busy}
      onChange={(event) => setValue(event.target.value)}
      onBlur={save}
      onKeyDown={(event) => {
        if (event.key === 'Enter') save();
      }}
    />
  );
}
