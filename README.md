# Swing Buzz — Staff Terminal (iOS)

Festival staff app for bracelet check-in, balance top-up and bar payments.
Native SwiftUI, ported from the Claude Design prototype
`Swing Buzz Staff App.dc.html` on the **Modernist** design system.

An Android sibling in Jetpack Compose follows once the iOS app is settled; both
will share a Firebase backend.

---

## One-time setup

This Mac has Xcode installed but `xcode-select` pointing at the Command Line
Tools, which stops `xcodebuild` from running. Fix it once:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

The scripts in `ios/scripts/` set `DEVELOPER_DIR` themselves so they work either way,
but Xcode's own simulator tooling and the live-preview integrations need the
pointer to be correct.

## Running it

```bash
open ios/BuzzTerminal.xcodeproj
```

⌘R runs it. Or from the command line:

```bash
./ios/scripts/run.sh
```

Sign in with either demo account on the login screen — the buttons fill the
fields for you. Any address starting `reception` or `bar` works and the password
is ignored (see *Known simplifications*).

There is no NFC hardware on the Simulator, so the scan sheet offers a
**"Prototype · simulate a bracelet"** panel with the five fixture chips:

| Chip | What it exercises |
| --- | --- |
| `04:A1:9C:7E` | unassigned → check-in flow |
| `04:B4:2F:11` | Marta, 23.50 € → top-up and successful payment |
| `04:C8:5D:03` | Jonas, 2.00 € → declined payment (insufficient funds) |
| `04:D2:0B:6A` | Elena, blocked → blocked screens |
| `04:E7:3A:2C` | Evening #14 (Friday) → an anonymous door sale |

### Jumping straight to a screen

`LaunchOverrides` is the debug-only port of the design prototype's props panel:

```bash
./ios/scripts/run.sh -sbScreen participant
./ios/scripts/run.sh -sbScreen bar -sbOffline
./ios/scripts/run.sh -sbScreen payreview-blocked
```

Screens: `reception`, `bar`, `assign`, `assign-evening`, `participant`,
`evening-participant`, `blocked`, `topup`, `receipt`, `cart`, `payreview`,
`payreview-short`, `payreview-blocked`, `payreview-unassigned`. Flags: `-sbOffline`,
`-sbScanning`. In Xcode the same arguments go in Scheme ▸ Run ▸ Arguments.

```bash
./ios/scripts/screenshots.sh   # every screen to ios/screenshots/
```

### Running against Firestore

The app uses the in-memory fixtures by default. `-sbBackend firebase` switches it
to `FirebaseTerminalRepository`, and `-sbEmulator` points that at local emulators
rather than the live festival database:

```bash
cd backend && firebase emulators:start --only firestore,auth --project swing-buzz
```

```bash
cd backend && ./seed-emulator.sh    # staff accounts with role claims, a few participants, drinks
```

```bash
./ios/scripts/run.sh -sbBackend firebase -sbEmulator -sbSignIn reception@example.test festival26 -sbScreen assign
```

`-sbSignIn` signs in on launch so an emulator run needs nobody at the keyboard;
`-sbScreen` is then applied *after* sign-in, so what you see came from the
repository rather than from fixtures. All DEBUG-only.

Drop `-sbEmulator` to talk to the real `swing-buzz` project. Do that deliberately:
those writes are real, and the ledger is append-only by design.

### Testing on the live project, then starting clean

Testing against production is the only way to prove the real thing works, and it
leaves real rows behind — the ledger is append-only, so the app itself cannot undo
them. `npm run reset` can, because the Admin SDK bypasses the rules.

```bash
cd backend/import-roster && npm run reset
```

That is a **dry run**: it prints what is in the database, how much money the ledger
records, and exactly what would go. Nothing is deleted without `--apply`, and
`--apply` alone is refused — you must also name the project:

```bash
cd backend/import-roster && npm run reset -- --apply --confirm=swing-buzz
```

Two flags rather than one because there are two different mistakes: running it at
all, and running it against the wrong project. A confirmation that names a
different project is refused, and that refusal is a test.

| scope | |
| --- | --- |
| `test-data` (default) | bracelets, ledger, balances, check-ins, door-sold evening tickets. **The imported roster stays**, so no re-import and no dependency on the Sheet being reachable. |
| `--scope=all` | the above plus every participant document. Re-run the import afterwards. |

Add `--drinks` to wipe the menu too. **Staff accounts and their role claims are
never touched**, in any scope — a reset should not lock your staff out an hour
before doors.

Restart the terminals afterwards: `FirebaseTerminalRepository` caches the next
evening-ticket number for the life of the process, and a wipe puts that cache out
of step with the database.

## Tests

Three suites, three runners, **125 tests**, all green.

```bash
./ios/scripts/test.sh
```

**35 iOS tests in 6 suites.** The domain logic that carries real rules — the
keypad, the check-in search, the charge decision, participant lifecycle, evening
tickets, money arithmetic. `Domain/` imports `Foundation` only, so the whole run
finishes in 0.02s once it has built. These are the parts most likely to be broken
by a well-meaning change, so run them before you push.

```bash
cd backend/rules-tests && ./test.sh
```

**49 rules tests in 7 suites**, against a throwaway Firestore emulator that the
script starts and tears down itself — it needs a JDK, which it will find even when
Homebrew has kept it off your `PATH`. Nothing here touches the real database: the
emulator comes up empty and each test writes its own fixtures as an admin.

This is where the money invariants are actually enforced, so this is where they
are actually tested: a balance moving without a ledger entry to justify it, a bar
terminal trying to credit, a replayed transaction id, a second desk claiming
evening ticket #14. Expect `PERMISSION_DENIED` noise in the output — those are the
passing tests.

