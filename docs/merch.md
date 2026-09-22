# Preordered merch

28 of the 105 paid registrations ordered a t-shirt, a tote bag, or both. The
desk needs to know which, and needs to record handing it over.

---

## The rule this had to work around

The Sheet's three merch columns — attire, size, colour — were in
`EXCLUDED_COLUMNS` from the first import, under a rule worth restating:

> Every field on a participant document is readable by every signed-in
> terminal, the bar included.

`allow read: if canRead()` on `participants/{id}`, and `canRead()` is every
role. A bartender pouring a gin and tonic has no business knowing what size
somebody wears.

That rule has **not** been relaxed. The merch order does not go on the
participant document. It goes in a subcollection:

```
participants/{id}/merch/order     item, size, colour, orderHash
                                  collectedAt, collectedBy
```

```
allow read: if isReception();     // not canRead() — the narrower rule IS the feature
```

The bar can still read the person, because it needs a name, a balance and
whether they are blocked. It cannot read this. There is a rules test that
asserts exactly that pair, and it is the first one in the suite.

One document per person at a fixed path, `order`, so the terminal does a point
read rather than a query — no index, and it resolves from the offline cache the
way the bracelet lookup does.

## What the Sheet actually contains

```
  77  No Swing Buzz attire        10  S          10  Natural
  15  T-Shirt only: 20 €           7  M           8  Sky Blue
  10  T-Shirt and tote bag: 25 €   7  L           5  French Navy
   3  Tote bag only: 15 €          1  XL          3  Pale Pink
                                   1  XS          1  French Navy (Available only in XS, M, L, XL)
```

Four things follow, each with a test:

**"No Swing Buzz attire" is an option in all three dropdowns**, not a blank. Left
alone, 79 people arrive at the desk with an order reading *"No Swing Buzz
attire, size No Swing Buzz attire"*.

**The price is dropped.** `T-Shirt only: 20 €` becomes `shirt`. Same rule that
keeps pass-type prices in the Sheet: the merch is already paid for, the desk is
handing it over rather than selling it, and a price on that screen is a number
somebody will eventually try to collect.

**The item is matched on what the option contains**, not on the exact string.
Early-bird and full pricing are different strings for the same shirt, and a new
price must not silently become "ordered nothing".

**An unrecognised option becomes `unknown`, never `none`.** It reaches the desk
as *"Merch ordered — check the Sheet"*. A guest being told they ordered nothing
because the form grew a fifth option is the failure worth engineering against.

One colour carries a form note — `French Navy (Available only in XS, M, L, XL)`
— and a trailing parenthetical is stripped. That is an instruction to the person
filling in the form, and noise to the person handing over the shirt.

## The import must never un-collect anything

The same shape as balances, and the same reasoning. `collectedAt` and
`collectedBy` are absent from `MERCH_IMPORT_OWNED_FIELDS`, the payload omits
them, and every write is a merge. `assertTouchesOnlyMerchImportFields` throws if
a future edit adds one.

A re-import on Saturday afternoon that reset `collectedAt` would tell the desk
that forty people are still owed a t-shirt they are already wearing, and the
first anybody would know is a queue of people being handed a second one. The
test for it is named THE TRAP, and it uses the worst case: somebody who changed
size in the Sheet *after* collecting, which forces a write to a document that
already records a collection.

An order withdrawn in the Sheet is **retired**, not deleted — `item: 'none'` —
because deleting would also delete the record that something was handed over.

## At the desk

The section appears on the participant screen, under the balance, and **only
when something was ordered**. The other 77 screens are unchanged rather than
carrying an empty "Merch: none" row that trains everybody to stop reading.

| | |
| --- | --- |
| Ordered, not collected | `T-shirt · M · Sky Blue`, **Mark as collected** |
| Collected | struck through and greyed, `Collected Sat 20:59`, **Undo — not handed over** |
| Tote bag | `Tote bag` — no size, no colour, no dangling separator |
| Nothing ordered | no section at all |

**Collecting is reversible**, unlike a bracelet pairing. The cost of a mis-tap
here is a guest being told their shirt is already gone, and fixing that should
not need an organiser with a database open. The rules allow the round trip and
pin both fields: `collectedAt` must be the server clock, `collectedBy` must be
the caller, and nothing else on the document may change in the same write — a
terminal cannot turn a tote bag into a t-shirt.

A failed merch read is deliberately **not** an alert — a check-in must not be
interrupted by a t-shirt — but it is not silence either:

> Preorders could not be read. Check with an organiser before telling anybody
> they ordered nothing.

