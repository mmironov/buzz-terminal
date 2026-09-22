// ═══════════════════════════════════════════════════════════════════════════
//  Firestore ↔ panel mapping.
//
//  The third hand-written copy of these field names, after
//  `ios/…/Data/FirestoreMapping.swift` and `android/…/data/FirestoreMapping.kt`,
//  and for the same reason: `backend/firestore.rules` names every one of them and
//  69 rules tests assert on them. A rename that a schema-inference library would
//  silently follow is a change to a security contract.
//
//  Money is an integer of cents everywhere. Firestore numbers are doubles and
//  23.50 is not representable; `euros()` below is the only place it becomes a
//  string, and it is the same conversion `Money.description` does in Swift.
// ═══════════════════════════════════════════════════════════════════════════

export const COLLECTIONS = {
  participants: 'participants',
  /** A participant's extra class: one document, at a fixed id. */
  sessions: 'sessions',
  /** The extra classes on sale. Not passes: see `docs/special-sessions.md`. */
  specialSessions: 'specialSessions',
  transactions: 'transactions',
  bracelets: 'bracelets',
  drinks: 'drinks',
  /** Which colour wristband each pass type gets. One document per pass type. */
  braceletColours: 'braceletColours',
  /** What reception may sell at the desk, and for how much. */
  doorPasses: 'doorPasses',
  /** A door buyer's email. Reception and this panel only — never the bar. */
  contact: 'contact',
} as const;

export const PARTICIPANT_FIELDS = {
  ticketRef: 'ticketRef',
  name: 'name',
  nameLower: 'nameLower',
  ticketType: 'ticketType',
  country: 'country',
  level: 'level',
  /** The DANCE role of a door buyer: leader or follower. Never a staff role. */
  danceRole: 'danceRole',
  source: 'source',
  evening: 'evening',
  /** How a door sale was paid — `cash` or `card` — and what was collected. */
  paymentMethod: 'paymentMethod',
  pricePaid: 'pricePaid',
  eveningNumber: 'eveningNumber',
  braceletId: 'braceletId',
  checkedInAt: 'checkedInAt',
  balance: 'balance',
  isBlocked: 'isBlocked',
  blockReason: 'blockReason',
  blockedBy: 'blockedBy',
  blockedAt: 'blockedAt',
} as const;

export const DRINK_FIELDS = {
  name: 'name',
  price: 'price',
  sortOrder: 'sortOrder',
  isActive: 'isActive',
} as const;

export const DOOR_PASS_FIELDS = {
  name: 'name',
  price: 'price',
  /** Per-night prices for an evening ticket. A night left out falls back. */
  prices: 'prices',
  sortOrder: 'sortOrder',
  isActive: 'isActive',
  /** `'pass'` asks for a buyer; `'evening'` is the anonymous numbered ticket. */
  kind: 'kind',
} as const;

export const SPECIAL_SESSION_FIELDS = {
  name: 'name',
  price: 'price',
  sortOrder: 'sortOrder',
  isActive: 'isActive',
} as const;

export const CONTACT_FIELDS = {
  email: 'email',
  addedBy: 'addedBy',
  addedAt: 'addedAt',
} as const;

export const BRACELET_COLOUR_FIELDS = {
  passType: 'passType',
  /** One of `LEVELS`, or `''` meaning "any level". */
  level: 'level',
  /** One of `EVENINGS`, for the three wristbands that differ by night. */
  evening: 'evening',
  colour: 'colour',
  name: 'name',
} as const;

/**
 * The four dance levels, as `mapping.mjs` normalises them.
 *
 * The Sheet stores each as a sentence; the importer keeps only the leading
 * word. `firestore.rules` pins this exact list, so a fifth value cannot be
 * written — it would match nobody and look like a colour that does nothing.
 */
export const LEVELS = ['Intermediate', 'Advanced', 'Pro', 'Other'] as const;

