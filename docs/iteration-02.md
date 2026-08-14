# Iteration 2 — Firebase

Goal: replace the in-memory fixtures with a real backend, without rewriting the
app around it.

Result: the whole terminal runs on Firestore against enforced security rules.
Verified by driving the actual UI, not by reading code — 35 iOS, 24 importer and
49 rules tests green.

---

## 1. What changed

| Area | |
| --- | --- |
| `backend/firestore.rules` | the money invariants, with **49 executable tests** |
| `backend/firestore.indexes.json` | composite indexes + one field override |
| `backend/import-roster/` | Google Sheet → Firestore, `Status = Paid` only, 24 tests |
| `backend/rules-tests/` | emulator harness |
| `backend/seed-emulator.sh` | staff accounts with real claims, participants, drinks |
| `ios/…/Data/FirebaseTerminalRepository.swift` | the real backend, an `actor` |
| `ios/…/Data/FirestoreMapping.swift` | field names, hand-written on purpose |
| `ios/…/App/FirebaseBootstrap.swift` | SDK start-up and emulator wiring |
| `ios/…/Domain/` | `Participant` absorbed `WaitingGuest`; evening tickets |

No view changed to make Firestore work. That is the return on shaping
`TerminalRepository` like a network API in iteration 1 — `async throws`, mutations
returning new server state — rather than like a dictionary.

---

## 2. Concepts in play

### The model inverted, because the roster moved

`Participant.id` used to *be* a `BraceletID`: a participant only existed once a
chip was paired to them. With the roster coming from a Google Sheet, they exist
from the moment they buy a ticket, and the bracelet is something that happens
later. So `WaitingGuest` disappeared into `Participant`, and
`braceletId == nil` became the "arrived but not checked in" state.

The lesson worth keeping: **where identity comes from decides your model.** A
data-source change that sounds like plumbing rewrote the core type.

### Money invariants live in rules, not in server code

There is no server code. The terminals write to Firestore directly, because the
bar has to keep working when the wifi drops and Firestore's offline persistence
only covers *client* writes — a callable Cloud Function simply fails offline.

So the rules carry the weight, and they enforce three things:

1. A balance moves only by exactly the amount of a ledger entry written **in the
   same batch**. `getAfter()` makes this checkable, and it only sees documents
   written together — so splitting the two writes is not a slightly worse style,
   it is rejected.
2. Reception can only credit; the bar can only debit. From a **custom claim**,
   which only the Admin SDK can set, so a client cannot choose its own
   authorisation.
3. The ledger is append-only, and **the document id is the idempotency key**. A
   replayed offline write collides instead of double-charging.

`FieldValue.increment` is deliberately not used: an increment sentinel gives the
rules nothing to compare `balanceAfter == balanceBefore + signedAmount` against.
The cost is a lost-update window, which the rules then close by refusing a balance
that no longer agrees with its ledger entry.

### Reasoning about rules is not testing them

I wrote the rules, read them carefully, and described them confidently. Then the
emulator ran them and the first failure was in a test, not the rules:

```js
await assertFails(updateDoc(…, { ticketType: 'Full pass' }))   // already 'Full pass'
```

Writing a field the value it already holds produces an **empty diff**, so
`affectedKeys()` is empty and `hasOnly()` trivially passes. The rule correctly
allowed a write that changed nothing; my assertion was wrong. That class of thing
does not survive execution and does survive review.

Also settled in two seconds rather than after a deploy: whether `.upper()` exists
in a rules expression. It does.

### The bug that looked like an improvement

```swift
Firestore.firestore().useEmulator(withHost: "127.0.0.1", port: 8080)
```

Reads better than a manual settings assignment. Does not work. Calling it requires
touching `Firestore.firestore()`, which **creates the instance**, and after
creation the transport config is ignored — while `settings.host` still reports the
emulator address.

Symptoms, which look like two unrelated bugs:

- queries return **empty with no error** (served from an empty local cache)
- document reads fail as **"client is offline"**

Diagnosed by asking the emulator whether it had received anything. It had not.

The fix is one `settings` assignment applied before anything queries Firestore.
The comment explaining it is longer than the code, because the broken version is
the one that looks right.

### An actor, not `@unchecked Sendable`

`TerminalRepository` is `Sendable`. `FirebaseTerminalRepository` caches the next
evening-ticket number, so it has mutable state. An `actor` satisfies the
requirement honestly; `@unchecked Sendable` would be a promise nobody can verify.

### The sequence number that needs no counter

Door-sold tickets are numbered per evening. The obvious solution is a counter
document — extra collection, extra rules path, a contention point.

Instead the **id encodes the number**: `ev-friday-14`. Firestore's
create-fails-if-exists does the deduplication. Two desks selling at the same
moment collide and the loser retries with 15. The rules additionally check that the
id agrees with the `evening` and `eveningNumber` inside the document, so the two
cannot drift.

### Hand-written mapping instead of `Codable`

These field names are named by `firestore.rules` and asserted by 49 tests. A
property rename that `Codable` would silently follow is a change to a security
contract. So the strings are spelled out in one place, and a mismatch fails loudly.

---

## 3. Verified how

Not "it compiles". The full flow driven through the UI, with the resulting
documents inspected directly.

**Against the emulator**, loading the same `firestore.rules` that gets deployed —
not against the live project. Worth stating plainly, because the table below reads
like production and is not: participant `1041` is `seed-emulator.sh`'s Amélie Roux,
not anyone from the Sheet. What production has since verified is narrower and
read-only — sign-in, the custom claim, the drinks query and the roster read. No
money has ever moved there.

| Step | Result |
| --- | --- |
| Sign in, reception and bar | custom claim read, each routed to its own flow |
| Roster read | 3 → 2 awaiting, reflecting a check-in done seconds earlier |
| Pair a bracelet | `bracelets/04:A1:9C:7E → 1041` |
| Top up 20 € on the keypad | `balance: 2000`, ledger entry with `staffUid`, `terminalId`, server `createdAt` |
| Charge 8 € as **bar** | `balance: 1200` |
| Ledger reconciles | `+2000 − 800 = 1200 == balance` |
| Insufficient funds | *"has 2.00 €, the round costs 8.00 €. Short by 6.00 €"* |
| Blocked | refused as **blocked** despite having 14 €, i.e. correct precedence |
| Unassigned chip | **not recognised** |
| All three refusals | **zero** ledger entries, balances untouched |

That last row is the one worth having: the refusal copy promises "nothing was
charged", and it is now literally true rather than intended.

---

## 4. Still open

- **The importer has never run against the real Sheet.** It needs `SHEET_ID` and
  the service-account key. `npm run headers` first — it prints the live header row
  and a per-status count, so the column spellings can be confirmed before anything
  is written.
- **Firebase is opt-in.** `-sbBackend firebase`; fixtures remain the default so the
  screenshot pass and offline development keep working with no network. Flipping it
  is a one-line change when you want it.
- **Offline is still cosmetic.** The banner and queue count are UI only. Iteration 3.
- **NFC is still simulated.** Iteration 3, and it needs a physical device.
- **Door-sale cash is not recorded.** Evening tickets can be counted per evening,
  but the price paid is nowhere in Firestore. Worth deciding before end-of-night
  reconciliation matters.
- **Leftover balance on an expired evening ticket** has no policy yet.

## 5. Next

Iteration 3: Core NFC and a real write-behind offline queue. The queue is already
designed for — replaying a write blindly is safe, because the transaction id is the
document id and a duplicate collides. That property is tested, not hoped for.
