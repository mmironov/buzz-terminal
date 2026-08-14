# Organiser panel

The web half of the festival: participants, bracelet blocks, purchase history and
the drinks menu. React + TypeScript on Vite, talking to the same `swing-buzz`
Firestore the two terminal apps do.

It does two things, and the interesting part is everything it deliberately cannot
do. See *Authority* below.

```bash
cd web-admin
npm install
```

## Running it against the emulator

No Firebase project, no credentials, no real data. Three terminals:

```bash
cd backend && firebase emulators:start --only firestore,auth --project swing-buzz
```

```bash
cd backend && ./seed-emulator.sh          # staff accounts, three participants, the menu
cd web-admin && npm run seed:history      # bracelets, top-ups and itemised rounds
```

```bash
cd web-admin && npm run dev:emulator
```

Then <http://localhost:5173>, signing in as `admin@example.test` / `festival26`
— the fields come prefilled and a black banner across the top says the data is
not real.

`npm run seed:history` is worth knowing about. It does **not** use the Admin SDK:
it signs in as `reception@example.test` and `bar@example.test` with the client SDK
and sends exactly the batches the iOS and Android repositories send, so every
write goes through `firestore.rules`. If a write shape is wrong the script fails.
It is a rehearsal of the terminals, not a shortcut around them — which is also
what makes the history it produces worth looking at.

## Running it against the real project

```bash
cp .env.example .env.local     # then fill in from the Firebase console
npm run dev
```

The five values come from **Project settings → General → Your apps → Web app →
SDK setup and configuration**; register a web app there first if none exists.
`.env.local` is gitignored.

Those values are not secrets — a Firebase web config ships inside every web app
that talks to the project, and what protects the roster is `firestore.rules` plus
the `admin` custom claim, not the obscurity of an API key. They are gitignored
anyway, so that "project configuration stays out of git" is one rule rather than
three.

## Getting in

Sign-in needs an account whose token carries `role: admin`. Custom claims can
only be set with the Admin SDK — never from the Firebase console, and never by a
client — which is exactly why they are trustworthy:

```bash
cd backend/import-roster
npm run set-role -- you@swingbuzz.fest admin --apply
```

Then sign out and in again; a claim granted after this browser last signed in sits
behind a cached token otherwise. Signing in without the claim gets an explicit
"not an organiser" screen with that command in it, rather than a panel that
renders and then fails every read.

`admin` is not a terminal role. The iOS and Android apps refuse the account, and
reception and bar accounts are refused here.

## Authority

Two powers:

- **Block a bracelet**, with a reason, recorded against who did it and when. Every
  terminal then refuses it — no top-up, no drink — and shows the reason verbatim
  to whoever is at the desk. Blocking is also how an expired evening ticket gets
  frozen, since validity is not enforced anywhere in the app.
- **Own the drinks menu.** Add, rename, reprice, reorder, take off the menu, delete.

And, on purpose, no others:

| | |
| --- | --- |
| Adjust a balance | **No.** Money that moved is accounted for by a ledger entry. A correction with no entry behind it is the thing the ledger exists to prevent — if a guest is owed money, reception tops them up and history says so. |
| Edit or delete history | **No.** The ledger is append-only for every role, including this one. A dispute at the bar is answered by reading it. |
| Change a name, pass type or country | **No.** The roster belongs to the Google Sheet and the importer that reads it. |
| Pair or re-point a bracelet | **No.** That is reception's job, and a pairing is permanent by design. |
| Sell an evening ticket | **No.** Reception's hole, narrowly. |

None of that is enforced by this code. It is enforced by `firestore.rules`, and
asserted from both directions by the tests in `backend/rules-tests/` — deleting a
check here would produce a panel full of permission errors, not a panel that can
do more.

## Purchase history

Each participant expands into their ledger: every top-up and every round, newest
first, with the itemisation the bar recorded — `3 × Beer (4.00 € each)`, and the
price as it was **at the moment of sale**, so repricing a drink tomorrow cannot
rewrite tonight's receipt.

The footer adds the entries up and compares the total to the balance on the
bracelet. Those must agree; `firestore.rules` enforces it one entry at a time, and
this is the same arithmetic across all of them. A row saying they do not agree
means something wrote a balance the rules should have refused, which is worth
seeing on a screen rather than in a report nobody runs.

Charges written before the terminals recorded itemisation say *"Itemisation not
recorded"* rather than rendering an empty list that would read like "bought
nothing".

## Taking a drink off the menu vs deleting it

Both are here because they are different things:

- **Take off menu** sets `isActive: false`. The bar queries `isActive == true`, so
  it vanishes from every terminal, and one click puts it back. This is the one for
  a keg that ran out.
- **Delete** removes the document. For something entered by mistake. Safe only
  because ledger lines snapshot the drink's name and price, so last night's
  receipts do not depend on the document existing — before that was true, the
  rules forbade deletion outright.

## Deploying

```bash
npm run deploy
```

`tsc --noEmit && vite build`, then `firebase deploy --only hosting` using
`backend/firebase.json` — where `public` points back at `web-admin/dist`, so
moving either directory means editing the other. Hosting serves `index.html` for
every path (the panel routes in the browser) with long caches on the hashed assets
and none on `index.html`.

The bundle is about 760 kB, 230 kB gzipped, nearly all of it the Firebase SDK.
Not code-split: it is a two-screen internal tool loaded on a laptop, and the
alternative buys nothing worth the complexity.

## Design

The same Modernist system as the apps — the CSS custom properties at the top of
`src/styles.css` are the tokens transcribed into `ios/…/DesignSystem/Tokens.swift`,
back in the direction they came from. Archivo is self-hosted from the very file
both apps bundle. No rounded corners anywhere, structure by rule rather than
whitespace, and a single look with no dark variant, which is the call the apps
made too.

## Files

| | |
| --- | --- |
| `src/schema.ts` | **the load-bearing one.** Field names, types, and money formatting. Hand-written, like `FirestoreMapping.swift` and `FirestoreMapping.kt`, because `firestore.rules` names every one of these strings |
| `src/firebase.ts` | SDK start-up and emulator wiring |
| `src/useAuth.ts` | sign-in and the `admin` claim check |
| `src/Participants.tsx` | the roster, search, and the block control |
| `src/History.tsx` | one bracelet's ledger, and whether it reconciles |
| `src/Bar.tsx` | the drinks catalogue |
| `scripts/seed-history.mjs` | emulator fixtures, written through the rules |