/**
 * The wristbands the festival prints, in the order the organisers listed them.
 *
 * **A written-down list, not something derived from the roster.** The table
 * used to be built from whatever pass types people held, which meant a pass
 * type nobody had bought yet had no row — the Jazz Performance Track could not
 * be given a colour before the first person bought one — and the two that split
 * by level grew a fallback row nobody could tell apart from the level rows.
 * These ten are the piles of wristbands on the table at reception. There is one
 * row per pile, and it is here rather than in a component because it is a fact
 * about the festival.
 *
 * `passType` matches a participant's `ticketType` verbatim, case- and
 * whitespace-insensitively. `level` narrows it to one dance level. `evening`
 * matches the night instead: Friday, Saturday and Sunday are sold as one pass
 * type, so the night is the only thing that tells those three apart, and a
 * colour naming one is matched on the night alone.
 *
 * Anybody the list does not cover — a Full Pass with no level, one of the
 * Sheet's free-text upgrade strings — simply has no colour, and the tab says
 * how many such people there are rather than leaving it to be discovered at the
 * desk.
 */
export interface Wristband {
  /** The document id used when this row is first given a colour. */
  id: string;
  /** What the desk calls this pile. */
  label: string;
  /** The `ticketType` it matches. */
  passType: string;
  /** One of `LEVELS`, when this row is one level of a pass type. */
  level?: string;
  /** One of `EVENINGS`, for the three that differ by night. */
  evening?: EveningName;
}

export const WRISTBANDS: Wristband[] = [
  { id: 'full-pass-intermediate', label: 'Full Pass INT', passType: 'Full Pass', level: 'Intermediate' },
  { id: 'full-pass-advanced', label: 'Full Pass ADV', passType: 'Full Pass', level: 'Advanced' },
  { id: 'full-pass-pro', label: 'Full Pass PRO', passType: 'Full Pass', level: 'Pro' },
  { id: 'full-pass-gold', label: 'Full Pass Gold', passType: 'Full Pass Gold' },
  { id: 'party-pass', label: 'Party Pass', passType: 'Party Pass' },
  { id: 'party-pass-plus', label: 'Party Pass Plus', passType: 'Party Pass Plus' },
  { id: 'jazz-performance-track', label: 'Jazz Performance Track', passType: 'Jazz Performance Track' },
  { id: 'evening-friday', label: 'Friday Evening', passType: 'Evening Ticket', evening: 'friday' },
  { id: 'evening-saturday', label: 'Saturday Evening', passType: 'Evening Ticket', evening: 'saturday' },
  { id: 'evening-sunday', label: 'Sunday Evening', passType: 'Evening Ticket', evening: 'sunday' },
];

/**
 * Which wristband somebody gets — the same decision the apps make, in the same
 * order, so the panel's **People** counts are what the phones will actually do.
 *
 * The night first, because it is the only thing that can decide an evening
 * ticket. Then the pass type with the level, then the pass type on its own.
 */
export function wristbandFor(person: {
  ticketType: string;
  level: string;
  evening: string;
}): Wristband | null {
  const clean = (value: string) => value.trim().toLowerCase();
  if (person.evening) {
    return WRISTBANDS.find((band) => band.evening === clean(person.evening)) ?? null;
  }
  const sameType = WRISTBANDS.filter(
    (band) => !band.evening && clean(band.passType) === clean(person.ticketType)
  );
  return (
    sameType.find((band) => band.level && clean(band.level) === clean(person.level)) ??
    sameType.find((band) => !band.level) ??
    null
  );
}

/** The most characters `firestore.rules` accepts in a block reason. */
export const MAX_BLOCK_REASON = 300;
/** The most characters it accepts in a colour's spoken name. */
export const MAX_COLOUR_NAME = 40;
/** The most characters it accepts in a drink name. */
export const MAX_DRINK_NAME = 60;
/** The typo ceiling on a price, in cents. 1000 € is clear of any real drink. */
export const MAX_DRINK_PRICE = 100_000;

/** A pass name is written onto a participant as `ticketType`; the rules agree. */
export const MAX_PASS_NAME = 100;
/** 2000 € is a slipped decimal, not a festival pass. */
export const MAX_PASS_PRICE = 200_000;

