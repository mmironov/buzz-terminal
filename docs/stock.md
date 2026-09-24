# What is left behind the bar

Two numbers the festival wanted: how much is in the store right now, and — after
it is all over — what was drunk, when, so next year can be ordered properly.

---

## The thing that made this small

**The bar has been recording the answer all along.** Every charge writes its
itemisation and the server's clock, append-only, because the receipt and the
money had to be one fact:

```
participants/tkt-10432/transactions/8f14e45f-…
  type:      "charge"
  createdAt: <server timestamp>
  items: [ { drinkId: "gt", name: "Gin & tonic", unitPrice: 800, quantity: 2 } ]
```

So *what sold, and at what minute* is already there for every night of every
festival, and no terminal had to learn anything new. The two facts that were
missing are the ones a spreadsheet would have held:

```
stock/gin                    name "Gin", openingMl 700, sortOrder, isActive
stock/gin/movements/{id}     deltaMl +700, reason "Second bottle opened", at, by
drinks/gt.recipe             { gin: 50, tonic: 200 }      // millilitres per serving
```

Everything else is arithmetic:

```
left = opening + movements − Σ (sold × recipe)
```

**No iOS change was needed, and none was made.** The app on the phones is
untouched; this is entirely the organiser panel plus two rules.

## Millilitres, as integers

The same discipline as cents for money, for the same reason: `0.1 + 0.2` is not
`0.3` in a double, and a stock level that drifts by a millilitre a round is worse
than no stock level at all. Litres exist only on the way to the screen —
`litres()` on the way out, `parseLitres()` on the way in.

The store is entered in **litres**, because that is how a keg arrives. A recipe
is entered in **millilitres**, because a gin and tonic is 50 ml and nobody wants
to type `0.05` forty times on a Friday.

## The two ways this page can lie

Both are printed on it rather than left to be discovered:

- **A drink that sold with no recipe** pours nothing, so the store looks
  healthier than it is. That is the one direction this must never fail in
  quietly, so uncosted drinks are listed by name with how many sold.
- **A recipe pointing at something no longer in the store** is named too.

And a third, in the formatting: `litres()` shows one decimal to a hundred
litres. Rounding 10.8 L to "11 L" reads tidier and overstates the store, which
is the same failure in a smaller place.

**Going below zero is shown, not clamped.** A negative means the opening figure
or a recipe is wrong; clamping at zero would hide exactly the thing worth seeing.

## Movements, not edits

A new box carried in at midnight is a `movement`, not an edit to the opening
figure — append-only, like the ledger, and for the same reason: *how did we get
to four litres* is a question somebody asks next year, and an overwritten number
cannot answer it. A recount that finds less is a negative movement with a
reason.

## What a rule can and cannot check

`stock` documents are bounded the usual way — name length, integer millilitres,
a thousand-litre typo ceiling, admin-only writes, and no terminal may write
anything here at all.

**A recipe's values are not checked, and cannot be.** Rules have no loop and the
keys are stock ids nobody knows in advance, so "every value is a positive
integer" cannot be asserted the way the charge itemisation is unrolled into
eight fixed terms. The rule bounds the map to twelve entries; the panel writes
integers, and `toRecipe` drops anything that is not one — a drink whose recipe
was junk then shows up as *uncosted*, where somebody can see it.

## Reading everybody's ledger

The report adds up every charge ever written, which is a **collection-group
query**, and those need a rule of their own — a nested `match` does not
authorise one, and the failure is silent. That is how the special-session
takings table once shipped invisible. So:

```
match /{path=**}/transactions/{transactionId} { allow read: if isAdmin(); }
match /{path=**}/movements/{movementId}       { allow read: if isAdmin(); }
```

Organisers only — narrower than the per-participant rule, which lets a terminal
read the ledger of whoever is standing in front of it. One guest's round is the
bar's business; everybody's at once is not.

## Next year's dashboards

Deliberately not built, and deliberately not needed yet: the data for them is
being written tonight either way. `soldByDrink(entries, { from, to })` already
takes a half-open window, so a night is a window and an hour is a narrower one,
and consecutive nights cannot both claim the same round. An entry still in
flight — no server timestamp yet — belongs to no window but is in the total,
which is the honest place for it.

What that means in practice: **by-night and by-hour consumption can be computed
after the festival from data nobody has to remember to record**, as long as the
recipes are set before the drinks are poured. Recipes are read at report time,
not stamped onto sales, so fixing a wrong recipe next week retroactively fixes
every night — which is right for planning, and is why the bar's own receipts
snapshot the price instead.

## Verified

- **209 rules tests**, including: no terminal can write stock or even a
  movement, a movement cannot be rewritten or deleted, zero is not a movement,
  the recipe map is bounded, and the two collection-group reads work for the
  panel and for nobody else.
- **12 unit tests** on the arithmetic (`web-admin/src/inventory.test.ts`, run
  with `npm test` there): the half-open night window, a top-up that is not a
  sale, an uncosted drink being named rather than ignored, negative remainders
  surviving, and 10.8 L not reading as 11 L.
- **End to end against the emulator**, 2026-09-24, through the real rules: three
  items into the store, two drinks costed from the Bar tab, and 29 seeded drinks
  across two nights turning into 300 ml of gin poured (400 ml left, 57%) and 8 L
  off a 30 L keg. A second gin bottle carried in moved it to 1.1 L and 79%, and
  the uncosted water stayed named throughout.

## Still open

- **No dashboards.** By design, for now.
- **One bar.** If a second bar ever pours from its own store, `stock` would need
  to know which — and so would the charge, which currently records the terminal
  but not a bar.
- **Nothing warns the bartender.** Running out is visible in the panel only; the
  terminals read none of this, deliberately, so the till cannot be blocked by a
  planning number being wrong.
- **`web-admin/scripts/seed-history.mjs` is stale** — it rehearses the terminals
  through the rules, and has drifted behind them since door sales and
  replacements landed. It refuses every write on a fresh emulator, so the bar
  fixtures for this were seeded directly instead. Worth fixing before it is
  trusted again.
