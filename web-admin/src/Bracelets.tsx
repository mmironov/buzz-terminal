import { collection, deleteDoc, doc, onSnapshot, orderBy, query, setDoc } from 'firebase/firestore';
import { useEffect, useMemo, useState } from 'react';

import { db } from './firebase';
import {
  BRACELET_COLOUR_FIELDS,
  COLLECTIONS,
  EVENING_LABELS,
  MAX_COLOUR_NAME,
  MAX_PASS_PRICE,
  PAYMENT_METHOD_LABELS,
  SETTINGS,
  WRISTBANDS,
  euros,
  parseEuros,
  parseHexColour,
  shortTime,
  toBracelet,
  toBraceletColour,
  toParticipant,
  wristbandFor,
  type Bracelet,
  type BraceletColour,
  type Participant,
  type Wristband,
} from './schema';

// ═══════════════════════════════════════════════════════════════════════════
//  Which colour wristband each pile at reception is.
//
//  **Ten rows, written down, in the order the organisers gave them** — see
//  WRISTBANDS in schema.ts. Flat: no fallback row, no level nested under a pass
//  type, nothing that appears or disappears with the roster.
//
//  It used to be derived from whatever pass types people held, and both halves
//  of that were wrong for the job. A pass type nobody had bought yet had no row
//  at all, so the Jazz Performance Track could not be given a colour before the
//  first person bought one; and the two pass types that split by level also had
//  an "any level" row above them, which read as a second, competing answer —
//  somebody's way out of it was to set Full Pass to white and call it "No
//  color".
//
//  What derivation bought was that nothing could be stranded. That is kept, in
//  two places rather than by building the table out of the roster: a colour
//  matching none of the ten is listed underneath so it can be cleared, and
//  people matching none of the ten are counted so a free-text pass type in the
//  Sheet cannot quietly leave somebody with no colour.
// ═══════════════════════════════════════════════════════════════════════════

/** A sensible starting colour for a wristband nobody has coloured yet. */
const DEFAULT_COLOUR = '#1E6BB8';

interface Row {
  band: Wristband;
  /** How many people would be handed this wristband. */
  holders: number;
  colour: BraceletColour | null;
}