// ── Types ──────────────────────────────────────────────────────────────────

export interface Participant {
  id: string;
  ticketRef: string;
  name: string;
  ticketType: string;
  country: string;
  /** The DANCE level: one of LEVELS, or `''`. Never a permission. */
  level: string;
  /**
   * `'sheet'` for an imported registration, `'evening'` for an anonymous door
   * ticket, `'door'` for a pass sold at the desk with a buyer on it.
   */
  source: string;
  /** `'leader'`, `'follower'`, or `''` for everyone from the Sheet. */
  danceRole: string;
  /** `'friday'`, `'saturday'`, `'sunday'` — which night an evening ticket is
   *  for, and `''` for everybody else. It decides their wristband colour. */
  evening: string;
  /**
   * What the desk took for a pass sold at the door, and how.
   *
   * Both null for everybody from the Sheet, who paid a registration system
   * months ago. `pricePaid` is a snapshot in cents, taken at the moment of
   * sale: re-pricing a pass next week must not rewrite what was collected
   * tonight. It is **not** the balance — nothing was loaded onto the wristband.
   */
  paymentMethod: PaymentMethod | null;
  pricePaid: number | null;
  /** `null` until reception pairs a chip. Permanent once set. */
  braceletId: string | null;
  checkedInAt: Date | null;
  /** Cents. */
  balance: number;
  isBlocked: boolean;
  blockReason: string | null;
}

/**
 * One thing reception can sell at the desk.
 *
 * The price is shown to whoever is selling and is never charged by anything —
 * see the `doorPasses` block in firestore.rules. `name` is written verbatim onto
 * the buyer as their `ticketType`, which is why it is bounded the same way.
 */
/** The three nights an evening ticket can be sold for. */
export const EVENINGS = ['friday', 'saturday', 'sunday'] as const;
export type EveningName = (typeof EVENINGS)[number];

export const EVENING_LABELS: Record<EveningName, string> = {
  friday: 'Friday',
  saturday: 'Saturday',
  sunday: 'Sunday',
};

export interface DoorPass {
  id: string;
  name: string;
  /**
   * Cents. For an evening ticket this is the fallback: a night with no entry in
   * `prices` is sold at this.
   */
  price: number;
  /**
   * Cents per night, for a festival that charges differently on a Sunday.
   * Partial on purpose — only the nights that differ need an entry.
   */
  prices: Partial<Record<EveningName, number>>;
  sortOrder: number;
  isActive: boolean;
  /**
   * `'evening'` routes the terminal to the anonymous numbered flow — no name, no
   * email, pick a night. `'pass'` asks for the buyer's details.
   */
  kind: 'pass' | 'evening';
}

export interface Drink {
  id: string;
  name: string;
  /** Cents. */
  price: number;
  sortOrder: number;
  isActive: boolean;
}

export interface BraceletColour {
  /** The slug of the pass type. Only ever a document key. */
  id: string;
  /** The pass type verbatim, as it appears on a participant. This is what the
   *  apps match on — never the id, which is derived and could drift. */
  passType: string;
  /** One of `LEVELS`, or `''` for "any level" — the fallback every pass type
   *  uses until somebody splits it by level. */
  level: string;
  /** One of `EVENINGS`, or `''`. Set on the three colours that are about a
   *  night rather than a pass type, and matched on the night alone. */
  evening: string;
  /** `#RRGGBB`, upper case. The rules pin the format; see `isWellFormedColour`. */
  colour: string;
  /** What staff call it out loud. May be empty. */
  name: string;
}

/** One line of a charge, as the ledger snapshotted it at the moment of sale. */
export interface LedgerItem {
  drinkId: string;
  name: string;
  /** Cents, per unit — not the line total. */
  unitPrice: number;
  quantity: number;
}

