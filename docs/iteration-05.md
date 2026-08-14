# Iteration 5 — the organiser panel

Goal: give organisers the two things the festival cannot run without and neither
terminal should be able to do — freezing a bracelet, and setting the drinks prices.

Result: `web-admin/`, a React panel on the same Firestore, with a third custom
claim and a purchase history that itemises every round. Verified by driving the
actual UI against the emulator and then checking, from a bar client, that what the
panel did was real.

---

## 1. What changed

| Area | |
| --- | --- |
| `backend/firestore.rules` | an `admin` role; blocks with an audit trail; `drinks` writable; `items` on a charge |
| `backend/rules-tests/` | **69 tests**, up from 49 |
| `backend/import-roster/` | `set-role` accepts `admin`; `seed-drinks` demoted to a bootstrap |
| `backend/seed-emulator.sh` | an admin account |
| `backend/firebase.json` | hosting for the panel |
| `ios/…/Data/` | `CartLine.ledgerItem`, itemised charges, a new refusal |
| `android/…/data/` | the same, plus `:app`'s first unit tests |
| `web-admin/` | the panel |

Two screens: the roster with per-bracelet history and a block control, and the
drinks catalogue. What took the thinking was neither of those.

---

## 2. Concepts in play

### The interesting part of a role is what it cannot do

The panel needed two powers. The temptation is to give the `admin` claim broad
write access and keep the panel honest in its own code — which puts the invariants
back in a client, exactly where iteration 2 concluded they must not live.

So `admin` is **not a member of `isStaff()`**. Every money rule is written in terms
of `isStaff()`, `isReception()` and `isBar()`, so the new role is excluded from all
of them by construction rather than by remembering to exclude it from each one. The
panel then gets two narrow holes: a block change with four pinned fields, and the
`drinks` collection.

The rule this settles most sharply: **an admin cannot adjust a balance.** It is the
first thing anyone would ask for in an admin panel, and it would undo the point of
the ledger — money that moved is accounted for by an entry naming who moved it and
when, and a correction leaving no trace is what the whole design exists to prevent.
A guest who is owed money gets a top-up from reception, and history says so. The
panel's README leads with the table of what it cannot do, because that list *is* the
design.

### Rules cannot loop, and that is a hard budget

A charge now carries `items`, and the lines must add up to `amount`. Without that
check the itemisation would be a claim by the bar terminal rather than a fact about
the money — a receipt reading "1 × Water" against 14 € off a bracelet.

Firestore rules have no reduce, no map and no recursion. The sum has to be unrolled
to a fixed number of terms, and the cap on lines is what makes the unrolling total
rather than a check of the first few. I picked ten, wrote it, and the tests said:

```
Unable to evaluate the expression as the maximum of 1000 expressions
to evaluate has been reached.
```

A money write is a two-document batch that already spends its budget on the balance
invariant, and per-line validation is expensive — `items[i]` repeated eight times
costs eight times as much. The fix was both halves: index each line once and hand
it to a helper, and drop the cap to eight.

Worth being precise about why this matters. It is not a style problem. The rule
reads correctly at ten, deploys at ten, and refuses a perfectly valid eight-line
round in production with a permission error the bartender cannot act on. Nothing
short of running it reveals that, which is the same lesson iteration 2 wrote down
and a sharper example of it. There is now a test at exactly the cap, and a comment
saying that raising it means re-measuring rather than editing a number.

### Snapshots turned a "never delete" rule into a "delete is fine" rule

The schema used to say a withdrawn drink is deactivated and **never** deleted,
because deleting would orphan the ledger lines naming it. Reasonable — but the
ledger lines did not name it, because there were no lines.

Now each line snapshots the drink's name and unit price as they were at the moment
of sale. That is required anyway (a price change tomorrow must not rewrite tonight's
receipt), and it makes history self-contained, so the objection to deleting
evaporates. `allow delete: if isAdmin()` followed from a change made for an
unrelated reason.

The panel still offers both, and names the difference, because they are different
things: `isActive: false` for a keg that ran out (reversible, off the bar's menu
immediately), delete for a drink entered by mistake.

### The unit price, not the line total

The one bug in this change that no test on the server could catch. If the app writes
the line *total* into `unitPrice`, the sum still equals `amount` — because the total
was computed from the same wrong numbers — and the rules accept a receipt claiming
beer costs 12 €. It is internally consistent and completely wrong.

