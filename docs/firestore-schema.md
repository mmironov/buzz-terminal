# Firestore schema

Source of truth for the backend model. `backend/firestore.rules` enforces it;
`backend/import-roster/` populates the roster part of it from the Google Sheet.

## Where each piece of data comes from

| Data | Owner | Written by |
| --- | --- | --- |
| Who bought a ticket (name, ticket type, country) | the Google Sheet, `Status = Paid` only | the import script, via Admin SDK |
| Which chip belongs to whom | the reception terminal | the app, at check-in |
| Balance and its history | the terminals | the app, in Firestore transactions |
| Blocks | organisers | the web admin panel, `web-admin/` |
| Drinks and prices | organisers | the web admin panel; `npm run seed-drinks` bootstraps a fresh project |

The important line is the first one: **the Sheet owns identity, Firestore owns
everything that happens during the festival.** The import never writes a balance
and the app never writes a name.

---

## Pass types

Six, and the spelling is canonical — `ios/BuzzTerminal/Domain/Models.swift`
`TicketType` holds them:

`Party Pass` · `Party Pass Plus` · `Full Pass` · `Full Pass Gold` ·
`Jazz Performance Track` · `Evening Ticket`

The first five come from the Sheet. **`Evening Ticket` never does** — those are
sold at the door each evening and minted by reception. See *Evening tickets*.

## `participants/{participantId}`

One document per person who bought a ticket. Exists before the festival starts,
before any bracelet is anywhere near them.

`participantId` is derived from the Sheet's stable key (see *Identity* below) —
**not** auto-generated, because the import has to be re-runnable and must be able
to recognise a row it has already seen.

```
participants/tkt-10432
  // ── roster: from the Sheet, import-only, never client-writable ──
  ticketRef:     "TKT-10432"        // as printed on their ticket
  name:          "Amélie Roux"
  nameLower:     "amélie roux"      // for ordered queries and prefix search
  searchTokens:  ["amélie", "roux", "full", "pass"]
  ticketType:    "Full pass"
  country:       "France"          // the Sheet asks for a country, not a city
  importedAt:    <timestamp>
  rosterHash:    "9f2c…"            // skip the write when the row is unchanged

  // ── festival state: from the terminals ──
  braceletId:    null | "04:B4:2F:11"   // null means "awaiting check-in"
  checkedInAt:   null | <timestamp>
  balance:       0                       // integer euro cents, never a float
  lastTxId:      null | "<uuid>"         // ties the balance to its ledger entry
  updatedAt:     <timestamp>

  // ── organiser state: from the admin panel ──
  isBlocked:     false
  blockReason:   null | "Bracelet handed in at the door, Sat 01:20"
  blockedBy:     null | "<uid of the organiser who did it>"
  blockedAt:     null | <server timestamp>
```

Notes on specific fields:

- **`balance` is an integer of cents.** Same reason as `ios/BuzzTerminal/Domain/Money.swift`:
  `0.1 + 0.2 != 0.3` in binary floating point, and Firestore numbers are doubles.
  Storing 2350 rather than 23.50 keeps arithmetic exact end to end.
- **`braceletId == null` is the whole "waiting for check-in" state.** There is no
  separate collection of arrivals. This is why `WaitingGuest` and `Participant`
  collapse into one Swift type — see *Consequences for the app*.
- **`lastTxId`** exists purely so the security rules can verify a balance change
  against the ledger entry that justifies it. It is not otherwise interesting.
- **`rosterHash`** lets a re-import skip untouched rows, so running it mid-festival
  costs a read per row and almost no writes.
- **`blockReason` is required when `isBlocked` is true**, and cleared when it is
  false. The terminals show it verbatim on the blocked screen, so an empty one
  leaves whoever is standing at the desk with nothing to act on. `blockedBy` and
  `blockedAt` are the audit trail — a block is an organiser decision somebody will
  ask about afterwards — and the rules pin `blockedAt` to `request.time`, so it is
  the server's clock.

## `participants/{participantId}/transactions/{clientTxId}`

Append-only ledger. Immutable once written — a dispute at the bar is answered by
reading this, so it must not be editable, including by whoever wrote it.

```
participants/tkt-10432/transactions/8f14e45f-ceea-…
  clientTxId:    "8f14e45f-ceea-…"   // equal to the document id, deliberately
  type:          "topup" | "charge"
  amount:        2000                 // always positive, in cents
  signedAmount:  2000 | -2000         // what the balance moved by
  staffUid:      "<Firebase Auth uid>"
  terminalId:    "reception-02"        // which physical device
  createdAt:     <server timestamp>
  queuedOffline: true                  // optional; set when replayed from the queue

  // charges only — what the round bought
  items: [
    { drinkId: "beer",  name: "Beer",  unitPrice: 400, quantity: 3 },
    { drinkId: "water", name: "Water", unitPrice: 200, quantity: 1 },
  ]
```

