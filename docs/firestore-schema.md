# Firestore schema

Source of truth for the backend model. `backend/firestore.rules` enforces it;
`backend/import-roster/` populates the roster part of it from the Google Sheet.

## Where each piece of data comes from

| Data | Owner | Written by |
| --- | --- | --- |
| Who bought a ticket (name, ticket type, country) | the Google Sheet, `Status = Paid` only | the import script, via Admin SDK |
| Which chip belongs to whom | the reception terminal | the app, at check-in |
| Balance and its history | the terminals | the app, in Firestore transactions |
| Blocks | organisers | the web admin panel (not built yet) |
| Drinks and prices | organisers | console or a future admin panel |

The important line is the first one: **the Sheet owns identity, Firestore owns
everything that happens during the festival.** The import never writes a balance
and the app never writes a name.

---

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
  blockReason:   null | "Blocked in the admin panel on Sat 01:20 — …"
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
```

**The document id is the idempotency key.** The client generates a UUID per
attempt and writes to that id. When iteration 3's offline queue replays a write
it cannot know whether the original landed — so it just tries again, and a
duplicate fails with "already exists" rather than charging the guest twice.
Double-charging is prevented structurally, not by a check that could be forgotten.

`createdAt` must equal `request.time`, so it is the server's clock. An offline
terminal with a wrong date cannot backdate a charge.

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
  name:      "Draught beer"
  price:     400          // cents
  sortOrder: 0
  isActive:  true
```

Read-only to every terminal. Prices are an organiser decision, not a bar one.

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

`role` is a **custom claim** on the Firebase Auth user, either `"reception"` or
`"bar"`. The rules read it from the token, so a bar account cannot credit a
balance no matter what the app sends.

Custom claims can only be set with the Admin SDK — they are not settable from the
console UI. `backend/import-roster/` ships a `set-role` command for this; a proper
admin panel can take it over later.

This replaces the current prefix check in `InMemoryTerminalRepository.signIn`,
where the client decides its own role from the email address.

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