Both apps now build the total and the itemisation from the same array, and both have
a unit test pinning the unit price, on the iOS side and on Android. That is what
`:app` got its first test class for.

### A native confirm dialog is a hole in the test surface

Delete used `window.confirm`. It works for a person and is invisible to everything
else: under automation the dialog is auto-dismissed, so clicking Delete did
nothing, and I could not exercise the delete path at all. Neither could any future
test.

Replaced with a two-step confirmation inside the row, which is drivable, which can
say more than a dialog title, and which uses the space to point out that "take off
menu" is the reversible one an organiser probably wants. It also immediately caused
a second, smaller problem — the confirmation appears in the last cell and the table
reflowed around it, shuffling rows somebody might be mid-edit in — fixed with fixed
column widths.

### Fixtures that go through the rules

`seed-emulator.sh` writes the roster as the emulator's `owner`, which is right: the
roster genuinely belongs to an import that bypasses the rules. Bracelets and money
do not.

So `web-admin/scripts/seed-history.mjs` signs in as `reception@example.test` and
`bar@example.test` with the **client** SDK and sends exactly the batches the two
repositories send. A wrong write shape fails the script. It is a rehearsal of the
terminals rather than a shortcut around them — and it means the history the panel
displays was produced the way real history will be.

---

## 3. Verified how

The panel driven through its own UI against the emulator, then cross-examined from
a client with a bar token — because "the panel says the bracelet is blocked" and
"the bar cannot spend on it" are two different claims.

| Step | Result |
| --- | --- |
| Sign in as `admin@example.test` | roster live: 3 participants, balances, one awaiting check-in |
| Amélie's history | `+20.00`, `−14.00` itemised *3 × Beer (4.00 € each), 1 × Water*, `−6.00` |
| Ledger foot | **reconciles** against the 0.00 € on the bracelet |
| Block from the panel | `isBlocked`, reason, `blockedBy` = admin uid, `blockedAt` = server clock |
| **Bar charges the blocked bracelet** | **refused** |
| **Bar tries to lift the block** | **refused** |
| Lift from the panel | active again |
| Reprice beer 4.00 → 4.50, take water off the menu | both applied |
| **The bar's own query** (`isActive == true`, by `sortOrder`) | Beer **4.50**, Gin & Tonic 6.00 — no Water |
| **Bar tries to reprice, add, delete** | refused, refused, refused |
| Add "Espresso Martini" → `espresso-martini`, reorder, delete | all four |
| Sign in as `bar@example.test` | "Not an organiser", with the `set-role` command to fix it |

Only after that does the itemisation claim mean anything: those `items` arrays were
written by a bar-role client through the same rules the apps face, not by an admin
credential that bypasses them.

218 tests green across the four runners: 41 iOS, 67 Android, 69 rules, 41 importer.

---

## 4. Still open

- **The panel has never run against production.** It needs a web app registered in
  the Firebase console and an `admin` claim granted to a real account. Everything
  above is the emulator.
- **No itemisation on the terminals' own receipt screens.** Both apps write the
  lines and neither shows them back from the ledger; the receipt is still built from
  the cart in memory. Harmless, but it means the panel is currently the only place
  history is legible.
- **Eight distinct drinks per round** is a real ceiling. With a three-drink menu it
  is unreachable; a much larger menu and a big group could meet it, and the answer is
  to split the round. If that ever bites, the fix is measuring a higher cap, not
  assuming one.
- **Blocking cannot be scheduled**, so freezing every Friday evening ticket on
  Saturday morning is one click per bracelet. Fine for a few, tedious for fifty.
- **No audit trail on the menu.** Who repriced the beer, and when, is not recorded
  anywhere — unlike a block, which names its organiser. The ledger lines preserve
  what a drink cost at each sale, so nothing about the money is lost, but the
  question "who changed this" has no answer.
- **The panel has no test runner.** `npm run build` typechecks it; its behaviour is
  covered where the authority lives, in the rules tests. A component test would want
  a reason first.

## 5. Next

Iteration 3 is still the outstanding one: Core NFC and the real offline queue, on
both platforms. Nothing in this iteration changes that plan — though the offline
queue now has one more shape to replay, and the itemised charge is the one that
matters, since it is the write that has to survive being sent twice.
