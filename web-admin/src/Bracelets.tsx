import { collection, deleteDoc, doc, onSnapshot, orderBy, query, setDoc } from 'firebase/firestore';
import { useEffect, useMemo, useState } from 'react';

import { db } from './firebase';
import {
  BRACELET_COLOUR_FIELDS,
  COLLECTIONS,
  LEVELS,
  MAX_COLOUR_NAME,
  isHexColour,
  normaliseHexColour,
  slugify,
  splitsByLevel,
  toBraceletColour,
  toParticipant,
  type BraceletColour,
} from './schema';

// ═══════════════════════════════════════════════════════════════════════════
//  Which colour wristband each pass type gets, and where it matters, each
//  level within it.
//
//  The pass types are derived from the roster rather than hard-coded. The
//  Sheet's pass types are free text — "Full Pass - 205 € (Upgrade from Party)"
//  is a real value — and the importer keeps anything it does not recognise
//  verbatim. A fixed list here would silently leave those people with no
//  colour, and nobody would find out until somebody stood at the desk holding
//  the wrong wristband.
//
//  Every pass type gets an "Any level" row, which is the fallback and usually
//  the only row anybody fills in. Beneath it, Full Pass and Full Pass Gold get
//  a row per level in use — see SPLITS_BY_LEVEL. The other pass types record a
//  level too, but it is mostly "Other", and four rows of it per pass type is
//  noise in a table somebody has to scan.
// ═══════════════════════════════════════════════════════════════════════════

/** A sensible starting colour for a combination nobody has coloured yet. */
const DEFAULT_COLOUR = '#1E6BB8';

/** What an empty `level` means in a document, and on screen. */
const ANY_LEVEL = '';

interface Row {
  passType: string;
  /** `''` for the pass type's fallback row, otherwise one of LEVELS. */
  level: string;
  /** How many people hold this pass type — at this level, for a level row. */
  holders: number;
  colour: BraceletColour | null;
}

export function Bracelets() {
  const [colours, setColours] = useState<BraceletColour[] | null>(null);
  const [counts, setCounts] = useState<Map<string, number> | null>(null);
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
    // The whole roster, only to count pass types and levels. The Participants
    // tab already loads it; a few thousand documents is the strategy this panel
    // settles on everywhere else.
    return onSnapshot(
      collection(db, COLLECTIONS.participants),
      (snapshot) => {
        const tally = new Map<string, number>();
        for (const entry of snapshot.docs) {
          const person = toParticipant(entry);
          if (!person || !person.ticketType) continue;
          const bump = (key: string) => tally.set(key, (tally.get(key) ?? 0) + 1);
          bump(cellKey(person.ticketType, ANY_LEVEL));
          if (person.level) bump(cellKey(person.ticketType, person.level));
        }
        setCounts(tally);
      },
      (cause) => setError(cause.message)
    );
  }, []);

  const rows = useMemo((): Row[] => {
    if (!colours || !counts) return [];
    const byCell = new Map(colours.map((c) => [cellKey(c.passType, c.level), c]));

    // Every pass type anybody holds, plus any that only a mapping mentions — so
    // a colour set before the first import does not vanish from the table.
    const passTypes = new Set<string>();
    for (const key of counts.keys()) passTypes.add(splitKey(key).passType);
    for (const entry of colours) passTypes.add(entry.passType);

    const holders = (passType: string, level: string) =>
      counts.get(cellKey(passType, level)) ?? 0;

    return [...passTypes]
      .sort((a, b) => holders(b, ANY_LEVEL) - holders(a, ANY_LEVEL) || a.localeCompare(b))
      .flatMap((passType): Row[] => {
        const base: Row = {
          passType,
          level: ANY_LEVEL,
          holders: holders(passType, ANY_LEVEL),
          colour: byCell.get(cellKey(passType, ANY_LEVEL)) ?? null,
        };
        // Levels are offered for Full Pass and Full Pass Gold only — the two
        // whose classes split. A level already coloured is still listed
        // whatever its pass type, so a mapping made before this rule existed
        // can still be seen and cleared rather than being stranded.
        const levels = LEVELS.filter(
          (level) =>
            byCell.has(cellKey(passType, level)) ||
            (splitsByLevel(passType) && holders(passType, level) > 0)
        );
        return [
          base,
          ...levels.map((level) => ({
            passType,
            level,
            holders: holders(passType, level),
            colour: byCell.get(cellKey(passType, level)) ?? null,
          })),
        ];
      });
  }, [colours, counts]);

  if (error) return <p className="empty">Could not read the colours: {error}</p>;
  if (!colours || !counts) return <p className="empty">Reading pass types…</p>;

  // People with no colour at all: their pass type has no fallback, and their
  // own level has no override either.
  const uncovered = rows
    .filter((row) => row.level === ANY_LEVEL && !row.colour)
    .reduce((total, row) => total + row.holders, 0);

  return (
    <div className="stack">
      <div className="toolbar">
        <span className="count">
          {colours.length} colour{colours.length === 1 ? '' : 's'} set
          {uncovered > 0 ? ` · ${uncovered} people without one` : ''}
        </span>
      </div>

      {rows.length === 0 ? (
        <p className="empty">
          No pass types yet. They appear here as soon as the roster is imported.
        </p>
      ) : (
        <table className="table">
          <colgroup>
            <col />
            <col style={{ width: '90px' }} />
            <col style={{ width: '120px' }} />
            <col style={{ width: '200px' }} />
            <col style={{ width: '230px' }} />
          </colgroup>
          <thead>
            <tr>
              <th>Pass type &amp; level</th>
              <th className="num">People</th>
              <th>Colour</th>
              <th>Called</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <ColourRow key={cellKey(row.passType, row.level)} row={row} onError={setError} />
            ))}
          </tbody>
        </table>
      )}

      <p className="note">
        A level row overrides the <strong>Any level</strong> row above it; leave the
        level rows empty and everybody with that pass type gets the one colour.
        Only Full Pass and Full Pass Gold split by level, because those are the
        passes whose classes do. A combination with no colour simply shows no
        colour on a phone; nothing breaks, and nobody is told the wrong wristband.
      </p>
    </div>
  );
}

