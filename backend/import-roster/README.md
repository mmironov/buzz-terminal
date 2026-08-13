# Roster importer

Pulls the participant list from the Google Sheet into Firestore. Roster fields
only — it never writes a balance, a bracelet pairing, or a check-in.

Safe to run as often as you like, including mid-festival when late ticket sales
land in the Sheet.

```bash
cd backend/import-roster
npm install
```

## Setup, once

**1. A Firebase service-account key.** Firebase console → Project settings →
Service accounts → *Generate new private key*. Save it as
`backend/import-roster/serviceAccountKey.json`.

> This file is a credential with full admin access to your project. It is
> gitignored, and it must stay that way — never commit it, never put it in the
> iOS app, never paste it into a chat. If it leaks, revoke the key in the console
> immediately.

**2. Enable the Google Sheets API** on the same Google Cloud project:
`https://console.cloud.google.com/apis/library/sheets.googleapis.com`

**3. Share the Sheet with the service account.** Open `serviceAccountKey.json`,
copy the `client_email` value (it looks like
`something@your-project.iam.gserviceaccount.com`), and share the Sheet with that
address as **Viewer**. Viewer is enough — this tool only ever reads.

**4. Point it at your project and Sheet:**

```bash
export FIREBASE_PROJECT_ID=your-project-id
export SHEET_ID=1AbC…            # the long string in the Sheet URL between /d/ and /edit
export SHEET_RANGE='Participants!A1:Z10000'
```

## Then

```bash
npm run headers          # prints the Sheet's header row
```

Copy those column names into `mapping.mjs` and set `IDENTITY_COLUMN` to whichever
one is the stable unique key — a ticket or order reference. **Not** a row number,
**not** a name.

```bash
npm run import           # dry run: shows exactly what would change
npm run import -- --apply
```

Nothing is ever written without `--apply`.

## The other commands

```bash
npm run seed-drinks -- --apply              # write the drinks menu
npm run set-role -- bar@swingbuzz.fest bar --apply
npm test                                    # unit-tests the diff logic, no credentials needed
```

`set-role` writes the Firebase Auth custom claim the security rules read. Roles
cannot be set from the Firebase console — only through the Admin SDK — which is
precisely why they are trustworthy: no client can grant itself a role. The staff
member must sign out and back in before a new claim takes effect.

## What it will refuse to do

The importer stops rather than guess, because a wrong guess here corrupts
somebody's balance:

- **A blank identity value** → reports the sheet row numbers and exits.
- **A duplicated identity value** → reports both rows and exits. Two people
  sharing a key would share a balance.
- **A column in `mapping.mjs` that isn't in the Sheet** → lists the headers it
  actually found, so a typo is a two-second fix.
- **A roster field that is secretly festival state** → `buildPlan` throws if
  anyone later adds `balance` or `braceletId` to `toRosterFields`.

It also **never deletes**. People in Firestore who have vanished from the Sheet are
reported, with their balance and check-in state, and left alone. A refund is an
organiser decision, and the person may have money on a bracelet.

## Privacy

`EXCLUDED_COLUMNS` in `mapping.mjs` lists Sheet columns that deliberately do not
reach Firestore. Everything that does reach it is readable by **every** signed-in
terminal, including the bar — so emails, phone numbers, dietary requirements and
accessibility notes stay in the Sheet unless a terminal genuinely needs them.

The importer prints the columns it saw and ignored on every run, so nothing leaks
by being forgotten.

## Files

| File | |
| --- | --- |
| `mapping.mjs` | **the one you edit.** Column names, identity key, exclusions |
| `diff.mjs` | pure: Sheet rows + Firestore docs → a write plan |
| `diff.test.mjs` | unit tests for the above; runs with no credentials |
| `sheets.mjs` | Sheets API read, `spreadsheets.readonly` scope |
| `firestore.mjs` | Admin SDK writes, custom claims, drinks seed |
| `index.mjs` | CLI |
