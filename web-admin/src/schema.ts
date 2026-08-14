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
  transactions: 'transactions',
  bracelets: 'bracelets',
  drinks: 'drinks',
} as const;

export const PARTICIPANT_FIELDS = {
  ticketRef: 'ticketRef',
  name: 'name',
  nameLower: 'nameLower',
  ticketType: 'ticketType',
  country: 'country',
  source: 'source',
  evening: 'evening',
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

/** The most characters `firestore.rules` accepts in a block reason. */
export const MAX_BLOCK_REASON = 300;
/** The most characters it accepts in a drink name. */
export const MAX_DRINK_NAME = 60;
/** The typo ceiling on a price, in cents. 1000 € is clear of any real drink. */
export const MAX_DRINK_PRICE = 100_000;

// ── Types ──────────────────────────────────────────────────────────────────

export interface Participant {
  id: string;
  ticketRef: string;
  name: string;
  ticketType: string;
  country: string;
  /** `'sheet'` for an imported registration, `'evening'` for a door sale. */
  source: string;
  /** `null` until reception pairs a chip. Permanent once set. */
  braceletId: string | null;
  checkedInAt: Date | null;
  /** Cents. */
  balance: number;
  isBlocked: boolean;
  blockReason: string | null;
}

export interface Drink {
  id: string;
  name: string;
  /** Cents. */
  price: number;
  sortOrder: number;
  isActive: boolean;
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
}

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
    source: str(data[PARTICIPANT_FIELDS.source], 'sheet'),
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