function ColourRow({ row, onError }: { row: Row; onError: (message: string) => void }) {
  const [colour, setColour] = useState(row.colour?.colour ?? DEFAULT_COLOUR);
  const [name, setName] = useState(row.colour?.name ?? '');
  const [busy, setBusy] = useState(false);

  // Re-sync when the document changes underneath — another organiser on the same
  // panel, or this row's own write arriving back through the listener.
  useEffect(() => {
    setColour(row.colour?.colour ?? DEFAULT_COLOUR);
    setName(row.colour?.name ?? '');
  }, [row.colour?.colour, row.colour?.name]);

  const normalised = normaliseHexColour(colour);
  const trimmed = name.trim();
  const valid = isHexColour(normalised) && trimmed.length <= MAX_COLOUR_NAME;
  const dirty =
    normalised !== (row.colour?.colour ?? null) || trimmed !== (row.colour?.name ?? '');

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

  // Derived from the pass type and level, and only ever a key. The apps match on
  // the fields inside, so a slug collision between two long pass types shows up
  // here as one row overwriting another rather than as a participant quietly
  // getting somebody else's colour.
  const id = row.colour?.id ?? slugify(`${row.passType} ${row.level}`);
  const isBase = row.level === ANY_LEVEL;

  return (
    <tr className={row.colour ? '' : 'is-off'}>
      <td>
        {isBase ? (
          <>
            {row.passType}
            <div className="sub mono">{id}</div>
          </>
        ) : (
          // Indented, because it is an override of the row above rather than a
          // pass type of its own.
          <div style={{ paddingLeft: 18 }}>
            <span className="sub">↳ </span>
            {row.level}
            <div className="sub mono">{id}</div>
          </div>
        )}
      </td>
      <td className="num">{row.holders}</td>
      <td>
        <input
          aria-label={`Colour for ${row.passType}${isBase ? '' : ` ${row.level}`}`}
          type="color"
          value={normalised.toLowerCase()}
          onChange={(event) => setColour(event.target.value)}
        />
        <div className="sub mono">{normalised}</div>
      </td>
      <td>
        <input
          aria-label={`What staff call the colour for ${row.passType}${isBase ? '' : ` ${row.level}`}`}
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
                // `setDoc`, not `updateDoc`: this row may be the first mapping
                // for a combination, in which case there is no document yet.
                await setDoc(doc(db, COLLECTIONS.braceletColours, id), {
                  [BRACELET_COLOUR_FIELDS.passType]: row.passType,
                  [BRACELET_COLOUR_FIELDS.colour]: normalised,
                  ...(row.level ? { [BRACELET_COLOUR_FIELDS.level]: row.level } : {}),
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
              title={
                isBase
                  ? 'The terminals stop showing a colour for this pass type'
                  : 'This level falls back to the pass type’s colour'
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

/** A key for one (pass type, level) cell. The separator cannot occur in either. */
function cellKey(passType: string, level: string): string {
  return `${passType} ${level}`;
}

function splitKey(key: string): { passType: string; level: string } {
  const [passType = '', level = ''] = key.split(' ');
  return { passType, level };
}
