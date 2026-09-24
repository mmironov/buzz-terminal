# Staff, the guest list, and drinks on the festival

Two things that turned out to be one feature: knowing who works here, and
putting money on their account so they can drink at the bar.

---

## Where "staff" comes from

Nowhere new. The organisers already record it in the Sheet, in the bracket at
the end of `Pass Type`, next to the price:

```
Full Pass - 0 € (Staff member - Taster Teacher)
Party Pass - 0 € (Staff member - Musician)
Full Pass Gold - 0 € (Staff member - Main Teacher)
Saturday Evening - 0 € (Guest list)
Party Pass - 0 € (Guest list - Sakarias' friend)
```

So the importer reads it out of the column it already imports, and writes one
field:

```
participants/tkt-10432
  admission: "staff" | "guest"     // or "" for everybody who bought a ticket
```

Most brackets mean nothing of the sort — `(EARLY BIRD pricing)`, `(First
Installment 50%)`, `(Upgrade from Party - 135€ + 70€)`, `(Discount from last
year's competition)` — so it matches the two markers rather than treating any
bracket as a category. Two rules earn their place:

- **Every bracket is read, not just the first.** One row already carries
  `(EARLY BIRD pricing)` and then more text, so a scan that stopped at the first
  bracket is one form edit away from missing a staff member.
- **An unclosed bracket counts.** `"Party Pass - 0 € (Staff member - DJ"` is in
  the Sheet, twice, with no closing bracket. A plain `\(([^)]*)\)` misses both,
  and the first anybody would hear of it is two DJs who were not topped up.

## A single night, whatever the Sheet calls it

Most of the guest list came for one night, and the Sheet spells that two ways at
the same price — "Saturday Evening - 50 €" and "Saturday Party - 50 €". Both
normalise to the `Evening Ticket` pass type with the night recorded:

```
Saturday Evening - 0 € (Guest list)  →  ticketType "Evening Ticket", evening "saturday"
```

That is not tidying. The wristband colour lookup asks the **night** before it
asks the pass type, so before this those six people had no colour at all, and
the reception screen showed them the raw Sheet string — bracket, price and all.
Now they get Saturday's black wristband like anybody else who came on Saturday.

**Thursday is deliberately left out.** There is one "Thursday Party - 15 €" row,
and the festival's evenings are Friday, Saturday and Sunday in both apps, the
colours, the door flow and `firestore.rules`. A parser must not mint a fourth
night; it stays an unrecognised pass type, which every import reports.

The weekday has to come first, too: a **Party Pass** is every night of the
festival, and reading it as one night would hand a weekend guest an evening
ticket's colour.

## What is deliberately not imported

The job after the dash: Musician, Main Teacher, Barman, Reception, DJ, Venue.

Two of those are the names of the app's own roles. A field on a participant
document reading "Reception" would be taken for a permission sooner or later, by
a person or by a query — and `StaffRole` comes from a Firebase custom claim and
from nowhere else. `admission` says **how somebody got in**, never what they may
do. It is the same trap as the Sheet's `Role` column, which is the dance role.

If the crew list ever needs to be split by job, that is a second field with a
name that cannot be mistaken for a permission, and a conversation first.

## Topping them up

```bash
cd backend/import-roster && npm run topup -- --amount=20 --all
```

A dry run: who would be credited, from what balance to what, and who is being
passed over and why. Nothing moves without `--apply` and `--confirm=swing-buzz`,
the same two flags as a reset, for the same reason — this is money, and the
Admin SDK does not ask the rules for permission.

```bash
cd backend/import-roster && npm run topup -- --amount=20 --all --apply --confirm=swing-buzz
cd backend/import-roster && npm run topup -- --amount=12.50 --id=tkt-10432 --apply --confirm=swing-buzz
```

**Staff only, including when an id is named.** "Top up this staff member" is a
different request from "give somebody money", and the second one is reception's
job at the desk, where it is written down as cash. A named id that is not marked
staff is skipped with that as the reason, rather than quietly credited.

The guest list is not staff. They came in free; they do not drink free.

### Running it twice

Every run has a **label** — today's date unless `--label=` says otherwise — and
the ledger document id is derived from it:

```
participants/tkt-10432/transactions/staff-2026-09-25-tkt-10432
```

So a second run at the same label writes to a document that already exists, and
`create` refuses it. Re-running because the first run's output scrolled past is
safe; paying the whole crew twice takes a deliberately different label. The dry
run says *already credited under "2026-09-25"* rather than promising to credit
everybody again.

A **deliberate** second top-up is `--label=extra-shift`, which is a sentence
somebody has to type.

### What it writes

The same document a terminal writes, because the panel reads this history and
the balance invariant is "money moved, and here is the entry that says why":

```
participants/tkt-10432/transactions/staff-2026-09-25-tkt-10432
  clientTxId:   "staff-2026-09-25-tkt-10432"
  type:         "topup"
  amount:       2000
  signedAmount: 2000
  staffUid:     "import-roster"
  terminalId:   "import-roster"
  createdAt:    <server timestamp>
  method:       "comp"
  grant:        "2026-09-25"

participants/tkt-10432
  balance:  +2000        // read and written in one transaction
  lastTxId: "staff-2026-09-25-tkt-10432"
```

**`method: "comp"` is the one a terminal cannot write.** A top-up normally says
cash or card because the question it answers is what should be in the cash box
at the end of the night. Nobody paid for this one, and recording it as cash
would put money in that count that nobody can produce. The rules still refuse
anything but cash or card from a terminal — `comp` exists only on the far side
of the Admin SDK, which is the honest place for it. The panel labels it **Staff
credit** and prints the run's label beside it.

The balance is read and written **inside a Firestore transaction**, one person at
a time, because the bar may be charging somebody at that exact moment and a
stale read would quietly undo their round. Same reasoning as the app's, for the
same invariant.

A failure on one person is recorded and the run continues — one bad write must
not leave the rest of the crew unpaid — and the summary names whoever missed
out. Re-running skips the ones that worked.

### The ceiling

`--amount` is euros: `20`, or `12.50`. Anything over 500 € is refused, which is
not a policy about generosity — it is a slipped decimal point being caught
before thirty people get 2000 € each.

## Verified

- **23 unit tests** on the marking and the plan, including: the unclosed bracket
  in the real Sheet, a pricing bracket that must not count, the guest list not
  being staff, a named id that is not staff, a blocked account, a Party Pass
  that must not be read as a single night, and the one that matters — the same
  label credits nobody twice.
- **Applied to production**, 2026-09-24: 159 participants, **42 staff**, **7 on
  the guest list**, and six of those seven now holding a Saturday evening ticket
  with a colour behind it. The counts reconcile with the Sheet's own, which is
  what proves the two unclosed brackets were caught. No unrecognised pass types
  are left. Balances, wristbands and check-ins were untouched, including the
  three people who had been testing on the real app that morning.
- **End to end against the emulator**, 2026-09-24. Five people, three of them
  staff: `--all` credited two and skipped the blocked one; a second identical run
  credited nobody and said why; `--id` with a different label added 12.50 € to
  somebody who already had 27.50 €, leaving 40.00 € and two ledger entries that
  add up to it. A non-staff id was refused.

## Still open

- **Nobody is un-credited.** There is no way to take it back off an account from
  here; the ledger is append-only and reception cannot debit. A mistaken run is
  a database job.
- **The apps show nothing.** A staff member's screen looks like anybody else's,
  which is fine — the money is on the balance either way. The panel shows the
  **Staff** / **Guest list** tag beside the pass.
- **Android has none of this**, as with everything since the door sales.
