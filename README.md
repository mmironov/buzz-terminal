# Swing Buzz — Staff Terminal

Festival staff app for bracelet check-in, balance top-up and bar payments.
Ported from the Claude Design prototype `Swing Buzz Staff App.dc.html` on the
**Modernist** design system: SwiftUI in `ios/`, Jetpack Compose in `android/`,
React in `web-admin/`, all three against the same Firebase backend in `backend/`.

iOS is the finished one and everything down to "The Android app" describes it.
Android is in progress; that section says exactly how far. `web-admin/` is the
organiser panel — blocks and the drinks menu — and has its own section below.

---

## iOS: one-time setup

This Mac has Xcode installed but `xcode-select` pointing at the Command Line
Tools, which stops `xcodebuild` from running. Fix it once:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

The scripts in `ios/scripts/` set `DEVELOPER_DIR` themselves so they work either way,
but Xcode's own simulator tooling and the live-preview integrations need the
pointer to be correct.

## Running the iOS app

```bash
open ios/BuzzTerminal.xcodeproj
```

⌘R runs it. Or from the command line:

```bash
./ios/scripts/run.sh
```

That talks to the **real** `swing-buzz` project, so it wants a real staff account.
For the self-contained fixture version — no network, no credentials, invented
people:

```bash
./ios/scripts/run.sh -sbBackend memory
```

On that path the login screen offers two demo buttons that fill the fields for you,
any address starting `reception` or `bar` works, and the password is ignored. Those
buttons are hidden on the Firebase path, because there they cannot work.

There is no NFC hardware on the Simulator, so the scan sheet offers a
**"Prototype · simulate a bracelet"** panel with the five fixture chips. These
exist on the `-sbBackend memory` path only — production has its own bracelets, or
none yet:

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

### Running against the emulators

**Firestore is the default backend**, in debug and release alike — deliberately the
same, so what you develop against is what staff run. `-sbBackend memory` opts out
to the fixtures; `-sbEmulator` keeps Firebase but points it at local emulators
instead of the live festival database:

```bash
cd backend && firebase emulators:start --only firestore,auth --project swing-buzz
```

```bash
cd backend && ./seed-emulator.sh    # staff accounts with role claims, a few participants, drinks
```

```bash
./ios/scripts/run.sh -sbEmulator -sbSignIn reception@example.test festival26 -sbScreen assign
```

`-sbSignIn` signs in on launch so an emulator run needs nobody at the keyboard;
`-sbScreen` is then applied *after* sign-in, so what you see came from the
repository rather than from fixtures. All DEBUG-only.

Drop `-sbEmulator` and you are on the real `swing-buzz` project — which is the
default, so it is what you get by typing nothing. Those writes are real and the
ledger is append-only by design, so `npm run reset` is how you undo a test session.

### Onto staff phones

TestFlight, with a public link — no App Store listing, no UDIDs. Full runbook in
`docs/distribution.md`; it needs an Apple Developer Program membership.

```bash
ASC_KEY_ID=F85F3QH33R ASC_ISSUER_ID=<uuid> ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_F85F3QH33R.p8 ./ios/scripts/release.sh --upload
```

The team id comes from the project, so it needs no flag. The build number is
`git rev-list --count HEAD`, so it always rises and the same commit always yields
the same number — App Store Connect rejects a repeat. Credentials are checked before
anything builds, so a wrong path fails in under a second.

```bash
./ios/scripts/release.sh --unsigned
```

Archives for a real device with no team and no certificates, which is how to check
the archive still builds before any of the Apple paperwork exists.

⚠️ **TestFlight builds expire after 90 days and an expired build refuses to
launch.** Upload a fresh one the week of the festival.

### Re-importing the roster

People keep paying, so the roster keeps moving. The Sheet id is in
`backend/import-roster/sheet.json`, so this needs no arguments:

```bash
cd backend/import-roster && npm run headers
```

```bash
cd backend/import-roster && npm run import
```

`headers` prints the live header row and per-status counts — that is what catches a
renamed column, or a status spelled something other than `paid`, before anything is
written. `import` is a dry run showing exactly who would be created or changed; add
`--apply` to commit it.

Only `Status = paid` is imported, and only roster fields. Balances, bracelets and
check-in state belong to the terminals and are never touched, so re-importing
mid-festival cannot clobber somebody who has already checked in.

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

## The Android app

Jetpack Compose, the same Modernist design system, the same `swing-buzz` project.
Two Gradle modules:

```
android/
  domain/      the festival's rules — a plain Kotlin JVM module
  app/         Compose UI, the state machine, everything Android-only
  scripts/     build, test, run
```

