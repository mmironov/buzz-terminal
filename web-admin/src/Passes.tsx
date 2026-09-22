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
  DOOR_PASS_FIELDS,
  EVENINGS,
  EVENING_LABELS,
  MAX_PASS_NAME,
  MAX_PASS_PRICE,
  euros,
  parseEuros,
  slugify,
  toDoorPass,
  type DoorPass,
  type EveningName,
} from './schema';

// ═══════════════════════════════════════════════════════════════════════════
//  What reception can sell at the desk.
//
//  The price here is what somebody says out loud and takes in cash or on the
//  card machine. **Nothing in this system charges it.** The bracelet ledger is
//  for money ON a bracelet — top-ups and rounds at the bar — and a pass is not
//  that, so a door sale writes no ledger entry and moves no balance. If door
//  takings ever need counting in the app, that is a new thing to build, not a
//  number to read off this screen.
//
//  The name is the part to be careful with: it is written verbatim onto the
//  buyer as their `ticketType`, and `firestore.rules` checks the two agree. So a
//  pass renamed here changes what future buyers are sold, and leaves everybody
//  already holding one exactly as they were. That is why renaming is allowed at
//  all — the sold pass is a copy, not a reference.
//
//  One row is special: `kind: 'evening'` is the anonymous numbered ticket the
//  terminals have always sold. Reception picks a night instead of typing a
//  buyer's name. Its price is editable here like any other; its behaviour is not.
// ═══════════════════════════════════════════════════════════════════════════

export function Passes() {
  const [passes, setPasses] = useState<DoorPass[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const catalogue = query(
      collection(db, COLLECTIONS.doorPasses),
      orderBy(DOOR_PASS_FIELDS.sortOrder)
    );
    return onSnapshot(
      catalogue,
      (snapshot) => {
        setPasses(snapshot.docs.flatMap((entry) => toDoorPass(entry) ?? []));
        setError(null);
      },
      (cause) => setError(cause.message)
    );
  }, []);

  if (error) return <p className="empty">Could not read the door passes: {error}</p>;
  if (!passes) return <p className="empty">Reading the door passes…</p>;

  const onSale = passes.filter((pass) => pass.isActive);
  const unpriced = onSale.filter((pass) => pass.price === 0);

  return (
    <div className="stack">
      <AddPass existing={passes} onError={setError} />

      <div className="toolbar">
        <span className="count">
          {onSale.length} on sale at the desk
          {passes.length > onSale.length ? ` · ${passes.length - onSale.length} withdrawn` : ''}
          {unpriced.length ? ` · ${unpriced.length} with no price set` : ''}
        </span>
      </div>

      {passes.length === 0 ? (
        <p className="empty">
          Nothing is on sale at the door, so reception cannot sell a pass at all —
          the terminals only offer what is listed here. Add the first one above.
        </p>
      ) : (
        <table className="table table--drinks">
          {/* Wider price column than the drinks table's: this one holds three
              labelled boxes for an evening ticket, not a single figure. */}
          <colgroup>
            <col />
            <col style={{ width: '170px' }} />
            <col style={{ width: '100px' }} />
            <col style={{ width: '80px' }} />
            <col style={{ width: '300px' }} />
          </colgroup>
          <thead>
            <tr>
              <th>Pass</th>
              <th className="num">Price</th>
              <th>At the desk</th>
              <th>Order</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {passes.map((pass, index) => (
              <PassRow
                key={pass.id}
                pass={pass}
                isFirst={index === 0}
                isLast={index === passes.length - 1}
                neighbour={index === 0 ? passes[1] : passes[index - 1]}
                nextNeighbour={passes[index + 1]}
                onError={setError}
              />
            ))}
          </tbody>
        </table>
      )}

      <p className="note">
        Reception sells from this list in this order, and can sell nothing that is
        not on it — <code>firestore.rules</code> checks the pass against this
        collection as the sale is written, so a withdrawn or misspelt pass is
        refused rather than quietly minted. The price is displayed to whoever is
        selling; the money itself is taken at the desk and is not recorded here.
      </p>
    </div>
  );
}

