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

**4. Point it at the Sheet:**

```bash
export SHEET_ID=1AbC…            # the long string in the Sheet URL between /d/ and /edit
export SHEET_RANGE='Registrations!A1:Z10000'   # optional; defaults to the first tab
```

The Firebase project id is read from `../.firebaserc`, so it needs no flag.
Override with `--project=<id>` if you ever point this at a staging project.

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
npm run seed-drinks -- --apply              # the menu's first three, on a fresh project
npm run set-role -- bar@swingbuzz.fest bar --apply
npm run set-role -- you@swingbuzz.fest admin --apply
npm test                                    # unit-tests the diff logic, no credentials needed
```

`set-role` writes the Firebase Auth custom claim the security rules read. Roles
cannot be set from the Firebase console — only through the Admin SDK — which is
precisely why they are trustworthy: no client can grant itself a role. The staff
member must sign out and back in before a new claim takes effect.

Three roles: `reception` and `bar` are the terminals, `admin` is the web panel in
`web-admin/`. An `admin` can block bracelets and edit the menu and deliberately
cannot move money; it also cannot sign into the terminal apps, which refuse any
account that is not reception or bar.

`seed-drinks` is a **bootstrap**, not the way prices get set — the admin panel
owns the menu. Re-running it against a live festival would overwrite whatever an
organiser has done there, including reactivating a drink they took off tonight.

## Who gets imported

Only rows with **`Status` = `Paid`** (matched lowercased and trimmed, so `PAID`
and ` paid ` both count). Everything else — pending, expired, cancelled,
refunded, blank — is treated as if the registration does not exist. During the
festival, unpaid is the same as absent.

Every dry run prints a breakdown of what it skipped, by status. **Read it.** A
value nobody anticipated, say `Paid (bank transfer)`, is skipped by this rule and
the first anyone would know is a paying guest missing at the door.

Somebody already in Firestore whose status is no longer `Paid` is reported rather
than silently skipped — they may have checked in and loaded money onto a bracelet
before the refund. Never deleted; that money is real.

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