`:domain` has no Android dependency at all, which is how the iOS rule that
`Domain/` imports only Foundation is enforced on this side: you cannot reach for
a Composable or a Context in it, because neither is on the compile classpath. It
holds the models, the money arithmetic, the charge decision, the keypad, the
repository seam and the fixture backend — so all of that tests in seconds with
no emulator in sight.

```bash
cd android && ./scripts/run.sh
```

Builds, installs and launches. It boots the AVD named by `$AVD` (default
`BuzzPhone`) only when nothing is attached already, so plugging in a real phone
and running it uses the phone.

```bash
cd android && ./scripts/build.sh    # compile only, no device
```

`./scripts/test.sh` runs the domain suite; it is described under "Tests" below.

There is no JDK on this Mac's `PATH`. `scripts/_env.sh` points `JAVA_HOME` at the
one Android Studio ships — which is also the one Studio itself builds with, so
the IDE and the command line agree. That is the same trick `ios/scripts/_env.sh`
plays with `DEVELOPER_DIR`.

### What works today

All eleven screens, against Firestore, plus NFC, scan feedback and the offline
queue — the same three pieces iOS has, sharing the same pure logic in `:domain`.

One platform difference worth knowing before somebody "fixes" it: Android reads
chips in **reader mode**, which suppresses the platform's own tag animation, so the
Modernist scan overlay stays on screen for the whole read. Core NFC always presents
Apple's own sheet over the top. The Android scan is therefore closer to the design
than the iOS one. Sign-in reads the staff role from the
same custom claim the iOS app does, reception checks a bracelet in and takes
cash, the bar charges a round, and all four refusals — not recognised, blocked,
not enough balance, no role — reach the glass. The `when` over `Screen` is
exhaustive; there is no placeholder left to land on.

**Firestore is the default backend**, in debug and release alike, for the reason
the iOS app has it that way: different defaults per build type means you exercise
the fixtures all week and ship the real backend. `--es sbBackend memory` opts out
to the fixtures, and a clone with no `google-services.json` lands there anyway,
so the app stays walkable for someone who has not been through
`docs/firebase-setup.md`. A release build is not given that latitude — with no
configuration it refuses to start rather than put a convincing fake till in a
bartender's hands.

Against the emulators:

```bash
cd backend && firebase emulators:start --only firestore,auth --project swing-buzz
cd backend && ./seed-emulator.sh
```

```bash
adb reverse tcp:8080 tcp:8080 && adb reverse tcp:9099 tcp:9099
adb shell am start -n fest.swingbuzz.terminal/.MainActivity --ez sbEmulator true
```

Those two `adb reverse` lines are not optional, and the reason is worth knowing
before it costs an afternoon. The documented way for an Android emulator to reach
its host is `10.0.2.2`, and it does not work for an app on a current AVD:
`ip route` shows `10.0.2.0/24` on both `eth0` (the QEMU NAT, where that alias
lives) and `wlan0` (the emulated access point, where it does not). App traffic
binds to Wi-Fi, so the packets go to the virtual AP and vanish. From `adb shell`
the same address answers — measured here, the shell got HTTP 200 while the app's
own uid timed out after ten seconds and the Auth emulator logged neither. It
reads exactly like a broken app. `adb reverse` sidesteps the routing entirely and
works on a USB-attached phone too. `--es sbEmulatorHost <ip>` overrides it for a
device on the same wifi.

Debug builds carry a `network-security-config` permitting cleartext to those
loopback hosts only, because the emulators speak plain HTTP and Android has
refused cleartext by default since API 28. It lives in `src/debug/`, so a release
build keeps the platform default of refusing it everywhere.

Archivo comes across as the same variable `.ttf` the iOS app carries, asked for
four weights through `FontVariation` rather than shipped as four static cuts.
`designsystem/Gallery.kt` renders the whole system on one page — an Android
Studio preview now that sign-in owns the launch screen — and carries a weight
check, because the failure it guards against is invisible: Archivo's variable
default is `wght` 600, so a family that loads but never applies its variation
settings renders everything at semibold and reads as a design choice.

### Onto staff phones

**Firebase App Distribution**, in the same `swing-buzz` project — free, no Play
account, no review. Full runbook in `docs/distribution.md`.

```bash
./android/scripts/release.sh --distribute --group staff
```

`versionCode` is `git rev-list --count HEAD`, the same trick the iOS build number
uses: it always rises, and a device silently keeps the old build if it ever went
backwards.

