# Security-rules tests

```bash
./test.sh          # or: npm test
```

Starts a throwaway Firestore emulator, loads `../firestore.rules`, runs the
suite, tears it down. **Nothing touches the real `swing-buzz` database.**

First run installs dependencies and downloads the emulator jar, so give it a
minute. After that it's about two seconds.

## Why these exist

`firestore.rules` is the only thing standing between a bug and a bar terminal
crediting itself money. The terminals write to Firestore directly rather than
through Cloud Functions — because the bar has to keep working when the wifi
drops, and Firestore's offline persistence only covers client writes — so there
is no server code to put the invariants in. They live in the rules, and rules
that have only been read are not the same as rules that have been run.

Every rule is asserted **from both directions**: the allowed thing succeeds *and*
the forbidden thing fails. A rules file that denied everything would pass half a
suite otherwise.

## What is covered

69 tests. Every rule is asserted from both directions, so the count is roughly
double the number of rules.

- **Access.** Anonymous denied. Signed in with no `role` claim denied — that is
  the state of a freshly created staff account, and it should be able to do
  nothing until an admin grants a role.
- **Roster.** No terminal can create, delete, or rewrite any Sheet-owned field.
- **Blocks.** A terminal can neither apply nor lift one, and money is refused on
  a blocked bracelet.
- **Pairing.** Reception only, requires the matching `bracelets/{chipUid}`
  document in the same batch, cannot be re-pointed or deleted, and somebody
  already checked in cannot be given a second bracelet.
- **Money.** A bare balance write is refused. A balance that disagrees with its
  ledger entry is refused. The bar cannot credit; reception cannot debit. An
  entry cannot be attributed to another staff member. Overdrawing is refused;
  spending to exactly zero is allowed.
- **Ledger.** The document id must equal the idempotency key. A replayed
  transaction collides instead of double-charging. History cannot be edited or
  deleted. A client-supplied `createdAt` is refused, so a terminal with a wrong
  clock cannot backdate a charge. Sign must agree with type. Zero and negative
  amounts refused.
- **Itemisation.** A charge must say what it bought and the lines must add up to
  the amount charged; a mismatch, a missing itemisation and an itemised top-up are
  all refused. Tested **at the eight-line cap**, because the sum is unrolled and a
  chain one term short would silently stop counting. A ninth line is refused rather
  than ignored. A free line inside a paid round is allowed.
- **The admin panel.** It can block and unblock, with a reason, attributed, on the
  server clock — and it cannot move money, not even with a ledger entry to justify
  it; cannot rewrite the roster or a pairing; cannot smuggle a balance change in
  alongside a block; cannot sell an evening ticket. It owns `drinks`, where a
  malformed drink is refused and every write from a terminal still is.

## Two things worth knowing before editing

**Money writes are batches.** The rules use `getAfter()` to check a balance
against the ledger entry justifying it, and `getAfter()` only sees documents
written in the same batch or transaction. That is exactly the property that makes
the invariant enforceable — and it means a test that writes the two documents
separately will fail for the right reason.

**Writing a field its existing value is a no-op, not a write.** Firestore's
`diff()` produces no affected keys, so `hasOnly()` passes and the rule allows it.
Correct — nothing was rewritten — but it caught out the first version of the
roster test, which "rewrote" `ticketType` to the value it already had and
therefore passed when it should not have. There is now an explicit test pinning
that behaviour so nobody removes it.

## Requirements

Node, and a **working** JDK for the emulator. `test.sh` finds Homebrew's keg-only
`openjdk` on its own, so no shell configuration is needed:

```bash
brew install openjdk
```

The formula needs no sudo and stays in the Homebrew prefix. Note that macOS ships
a `/usr/bin/java` stub that exists even with no JDK installed — which is why the
script tests whether java *runs* rather than whether it is on `PATH`.
