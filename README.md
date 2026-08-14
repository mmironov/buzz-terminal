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
**"Prototype · simulate a bracelet"** panel with the four fixture chips:

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

## Tests

```bash
./ios/scripts/test.sh
```

25 tests across 4 suites, all green.

The three pieces of domain logic that carry real rules — the keypad, the check-in
search, and the charge decision — have dedicated regression cover in
`ios/BuzzTerminalTests/DomainTests.swift`. They are the parts most likely to be
broken by a well-meaning change, so run the suite before you push.

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

Honest list of what is faked in iteration 1, and when it stops being faked.

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
- **The server re-checks the balance on charge.** `PaymentDecision` runs on the
  client so the operator gets an instant answer, but
  `InMemoryTerminalRepository.charge` verifies again — a second terminal may have
  spent the money in between. Firestore transactions make this real in
  iteration 2.

---

## Roadmap

1. ✅ **Iteration 1** — project, Modernist design system in SwiftUI, all 10
   screens on an in-memory repository, 25 tests green.
   See `docs/iteration-01.md`.
2. **Iteration 2** — Firebase. Backend design done and committed:
   `docs/firestore-schema.md`, `backend/firestore.rules`,
   `backend/firestore.indexes.json`, and `backend/import-roster/`
   (Google Sheet → Firestore, roster fields only).
   Follow `docs/firebase-setup.md` to create the project; the Swift side
   (`FirebaseTerminalRepository`) lands once `GoogleService-Info.plist` exists.
3. **Iteration 3** — Core NFC bracelet reading, real offline queue with sync.
4. **Iteration 4** — Android app in Jetpack Compose against the same backend.

## Credits

Archivo by Omnibus-Type, under the SIL Open Font License — see
`ios/BuzzTerminal/Resources/Fonts/OFL.txt`.
