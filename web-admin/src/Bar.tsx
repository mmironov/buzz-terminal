import {
  collection,
  deleteDoc,
  doc,
  getDoc,
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
  DRINK_FIELDS,
  STOCK_FIELDS,
  MAX_DRINK_NAME,
  MAX_DRINK_PRICE,
  parseEuros,
  slugify,
  toDrink,
  toStockItem,
  type Drink,
  type StockItem,
} from './schema';
import { litres } from './inventory';

// ═══════════════════════════════════════════════════════════════════════════
//  The drinks menu.
//
//  Two different ways to stop selling something, and the difference matters
//  enough that the screen names it rather than offering one "delete" and hoping:
//
//    · Take off the menu — `isActive: false`. The bar's query is
//      `isActive == true`, so it disappears from every terminal within a refresh,
//      and it comes back with one click. This is the one for a keg that ran out.
//    · Delete — the document goes. For something entered by mistake. Safe now
//      only because ledger lines snapshot the drink's name and price at the moment
//      of sale, so last night's receipts do not depend on this document existing.
//
//  Prices are cents end to end. `parseEuros` is the only place a typed "4.50"
//  becomes 450, and it refuses a third decimal rather than rounding it.
// ═══════════════════════════════════════════════════════════════════════════

export function Bar() {
  const [drinks, setDrinks] = useState<Drink[] | null>(null);
  const [stock, setStock] = useState<StockItem[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // What is behind the bar, so a drink can say what it takes out of it. Read
    // here rather than passed down: the Stock tab may never have been opened.
    const store = query(collection(db, COLLECTIONS.stock), orderBy(STOCK_FIELDS.sortOrder));
    return onSnapshot(store, (snapshot) =>
      setStock(snapshot.docs.flatMap((entry) => toStockItem(entry) ?? []))
    );
  }, []);

  useEffect(() => {
    // Every drink, active or not — the bar's query filters, this one must not.
    const menu = query(collection(db, COLLECTIONS.drinks), orderBy(DRINK_FIELDS.sortOrder));
    return onSnapshot(
      menu,
      (snapshot) => {
        setDrinks(snapshot.docs.flatMap((entry) => toDrink(entry) ?? []));
        setError(null);
      },
      (cause) => setError(cause.message)
    );
  }, []);

  if (error) return <p className="empty">Could not read the menu: {error}</p>;
  if (!drinks) return <p className="empty">Reading the menu…</p>;

  const active = drinks.filter((drink) => drink.isActive);

  return (
    <div className="stack">
      <AddDrink existing={drinks} onError={setError} />

      <div className="toolbar">
        <span className="count">
          {active.length} on the menu
          {drinks.length > active.length ? ` · ${drinks.length - active.length} taken off` : ''}
        </span>
      </div>

      {drinks.length === 0 ? (
        <p className="empty">
          The menu is empty, so the bar has nothing to sell. Add the first drink above.
        </p>
      ) : (
        <table className="table table--drinks">
          {/* Fixed widths, because the delete confirmation appears inside the last
              cell and a column that resized around it would shuffle every row on
              screen — including the ones somebody is mid-edit in. */}
          <colgroup>
            <col />
            <col style={{ width: '120px' }} />
            <col style={{ width: '110px' }} />
            <col style={{ width: '100px' }} />
            <col style={{ width: '340px' }} />
          </colgroup>
          <thead>
            <tr>
              <th>Drink</th>
              <th className="num">Price</th>
              <th>Uses</th>
              <th>On the menu</th>
              <th>Order</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {drinks.map((drink, index) => (
              <DrinkRow
                key={drink.id}
                drink={drink}
                isFirst={index === 0}
                isLast={index === drinks.length - 1}
                neighbour={index === 0 ? drinks[1] : drinks[index - 1]}
                nextNeighbour={drinks[index + 1]}
                stock={stock}
                onError={setError}
              />
            ))}
          </tbody>
        </table>
      )}

      <p className="note">
        The bar reads <code>isActive == true</code> ordered by this list, so a change
        here reaches the terminals the next time a bartender opens the menu. Prices
        are recorded onto each sale as it happens, so repricing a drink never
        rewrites a receipt from earlier tonight.
      </p>
    </div>
  );
}