export interface Transaction {
  id: string;
  type: 'topup' | 'charge';
  /** Always positive, in cents. */
  amount: number;
  /** What the balance moved by: `+amount` for a top-up, `-amount` for a charge. */
  signedAmount: number;
  staffUid: string;
  terminalId: string;
  createdAt: Date | null;
  /**
   * What a charge bought. Empty for a top-up, and empty for charges written
   * before the terminals recorded this — see `historyNote` in History.tsx.
   */
  items: LedgerItem[];
  /**
   * How a top-up was paid: cash or card. `null` on every charge.
   *
   * The rules now require one on a top-up, so a null here should be unreachable
   * for new entries. The panel still shows it as "Method not recorded" rather
   * than as a blank, because the day it does appear is the day something wrote
   * a top-up these rules were supposed to refuse — which is worth seeing.
   */
  method: PaymentMethod | null;
}

export type PaymentMethod = 'cash' | 'card';

/**
 * One extra class an organiser runs, as they priced it.
 *
 * Not a `DoorPass`: a class admits nobody, creates no participant and is never
 * sold at the door. It has its own collection for that reason.
 */
export interface SpecialSession {
  id: string;
  name: string;
  /** Cents. */
  price: number;
  sortOrder: number;
  isActive: boolean;
}

export function toSpecialSession(doc: Doc): SpecialSession | null {
  const data = doc.data();
  const name = data[SPECIAL_SESSION_FIELDS.name];
  const price = int(data[SPECIAL_SESSION_FIELDS.price]);
  if (typeof name !== 'string' || price === null) return null;

  return {
    id: doc.id,
    name,
    price,
    sortOrder: int(data[SPECIAL_SESSION_FIELDS.sortOrder]) ?? 0,
    isActive: data[SPECIAL_SESSION_FIELDS.isActive] !== false,
  };
}

/** One extra class somebody bought at the desk, and what they paid for it. */
export interface SessionSale {
  /** The catalogue id, which is also the document id. */
  sessionId: string;
  /** The class's name and price as the catalogue held them when it was sold. */
  name: string;
  /** Cents. */
  price: number;
  method: PaymentMethod;
  soldAt: Date | null;
  soldBy: string;
}

export function toSessionSale(doc: Doc): SessionSale | null {
  const data = doc.data();
  const name = data['name'];
  const price = int(data['price']);
  const method = toPaymentMethod(data['method']);
  // A sale that cannot say what it was or what was paid is dropped rather than
  // counted: a blank in a takings total is worse than a row that is not there.
  if (typeof name !== 'string' || price === null || method === null) return null;

  return {
    sessionId: str(data['sessionId'], doc.id),
    name,
    price,
    method,
    soldAt: date(data['soldAt']),
    soldBy: str(data['soldBy']),
  };
}

/** The two spellings `firestore.rules` accepts, and nothing else. */
const toPaymentMethod = (value: unknown): PaymentMethod | null =>
  value === 'cash' || value === 'card' ? value : null;

export const PAYMENT_METHOD_LABELS: Record<PaymentMethod, string> = {
  cash: 'Cash',
  card: 'Card',
};

// ── Reading ────────────────────────────────────────────────────────────────
//
// Tolerant of odd documents, the same way the two apps are: the roster is edited
// by humans in a Google Sheet, and a row that is merely strange should render
// rather than take the panel down. Intolerant of a missing name or balance, since
// there is nothing sensible to show instead.

type Doc = { id: string; data: () => Record<string, unknown> };

const str = (value: unknown, fallback = ''): string =>
  typeof value === 'string' ? value : fallback;

const int = (value: unknown): number | null =>
  typeof value === 'number' && Number.isFinite(value) ? Math.trunc(value) : null;

/** Firestore hands back a Timestamp; everything else here wants a Date. */
const date = (value: unknown): Date | null => {
  if (value && typeof value === 'object' && 'toDate' in value) {
    const toDate = (value as { toDate: unknown }).toDate;
    if (typeof toDate === 'function') return toDate.call(value) as Date;
  }
  return null;
};

