# Handing this project to a fresh session

Paste the block below as the first message in a new Claude Code session, from this
machine, with the working directory set to this repository. Everything after it is
context for whoever is reading rather than for the model.

---

```
I'm picking up the Swing Buzz festival staff terminal project at
/Users/miroslavmironov/Projects/iOS/buzz-terminal. Read README.md and docs/ before
changing anything — they explain the reasoning behind most decisions, and the code
comments carry the rest.

WHAT IT IS
A festival cashless-bar system, three clients against one Firebase project (swing-buzz):
- ios/          SwiftUI staff terminal (reception + bar), the finished one. Build 113
                on TestFlight, built from commit 3f6ea15.
- web-admin/    React + Vite organiser panel, live at https://swing-buzz.web.app
- android/      Jetpack Compose, STALE — missing door sales, special sessions,
                wristband replacement, stock, and the bar-menu rework.
- backend/      firestore.rules (210 tests), import-roster/ (Google Sheet → Firestore,
                100 tests), rules-tests/

STATE: the festival (24–27 Sep 2026) is over and the data is the only copy.
origin/main = 88059e8, working tree clean. Production holds 185 participants,
1109 ledger entries, 906 € of unspent balances, 13 stock items, 16 costed drinks.

⚠️ DO NOT RUN `npm run reset` AGAINST PRODUCTION. It deletes ledger entries
permanently (the Admin SDK bypasses append-only) and there is NO BACKUP — Firestore
PITR and scheduled backups are both disabled, confirmed via the API. Every festival
number lives only in that database.

HOUSE RULES THAT MATTER
- Money is integer cents; stock is integer millilitres. Never floats.
- A balance moves ONLY with a matching ledger entry in the same batch; reception may
  credit, the bar may debit, nobody may edit history.
- backend/import-roster/serviceAccountKey.json is a real admin credential that bypasses
  every security rule. Never commit it, never put it in an app, never paste it anywhere.
  GoogleService-Info.plist, google-services.json and AuthKey_*.p8 are gitignored too.
- Only Sheet rows with Status = paid are imported. The Sheet's "Role" column is the
  DANCE role and must never be mapped to `role` (that's the auth claim). Email, phone,
  comments, partner details and receipts must never reach a participant document —
  every field there is readable by every terminal including the bar.
- A collection-group query needs its own rule; a nested match does not authorise it,
  and the failure is silent. This has bitten twice.
- Verify by executing, not by reading: ios/scripts/test.sh (180 tests),
  backend/rules-tests/test.sh (210), backend/import-roster `npm test` (100),
  web-admin `npm test` (14) and `npx tsc --noEmit`.
- Commit in small steps with the reasoning in the message; never commit and push in one
  action; push only when asked.

KNOWN TRAP: drink document ids no longer match their names (`water` sells
"Beer - Lager", `gt` sells "Wine", `run-coke` sells "Gin", `beer` sells "Beer - Craft").
Group bar analytics by the ledger's snapshotted NAME, never by drinkId. Nothing is
broken — ledger lines snapshot name and price at the moment of sale — but it cost one
wrong answer already.

OPEN ITEMS, roughly in priority order
1. Cola stock reads −10.2 L — either an unrecorded delivery or a recipe that
   double-counts (Cola is 330 ml alone and inside Cuba Libre / Whiskey Cola).
2. 259 € of guests' own money is unspent on wristbands and there is no refund path in
   the app. A policy decision, then possibly a feature.
3. Enter € / litre costs in the panel's Stock tab (the field exists, deliberately
   optional) to turn 359.8 L poured into a cost of goods.
4. TestFlight is internal-only: build 113 reaches three Apple accounts. An external
   group + public link + Beta App Review is needed before staff can install it.
5. Enable Firestore PITR and delete protection (needs the Blaze plan) — see the
   warning above.
6. web-admin/scripts/seed-history.mjs is stale; it refuses every write on a fresh
   emulator because the rules moved on.
7. Tidy the drink ids after creating properly-named documents (see the trap above).
8. Android is a long way behind; decide whether it's worth catching up.
9. Possibly import the Sheet's dance role as `danceRole` (door sales already write it)
   so next year's bar stats can split leaders and followers.

Start by reading README.md, docs/stock.md, docs/staff-credit.md and
docs/firestore-schema.md, then tell me what you'd like to work on — don't change
anything until I've said what I want.
```

---

## Notes for the human

**The last paragraph of the prompt is load-bearing.** It stops a fresh session from
helpfully running an import or a reset before you have said what you want. With no
backup enabled, that sentence is the one to keep even if the rest is trimmed.

**Local secrets are not in the repository** and a session on another machine would not
have them. On this Mac they already exist, at:

| | |
| --- | --- |
| `backend/import-roster/serviceAccountKey.json` | Admin SDK — bypasses every rule |
| `ios/BuzzTerminal/Resources/GoogleService-Info.plist` | the iOS app's Firebase config |
| `web-admin/.env.local` | the panel's Firebase config |
| `~/.appstoreconnect/private_keys/AuthKey_F85F3QH33R.p8` | TestFlight uploads |

**The toolchain quirk that wastes the most time:** `xcode-select` points at the Command
Line Tools, so bare `xcodebuild` refuses to run. The scripts in `ios/scripts/` set
`DEVELOPER_DIR` themselves and work either way; a hand-typed `xcodebuild` will not.
The Firestore emulator needs the Homebrew JDK at `/opt/homebrew/opt/openjdk/bin`.

**Where the festival's numbers came from.** Nothing was precomputed: every figure in the
closing summary was derived from the ledger with throwaway scripts — charges carry an
itemisation and a server timestamp, and consumption is derived from those against each
drink's recipe. Any of it can be recomputed, sliced by night, hour, pass type, country
or person, as long as the database survives. See `docs/stock.md` for how the derivation
works and why nothing is stored precomputed.