/** The row, in place-editable. A price edit is one field and one Save. */
function DrinkRow({
  drink,
  isFirst,
  isLast,
  neighbour,
  nextNeighbour,
  stock,
  onError,
}: {
  drink: Drink;
  isFirst: boolean;
  isLast: boolean;
  neighbour: Drink | undefined;
  nextNeighbour: Drink | undefined;
  stock: StockItem[];
  onError: (message: string) => void;
}) {
  const [name, setName] = useState(drink.name);
  const [price, setPrice] = useState(centsToInput(drink.price));
  const [busy, setBusy] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  // Re-sync when the document changes underneath — another organiser editing the
  // same menu, or this row's own write coming back through the listener.
  useEffect(() => {
    setName(drink.name);
    setPrice(centsToInput(drink.price));
  }, [drink.name, drink.price]);

  const cents = parseEuros(price);
  const trimmed = name.trim();
  const nameOK = trimmed.length > 0 && trimmed.length <= MAX_DRINK_NAME;
  const priceOK = cents !== null && cents <= MAX_DRINK_PRICE;
  const dirty = trimmed !== drink.name || cents !== drink.price;

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

  const ref = doc(db, COLLECTIONS.drinks, drink.id);

  return (
    <tr className={drink.isActive ? '' : 'is-off'}>
      <td>
        <input
          aria-label={`Name of ${drink.name}`}
          value={name}
          maxLength={MAX_DRINK_NAME + 10}
          onChange={(event) => setName(event.target.value)}
        />
        <div className="sub mono">{drink.id}</div>
      </td>
      <td className="num">
        <input
          aria-label={`Price of ${drink.name}`}
          className="price"
          inputMode="decimal"
          value={price}
          onChange={(event) => setPrice(event.target.value)}
        />
        {priceOK ? null : <div className="field__hint field__hint--bad">Not a price</div>}
      </td>
      <td>
        <Recipe drink={drink} stock={stock} onError={onError} />
      </td>
      <td>
        {drink.isActive ? (
          <span className="tag tag--ok">On</span>
        ) : (
          <span className="tag tag--quiet">Off</span>
        )}
      </td>
      <td className="mono sub">
        <div className="actions">
          <button
            className="btn"
            type="button"
            disabled={busy || isFirst || !neighbour}
            title="Earlier in the bar's list"
            onClick={() => neighbour && run(() => swapOrder(drink, neighbour))}
          >
            ↑
          </button>
          <button
            className="btn"
            type="button"
            disabled={busy || isLast || !nextNeighbour}
            title="Later in the bar's list"
            onClick={() => nextNeighbour && run(() => swapOrder(drink, nextNeighbour))}
          >
            ↓
          </button>
        </div>
      </td>
      <td>
        {/* Two clicks to delete, in the row itself, rather than a window.confirm.
            A native dialog cannot be driven by anything automated — it is
            auto-dismissed, so the delete path is untestable and was in fact
            unverified until this replaced it — and it has nowhere to explain that
            "Take off menu" is the reversible one an organiser probably wants. */}
        {confirmingDelete ? (
          <div className="actions">
            <span className="field__hint">
              Delete <strong>{drink.name}</strong> for good? Past receipts keep their own
              copy of the name and price, so history is safe. If it is merely sold out,
              take it off the menu instead — that can be undone.
            </span>
            <button
              className="btn btn--danger"
              type="button"
              disabled={busy}
              onClick={() => run(() => deleteDoc(ref))}
            >
              Yes, delete
            </button>
            <button
              className="btn"
              type="button"
              disabled={busy}
              onClick={() => setConfirmingDelete(false)}
            >
              Keep it
            </button>
          </div>
        ) : (
          <div className="actions">
            <button
              className="btn btn--primary"
              type="button"
              disabled={busy || !dirty || !nameOK || !priceOK}
              onClick={() =>
                run(async () => {
                  await updateDoc(ref, {
                    [DRINK_FIELDS.name]: trimmed,
                    [DRINK_FIELDS.price]: cents as number,
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
              onClick={() =>
                run(() => updateDoc(ref, { [DRINK_FIELDS.isActive]: !drink.isActive }))
              }
            >
              {drink.isActive ? 'Take off menu' : 'Put back on'}
            </button>
            <button
              className="btn btn--danger"
              type="button"
              disabled={busy}
              onClick={() => setConfirmingDelete(true)}
            >
              Delete
            </button>
          </div>
        )}
      </td>
    </tr>
  );
}

function AddDrink({
  existing,
  onError,
}: {
  existing: Drink[];
  onError: (message: string) => void;
}) {
  const [name, setName] = useState('');
  const [price, setPrice] = useState('');
  const [busy, setBusy] = useState(false);

  const cents = parseEuros(price);
  const trimmed = name.trim();
  const nameOK = trimmed.length > 0 && trimmed.length <= MAX_DRINK_NAME;
  const priceOK = cents !== null && cents <= MAX_DRINK_PRICE;

  async function add() {
    setBusy(true);
    try {
      const id = slugify(trimmed);
      // A readable id is worth a round trip to protect: `beer` reconciles by eye,
      // and silently overwriting an existing drink — including a deactivated one
      // still named in last night's receipts — would be the wrong kind of quiet.
      if ((await getDoc(doc(db, COLLECTIONS.drinks, id))).exists()) {
        onError(`There is already a drink with the id "${id}". Rename this one.`);
        return;
      }
      const highest = existing.reduce((max, drink) => Math.max(max, drink.sortOrder), -1);
      await setDoc(doc(db, COLLECTIONS.drinks, id), {
        [DRINK_FIELDS.name]: trimmed,
        [DRINK_FIELDS.price]: cents as number,
        [DRINK_FIELDS.sortOrder]: highest + 1,
        [DRINK_FIELDS.isActive]: true,
      });
      setName('');
      setPrice('');
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card">
      <p className="card__title">Add a drink</p>
      <div className="drink-form">
        <label className="field">
          <span className="kicker">Name</span>
          <input
            value={name}
            maxLength={MAX_DRINK_NAME + 10}
            placeholder="Gin &amp; Tonic"
            onChange={(event) => setName(event.target.value)}
          />
          {trimmed ? <span className="field__hint mono">id: {slugify(trimmed)}</span> : null}
        </label>
        <label className="field">
          <span className="kicker">Price €</span>
          <input
            inputMode="decimal"
            value={price}
            placeholder="6.00"
            onChange={(event) => setPrice(event.target.value)}
          />
          {price && !priceOK ? (
            <span className="field__hint field__hint--bad">Two decimals at most</span>
          ) : null}
        </label>
        <button
          className="btn btn--primary"
          type="button"
          disabled={busy || !nameOK || !priceOK}
          onClick={() => void add()}
        >
          {busy ? 'Adding…' : 'Add'}
        </button>
      </div>
    </div>
  );
}

/**
 * Trade two drinks' positions in the bar's list.
 *
 * Two writes rather than a batch: the rules validate each drink document on its
 * own, there is no invariant spanning the pair, and a half-applied swap is a menu
 * in a slightly odd order rather than anything that costs money. Not worth the
 * ceremony a batch would add.
 */
async function swapOrder(a: Drink, b: Drink): Promise<void> {
  await updateDoc(doc(db, COLLECTIONS.drinks, a.id), { [DRINK_FIELDS.sortOrder]: b.sortOrder });
  await updateDoc(doc(db, COLLECTIONS.drinks, b.id), { [DRINK_FIELDS.sortOrder]: a.sortOrder });
}

/** 450 → `"4.50"`, for an editable field. */
function centsToInput(cents: number): string {
  return `${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, '0')}`;
}

/**
 * What one serving takes out of the store.
 *
 * Typed in millilitres rather than litres: a gin and tonic is 50 ml of gin, and
 * "0.05" is a number nobody wants to type forty times on a Friday. The store
 * itself is entered in litres, because that is how a keg arrives — the two units
 * meet here, and both become integer millilitres before anything is written.
 *
 * A drink with no recipe is a real state, not a zero: the Stock tab lists what
 * sold uncosted rather than quietly pretending those drinks poured nothing.
 */
function Recipe({
  drink,
  stock,
  onError,
}: {
  drink: Drink;
  stock: StockItem[];
  onError: (message: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState(false);

  const summary = Object.entries(drink.recipe)
    .map(([stockId, ml]) => {
      const item = stock.find((entry) => entry.id === stockId);
      return `${litres(ml)} ${item?.name ?? stockId}`;
    })
    .join(' · ');

  if (stock.length === 0) {
    return <span className="sub">Nothing in the store yet</span>;
  }

  if (!editing) {
    return (
      <div className="actions">
        <span className={summary ? 'sub' : 'field__hint'}>{summary || 'Not costed'}</span>
        <button
          className="btn"
          type="button"
          onClick={() => {
            setDraft(
              Object.fromEntries(
                stock.map((item) => [item.id, drink.recipe[item.id] ? String(drink.recipe[item.id]) : ''])
              )
            );
            setEditing(true);
          }}
        >
          {summary ? 'Edit' : 'Cost it'}
        </button>
      </div>
    );
  }

  const parsed: Record<string, number> = {};
  let bad = false;
  for (const [stockId, value] of Object.entries(draft)) {
    const text = value.trim();
    if (!text) continue;
    const ml = Number(text);
    if (!Number.isInteger(ml) || ml <= 0) {
      bad = true;
      continue;
    }
    parsed[stockId] = ml;
  }

  async function save() {
    setBusy(true);
    try {
      await updateDoc(doc(db, COLLECTIONS.drinks, drink.id), { [DRINK_FIELDS.recipe]: parsed });
      setEditing(false);
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="recipe">
      {stock.map((item) => (
        <label className="recipe__line" key={item.id}>
          <input
            aria-label={`Millilitres of ${item.name} in ${drink.name}`}
            className="price"
            inputMode="numeric"
            placeholder="0"
            value={draft[item.id] ?? ''}
            onChange={(event) => setDraft({ ...draft, [item.id]: event.target.value })}
          />
          <span>ml {item.name}</span>
        </label>
      ))}
      <div className="actions">
        <button className="btn btn--primary" type="button" disabled={busy || bad} onClick={save}>
          {bad ? 'Whole millilitres' : 'Save'}
        </button>
        <button className="btn btn--ghost" type="button" onClick={() => setEditing(false)}>
          Cancel
        </button>
      </div>
    </div>
  );
}