export function Bracelets() {
  const [colours, setColours] = useState<BraceletColour[] | null>(null);
  const [counts, setCounts] = useState<Map<string, number> | null>(null);
  /** The pass types and levels nobody's wristband covers, with their counts. */
  const [strays, setStrays] = useState<Map<string, number> | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const mappings = query(
      collection(db, COLLECTIONS.braceletColours),
      orderBy(BRACELET_COLOUR_FIELDS.passType)
    );
    return onSnapshot(
      mappings,
      (snapshot) => {
        setColours(snapshot.docs.flatMap((entry) => toBraceletColour(entry) ?? []));
        setError(null);
      },
      (cause) => setError(cause.message)
    );
  }, []);

  useEffect(() => {
    // The whole roster, only to count who gets which wristband. The Participants
    // tab already loads it; a few thousand documents is the strategy this panel
    // settles on everywhere else.
    return onSnapshot(
      collection(db, COLLECTIONS.participants),
      (snapshot) => {
        const tally = new Map<string, number>();
        const unmatched = new Map<string, number>();
        for (const entry of snapshot.docs) {
          const person = toParticipant(entry);
          if (!person || (!person.ticketType && !person.evening)) continue;
          const bump = (map: Map<string, number>, key: string) =>
            map.set(key, (map.get(key) ?? 0) + 1);
          // The same decision the apps make, in the same order, so these counts
          // are what the phones will do rather than a second opinion about it.
          const band = wristbandFor(person);
          if (band) bump(tally, band.id);
          else bump(unmatched, [person.ticketType, person.level].filter(Boolean).join(' · '));
        }
        setCounts(tally);
        setStrays(unmatched);
      },
      (cause) => setError(cause.message)
    );
  }, []);

  const { rows, leftovers } = useMemo((): {
    rows: Row[];
    leftovers: BraceletColour[];
  } => {
    if (!colours || !counts) return { rows: [], leftovers: [] };

    // A colour is filed under the wristband it would colour, by its fields and
    // never by its document id: the id is derived, and one that disagreed with
    // its contents would land the colour on the wrong pile here while matching
    // somebody else entirely on a phone.
    const byBand = new Map<string, BraceletColour>();
    const leftovers: BraceletColour[] = [];
    for (const colour of colours) {
      const band = wristbandFor({
        ticketType: colour.passType,
        level: colour.level,
        evening: colour.evening,
      });
      // `wristbandFor` answers with the *fallback* row for a pass type when the
      // level does not match one, which is right for a person and wrong for a
      // colour: a `Full Pass · Other` colour is not the Full Pass INT row.
      const exact =
        band &&
        (colour.evening
          ? band.evening === colour.evening.trim().toLowerCase()
          : (band.level ?? '').toLowerCase() === colour.level.trim().toLowerCase());
      if (band && exact) byBand.set(band.id, colour);
      else leftovers.push(colour);
    }

    return {
      rows: WRISTBANDS.map((band) => ({
        band,
        holders: counts.get(band.id) ?? 0,
        colour: byBand.get(band.id) ?? null,
      })),
      leftovers,
    };
  }, [colours, counts]);

  if (error) return <p className="empty">Could not read the colours: {error}</p>;
  if (!colours || !counts) return <p className="empty">Reading the roster…</p>;

  const set = rows.filter((row) => row.colour).length;
  // People whose own wristband has no colour yet. Not the same as the strays
  // below, who have no wristband at all.
  const waiting = rows
    .filter((row) => !row.colour)
    .reduce((total, row) => total + row.holders, 0);

  return (
    <div className="stack">
      <div className="toolbar">
        <span className="count">
          {set} of {rows.length} coloured
          {waiting > 0
            ? ` · ${waiting} ${waiting === 1 ? 'person' : 'people'} waiting on one`
            : ''}
        </span>
      </div>

      <table className="table table--colours">
        <colgroup>
          <col />
          <col style={{ width: '90px' }} />
          <col style={{ width: '190px' }} />
          <col style={{ width: '180px' }} />
          <col style={{ width: '230px' }} />
        </colgroup>
        <thead>
          <tr>
            <th>Wristband</th>
            <th className="num">People</th>
            <th>Colour</th>
            <th>Called</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <ColourRow key={row.band.id} row={row} onError={setError} />
          ))}
        </tbody>
      </table>

      <Strays strays={strays} />
      <Leftovers leftovers={leftovers} onError={setError} />
      <Replacements onError={setError} />

      <p className="note">
        One row per pile of wristbands, and nothing else. Paste a hex into the box
        beside the swatch, with or without the <span className="mono">#</span>.
        A row left without a colour simply shows no colour on a phone; nothing
        breaks, and nobody is told the wrong wristband. The three evening rows are
        matched on the night — all three are sold as one pass type, so the night is
        the only thing that tells them apart.
      </p>
    </div>
  );
}

/**
 * People no wristband covers: a Full Pass with no level, or one of the Sheet's
 * free-text pass types like `Full Pass - 205 € (Upgrade from Party)`.
 *
 * This is what a table built out of the roster gave for free, and it is the one
 * thing worth keeping from it. Left unsaid, the first anybody would know is
 * somebody standing at the desk with no colour on their screen.
 */
function Strays({ strays }: { strays: Map<string, number> | null }) {
  if (!strays || strays.size === 0) return null;
  const total = [...strays.values()].reduce((sum, count) => sum + count, 0);

  return (
    <p className="note note--warn">
      <strong>
        {total} {total === 1 ? 'person matches' : 'people match'} none of these rows
      </strong>{' '}
      and will show no colour at the desk:{' '}
      {[...strays.entries()]
        .sort((a, b) => b[1] - a[1])
        .map(([what, count]) => `${what || '(no pass type)'} — ${count}`)
        .join(', ')}
      . Either their pass type is written differently in the Sheet, or they have no
      level where the wristband needs one.
    </p>
  );
}

/**
 * Colours that match none of the ten: a mapping made before this list existed,
 * or a level colour on a pass type that is no longer split by level.
 *
 * They are shown rather than hidden because a document nobody can see is still
 * deciding somebody's colour on a phone — that is exactly how `Full Pass` ended
 * up white and called "No color".
 */