```bash
cd backend/import-roster && npm test
```

**41 importer tests** over the Sheet mapping, the drinks menu and the reset, against
pure functions and a fake Firestore — no network, no emulator. Four earn their keep
on their own: the one that stops `Full Pass Gold` being filed as plain `Full Pass`,
the one asserting no personal data can reach Firestore, the one pinning a withdrawn
drink to `isActive: false` rather than deleted so the ledger lines that name it still
resolve, and the one refusing a reset whose `--confirm` names a different project.

Reasoning about security rules is not testing them — `docs/iteration-02.md` has
the case where my rules were right and my confident assertion about them was
wrong.

---

## How it is put together

```
ios/                       the SwiftUI app
  BuzzTerminal.xcodeproj
  BuzzTerminal/
    App/                   entry point, the state machine, debug launch overrides
    DesignSystem/          Modernist tokens, typography, components, glyphs
    Domain/                models and business rules — no SwiftUI import anywhere
    Data/                  repository + bracelet-reader protocols and their mocks
    Features/              one folder per flow, one file per screen
    Resources/             Archivo (variable font) and the asset catalogue
  BuzzTerminalTests/
  scripts/                 build, test, run, screenshots
backend/                   shared by every client
  firestore.rules          the money invariants
  firestore.indexes.json
  firebase.json
  import-roster/           Google Sheet → Firestore
docs/                      schema, setup, per-iteration walkthroughs
android/                   iteration 4
```

Nothing under `backend/` is part of the Xcode project — the two synchronized
folder groups are `BuzzTerminal/` and `BuzzTerminalTests/`, so the Node tooling
cannot affect an app build.

Three boundaries do the load-bearing work:

- **`TerminalRepository`** — every backend call, written the way a network API
  behaves (`async throws`, mutations return new server state). Iteration 2 swaps
  `InMemoryTerminalRepository` for a Firebase one without touching a view.
- **`BraceletReader`** — so the app is fully developable on a Mac, where Core NFC
  does not exist. Iteration 3 adds `CoreNFCBraceletReader`.
- **`Domain/`** — imports `Foundation` only. Everything testable in microseconds.

`AppModel` is one `@Observable` state machine with a flat `Screen` enum rather
than a `NavigationStack`. That is deliberate; the reasoning is in the file.

The project uses Xcode's **file-system synchronized groups**, so new `.swift`
files in these folders are picked up automatically — no `project.pbxproj` edit
and no merge conflict.

---

## Known simplifications

Honest list of what is still faked, and when it stops being faked.

| Area | Current state | Fixed in |
| --- | --- | --- |
| Auth | real Firebase Auth exists behind `-sbBackend firebase`; the fixture path still accepts any `reception*` / `bar*` address | 2 — flip the default |
| Data | fixtures by default; Firestore behind a flag | 2 — flip the default |
| Balances | ledger + rules-enforced balance in Firestore; the fixture path is client-side arithmetic | 2 — flip the default |
| Offline | banner and queue count are cosmetic; no reachability, no queue | 3 — write-behind queue |
| NFC | simulated chip picker | 3 — Core NFC (needs a device + entitlement) |
| Dynamic Type | fixed point sizes; text does not scale | later — the 66pt display sizes need a layout pass first |
| Localisation | English strings inline; `"23.50 €"` is locale-independent by design | later |
| App icon | placeholder slot, no artwork | later |

Two intentional deviations from the prototype, both improvements:

- **Money is `Int` cents, not a `Double`.** The prototype used a JS number; that
  cannot represent 0.10 exactly, and balances accumulate error under repeated
  top-ups. See `Domain/Money.swift`.
- **The balance is re-checked, not trusted.** `PaymentDecision` runs on the client
  so the operator gets an instant answer, and the repository verifies again — a
  second terminal may have spent the money in between. On Firestore this is no
  longer a courtesy: `firestore.rules` refuses any balance that does not agree with
  the ledger entry written in the same batch, so a stale client cannot overdraw
  even if it tries.

---

## Roadmap

1. ✅ **Iteration 1** — project, Modernist design system in SwiftUI, every screen
   on an in-memory repository. See `docs/iteration-01.md`.
2. ✅ **Iteration 2** — Firebase. The terminal runs on Firestore against enforced
   rules. **83 paid participants live**, imported from the Google Sheet. Schema in
   `docs/firestore-schema.md`, invariants in `backend/firestore.rules`, project
   setup in `docs/firebase-setup.md`, walkthrough in `docs/iteration-02.md`.

   Be precise about what is verified where, because the two are easy to conflate:

   | | |
   | --- | --- |
   | **Emulator**, same `firestore.rules` the deploy uses | both roles, pairing, top-up, charge, all three refusals, a reconciling ledger |
   | **Production** | sign-in, custom claim, the drinks query, the 83-person roster read — **read-only** |

   No money has ever moved in production: zero bracelets, zero ledger entries. The
   write path is proven against the rules, not yet against the live project.
3. **Iteration 3** — Core NFC bracelet reading, real offline queue with sync.
   NFC needs a physical device and the entitlement, so it is the first thing here
   the Simulator cannot verify.
4. **Iteration 4** — Android app in Jetpack Compose against the same backend.

The production menu is **Water 2 €, Beer 4 €, Gin & Tonic 6 €**, seeded by
`npm run seed-drinks -- --apply` and owned by the web admin panel once that exists.
The ten drinks in `SampleData` are the design prototype's invention and stay on the
fixture path only.

One thing still stands between iteration 2 and a festival: Firebase is opt-in — see
the table above.

## Credits

Archivo by Omnibus-Type, under the SIL Open Font License — see
`ios/BuzzTerminal/Resources/Fonts/OFL.txt`.
