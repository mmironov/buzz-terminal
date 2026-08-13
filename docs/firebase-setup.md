# Firebase setup

Everything here needs your Google account, so it is yours to do. I cannot create
the project, generate credentials, or share the Sheet on your behalf.

Work through it in order. Steps 1–4 unblock the importer; steps 5–7 unblock the
iOS app.

---

## 1. Create the project

[console.firebase.google.com](https://console.firebase.google.com) → *Add project*.

- Name it something like `swing-buzz` — note the **project id** it generates
  (often with a suffix, `swing-buzz-a1b2c`), which is what the tooling wants.
  **Done: this project is `swing-buzz`.**
- Google Analytics: not needed, skip it.
- **Stay on the free Spark plan.** Nothing in this design needs Blaze: no Cloud
  Functions, no Cloud Scheduler. The importer runs on your Mac.

## 2. Firestore

*Build → Firestore Database → Create database*.

- **Standard edition**, not Enterprise. Enterprise is Firestore with MongoDB
  compatibility — accessed through MongoDB drivers, for teams migrating off
  MongoDB. It does not use Firebase Security Rules, which is our entire
  access-control model, and it is not on the free tier. If a description mentions
  *MongoDB compatibility*, that is the wrong one.
- **Native mode**, if asked. The Firebase console picks this for you; the Google
  Cloud console asks. Datastore mode has no real-time listeners and no mobile SDK.
- Start in **production mode**. Not test mode — test mode leaves the database
  world-readable for 30 days, and this one holds people's names and balances.
  The real rules go in at step 4.
- Location: pick the region closest to the festival. **This cannot be changed
  later** — an existing database's region is fixed for its lifetime.
  **Done: `europe-west10` (Berlin), single-region.**

All four are effectively permanent: edition, mode and region cannot be converted
on an existing database, so getting one wrong means deleting and recreating.

> **What happened here.** The console defaulted the location to `nam5` (US
> multi-region). Caught while the database was still empty and recreated in
> `europe-west10`. Two reasons: every scan, top-up and charge from a European
> venue was crossing the Atlantic — roughly 100–150 ms per round trip on a device
> being used one-handed with a queue at the bar — and the roster is names, cities
> and ticket purchases of EU residents, which is far simpler to reason about when
> it never leaves the EU. Deleting an empty database costs nothing; migrating a
> populated one costs a lot.

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
firebase deploy --only firestore:rules,firestore:indexes
```

No `firebase use --add` needed: `backend/.firebaserc` already aliases `swing-buzz`
as the default project. It is committed on purpose — a project id is not a secret
(it ships inside every app binary via the plist) and committing it means anyone
with access can deploy without guessing.

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

## 6. The emulator and the rules tests — done

```bash
cd backend/rules-tests && ./test.sh
```

36 tests against a throwaway Firestore emulator; nothing touches the real
database. See `backend/rules-tests/README.md` for what is covered.

The emulator needs a JDK. Installed via the Homebrew **formula**
(`brew install openjdk`) rather than the `temurin` cask: the formula needs no
sudo and stays inside the Homebrew prefix. It is keg-only, so `test.sh` locates
it rather than requiring anything on your `PATH`.

Run these before deploying a rules change. `firebase deploy` will happily ship a
rules file that locks out every terminal, or one that lets the bar credit itself.

## 7. Tell me

- ~~The **project id**~~ — `swing-buzz`, wired into `backend/.firebaserc`
- ~~The Firestore **region**~~ — `europe-west10` (Berlin), `(default)` database
- ~~The **plist**~~ — in place; the app logs "Firebase configured for project
  swing-buzz" at launch
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