The signing key is created once, by `./android/scripts/keystore.sh` — not by
calling `keytool` yourself, which fails with "Unable to locate a Java Runtime"
because this Mac has no JDK on `PATH`. It writes `android/keystore.properties`
and the `.jks`, both gitignored. Without them the release variant still builds,
unsigned, which no device will install — so it cannot pass for a real one.

**The keystore is not recoverable**: Android refuses an update signed by a
different key, and the only way out is uninstalling from every phone.

### Toolchain, and why these versions

| | |
| --- | --- |
| **AGP 9.2.1** | deliberately not the newest. Studio refuses to open a project whose AGP is ahead of it, and an IDE that cannot open the project is worse than being one release behind. Raise it when Studio is updated. |
| **Gradle 9.5** | what AGP 9 requires. |
| **no `kotlin-android` plugin** | from AGP 9 the Android plugin brings Kotlin itself and applying both is an error. `:domain` still applies `kotlin.jvm`, because it is not an Android module. |
| **compileSdk 37** | not a preference: androidx 1.12 and core-ktx 1.19 refuse to be compiled against 36. |
| **minSdk 26** | `java.time`, which the domain uses for check-in timestamps, and variable-font support, which Archivo needs. |

Two AVD settings that `avdmanager` gets wrong by default, both of which look
exactly like a hung emulator rather than a misconfiguration: `hw.gpu.enabled=no`
renders a black screen forever on API 37, and `hw.keyboard=no` makes typing an
address into the sign-in field impossible from the host keyboard.

---

## The organiser panel

`web-admin/` — React and TypeScript on Vite, the same Modernist look, the same
`swing-buzz` project. Two screens, and the interesting part is what it cannot do.

**Participants.** The whole roster live, searchable by name, ticket reference, pass
type or chip id, showing each person's bracelet, balance and block state. Expanding
a row gives their ledger: every top-up and every round, newest first, itemised —
`3 × Beer (4.00 € each)` — with the prices as they were at the moment of sale, and
a footer saying whether the entries add up to the balance on the bracelet.

**Bar.** The drinks catalogue: add, rename, reprice, reorder, take off the menu,
delete. Taking off the menu (`isActive: false`) is the reversible one for a keg that
ran out; deleting is for something entered by mistake.

Blocking a bracelet is the panel's only write to a person. It cannot edit the roster
or touch history, and it cannot adjust a balance silently — a balance moves only
alongside a ledger entry in the same batch, for every role. Enforced by
`firestore.rules`, not by the panel's own code, so removing a check there produces
permission errors rather than extra authority. `docs/firestore-schema.md`, "Roles",
has the table.

Getting in needs an account whose token carries `role: admin`:

```bash
cd backend/import-roster && npm run set-role -- you@swingbuzz.fest admin --apply
```

An `admin` **also counts as reception**: the same account signs into the terminal
apps and gets the reception flow, so an organiser can check people in and top them
up without a second login. It still cannot charge — debiting is the bar's alone.
Reception and bar accounts cannot sign into the panel.

Running it locally against the emulators needs no Firebase project at all:

```bash
cd backend && firebase emulators:start --only firestore,auth --project swing-buzz
cd backend && ./seed-emulator.sh          # accounts, three participants, the menu
cd web-admin && npm run seed:history      # bracelets, top-ups, itemised rounds
cd web-admin && npm run dev:emulator      # localhost:5173, prefilled sign-in
```

`seed:history` deliberately avoids the Admin SDK: it signs in as reception and bar
with the client SDK and sends exactly the batches the two apps send, so every write
goes through the rules and a wrong shape fails loudly. Full runbook, including
`npm run deploy` to Firebase Hosting, in `web-admin/README.md`.

## Tests

Four runners, **218 tests**, all green: 41 iOS, 67 Android, 69 rules, 41 importer.

```bash
./ios/scripts/test.sh
```

**41 iOS tests in 7 suites.** The domain logic that carries real rules — the
keypad, the check-in search, the charge decision, participant lifecycle, evening
tickets, money arithmetic. `Domain/` imports `Foundation` only, so the whole run
finishes in 0.02s once it has built. These are the parts most likely to be broken
by a well-meaning change, so run them before you push.

The seventh suite is the odd one out: it covers the ledger itemisation a charge
carries, which is a Firestore payload rather than domain logic. It is there because
the field names are a security contract, and because writing the line total where
the unit price belongs would still add up against a total computed the same wrong
way — the rules would accept a receipt claiming beer costs 12 €, and nothing
downstream would notice.

```bash
cd android && ./scripts/test.sh
```

