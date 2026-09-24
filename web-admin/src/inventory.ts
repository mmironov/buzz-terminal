// ═══════════════════════════════════════════════════════════════════════════
//  What is left behind the bar.
//
//  Nothing here talks to Firestore, so the arithmetic that decides "we have
//  four litres of gin" can be tested without a database — and it is, in
//  stock.test.ts. That matters more than usual: this is the number somebody
//  acts on at 2am when deciding whether to send for more.
//
//  **Millilitres as integers, everywhere.** Litres are a presentation detail.
//  The same discipline as cents for money, and for the same reason: 0.1 + 0.2
//  is not 0.3 in a double, and a stock level that drifts by a millilitre per
//  sale is worse than no stock level at all.
//
//  Consumption is DERIVED, never stored. The bar already writes what it sold,
//  itemised and timestamped, in the ledger it has always written; a recipe says
//  what a serving costs the store. So this file is the only thing that had to be
//  invented, and last night's numbers can be recomputed differently next year
//  without the bar having recorded anything else.
// ═══════════════════════════════════════════════════════════════════════════

/** The shape this needs from a ledger entry — see `Transaction` in schema.ts. */
export interface ChargeLike {
  type: 'topup' | 'charge';
  createdAt: Date | null;
  items: { drinkId: string; name: string; quantity: number }[];
}

export interface SoldLine {
  drinkId: string;
  /** The name as it was at the moment of sale, from the ledger's own snapshot. */
  name: string;
  quantity: number;
}

/**
 * How many of each drink were sold, optionally within a window.
 *
 * The window is half-open — `from` inclusive, `to` exclusive — so consecutive
 * nights cannot both claim the same round. An entry with no timestamp (a write
 * still in flight) is counted in the total but belongs to no night, which is
 * the honest place for it.
 */
export function soldByDrink(
  entries: ChargeLike[],
  window?: { from?: Date; to?: Date }
): SoldLine[] {
  const totals = new Map<string, SoldLine>();

  for (const entry of entries) {
    if (entry.type !== 'charge') continue;
    if (window?.from || window?.to) {
      if (!entry.createdAt) continue;
      if (window.from && entry.createdAt < window.from) continue;
      if (window.to && entry.createdAt >= window.to) continue;
    }
    for (const line of entry.items) {
      const seen = totals.get(line.drinkId);
      if (seen) {
        seen.quantity += line.quantity;
      } else {
        totals.set(line.drinkId, {
          drinkId: line.drinkId,
          name: line.name,
          quantity: line.quantity,
        });
      }
    }
  }

  return [...totals.values()].sort((a, b) => b.quantity - a.quantity);
}

export interface StockRow {
  id: string;
  name: string;
  openingMl: number;
  /** Cents per litre as entered, or null while nobody has said. */
  costPerLitreCents: number | null;
  /** What was poured, in cents — null until a cost is known. */
  pouredCost: number | null;
  /** What is still in the store is worth, in cents. Null likewise. */
  remainingValue: number | null;
  /** Deliveries and recounts since opening, netted. */
  movedMl: number;
  /** What the sales say has been poured. */
  consumedMl: number;
  remainingMl: number;
  /** Remaining as a share of what there ever was, or null when there was none. */
  fractionLeft: number | null;
  /** Which drinks drew on this, biggest first — the "what is drinking the gin". */
  drawnBy: { drinkId: string; name: string; ml: number }[];
}

export interface StockReport {
  rows: StockRow[];
  /**
   * Drinks that sold but have no recipe, so their consumption is in nobody's
   * column. Named rather than ignored: a missing recipe makes the stock look
   * healthier than it is, which is the one direction this must never fail in.
   */
  uncosted: SoldLine[];
  /** Recipe entries pointing at a stock item that no longer exists. */
  orphanedRecipes: { drinkId: string; stockId: string }[];
}

/**
 * Put the three sources together: what was there, what arrived, what was sold.
 *
 * `remainingMl` can go negative, and is left that way. It means the recipes or
 * the opening figure are wrong, and rounding it up to zero would hide exactly
 * the thing worth seeing.
 */
