# Special sessions

An extra class somebody adds to their weekend — **Lindy Hop with Sakarias &
Elice** or **Jazz with Patrik**, 25 € each — sold at the desk to a person who is
already here. It is the third thing the participant screen can do, beside the
preordered merch and the free shirt.

---

## Where it lives, and why there

```
participants/tkt-10432/sessions/jazz-patrik
  sessionId: "jazz-patrik"     // the catalogue id, repeated so a group read can read it
  name:      "Jazz with Patrik"  // the catalogue's name at the moment of sale
  price:     2500                // cents, likewise a snapshot
  method:    "cash" | "card"     // mandatory
  soldAt:    <server timestamp>
  soldBy:    "<uid of whoever was on the desk>"
```

**One document per class bought, and the document existing *is* the sale.**
There is no `sold: false` state, exactly as somebody who ordered no t-shirt has
no order document. Somebody who bought both classes has two documents; somebody
who bought neither has none, which is nearly everybody.

**A subcollection, reception-only**, like merch and for the same reason: every
participant document is readable by every terminal including the bar, and what
somebody bought — with a price attached — is not the bar's business.

**Written once.** `allow update` and `allow delete` are both `false`. A sale that
can be rewritten is a sale nobody can count a cash box against, so a second tap
on a class somebody already bought fails rather than quietly replacing the method
the first one recorded. A genuine mistake is an organiser's job with the database
open, which is the same stance the ledger takes.

**The name and the price are snapshots**, for the third time in this codebase and
the same reason as the other two (a ledger line's `unitPrice`, a door sale's
`pricePaid`): renaming a class or repricing it next week must not rewrite what
was taken today. The panel groups its totals by the name each sale recorded, so a
rename shows up as two rows rather than as history quietly changing.

## The catalogue

The two classes are rows in `doorPasses`, the same collection reception sells
passes from, with `kind: "session"`:

```
doorPasses/jazz-patrik
  name:      "Jazz with Patrik"
  price:     2500
  kind:      "session"
  isActive:  true
  sortOrder: 7
```

One catalogue rather than two, so the price and the wording are an organiser's to
change in the panel they already use — the Door passes tab edits these rows like
any other, and marks them *extra class* under the id.

`kind` is a behaviour, not a label, exactly as it is for the evening ticket:

- the door picker filters them out, because a class is not a ticket and nobody
  is admitted by one;
- `firestore.rules` **refuses a door sale pointing at one**, so a terminal that
  somehow offered it could not mint a participant called "Jazz with Patrik";
- a session sale checks the other way: the catalogue row must exist, its name
  must match what is being recorded, and its `kind` must be `session`. Reception
  sells the classes the festival runs, at the names an organiser gave them, and
  cannot invent a 200 € private lesson.

## At the desk

Under the free shirt on the participant screen, one row per class: what it is,
what it costs, cash or card, and a button that says **Sell · 25.00 €** once a
method is picked and **Choose cash or card** until then — the same shape as the
free shirt above it and the same rule as the top-up keypad.

A sold class loses its controls and reads **Sold Sat 14:03 · Cash** in green.
There is no undo, per the rule above.

The section is hidden entirely when the catalogue has no session rows, and on the
confirmation screen of a door sale — that participant does not exist yet, so
there is nothing to hang a class off.

## In the panel

**Special sessions sold**, under the door catalogue: one row per class, the
number sold, cash against card, and a total. It is a collection-group read across
every participant's `sessions`, which needs **its own rule** —
`match /{path=**}/sessions/{sessionId}` — because a nested `match` does not
authorise a collection-group query. That is asserted by a test, since the failure
is silent: the table simply never appears.

## Verified

- **166 rules tests**, including: the bar can neither read nor sell one, a class
  the organisers never listed is refused, a name that disagrees with the
  catalogue is refused, an ordinary pass cannot be sold as a session, a session
  cannot be sold as a door pass, the method and the price are mandatory and
  bounded, `soldAt`/`soldBy` are the server's and the operator's, and a sale
  cannot be updated or deleted once written.
- **154 iOS tests**, including that a session is never something the door sells
  and that the name and price on a sale do not follow the catalogue afterwards.
- **End to end against the emulator**, 2026-09-22. Sold *Jazz with Patrik* for
  cash from Amélie Roux's screen: the write landed through the real rules as
  `{ method: "cash", price: 2500, sessionId: "jazz-patrik" }` with the server's
  clock and the reception uid, the row flipped to *Sold Tue 22:51 · Cash*, and
  the panel totalled it as one sale, 25.00 € cash.

## Still open

- **Nothing is in production yet.** The two catalogue rows have to be written
  there before the desk can sell anything: `DEFAULT_DOOR_PASSES` has them for a
  fresh project, but `npm run seed-passes` rewrites every price it knows about,
  so production wants a targeted write of just these two rows instead.
- **No undo.** Deliberate, but it means a mis-tap needs an organiser with the
  database open. If that turns out to be common, the narrow fix is an
  admin-only delete rather than making the sale editable.
- **The bar cannot see it**, which is the intent, but it also means the class
  list at the door is not visible from a bar terminal if anybody ever wants it
  there.
- **Android has none of this**, like everything else from this weekend's work.