export function toParticipant(doc: Doc): Participant | null {
  const data = doc.data();
  const name = data[PARTICIPANT_FIELDS.name];
  const balance = int(data[PARTICIPANT_FIELDS.balance]);
  if (typeof name !== 'string' || balance === null) return null;

  return {
    id: doc.id,
    ticketRef: str(data[PARTICIPANT_FIELDS.ticketRef]),
    name,
    ticketType: str(data[PARTICIPANT_FIELDS.ticketType]),
    country: str(data[PARTICIPANT_FIELDS.country]),
    level: str(data[PARTICIPANT_FIELDS.level]),
    source: str(data[PARTICIPANT_FIELDS.source], 'sheet'),
    danceRole: str(data[PARTICIPANT_FIELDS.danceRole]),
    evening: str(data[PARTICIPANT_FIELDS.evening]),
    paymentMethod: toPaymentMethod(data[PARTICIPANT_FIELDS.paymentMethod]),
    pricePaid: int(data[PARTICIPANT_FIELDS.pricePaid]),
    braceletId: str(data[PARTICIPANT_FIELDS.braceletId]) || null,
    checkedInAt: date(data[PARTICIPANT_FIELDS.checkedInAt]),
    balance,
    isBlocked: data[PARTICIPANT_FIELDS.isBlocked] === true,
    blockReason: str(data[PARTICIPANT_FIELDS.blockReason]) || null,
  };
}

export function toDrink(doc: Doc): Drink | null {
  const data = doc.data();
  const name = data[DRINK_FIELDS.name];
  const price = int(data[DRINK_FIELDS.price]);
  if (typeof name !== 'string' || price === null) return null;

  return {
    id: doc.id,
    name,
    price,
    sortOrder: int(data[DRINK_FIELDS.sortOrder]) ?? 0,
    // Absent means active: the seed script wrote documents without the field
    // before the bar started querying on it.
    isActive: data[DRINK_FIELDS.isActive] !== false,
  };
}

export function toDoorPass(doc: Doc): DoorPass | null {
  const data = doc.data();
  const name = data[DOOR_PASS_FIELDS.name];
  const price = int(data[DOOR_PASS_FIELDS.price]);
  if (typeof name !== 'string' || price === null) return null;

  const raw = data[DOOR_PASS_FIELDS.prices];
  const prices: Partial<Record<EveningName, number>> = {};
  if (raw && typeof raw === 'object') {
    for (const night of EVENINGS) {
      const value = int((raw as Record<string, unknown>)[night]);
      if (value !== null) prices[night] = value;
    }
  }

  return {
    id: doc.id,
    name,
    price,
    prices,
    sortOrder: int(data[DOOR_PASS_FIELDS.sortOrder]) ?? 0,
    isActive: data[DOOR_PASS_FIELDS.isActive] !== false,
    // Anything unrecognised is an ordinary pass. A terminal that met a `kind` it
    // did not know and refused to sell would be worse than one that asks for a
    // name it did not strictly need.
    kind: data[DOOR_PASS_FIELDS.kind] === 'evening' ? 'evening' : 'pass',
  };
}

export function toBraceletColour(doc: Doc): BraceletColour | null {
  const data = doc.data();
  const passType = data[BRACELET_COLOUR_FIELDS.passType];
  const colour = data[BRACELET_COLOUR_FIELDS.colour];
  // Both required, and a malformed colour is dropped rather than rendered: a
  // swatch of the wrong colour is worse than no swatch, because somebody hands
  // over a wristband on the strength of it.
  if (typeof passType !== 'string' || !passType) return null;
  if (typeof colour !== 'string' || !isHexColour(colour)) return null;

  return {
    id: doc.id,
    passType,
    level: str(data[BRACELET_COLOUR_FIELDS.level]),
    evening: str(data[BRACELET_COLOUR_FIELDS.evening]),
    colour,
    name: str(data[BRACELET_COLOUR_FIELDS.name]),
  };
}

/** `#RRGGBB`, upper case — the exact shape `firestore.rules` enforces. */
export function isHexColour(value: string): boolean {
  return /^#[0-9A-F]{6}$/.test(value);
}