function Leftovers({
  leftovers,
  onError,
}: {
  leftovers: BraceletColour[];
  onError: (message: string) => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  if (leftovers.length === 0) return null;

  async function clear(id: string) {
    setBusy(id);
    try {
      await deleteDoc(doc(db, COLLECTIONS.braceletColours, id));
    } catch (cause) {
      onError(cause instanceof Error ? cause.message : String(cause));
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="stack">
      <h2 className="card__title">Colours matching no wristband</h2>
      <table className="table">
        <tbody>
          {leftovers.map((colour) => (
            <tr key={colour.id} className="is-off">
              <td>
                {[colour.passType, colour.level, colour.evening].filter(Boolean).join(' · ')}
                <div className="sub mono">{colour.id}</div>
              </td>
              <td style={{ width: '190px' }}>
                <div className="colour">
                  <span
                    className="swatch"
                    style={{ background: colour.colour }}
                    aria-hidden="true"
                  />
                  <span className="mono">{colour.colour}</span>
                </div>
              </td>
              <td style={{ width: '180px' }}>{colour.name}</td>
              <td style={{ width: '230px' }}>
                <button
                  className="btn"
                  type="button"
                  disabled={busy === colour.id}
                  title="The terminals stop using this colour for anybody"
                  onClick={() => clear(colour.id)}
                >
                  Clear
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="note">
        These are still live: the apps read every colour document, so one of these
        can be what somebody is shown even though no row above claims it. Clearing
        them is safe once the rows above say what they should.
      </p>
    </div>
  );
}

/**
 * Wristbands that were replaced, and what the desk took for them.
 *
 * Reads the whole `bracelets` collection — one document per wristband ever
 * issued, a few hundred at most — because the two halves of a replacement live
 * on two different chips: the reason is on the one that died, the fee is on the
 * one that took over. Joined here by participant.
 *
 * The fee an organiser sets lives at the top of this block, because this is the
 * tab about wristbands and it is the only number the replacement flow needs.
 */
function Replacements({ onError }: { onError: (message: string) => void }) {
  const [bracelets, setBracelets] = useState<Bracelet[] | null>(null);
  const [people, setPeople] = useState<Map<string, Participant>>(new Map());
  const [fee, setFee] = useState<number | null>(null);
  const [feeInput, setFeeInput] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    return onSnapshot(
      collection(db, COLLECTIONS.bracelets),
      (snapshot) => setBracelets(snapshot.docs.flatMap((entry) => toBracelet(entry) ?? [])),
      (cause) => onError(cause.message)
    );
  }, [onError]);

  useEffect(() => {
    return onSnapshot(
      collection(db, COLLECTIONS.participants),
      (snapshot) => {
        const byId = new Map<string, Participant>();
        for (const entry of snapshot.docs) {
          const person = toParticipant(entry);
          if (person) byId.set(person.id, person);
        }
        setPeople(byId);
      },
      (cause) => onError(cause.message)
    );
  }, [onError]);

  useEffect(() => {
    return onSnapshot(
      doc(db, COLLECTIONS.settings, SETTINGS.braceletsDocumentId),
      (snapshot) => {
        const cents = snapshot.data()?.[SETTINGS.replacementFee];
        setFee(typeof cents === 'number' ? Math.trunc(cents) : null);
      },
      (cause) => onError(cause.message)
    );
  }, [onError]);

  // What the box shows: whatever is being typed, else what is configured, else
  // nothing — a blank field for a festival that has not set a fee.
  const shown = feeInput ?? (fee === null ? '' : (fee / 100).toFixed(2));
  const parsed = parseEuros(shown);
  const feeValid = parsed !== null && parsed <= MAX_PASS_PRICE;
  const feeDirty = parsed !== fee;

  const replaced = (bracelets ?? [])
    .filter((chip) => chip.invalidatedAt !== null)
    .sort((a, b) => (b.invalidatedAt?.getTime() ?? 0) - (a.invalidatedAt?.getTime() ?? 0));

  // The fee is on the wristband that took over, so it is found by owner: the
  // one chip of theirs that is still live and carries a fee.
  const feeFor = (participantId: string) =>
    (bracelets ?? []).find(
      (chip) => chip.participantId === participantId && chip.replacementFee !== null
    ) ?? null;

  const takings = (bracelets ?? []).reduce(
    (sum, chip) => {
      if (chip.replacementFee === null || chip.replacementMethod === null) return sum;
      return { ...sum, [chip.replacementMethod]: sum[chip.replacementMethod] + chip.replacementFee };
    },
    { cash: 0, card: 0 }
  );

  return (
    <div className="stack">
      <h2 className="card__title">Replacing a lost wristband</h2>

      <div className="drink-form">
        <label className="field">
          <span>What a replacement costs</span>
          <input
            value={shown}
            inputMode="decimal"
            placeholder="1.00"
            onChange={(event) => setFeeInput(event.target.value)}
          />
        </label>
        <div />
        <button
          className="btn btn--primary"
          type="button"
          disabled={busy || !feeValid || !feeDirty}
          onClick={async () => {
            if (parsed === null) return;
            setBusy(true);
            try {
              await setDoc(doc(db, COLLECTIONS.settings, SETTINGS.braceletsDocumentId), {
                [SETTINGS.replacementFee]: parsed,
              });
              setFeeInput(null);
            } catch (cause) {
              onError(cause instanceof Error ? cause.message : String(cause));
            } finally {
              setBusy(false);
            }
          }}
        >
          Save the fee
        </button>
      </div>

      <p className="note">
        Reception can charge this when it replaces a wristband, or waive it — a
        snapped clasp is the festival's fault. It is taken at the desk in cash or
        on the card machine and <strong>does not touch the balance</strong>: the
        ledger stays the record of what somebody has spent at the bar. Set it to
        nothing and the desk is offered no fee at all.
      </p>

      {replaced.length === 0 ? null : (
        <>
          <table className="table">
            <colgroup>
              <col />
              <col style={{ width: '150px' }} />
              <col style={{ width: '120px' }} />
              <col style={{ width: '140px' }} />
            </colgroup>
            <thead>
              <tr>
                <th>Guest &amp; reason</th>
                <th>Old bracelet</th>
                <th>Replaced</th>
                <th className="num">Fee</th>
              </tr>
            </thead>
            <tbody>
              {replaced.map((chip) => {
                const person = people.get(chip.participantId);
                const paid = feeFor(chip.participantId);
                return (
                  <tr key={chip.id}>
                    <td>
                      {person?.name ?? chip.participantId}
                      <div className="sub">{chip.reason || '—'}</div>
                    </td>
                    <td className="mono sub">{chip.id}</td>
                    <td className="mono sub">{shortTime(chip.invalidatedAt)}</td>
                    <td className="num">
                      {paid?.replacementFee == null ? (
                        <span className="tag tag--quiet">Waived</span>
                      ) : (
                        <>
                          {euros(paid.replacementFee)}
                          <div className="sub">
                            {paid.replacementMethod
                              ? PAYMENT_METHOD_LABELS[paid.replacementMethod]
                              : ''}
                          </div>
                        </>
                      )}
                    </td>
                  </tr>
                );
              })}
              <tr>
                <td className="name">
                  {replaced.length} replaced
                </td>
                <td />
                <td className="name num">{PAYMENT_METHOD_LABELS.cash} {euros(takings.cash)}</td>
                <td className="name num">{PAYMENT_METHOD_LABELS.card} {euros(takings.card)}</td>
              </tr>
            </tbody>
          </table>

          <p className="note">
            Every wristband ever issued keeps its own row in the database, so this
            is the history rather than a list that forgets: a guest who has lost
            two appears twice, and the chip that was handed in still says whose it
            was. None of them resolve any more — a found wristband buys nothing.
          </p>
        </>
      )}
    </div>
  );
}

function ColourRow({ row, onError }: { row: Row; onError: (message: string) => void }) {
  // The typed text, not a colour: an organiser pasting a hex goes through "#1E",
  // "#1E6B" and every other unreadable state on the way, and a field that
  // rewrites what it holds while somebody is typing into it cannot be typed into.
  // `parseHexColour` turns it into a colour when it is one.
  const [typed, setTyped] = useState(row.colour?.colour ?? DEFAULT_COLOUR);
  const [name, setName] = useState(row.colour?.name ?? '');
  const [busy, setBusy] = useState(false);

  // Re-sync when the document changes underneath — another organiser on the same
  // panel, or this row's own write arriving back through the listener.
  useEffect(() => {
    setTyped(row.colour?.colour ?? DEFAULT_COLOUR);
    setName(row.colour?.name ?? '');
  }, [row.colour?.colour, row.colour?.name]);

  const parsed = parseHexColour(typed);
  const trimmed = name.trim();
  const valid = parsed !== null && trimmed.length <= MAX_COLOUR_NAME;
  const dirty = parsed !== (row.colour?.colour ?? null) || trimmed !== (row.colour?.name ?? '');
  // The swatch has to hold some colour; while the hex is half-typed it keeps
  // showing the last one that was a colour.
  const swatch = (parsed ?? row.colour?.colour ?? DEFAULT_COLOUR).toLowerCase();

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

  const { band } = row;
  // Written under the label because the label is what the desk calls the pile —
  // "Full Pass INT" is nobody's `ticketType`, and this line is the rule that
  // decides who actually gets it.
  const matches = [band.passType, band.level, band.evening && EVENING_LABELS[band.evening]]
    .filter(Boolean)
    .join(' · ');
  // The id an existing colour lives under, so a document is never duplicated;
  // the wristband's own id when this row is coloured for the first time.
  const id = row.colour?.id ?? band.id;

  return (
    <tr className={row.colour ? '' : 'is-off'}>
      <td>
        <span className="name">{band.label}</span>
        {/* Only when it says something the label does not: "Full Pass INT" is
            nobody's ticketType, while "Party Pass" is exactly its own row. */}
        {matches === band.label ? null : <div className="sub">{matches}</div>}
      </td>
      <td className="num">{row.holders}</td>
      <td>
        <div className="colour">
          <input
            aria-label={`Colour for ${band.label}`}
            type="color"
            value={swatch}
            onChange={(event) => setTyped(event.target.value.toUpperCase())}
          />
          <input
            className="hex mono"
            aria-label={`Hex colour for ${band.label}`}
            value={typed}
            spellCheck={false}
            // No maxLength: a hex pasted out of an email arrives with a space or
            // a newline around it often enough, and 7 characters would cut a
            // valid colour down to an invalid one. `parseHexColour` trims.
            placeholder="#1E6BB8"
            onChange={(event) => setTyped(event.target.value)}
          />
        </div>
        {parsed === null ? (
          <div className="field__hint field__hint--bad">Not a colour — try #1E6BB8</div>
        ) : null}
      </td>
      <td>
        <input
          aria-label={`What staff call the colour for ${band.label}`}
          value={name}
          maxLength={MAX_COLOUR_NAME}
          placeholder="Sky Blue"
          onChange={(event) => setName(event.target.value)}
        />
      </td>
      <td>
        <div className="actions">
          <button
            className="btn btn--primary"
            type="button"
            disabled={busy || !valid || !dirty}
            onClick={() =>
              run(async () => {
                // Unreachable — the button is disabled until the hex is a
                // colour — and here so that half a hex can never be written.
                if (parsed === null) return;
                // `setDoc`, not `updateDoc`: this row may never have been
                // coloured, in which case there is no document yet.
                await setDoc(doc(db, COLLECTIONS.braceletColours, id), {
                  [BRACELET_COLOUR_FIELDS.passType]: band.passType,
                  [BRACELET_COLOUR_FIELDS.colour]: parsed,
                  ...(band.level ? { [BRACELET_COLOUR_FIELDS.level]: band.level } : {}),
                  ...(band.evening ? { [BRACELET_COLOUR_FIELDS.evening]: band.evening } : {}),
                  ...(trimmed ? { [BRACELET_COLOUR_FIELDS.name]: trimmed } : {}),
                });
              })
            }
          >
            {row.colour ? 'Save' : 'Set colour'}
          </button>
          {row.colour ? (
            <button
              className="btn"
              type="button"
              disabled={busy}
              aria-label={`Clear the colour for ${band.label}`}
              title={
                row.holders > 0
                  ? `${row.holders} ${
                      row.holders === 1 ? 'person is' : 'people are'
                    } shown this colour and would be left with none`
                  : 'Nobody is shown this colour yet'
              }
              onClick={() => run(() => deleteDoc(doc(db, COLLECTIONS.braceletColours, id)))}
            >
              Clear
            </button>
          ) : null}
        </div>
      </td>
    </tr>
  );
}