export function stockReport({
  items,
  drinks,
  sold,
  movements,
}: {
  items: {
    id: string;
    name: string;
    openingMl: number;
    isActive: boolean;
    costPerLitreCents?: number | null;
  }[];
  drinks: { id: string; name: string; recipe: Record<string, number> }[];
  sold: SoldLine[];
  movements: Record<string, number>;
}): StockReport {
  const recipeFor = new Map(drinks.map((d) => [d.id, d.recipe]));
  const known = new Set(items.map((i) => i.id));

  const consumed = new Map<string, number>();
  const drawnBy = new Map<string, { drinkId: string; name: string; ml: number }[]>();
  const uncosted: SoldLine[] = [];
  const orphanedRecipes: { drinkId: string; stockId: string }[] = [];

  for (const line of sold) {
    const recipe = recipeFor.get(line.drinkId);
    // A drink sold under a name the catalogue no longer has, or one nobody has
    // costed. Both end up here rather than silently contributing nothing.
    if (!recipe || Object.keys(recipe).length === 0) {
      uncosted.push(line);
      continue;
    }
    for (const [stockId, perServing] of Object.entries(recipe)) {
      if (!known.has(stockId)) {
        orphanedRecipes.push({ drinkId: line.drinkId, stockId });
        continue;
      }
      const ml = perServing * line.quantity;
      consumed.set(stockId, (consumed.get(stockId) ?? 0) + ml);
      const list = drawnBy.get(stockId) ?? [];
      list.push({ drinkId: line.drinkId, name: line.name, ml });
      drawnBy.set(stockId, list);
    }
  }

  const rows = items.map((item) => {
    const movedMl = movements[item.id] ?? 0;
    const consumedMl = consumed.get(item.id) ?? 0;
    const everHad = item.openingMl + movedMl;
    const cost = item.costPerLitreCents ?? null;
    const remainingMl = everHad - consumedMl;
    return {
      id: item.id,
      name: item.name,
      openingMl: item.openingMl,
      costPerLitreCents: cost,
      pouredCost: costOf(consumedMl, cost),
      remainingValue: costOf(remainingMl, cost),
      movedMl,
      consumedMl,
      remainingMl: everHad - consumedMl,
      fractionLeft: everHad > 0 ? (everHad - consumedMl) / everHad : null,
      drawnBy: (drawnBy.get(item.id) ?? []).sort((a, b) => b.ml - a.ml),
    };
  });

  return { rows, uncosted, orphanedRecipes };
}

/**
 * What some millilitres cost, in cents, or null when nobody has said.
 *
 * Null rather than zero throughout: "this was free" and "nobody has entered a
 * price" are different facts, and a total that silently treats the second as the
 * first is the sort of number somebody takes to a supplier.
 */
export function costOf(ml: number, centsPerLitre: number | null): number | null {
  if (centsPerLitre === null) return null;
  return Math.round((ml * centsPerLitre) / 1000);
}

/** `"4.5 L"`, or `"350 ml"` below a litre. Negative is shown, not hidden. */
export function litres(ml: number): string {
  const sign = ml < 0 ? '-' : '';
  const abs = Math.abs(ml);
  if (abs < 1000) return `${sign}${abs} ml`;
  const value = abs / 1000;
  // One decimal all the way to a hundred litres. Rounding 10.8 to "11 L" reads
  // tidier and overstates the store, which is the one direction this must never
  // fail in — somebody decides whether to send for more on this number.
  return `${sign}${abs < 100000 ? value.toFixed(1) : Math.round(value)} L`;
}

/** Millilitres from a typed "0.7" (litres). Refuses anything it cannot read. */
export function parseLitres(input: string): number | null {
  const text = input.trim().replace(/\s*(l|L|litres?|liters?)$/, '').replace(',', '.');
  if (!/^\d+(\.\d{1,3})?$/.test(text)) return null;
  const ml = Math.round(Number(text) * 1000);
  return Number.isFinite(ml) ? ml : null;
}