**67 Android tests**, plain JVM, no emulator. Sixty are in `:domain`, and seven in
`:app` — the mirror of the iOS itemisation suite, and the only tests that module
has, because the Firestore field names are a contract `:domain` deliberately cannot
see. Thirty-six of the domain tests are
the iOS suite case for case — same rules, same order — so a change to one side
should show up as a change to both, and a divergence in the two apps' behaviour
is a failing test rather than a discovery at the festival. The keypad's 999 €
cap is covered here and not there; that rule was written on the iOS side and
never asserted.

The other 21 cover the fixture repository, which the iOS side does not test at
all — it is exercised only by using the app. They are worth their file because
the rules they assert are the rules `firestore.rules` enforces with real money
behind them: a blocked bracelet buying nothing whatever its balance, a refused
charge leaving the balance untouched, a second chip for the same guest refused
rather than stranding the first one's, and twenty simultaneous top-ups all
landing.

```bash
cd backend/rules-tests && ./test.sh
```

**69 rules tests in 10 suites**, against a throwaway Firestore emulator that the
script starts and tears down itself — it needs a JDK, which it will find even when
Homebrew has kept it off your `PATH`. Nothing here touches the real database: the
emulator comes up empty and each test writes its own fixtures as an admin.

This is where the money invariants are actually enforced, so this is where they
are actually tested: a balance moving without a ledger entry to justify it, a bar
terminal trying to credit, a replayed transaction id, a second desk claiming
evening ticket #14, a charge whose itemisation does not add up to what left the
bracelet, and an organiser panel trying to move money. Expect `PERMISSION_DENIED`
noise in the output — those are the passing tests.

One of these tests earns its place by being expensive rather than by being clever:
the eight-line charge at the itemisation cap. Rules cannot loop, so that sum is
unrolled, and at ten lines it exceeded Firestore's budget of 1,000 expressions per
request — a production-only failure that the rule text gives no hint of, found
because the test ran.

```bash
cd backend/import-roster && npm test
```

**41 importer tests** over the Sheet mapping, the drinks menu and the reset, against
pure functions and a fake Firestore — no network, no emulator. Four earn their keep
on their own: the one that stops `Full Pass Gold` being filed as plain `Full Pass`,
the one asserting no personal data can reach Firestore, the one pinning a drink the
seed no longer lists to `isActive: false` rather than deleted, and the one refusing a
reset whose `--confirm` names a different project.

The panel has no test runner of its own. `npm run build` typechecks it, and what it
does is checked where the authority actually lives: the rules tests assert every
power it has and every one it does not, from both directions.

Reasoning about security rules is not testing them — `docs/iteration-02.md` has
the case where my rules were right and my confident assertion about them was
wrong.

---

## How the iOS app is put together

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
  firebase.json            rules, indexes, emulators
  import-roster/           Google Sheet → Firestore
  rules-tests/             the emulator harness
docs/                      schema, setup, per-iteration walkthroughs
android/                   the Jetpack Compose app
  domain/                  models, rules, the repository seam — no Android
  app/                     Compose UI, AppModel, the Android-only bits
  scripts/                 build, test, run
web-admin/                 the organiser panel (React, Vite)
  src/schema.ts            the field names, hand-written like both apps' mappings
  scripts/                 emulator fixtures, written through the rules
  firebase.json            hosting — deliberately not in backend/, see its README