**The document id is the idempotency key.** The client generates a UUID per
attempt and writes to that id. When iteration 3's offline queue replays a write
it cannot know whether the original landed — so it just tries again, and a
duplicate fails with "already exists" rather than charging the guest twice.
Double-charging is prevented structurally, not by a check that could be forgotten.

`createdAt` must equal `request.time`, so it is the server's clock. An offline
terminal with a wrong date cannot backdate a charge.

### `items`: the receipt and the money are one fact

A charge must carry `items`; a top-up must not, because cash over the counter buys
nothing. **The line totals must equal `amount`**, and the rules check it. Without
that, the itemisation would be a claim by the bar terminal rather than a fact about
the money — a receipt reading "1 × Water" against 14 € off the bracelet.

Each line **snapshots** the drink's name and price as they were at the moment of
sale rather than referencing `drinks/{drinkId}`. Two consequences worth having:
repricing a drink tomorrow cannot rewrite tonight's receipt, and a drink can be
deleted from the catalogue without orphaning the history that names it. The second
is why `drinks` is now deletable at all — see below.

**At most eight distinct drinks per charge.** Quantities are unlimited; it is the
number of different drinks that is capped, and the cap is measured rather than
chosen. Rules cannot loop — no reduce, no map, no recursion — so the sum is
unrolled to a fixed eight terms, and Firestore stops evaluating after 1,000
expressions per request, inside a batch that is already spending its budget on the
balance invariant. Ten lines exceeded it: the rules tests failed with *"maximum of
1000 expressions to evaluate has been reached"*, which is a production failure that
reading the rule would never have revealed. The apps check the count first so the
bar gets "split the round" instead of a PERMISSION_DENIED. Raising the cap means
re-measuring, not just editing the number.

Charges written before this existed have no `items`, and the admin panel says
*"Itemisation not recorded"* rather than rendering an empty list that would read
like "bought nothing".

## Evening tickets

Passes are also sold on the door on Friday, Saturday and Sunday. Those buyers have
no Sheet row, so reception creates the participant — the **only** case where a
client may create one.

```
participants/ev-friday-14
  source:        "evening"          // vs "sheet"
  ticketType:    "Evening Ticket"
  evening:       "friday"
  eveningNumber: 14
  ticketRef:     "EV-FRIDAY-14"
  name:          "Evening #14"      // a label, not a person
  country:       ""
  braceletId:    "04:E7:3A:2C"      // paired at the moment of sale
  checkedInAt:   <server timestamp>
  balance:       0
  createdBy:     "<uid of who sold it>"
```

Three things make this safe to allow:

**The id is the sequence.** `ev-friday-14` — so Firestore's create-fails-if-exists
does the deduplication. Two desks selling simultaneously collide on `#14` and the
loser retries with `#15`. No counter document, no coordination, no lost numbers
under contention.

**Every field is pinned by the rules,** including that the id agrees with
`evening` and `eveningNumber`, that `ticketType` is exactly `Evening Ticket`, that
`balance` is zero, and that `country` is empty. Reception can mint an anonymous
evening ticket and cannot mint anything else — not a Full Pass Gold, not one
starting with 500 € on it, not one carrying a name.

**Anonymous by construction.** There is nowhere to put personal data even if a
terminal tried; `name` is the generated label.

Validity is **not enforced anywhere.** A Friday ticket presented on Saturday still
works, and organisers freeze it by hand from the admin panel using the same
`isBlocked` flag as any other bracelet. That is a deliberate decision: it keeps
date arithmetic out of the app and a fifth refusal case out of `PaymentDecision`.

A guest returning on a second evening buys a **new ticket on a new bracelet**, so
"a bracelet is permanently paired" stays true and the pairing rules are untouched.
Any balance left on the first evening's bracelet stays there.

> Not recorded: the cash taken for the ticket itself. `npm run headers`-style
> reconciliation can count evening-ticket documents per evening, but the price is
> nowhere in Firestore. Worth revisiting if end-of-night cash reconciliation needs
> to include door sales.

## `bracelets/{chipUid}`

Reverse lookup, so a scan is a single point read by document id — no query, no
index, and it resolves straight from the offline cache when the wifi is out.

```
bracelets/04:B4:2F:11
  participantId: "tkt-10432"
  staffUid:      "<uid of whoever paired it>"
  pairedAt:      <server timestamp>
```

Create-only. Re-pointing a chip at a different guest would silently transfer
their balance; the design's answer is a fresh bracelet, and the rules enforce it.

## `drinks/{drinkId}`

```
drinks/beer
  name:      "Beer"
  price:     400          // cents
  sortOrder: 1
  isActive:  true
```

Read-only to every terminal. Prices are an organiser decision, not a bar one, so
writes are granted to the `admin` claim alone — the web admin panel owns this
collection. `npm run seed-drinks` still exists to put something on the bar's screen
on a fresh project, and re-running it against a live festival would overwrite what
an organiser has since done, including reactivating a drink they took off tonight.

Two ways to stop selling something, and they are different:

- **`isActive: false`** — the bar queries `isActive == true`, so it leaves the menu
  at once and comes back with one click. This is the one for a keg that ran out.
