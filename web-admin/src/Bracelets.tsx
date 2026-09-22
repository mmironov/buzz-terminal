import { collection, deleteDoc, doc, onSnapshot, orderBy, query, setDoc } from 'firebase/firestore';
import { useEffect, useMemo, useState } from 'react';

import { db } from './firebase';
import {
  BRACELET_COLOUR_FIELDS,
  COLLECTIONS,
  LEVELS,
  MAX_COLOUR_NAME,
  parseHexColour,
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
//  Most pass types get one row, "Any level", and that is the whole mapping.
//  Full Pass and Full Pass Gold get a row per level instead — see
//  SPLITS_BY_LEVEL — because every holder of those two has a level and their
//  classes split by it.
//
//  **They are not offered an "Any level" row of their own.** They had one, and
//  it read as a second, competing answer to a question the level rows had
//  already answered — one organiser's way out of it was to set Full Pass to
//  white and call it "No color". The row now appears for those two pass types
//  only while it is still deciding somebody's wristband: while a level in use
//  has no colour, or while a leftover document from before this rule is still
//  sitting in the database. It says how many people that is, and when it is
//  nobody the only thing offered is Clear.
// ═══════════════════════════════════════════════════════════════════════════

/** A sensible starting colour for a combination nobody has coloured yet. */
const DEFAULT_COLOUR = '#1E6BB8';

/** What an empty `level` means in a document, and on screen. */
const ANY_LEVEL = '';

interface Row {
  passType: string;
  /** `''` for the pass type's fallback row, otherwise one of LEVELS. */
  level: string;
  /**
   * How many people this row's colour actually reaches.
   *
   * For a level row, everybody at that level. For an "Any level" row, everybody
   * with the pass type whose own level has no colour — which on a pass type
   * that splits by level is the number that says what clearing it would cost.
   */
  holders: number;
  colour: BraceletColour | null;
  /**
   * Whether this row may be given a colour.
   *
   * False on one row only: the "Any level" row of a pass type that splits by
   * level, where every holder is already covered by their level. The document
   * is a leftover and the only useful thing to do with it is clear it.
   */
  editable: boolean;
  /**
   * How many people would be left with no colour at all if this row were
   * cleared — which is the one thing worth knowing before clearing it. Zero
   * when something else still covers them: the pass type's "Any level" colour
   * under a level row, or the level colours under an "Any level" row.
   */
  uncoveredIfCleared: number;
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

  const { rows, uncovered } = useMemo((): { rows: Row[]; uncovered: number } => {
    if (!colours || !counts) return { rows: [], uncovered: 0 };
    const byCell = new Map(colours.map((c) => [cellKey(c.passType, c.level), c]));

    // Every pass type anybody holds, plus any that only a mapping mentions — so
    // a colour set before the first import does not vanish from the table.
    const passTypes = new Set<string>();
    for (const key of counts.keys()) passTypes.add(splitKey(key).passType);
    for (const entry of colours) passTypes.add(entry.passType);

    const holders = (passType: string, level: string) =>
      counts.get(cellKey(passType, level)) ?? 0;

    let uncovered = 0;

    const rows = [...passTypes]
      .sort((a, b) => holders(b, ANY_LEVEL) - holders(a, ANY_LEVEL) || a.localeCompare(b))
      .flatMap((passType): Row[] => {
        const splits = splitsByLevel(passType);
        const general = byCell.get(cellKey(passType, ANY_LEVEL)) ?? null;

        // Levels are offered for Full Pass and Full Pass Gold only — the two
        // whose classes split. A level already coloured is still listed
        // whatever its pass type, so a mapping made before this rule existed
        // can still be seen and cleared rather than being stranded.
        const levels = LEVELS.filter(
          (level) => byCell.has(cellKey(passType, level)) || (splits && holders(passType, level) > 0)
        );

        // Everybody the level colours do not reach: the levels with no colour of
        // their own, and anyone whose level is blank, who no level row can cover.
        // This is what the "Any level" row is for, and the number it is worth.
        const withoutLevelColour =
          holders(passType, ANY_LEVEL) -
          LEVELS.filter((level) => byCell.has(cellKey(passType, level))).reduce(
            (total, level) => total + holders(passType, level),
            0
          );
        if (!general) uncovered += withoutLevelColour;

        const levelRows = levels.map((level) => ({
          passType,
          level,
          holders: holders(passType, level),
          colour: byCell.get(cellKey(passType, level)) ?? null,
          editable: true,
          uncoveredIfCleared: general ? 0 : holders(passType, level),
        }));

        // A pass type that splits by level is shown its "Any level" row only
        // while that row still does something: somebody uncovered, or a
        // document left over from before it stopped being offered.
        if (splits && withoutLevelColour === 0 && !general) return levelRows;

        return [
          {
            passType,
            level: ANY_LEVEL,
            holders: withoutLevelColour,
            colour: general,
            editable: !splits || withoutLevelColour > 0,
            uncoveredIfCleared: withoutLevelColour,
          },
          ...levelRows,
        ];
      });

    return { rows, uncovered };
  }, [colours, counts]);

  if (error) return <p className="empty">Could not read the colours: {error}</p>;
  if (!colours || !counts) return <p className="empty">Reading pass types…</p>;

  return (
    <div className="stack">
      <div className="toolbar">
        <span className="count">
          {colours.length} colour{colours.length === 1 ? '' : 's'} set
          {uncovered > 0
            ? ` · ${uncovered} ${uncovered === 1 ? 'person' : 'people'} without one`
            : ''}
        </span>
      </div>

      {rows.length === 0 ? (
        <p className="empty">
          No pass types yet. They appear here as soon as the roster is imported.
        </p>
      ) : (
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
        <strong>Full Pass and Full Pass Gold are coloured by level</strong>, because
        those are the passes whose classes split and every holder of one has a
        level. The other pass types get a single <strong>Any level</strong> colour,
        which covers everybody holding one. Paste a hex straight into the box beside
        the swatch, with or without the <span className="mono">#</span>. A row left
        without a colour simply shows no colour on a phone; nothing breaks, and
        nobody is told the wrong wristband.
      </p>
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

  // Derived from the pass type and level, and only ever a key. The apps match on
  // the fields inside, so a slug collision between two long pass types shows up
  // here as one row overwriting another rather than as a participant quietly
  // getting somebody else's colour.
  const id = row.colour?.id ?? slugify(`${row.passType} ${row.level}`);
  const isBase = row.level === ANY_LEVEL;
  const splits = splitsByLevel(row.passType);
  // What this row is, in words, for the screen reader and for every tooltip.
  const what = `${row.passType}${isBase ? '' : `, ${row.level}`}`;

  return (
    <tr className={row.colour ? '' : 'is-off'}>
      <td>
        {splits ? (
          // No pass-type row to sit under: these rows are the mapping, so each
          // one names the whole combination rather than relying on the row above.
          <>
            {row.passType} <span className="sub">· {isBase ? 'any level' : row.level}</span>
            <div className="sub mono">{id}</div>
            {!row.editable ? (
              <div className="sub">Left over — this pass type is coloured by level</div>
            ) : null}
          </>
        ) : isBase ? (
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
        <div className="colour">
          <input
            aria-label={`Colour for ${what}`}
            type="color"
            value={swatch}
            disabled={!row.editable}
            onChange={(event) => setTyped(event.target.value.toUpperCase())}
          />
          <input
            className="hex mono"
            aria-label={`Hex colour for ${what}`}
            value={typed}
            disabled={!row.editable}
            spellCheck={false}
            // No maxLength: a hex pasted out of an email arrives with a space or
            // a newline around it often enough, and 7 characters would cut a
            // valid colour down to an invalid one. `parseHexColour` trims.
            placeholder="#1E6BB8"
            onChange={(event) => setTyped(event.target.value)}
          />
        </div>
        {row.editable && parsed === null ? (
          <div className="field__hint field__hint--bad">Not a colour — try #1E6BB8</div>
        ) : null}
      </td>
      <td>
        <input
          aria-label={`What staff call the colour for ${what}`}
          value={name}
          maxLength={MAX_COLOUR_NAME}
          disabled={!row.editable}
          placeholder="Sky Blue"
          onChange={(event) => setName(event.target.value)}
        />
      </td>
      <td>
        <div className="actions">
          {row.editable ? (
            <button
              className="btn btn--primary"
              type="button"
              disabled={busy || !valid || !dirty}
              onClick={() =>
                run(async () => {
                  // Unreachable — the button is disabled until the hex is a
                  // colour — and here so that half a hex can never be written.
                  if (parsed === null) return;
                  // `setDoc`, not `updateDoc`: this row may be the first mapping
                  // for a combination, in which case there is no document yet.
                  await setDoc(doc(db, COLLECTIONS.braceletColours, id), {
                    [BRACELET_COLOUR_FIELDS.passType]: row.passType,
                    [BRACELET_COLOUR_FIELDS.colour]: parsed,
                    ...(row.level ? { [BRACELET_COLOUR_FIELDS.level]: row.level } : {}),
                    ...(trimmed ? { [BRACELET_COLOUR_FIELDS.name]: trimmed } : {}),
                  });
                })
              }
            >
              {row.colour ? 'Save' : 'Set colour'}
            </button>
          ) : null}
          {row.colour ? (
            <button
              className="btn"
              type="button"
              disabled={busy}
              aria-label={`Clear the colour for ${what}`}
              title={
                row.uncoveredIfCleared > 0
                  ? `${row.uncoveredIfCleared} ${
                      row.uncoveredIfCleared === 1 ? 'person is' : 'people are'
                    } shown this colour and would be left with none`
                  : isBase
                    ? 'Nobody is shown this colour; the level rows cover them all'
                    : 'These people fall back to the pass type’s colour'
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