```

Nothing under `backend/` is part of the Xcode project — the two synchronized
folder groups are `BuzzTerminal/` and `BuzzTerminalTests/`, so the Node tooling
cannot affect an app build.

Three boundaries do the load-bearing work:

- **`TerminalRepository`** — every backend call, written the way a network API
  behaves (`async throws`, mutations return new server state). Iteration 2 swaps
  `InMemoryTerminalRepository` for a Firebase one without touching a view.
- **`BraceletReader`** — so the app is fully developable on a Mac, where Core NFC
  does not exist. `CoreNFCBraceletReader` fills it in on hardware — see `docs/nfc.md`.
- **`Domain/`** — imports `Foundation` only. Everything testable in microseconds.

`AppModel` is one `@Observable` state machine with a flat `Screen` enum rather
than a `NavigationStack`. That is deliberate; the reasoning is in the file.

The project uses Xcode's **file-system synchronized groups**, so new `.swift`
files in these folders are picked up automatically — no `project.pbxproj` edit
and no merge conflict.

---

## Known simplifications (iOS)

Honest list of what is still faked, and when it stops being faked. Android's
equivalent is "The Android app" above — it is behind on more than this.

| Area | Current state | Fixed in |
| --- | --- | --- |
| Auth | ✅ real Firebase Auth, custom-claim roles. `-sbBackend memory` still accepts any `reception*` / `bar*` address, and that path only | — |
| Data | ✅ Firestore by default, debug and release alike | — |
| Balances | ✅ ledger + rules-enforced balance. The `-sbBackend memory` path is client-side arithmetic | — |
| Offline | ✅ real: Firestore's durable queue, real connectivity, and a reconciliation screen for refused replays — `docs/offline.md` | — |
| NFC | ✅ Core NFC reads real bracelets on a device; the simulated picker remains where hardware is absent, and behind `-sbScanner simulated` | — |
| Dynamic Type | fixed point sizes; text does not scale | later — the 66pt display sizes need a layout pass first |
| Localisation | English strings inline; `"23.50 €"` is locale-independent by design | later |
| App icon | generated, on-brand, deliberately plain — `ios/scripts/makeicon.swift` redraws it | when someone wants real artwork |

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
   rules. **85 paid participants live**, imported from the Google Sheet. Schema in
   `docs/firestore-schema.md`, invariants in `backend/firestore.rules`, project
   setup in `docs/firebase-setup.md`, walkthrough in `docs/iteration-02.md`.

   Be precise about what is verified where, because the two are easy to conflate:

   | | |
   | --- | --- |
   | **Emulator**, same `firestore.rules` the deploy uses | both roles, pairing, top-up, charge, all three refusals, a reconciling ledger |
   | **Production** | sign-in, custom claim, the drinks query, the roster read, **and one real check-in and top-up** |

   The money path now works on the live project, not only against the rules. On
   19 Aug 2026 chip `99:C8:65:13` was paired to participant `159` and topped up
   50 €, and the ledger reconciles: one `topup` entry of `5000`, balance `5000`,
   stamped with the staff uid and terminal id. A **charge** has still only ever
   run against the emulator. `npm run reset -- --apply --confirm=swing-buzz`
   clears test traces before doors.
3. ✅ **Iteration 3** — Core NFC and the offline queue, both verified against real
   hardware and a real backend rather than reasoned about. NFC is
   verified against physical wristbands: a chip reads as `1D:94:9D:D4:11:10:80`.
   `docs/nfc.md` covers the entitlement, the system scan sheet, and the two checks
   worth running on a batch of bracelets before trusting it.
4. 🔄 **Iteration 4** — Android app in Jetpack Compose against the same backend.
   Done: the Gradle project, the domain ported with its tests, Modernist in
   Compose, the `AppModel` state machine, all eleven screens, and a
   `FirebaseTerminalRepository` that writes the same documents the Swift one
   does — verified against the emulator, the same way iteration 2 was. Details in
   "The Android app" above.

   Also done, catching up with iteration 3: **real NFC** via reader mode, **scan
   sounds and haptics** at the same three frequencies as iOS, and the **offline
   queue** with the same reconciliation screen. `docs/nfc.md` and
   `docs/offline.md` cover both platforms.

   Still to do: a run against production, which has not happened from Android at
   all, and a real chip read on Android hardware.

   **Not** to do: the tag inspector and the batch audit stay iOS-only. Bracelet
   auditing will be done on iPhones, so a Compose port would be a second
   implementation of the duplicate-detection rule with nothing asking for it.
5. ✅ **Iteration 5** — the organiser panel, `web-admin/`. Blocks with an audit
   trail, purchase history, and the drinks menu moved out of a seed script and into
   an organiser's hands. It also added itemisation to the ledger, which is a change
   to the money rules and therefore to both apps: a charge now records what it
   bought, and the lines must add up to what left the bracelet. Section above,
   walkthrough in `docs/iteration-05.md`, runbook in `web-admin/README.md`.

   Not verified against production: the panel has only ever run against the
   emulator. Pointing it at the live project needs a web app registered in the
   Firebase console and an `admin` claim granted.

The production menu is **Water 2 €, Beer 4 €, Gin & Tonic 6 €**, bootstrapped by
`npm run seed-drinks -- --apply` and now owned by the organiser panel — re-running
that seed against a live festival would overwrite what an organiser has done there.
The ten drinks in `SampleData` are the design prototype's invention and stay on the
fixture path only.

A release build talks to Firestore or refuses to launch. There is no fixture
fallback outside DEBUG, on purpose: a till that convincingly pretends to work —
accepting any `reception*` login, serving invented drinks, taking payments that go
nowhere — is far worse in a bartender's hands than one that will not start. The
reasoning is in `App/BuzzTerminalApp.swift`.

## Credits

Archivo by Omnibus-Type, under the SIL Open Font License. Both apps ship the
same variable `.ttf`; the licence travels with each copy —
`ios/BuzzTerminal/Resources/Fonts/OFL.txt` and `android/app/licenses/OFL.txt`.