That line exists because of how this feature was first met in production. The
rules had not been deployed, the repository swallowed every `PERMISSION_DENIED`
into nil so a bar terminal would not error, and the result was a screen that
said nothing at all — indistinguishable from "this guest ordered nothing", with
the data sitting correctly in Firestore the whole time.

So the denial is now swallowed **only for the bar**, where the rules refuse it
on purpose. Reception being refused means undeployed rules or a stale token,
and somebody should find out. Subcollection rules do not inherit from the
parent: `participants/{id}` being readable never made `.../merch/order`
readable, which is the trap worth remembering if this is ever ported.

## Verified

- **82 iOS tests**, including the summary's awkward cases — a tote bag has no
  size, and a naive join leaves `Tote bag · · ` on screen.
- **82 rules tests.** The bar can read the participant and cannot read the
  merch; the bar cannot hand merch over; a terminal cannot edit the order; and
  nothing can be collected that was never ordered.
- **57 importer tests**, including the re-import trap above.
- Driven through the real UI on the Simulator, 2026-09-20: full order, tote
  only, already collected on load, mark, undo, and a participant with no order
  showing no section.

**In production, 2026-09-20.** The rules are deployed — the live ruleset carries
`allow read: if isReception()` on the merch match — and the import has run:
**28 orders** across the roster, each with `collectedAt: null`. Spot-checked
against the Sheet: participant `212` reads `shirt · L · Natural`.

## Still open

- **Nothing has been collected on a real phone.** The data and the rules are
  live, but the write path — `collectedAt` stamped by the server, `collectedBy`
  the caller — has only ever run against fixtures and the emulator.
- **No TestFlight build contains this yet.** Build 73 is the check-in rework;
  merch came after it.
- **The check-in list does not say who has merch waiting.** Reception has to
  open a guest to find out. A flag on the row would need a collection-group
  read of 105 documents, so it was left out; worth revisiting if the desk finds
  itself opening people speculatively.
- **Android has none of this.** No model, no screen, no repository call.
- **Sizes are not reconciled against stock.** The app reports what was ordered;
  whether a Sky Blue M is in the box is a question for the person holding it.


---

# The free shirt

Some people get a shirt for nothing — teachers, volunteers, whoever the
organisers put on the list. The Sheet's `Free T-Shirt` column says who: `TRUE`
for five of the hundred and ten paid rows, blank for everybody else.

It lives beside the preorder, in `participants/{id}/merch/freeShirt`, behind the
same rule: reception reads it, the bar does not.

```
participants/tkt-10432/merch/freeShirt
  // ── from the Sheet, import-only ──
  entitled:     true
  importedAt:   <timestamp>

  // ── festival state: from the terminals ──
  size:         null | "M"
  colour:       null | "Natural"
  collectedAt:  null | <server timestamp>
  collectedBy:  null | "<uid of whoever was on the desk>"
```

## The one difference from a preorder, and everything that follows from it

A preordered shirt was chosen months ago, so the Sheet knows the item, the size
and the colour, and the terminal may only say it was handed over. **Nobody chose
a free shirt in advance.** The Sheet knows only *that* somebody gets one; the
size and the colour are picked at the desk, off whatever is in the box.

So `size` and `colour` are festival state here, where on an order they are
import-owned. Three consequences, each of them enforced rather than intended:

- **The importer must never write them.** `FREE_SHIRT_IMPORT_OWNED_FIELDS` is
  `['entitled', 'importedAt']` and `assertTouchesOnlyFreeShirtImportFields`
  throws otherwise. An import that wrote a blank size over `L · Sky Blue` would
  erase the record of what somebody was actually given, and the desk would hand
  them a second shirt.
- **The rules let the terminal write them**, which the `order` rule does not.
  `firestore.rules` branches on the document id inside `match /merch/{merchId}`:
  `order` allows only `collectedAt` and `collectedBy` to change, `freeShirt`
  also allows `size` and `colour`.
- **A handover must name the shirt.** The rules refuse a `collectedAt` with a
  null size or colour, because "a shirt, size unknown, handed over" is how
  somebody ends up with two. The app keeps the button disabled until both are
  chosen, so the refusal arrives as a button that waits rather than a red banner
  in front of somebody holding a shirt.

`entitled` is the Sheet's word and no terminal can touch it — the rule's
`hasOnly` list has no room for it. Somebody taken off the list is **retired**
(`entitled: false`) rather than deleted, exactly as a withdrawn order is: the
shirt may already be on their back, and the record of that outlives the
entitlement.

## What the desk sees

The section only appears for the five people who are owed one. Two rows of
one-tap choices — five sizes, four colours in the Sheet's own spelling — then
**Mark as handed over**. Afterwards the choice reads back struck through with
the time beside it, and an **Undo** for the mis-tap, which is reversible for the
same reason the preorder's is.