function PassRow({
  pass,
  isFirst,
  isLast,
  neighbour,
  nextNeighbour,
  onError,
}: {
  pass: DoorPass;
  isFirst: boolean;
  isLast: boolean;
  neighbour: DoorPass | undefined;
  nextNeighbour: DoorPass | undefined;
  onError: (message: string) => void;
}) {
  const isEvening = pass.kind === 'evening';
  const [name, setName] = useState(pass.name);
  const [price, setPrice] = useState(centsToInput(pass.price));
  // One box per night for an evening ticket. Seeded from the flat price where a
  // night has no entry of its own, so the three start at what was already being
  // charged rather than at zero.
  const [nights, setNights] = useState(() => nightInputs(pass));
  const [busy, setBusy] = useState(false);
  const [confirmingDelete, setConfirmingDelete] = useState(false);

  useEffect(() => {
    setName(pass.name);
    setPrice(centsToInput(pass.price));
    setNights(nightInputs(pass));
  }, [pass.name, pass.price, pass.prices.friday, pass.prices.saturday, pass.prices.sunday]);

  const cents = parseEuros(price);
  const nightCents = Object.fromEntries(
    EVENINGS.map((night) => [night, parseEuros(nights[night])])
  ) as Record<EveningName, number | null>;

  const trimmed = name.trim();
  const nameOK = trimmed.length > 0 && trimmed.length <= MAX_PASS_NAME;
  const flatPriceOK = cents !== null && cents <= MAX_PASS_PRICE;
  const nightsOK = EVENINGS.every(
    (night) => nightCents[night] !== null && (nightCents[night] as number) <= MAX_PASS_PRICE
  );
  const priceOK = isEvening ? nightsOK : flatPriceOK;
  const dirty =
    trimmed !== pass.name ||
    (isEvening
      ? EVENINGS.some((night) => nightCents[night] !== (pass.prices[night] ?? pass.price))
      : cents !== pass.price);

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

  const ref = doc(db, COLLECTIONS.doorPasses, pass.id);

  return (
    <tr className={pass.isActive ? '' : 'is-off'}>
      <td>
        <input
          aria-label={`Name of ${pass.name}`}
          value={name}
          maxLength={MAX_PASS_NAME}
          onChange={(event) => setName(event.target.value)}
        />
        <div className="sub mono">
          {pass.id}
          {isEvening ? ' · priced per night' : ''}
        </div>
      </td>
      <td className="num">
        {isEvening ? (
          // Friday, Saturday and Sunday can cost different amounts, so this row
          // has three boxes where every other row has one. The terminal shows
          // them beside the nights, not on the list of passes.
          <div className="stack stack--tight">
            {EVENINGS.map((night) => (
              <label key={night} className="night">
                <span className="sub">{EVENING_LABELS[night]}</span>
                <input
                  aria-label={`${EVENING_LABELS[night]} price of ${pass.name}`}
                  className="price"
                  inputMode="decimal"
                  value={nights[night]}
                  onChange={(event) =>
                    setNights((current) => ({ ...current, [night]: event.target.value }))
                  }
                />
              </label>
            ))}
            {nightsOK ? null : <div className="field__hint field__hint--bad">Not a price</div>}
          </div>
        ) : (
          <>
            <input
              aria-label={`Price of ${pass.name}`}
              className="price"
              inputMode="decimal"
              value={price}
              onChange={(event) => setPrice(event.target.value)}
            />
            {flatPriceOK ? null : <div className="field__hint field__hint--bad">Not a price</div>}
            {flatPriceOK && cents === 0 ? (
              // Zero is legal and is occasionally meant — a comp — but far more
              // often it is a row nobody has got round to pricing, and the desk
              // would read "0.00 €" to a paying customer.
              <div className="field__hint">No price set</div>
            ) : null}
          </>
        )}
      </td>
      <td>
        {pass.isActive ? (
          <span className="tag tag--ok">On sale</span>
        ) : (
          <span className="tag tag--quiet">Withdrawn</span>
        )}
      </td>
      <td className="mono sub">
        <div className="actions">
          <button
            className="btn"
            type="button"
            disabled={busy || isFirst || !neighbour}
            title="Earlier in the terminal's list"
            onClick={() => neighbour && run(() => swapOrder(pass, neighbour))}
          >
            ↑
          </button>
          <button
            className="btn"
            type="button"
            disabled={busy || isLast || !nextNeighbour}
            title="Later in the terminal's list"
            onClick={() => nextNeighbour && run(() => swapOrder(pass, nextNeighbour))}
          >
            ↓
          </button>
        </div>
      </td>
      <td>
        {confirmingDelete ? (
          <div className="actions">
            <span className="field__hint">
              Delete <strong>{pass.name}</strong> for good? Everybody already sold one
              keeps it — their pass type is their own copy of this name. If it is
              merely not on sale tonight, withdraw it instead; that can be undone.
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
                    [DOOR_PASS_FIELDS.name]: trimmed,
                    ...(isEvening
                      ? {
                          [DOOR_PASS_FIELDS.prices]: Object.fromEntries(
                            EVENINGS.map((night) => [night, nightCents[night] as number])
                          ),
                          // The flat price stays the fallback, and keeping it in
                          // step with Friday means a terminal that never heard of
                          // per-night prices still quotes something sensible.
                          [DOOR_PASS_FIELDS.price]: nightCents.friday as number,
                        }
                      : { [DOOR_PASS_FIELDS.price]: cents as number }),
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
                pass.isActive
                  ? 'Reception stops being offered this pass'
                  : 'Reception can sell this again'
              }
              onClick={() =>
                run(() => updateDoc(ref, { [DOOR_PASS_FIELDS.isActive]: !pass.isActive }))
              }
            >
              {pass.isActive ? 'Withdraw' : 'Put back on sale'}
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

function AddPass({
  existing,
  onError,
}: {
  existing: DoorPass[];
  onError: (message: string) => void;
}) {
  const [name, setName] = useState('');
  const [price, setPrice] = useState('');
  const [busy, setBusy] = useState(false);

  const cents = parseEuros(price);
  const trimmed = name.trim();
  const nameOK = trimmed.length > 0 && trimmed.length <= MAX_PASS_NAME;
  const priceOK = cents !== null && cents <= MAX_PASS_PRICE;

  async function add() {
    setBusy(true);
    try {
      const id = slugify(trimmed);
      if ((await getDoc(doc(db, COLLECTIONS.doorPasses, id))).exists()) {
        onError(`There is already a pass with the id "${id}". Rename this one.`);
        return;
      }
      const highest = existing.reduce((max, pass) => Math.max(max, pass.sortOrder), -1);
      await setDoc(doc(db, COLLECTIONS.doorPasses, id), {
        [DOOR_PASS_FIELDS.name]: trimmed,
        [DOOR_PASS_FIELDS.price]: cents as number,
        [DOOR_PASS_FIELDS.sortOrder]: highest + 1,
        [DOOR_PASS_FIELDS.isActive]: true,
        // Always an ordinary pass. The anonymous evening ticket is a behaviour
        // the terminals implement, not something to be created by typing a name
        // into this box — there is exactly one of it and it already exists.
        [DOOR_PASS_FIELDS.kind]: 'pass',
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
    <div className="addrow">
      <div className="field">
        <label htmlFor="pass-name">New pass</label>
        <input
          id="pass-name"
          value={name}
          maxLength={MAX_PASS_NAME}
          placeholder="Workshop Pass"
          onChange={(event) => setName(event.target.value)}
        />
      </div>
      <div className="field">
        <label htmlFor="pass-price">Price</label>
        <input
          id="pass-price"
          className="price"
          inputMode="decimal"
          value={price}
          placeholder="120.00"
          onChange={(event) => setPrice(event.target.value)}
        />
        {price && !priceOK ? (
          <div className="field__hint field__hint--bad">
            Euros, at most two decimals — up to {euros(MAX_PASS_PRICE)}
          </div>
        ) : null}
      </div>
      <button
        className="btn btn--primary"
        type="button"
        disabled={busy || !nameOK || !priceOK}
        onClick={() => void add()}
      >
        Add to the desk
      </button>
    </div>
  );
}

/**
 * What the three night boxes start with.
 *
 * A night with no entry of its own shows the flat price, so an organiser
 * opening this for the first time sees 45 · 45 · 45 rather than three blanks —
 * and saving keeps whatever they did not change.
 */
function nightInputs(pass: DoorPass): Record<EveningName, string> {
  return Object.fromEntries(
    EVENINGS.map((night) => [night, centsToInput(pass.prices[night] ?? pass.price)])
  ) as Record<EveningName, string>;
}

/** Swap two rows' `sortOrder`, which is what the arrows do. */
async function swapOrder(a: DoorPass, b: DoorPass) {
  await Promise.all([
    updateDoc(doc(db, COLLECTIONS.doorPasses, a.id), { [DOOR_PASS_FIELDS.sortOrder]: b.sortOrder }),
    updateDoc(doc(db, COLLECTIONS.doorPasses, b.id), { [DOOR_PASS_FIELDS.sortOrder]: a.sortOrder }),
  ]);
}

/** Cents to what somebody types: `20500` → `"205.00"`. */
function centsToInput(cents: number): string {
  return (cents / 100).toFixed(2);
}