/**
 * A colour out of whatever somebody typed or pasted, or `null` when it is not a
 * colour at all.
 *
 * Two jobs in one function. The first is what an `<input type="color">`
 * produces: browsers return lower case and the rules demand upper, and
 * normalising here rather than loosening the rule keeps one spelling in the
 * database, so two organisers picking the same colour cannot produce two
 * different strings. The second is a paste — the wristbands are ordered by hex
 * and the supplier's mail says `1E6BB8`, so the hash is optional and `#fff` is
 * expanded the way CSS expands it.
 *
 * `null` rather than a guess for anything else. There is no partial credit on a
 * colour: somebody hands over a wristband on the strength of the swatch.
 */
export function parseHexColour(input: string): string | null {
  const digits = input.trim().replace(/^#/, '').toUpperCase();
  // `#FFF` → `#FFFFFF`, the CSS expansion. A supplier's swatch list is as likely
  // to be written short as long, and both name exactly one colour.
  if (/^[0-9A-F]{3}$/.test(digits)) {
    return `#${[...digits].map((digit) => digit + digit).join('')}`;
  }
  return /^[0-9A-F]{6}$/.test(digits) ? `#${digits}` : null;
}

export function toTransaction(doc: Doc): Transaction | null {
  const data = doc.data();
  const type = data['type'];
  const amount = int(data['amount']);
  if ((type !== 'topup' && type !== 'charge') || amount === null) return null;

  const raw = data['items'];
  const items: LedgerItem[] = Array.isArray(raw)
    ? raw.flatMap((entry): LedgerItem[] => {
        if (!entry || typeof entry !== 'object') return [];
        const line = entry as Record<string, unknown>;
        const unitPrice = int(line['unitPrice']);
        const quantity = int(line['quantity']);
        if (unitPrice === null || quantity === null) return [];
        return [
          {
            drinkId: str(line['drinkId']),
            name: str(line['name'], '(unnamed)'),
            unitPrice,
            quantity,
          },
        ];
      })
    : [];

  return {
    id: doc.id,
    type,
    amount,
    signedAmount: int(data['signedAmount']) ?? (type === 'topup' ? amount : -amount),
    staffUid: str(data['staffUid']),
    terminalId: str(data['terminalId']),
    createdAt: date(data['createdAt']),
    items,
    method: toPaymentMethod(data['method']),
  };
}

// ── Formatting ─────────────────────────────────────────────────────────────

/**
 * `"23.50 €"`. Deliberately locale-independent, matching `Money.description` in
 * Swift and Kotlin: an organiser reading a balance off this screen to somebody
 * holding a phone must see the same string they do.
 */
export function euros(cents: number): string {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')} €`;
}

/**
 * Cents from what somebody typed into a price field, or `null` if it is not a
 * price. Accepts `4`, `4.5`, `4.50` and a comma decimal separator, and refuses
 * anything with more than two decimal places rather than rounding it — a price
 * silently becoming 4.56 € is worse than being told to fix it.
 */
export function parseEuros(input: string): number | null {
  const trimmed = input.trim().replace(',', '.');
  if (!/^\d+(\.\d{1,2})?$/.test(trimmed)) return null;
  const [whole = '0', fraction = ''] = trimmed.split('.');
  return Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
}

/** `"Fri 17:12"`, the same 24-hour format the terminals show. */
export function shortTime(value: Date | null): string {
  if (!value) return '—';
  const day = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][value.getDay()];
  const time = `${String(value.getHours()).padStart(2, '0')}:${String(
    value.getMinutes()
  ).padStart(2, '0')}`;
  return `${day} ${time}`;
}

/**
 * A document id for a new drink, derived from its name: `Espresso Martini` →
 * `espresso-martini`.
 *
 * A readable id rather than a random one because these ids are what ledger lines
 * carry in `drinkId`, and `beer` is a great deal easier to reconcile by eye at 2am
 * than `x7Kq2…`. Falls back to a timestamp for a name with no usable characters.
 */
export function slugify(name: string): string {
  const slug = name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')   // combining marks left by NFD
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 40);
  return slug || `drink-${Date.now()}`;
}
