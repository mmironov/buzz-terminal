# Firebase setup

Everything here needs your Google account, so it is yours to do. I cannot create
the project, generate credentials, or share the Sheet on your behalf.

Work through it in order. Steps 1–4 unblock the importer; steps 5–7 unblock the
iOS app.

---

## 1. Create the project

[console.firebase.google.com](https://console.firebase.google.com) → *Add project*.

- Name it something like `swing-buzz` — note the **project id** it generates
  (often `swing-buzz-a1b2c`), which is what the tooling wants.
- Google Analytics: not needed, skip it.
- **Stay on the free Spark plan.** Nothing in this design needs Blaze: no Cloud
  Functions, no Cloud Scheduler. The importer runs on your Mac.

## 2. Firestore

*Build → Firestore Database → Create database*.

- Start in **production mode**. Not test mode — test mode leaves the database
  world-readable for 30 days, and this one holds people's names and balances.
  The real rules go in at step 4.
- Location: pick the region closest to the festival and note it. **This cannot be
  changed later.** `europe-west3` (Frankfurt) or `europe-west1` (Belgium) are the
  usual European choices.

## 3. Authentication

*Build → Authentication → Get started → Email/Password → Enable.*

Leave passwordless sign-in off. Then create the staff accounts you need under
*Users → Add user*, e.g.:

- `reception@swingbuzz.fest`
- `bar@swingbuzz.fest`

Roles are **not** set here — there is nowhere in the console to do it. Step 4c
handles that. Until a role claim exists, the security rules deny that account
everything, which is the correct default.

## 4. Deploy the rules and run the importer

You will need the Firebase CLI for the rules:

```bash
npm install -g firebase-tools
cd backend
firebase login
firebase use --add        # pick the project, alias it "default"
firebase deploy --only firestore:rules,firestore:indexes
```

`firestore.rules` and `firestore.indexes.json` live in `backend/`, alongside the
`firebase.json` that points at them — which is why the CLI is run from there.

**4b.** Follow `backend/import-roster/README.md` for the service-account key, the
Sheets API, and sharing the Sheet. Then:

```bash
cd backend/import-roster && npm install
npm run headers                    # tells you the Sheet's columns
# …edit mapping.mjs…
npm run import                     # dry run
npm run import -- --apply
npm run seed-drinks -- --apply
```

**4c.** Give each staff account its role:

```bash
npm run set-role -- reception@swingbuzz.fest reception --apply
npm run set-role -- bar@swingbuzz.fest bar --apply
```

## 5. Register the iOS app

*Project settings → General → Your apps → Add app → iOS.*

- Bundle id: **`fest.swingbuzz.BuzzTerminal`** — must match exactly, it is what
  `PRODUCT_BUNDLE_IDENTIFIER` is set to in the project.
- App nickname: anything.
- Download `GoogleService-Info.plist` and put it at
  **`ios/BuzzTerminal/Resources/GoogleService-Info.plist`**.

It is gitignored. That is intentional: it identifies your project and pins the
API keys, and while it is not a secret in the way a service-account key is, it
does not belong in a repo that might one day be shared. Anyone else building the
app downloads their own.

Skip the console's "add the SDK" instructions — the SPM wiring is my job once the
plist is in place.

## 6. Optional but recommended: the emulator

Lets you test the security rules without touching real data, and lets me write
executable tests for them. Needs a Java runtime, which is why it is not set up
yet:

```bash
brew install --cask temurin        # a JDK; no sudo needed
firebase emulators:start
```

The rules in `backend/firestore.rules` guard real money and have **never been executed**
— only reasoned about. I would rather they had tests before a festival relies on
them. Say the word once Java is installed.

## 7. Tell me

- The **project id**
- The Firestore **region** you picked
- That the plist is in `ios/BuzzTerminal/Resources/`
- The Sheet's **header row**, and which column is the stable unique key

Then I will do the Swift side: the `Domain/` change described at the end of
`docs/firestore-schema.md`, the SPM dependency, and `FirebaseTerminalRepository`
behind the existing `TerminalRepository` protocol.

---

## Cost

Free tier, comfortably. A festival of a few thousand participants with a couple of
terminals is far below the Spark plan's daily limits (50k document reads, 20k
writes). The design keeps it that way on purpose:

- A bracelet scan is a **point read by document id**, not a query.
- The roster is loaded once and filtered in memory, not re-queried per keystroke.
- `rosterHash` means a re-import writes only rows that actually changed.

## What is deliberately not here

- **No Cloud Functions.** The terminals write to Firestore directly, because the
  bar must keep working when the wifi drops and Firestore's offline persistence
  only applies to client writes — a callable function just fails offline. This is
  why the money invariants live in `backend/firestore.rules` rather than in server code.
- **No admin panel.** Blocking a bracelet and lifting a block are organiser
  actions the design attributes to a web panel that does not exist yet. Until it
  does, `isBlocked` is edited in the Firestore console. The rules already forbid
  any terminal from changing it.
