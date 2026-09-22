# Special sessions

One extra class somebody adds to their weekend — **Lindy Hop with Sakarias &
Elice** or **Jazz with Patrik**, 25 € each — sold at the desk to a person who is
already here. It is the third thing the participant screen can do, beside the
preordered merch and the free shirt.

**One each.** The two classes are radio buttons, not two independent sales, and
the path is what enforces it rather than the screen.

---

## Where it lives, and why there

```
participants/tkt-10432/sessions/booked
  sessionId: "jazz-patrik"       // WHICH class — a field, because the id is fixed
  name:      "Jazz with Patrik"  // the catalogue's name at the moment of sale
  price:     2500                // cents, likewise a snapshot
  method:    "cash" | "card"     // mandatory
  soldAt:    <server timestamp>
  soldBy:    "<uid of whoever was on the desk>"
```

**One document at a fixed id, and the document existing *is* the sale.** There is
no `sold: false` state, exactly as somebody who ordered no t-shirt has no order
document, and no second document either: `booked` is the whole subcollection.

**That fixed id is what makes "one each" true.** `create` fails if the document
is already there, so a second class cannot be sold to the same person whatever a
terminal sends — the same deduplication-by-construction the door sale's `door-7`
uses, and the same reason the rules refuse an update. The screen's radio buttons
are the near side of the same rule; the far side does not depend on them.

**A subcollection, reception-only**, like merch and for the same reason: every
participant document is readable by every terminal including the bar, and what
somebody bought — with a price attached — is not the bar's business.

**Written once.** `allow update` and `allow delete` are both `false`. A sale that
can be rewritten is a sale nobody can count a cash box against, so a second tap
fails rather than quietly replacing the class or the method the first one
recorded. A genuine mistake is an organiser's job with the database
open, which is the same stance the ledger takes.

**The name and the price are snapshots**, for the third time in this codebase and
the same reason as the other two (a ledger line's `unitPrice`, a door sale's
`pricePaid`): renaming a class or repricing it next week must not rewrite what
was taken today. The panel groups its totals by the name each sale recorded, so a
rename shows up as two rows rather than as history quietly changing.

## The catalogue

A collection of its own, and this is the part that was wrong first time round:

```
specialSessions/jazz-patrik
  name:      "Jazz with Patrik"
  price:     2500
  sortOrder: 1
  isActive:  true
```

**A class is not a pass.** It admits nobody, creates no participant, and is never
sold at the door. It lived in `doorPasses` behind a `kind` for one afternoon, and
everything that followed from that was work spent keeping two different things
apart in one list: filtering the door picker, a rule stopping a class being sold
as a ticket, and a row in the panel's *Door passes* tab labelled "not a pass". A
separate collection deletes all three.

Owned by organisers in the panel's **Sessions** tab — add, rename, reprice,
withdraw, delete — like every other price list, and read by reception only: the
bar neither shows the classes nor sells them.

The sale checks against it: the class must exist and its name must match what is
being recorded, which is the same protection a door pass gets against
`doorPasses`, and the reason reception cannot invent a 200 € private lesson.

## At the desk

Under the free shirt on the participant screen: the two classes as radio buttons
with their prices, cash or card beneath them, and one button. It says **Choose a
session**, then **Choose cash or card**, then **Sell · 25.00 €** — naming what is
missing rather than sitting there greyed out, the same rule as the top-up keypad
and the buyer form.

Once sold, the whole choice collapses to one line of record: the class, the
price, and **Sold Sat 14:03 · Cash** in green. No controls come back, because
there is nothing left to sell this person and no undo.

The section is hidden entirely when the catalogue has no session rows, and on the
confirmation screen of a door sale — that participant does not exist yet, so
there is nothing to hang a class off.

## In the panel

The **Sessions** tab: the classes at the top, with what they cost, and **Sold so
far** underneath — one row per class, the number sold, cash against card, and a
total. It is a collection-group read across every participant's `sessions`, which
needs **its own rule** — `match /{path=**}/sessions/{sessionId}` — because a
nested `match` does not authorise a collection-group query. That is asserted by a
test, since the failure is silent: the table simply never appears.

## Verified

- **172 rules tests**, including: **a second class is refused**, a sale written
  anywhere but `booked` is refused, the bar can neither read nor sell one, a
  class the organisers never listed is refused, a name that disagrees with the
  catalogue is refused, an ordinary pass cannot be sold as a session, a session
  cannot be sold as a door pass, the method and the price are mandatory and
  bounded, `soldAt`/`soldBy` are the server's and the operator's, and a sale
  cannot be updated or deleted once written; and, on the catalogue itself, that
  an organiser writes it and reception does not, the bar cannot read it, and a
  `kind: session` row is refused in `doorPasses` so the two cannot drift back
  together.
- **156 iOS tests**, including that a session is never something the door sells
  and that the name and price on a sale do not follow the catalogue afterwards.
- **End to end against the emulator**, 2026-09-22. Sold *Lindy Hop with Sakarias
  & Elice* by card from Amélie Roux's screen: the write landed through the real
  rules at `sessions/booked` as
  `{ sessionId: "lindy-sakarias-elice", method: "card", price: 2500 }` with the
  server's clock and the reception uid, the section collapsed to *Sold Tue 23:02
  · Card* with no controls left, and the panel totalled it as one sale, 25.00 €
  on card.

## Still open

- **Nothing is in production yet.** The two classes have to be written to
  `specialSessions` before the desk can sell anything. `DEFAULT_SPECIAL_SESSIONS`
  and `seedSpecialSessions` are there for a fresh project; production wants the
  same two documents written once, after which the Sessions tab owns them.
- **No undo, and no second class.** Both deliberate, and both mean a mis-tap
  needs an organiser with the database open — including picking the wrong class
  of the two. If that turns out to be common, the narrow fix is an admin-only
  delete rather than making the sale editable.
- **The bar cannot see it**, which is the intent, but it also means the class
  list at the door is not visible from a bar terminal if anybody ever wants it
  there.
- **Android has none of this**, like everything else from this weekend's work.