- **Delete** — for a drink entered by mistake. This used to be forbidden outright,
  on the grounds that it would orphan the ledger lines naming the drink. Those lines
  now snapshot the name and price at the moment of sale, so history is
  self-contained and the objection no longer holds.

That query — `isActive == true` ordered by `sortOrder` — is composite, so it needs
an index. Nothing local catches a missing one: **the emulator does not enforce
indexes**, and production answers with `FAILED_PRECONDITION` and no rows rather than
a slow result. It is in `firestore.indexes.json`; keep it there.

---

## Identity: the part that must be right

The import needs a **stable, unique key per Sheet row**. `participantId` is
derived from it. Get this wrong and re-running the import either duplicates
people or overwrites a checked-in guest's balance.

Good keys, in order of preference:

1. A ticket or order reference from the ticketing system — unique by construction.
   **This is what we use: the `Id` column of the registrations sheet.**
2. Email address — unique in practice, but people mistype it and it changes.
3. A Sheet row number — **not stable.** Sorting or inserting a row reassigns it.
4. Name, or name + city — **not safe.** Festivals get two Anna Kowalskis.

If the Sheet has no such column, the fix is to add one and never edit it, rather
than to make the importer guess. The importer refuses to run rather than fall back
to a fragile key.

## Search

The check-in screen filters as reception types. Two strategies, and the roster
size decides which:

- **Up to a few thousand people:** load everyone with `braceletId == null` once,
  filter in memory with the `matches(query:)` predicate the app already has.
  Simple, instant, works offline. This is the plan.
- **Beyond that:** query on `searchTokens array-contains <lowercased prefix>`,
  which the second index in `backend/firestore.indexes.json` supports. Requires the
  importer to write token prefixes; ask when you get there.

Full substring matching (finding "Roux" by typing "oux") is not something
Firestore does. The in-memory path keeps the behaviour the tests already pin
down; the token path would only match from word starts. Worth knowing before the
roster grows.

## Roles

`role` is a **custom claim** on the Firebase Auth user: `"reception"`, `"bar"` or
`"admin"`. The rules read it from the token, so a bar account cannot credit a
balance no matter what the app sends.

Custom claims can only be set with the Admin SDK — they are not settable from the
console UI. `backend/import-roster/` ships a `set-role` command for this.

```bash
npm run set-role -- bar@swingbuzz.fest bar --apply
npm run set-role -- you@swingbuzz.fest admin --apply
```

This replaces the current prefix check in `InMemoryTerminalRepository.signIn`,
where the client decides its own role from the email address.

### admin includes reception; bar stands alone

`reception` and `bar` are the terminals. `admin` is the web panel in `web-admin/`,
**and counts as reception** — in the rules, `isReception()` accepts both. An
organiser is the person who ends up on the desk when it is busy, and making them
carry a second account to check somebody in was friction with no security benefit,
given they can already set prices and freeze bracelets.

| | reception | bar | admin |
| --- | --- | --- | --- |
| Read everything | ✓ | ✓ | ✓ |
| Credit a balance (top-up) | ✓ | | ✓ |
| **Debit a balance (charge)** | | ✓ | |
| Pair a bracelet | ✓ | | ✓ |
| Sell an evening ticket | ✓ | | ✓ |
| Block / unblock a bracelet | | | ✓ |
| Write the drinks menu | | | ✓ |
| Edit the roster, or history | | | |

The last row is empty on purpose: roster fields belong to the Sheet import, and the
ledger is append-only for everybody.

**The debit row is the one that stays narrow.** `isBar()` accepts `bar` and nothing
else, so an organiser cannot take money off a bracelet. The asymmetry is deliberate:
a credit is undone by another credit, while a charge is the thing a guest disputes
at the bar, and keeping the debit side to one role means "who spent this?" has
exactly one answer.

Two invariants survive the change, and both are tested:

- A balance still moves **only** alongside a ledger entry written in the same batch,
  whatever the role. An admin cannot make a silent adjustment; that is what the
  ledger exists to prevent.
- Roster fields and history are off limits to every role.

An `admin` signing into a terminal app gets the **reception** flow. `StaffRole` has
no admin case in either app — that enum is what a terminal can *do*, and an organiser
at the desk is doing reception's job. The panel's own powers stay in the web app.

---

## Consequences for the app

Three changes to Swift, in the order they need doing:

1. **`Participant` and `WaitingGuest` collapse into one type** with an optional
   `braceletId`. "Waiting" becomes a computed property, not a separate model.
   `WaitingGuest.matches(query:)` moves across unchanged.
2. **`Participant.id` stops being a `BraceletID`** and becomes the roster id. The
   bracelet becomes a property, and `BraceletID` is still its own type — the two
   just stop being the same thing.
3. **`TerminalRepository` gains a terminal identity** so ledger entries can record
   which device took the cash. The protocol's shape otherwise survives intact,
   which was the point of writing it the way it is.

None of that touches a view.
