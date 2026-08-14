# Getting the app onto staff phones

No App Store listing. **TestFlight**, with an external group and a public link:
staff tap a link, install TestFlight, and get the app — no UDIDs collected, no
App Store Connect access handed out, and updates arrive over the air.

---

## The one thing that will bite you

**TestFlight builds expire 90 days after upload, and an expired build will not
launch.** Not "shows a warning" — refuses to start. A build uploaded in June is
dead by September.

So: **upload a fresh build in the week before the festival**, whatever else is
true. Put it on the run sheet next to collecting the float.

The second-order version of the same trap: a build uploaded on the Wednesday
before is fine for the weekend but dead by the next event. Every festival needs
its own upload.

---

## Where this currently stands

Verified on 2026-08-14, before the membership was active:

| step | |
| --- | --- |
| Archive for a real device, unsigned | ✅ `** ARCHIVE SUCCEEDED **`, arm64 |
| Archive **signed**, team `8LAN4FPYMS` | ✅ `** ARCHIVE SUCCEEDED **` |
| Export for App Store Connect | ❌ blocked on the membership |
| Upload | not attempted |

The export fails like this, and the message is worth recognising rather than
debugging:

```
error: No signing certificate "iOS Distribution" found
error: Team "Miroslav Mironov" does not have permission to
       create "iOS App Store" provisioning profiles.
```

Nothing is misconfigured. A **free Personal Team cannot create App Store profiles**
at all — only a paid membership issues the iOS Distribution certificate that export
needs. The same command should work once enrolment completes.

### The Personal Team stage, and its 7-day fuse

Signing in to Xcode with a plain Apple Account gives a Personal Team, which is
enough to install on your own iPhone and no further. Its profile lasts **7 days**:

```
Name:            iOS Team Provisioning Profile: fest.swingbuzz.BuzzTerminal
TeamIdentifier:  8LAN4FPYMS
ExpirationDate:  Fri Aug 21 14:57:19 EET 2026
```

When it expires the app stops launching on the phone. Rebuilding from Xcode issues
a fresh one; a paid membership makes them last a year instead.

Note that a plain ⌘R install runs the **in-memory fixtures**, so it exercises the
design and not the backend. To point the phone at production, add
`-sbBackend firebase` to the scheme's launch arguments — see the README.

## One-time setup

### 1. Apple Developer Program — the critical path

$99/year, and nothing below works without it.

**Enrol as an Individual, not an Organisation.** Individual is usually active
within a day or two. Organisation needs a D-U-N-S number and Apple verifying the
legal entity, which runs days to weeks and is the standard way a festival deadline
is missed. The only cost is the seller name shown publicly, and nothing here is
published.

Enrol at <https://developer.apple.com/programs/enroll>.

### 2. Team ID

developer.apple.com → **Membership details** → a 10-character string like
`A1B2C3D4E5`. Either set it once in Xcode (target → Signing & Capabilities → Team)
or pass it per build:

```bash
DEVELOPMENT_TEAM=A1B2C3D4E5 ./ios/scripts/release.sh
```

### 3. Register the bundle id and create the app record

The bundle id is **`fest.swingbuzz.BuzzTerminal`** — it is already in the project
and must match exactly.

- developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → `+`
  → App IDs → App → that bundle id.
- appstoreconnect.apple.com → **Apps** → `+` → New App. Platform iOS, the bundle id
  above, an SKU (anything, e.g. `buzz-terminal`), and a name.

The name must be unique across the whole App Store even though you never publish,
so "Staff Terminal" may be taken; "Swing Buzz Staff" or similar works. This name is
only ever seen by your staff.

### 4. App Store Connect API key, for uploading from the terminal

appstoreconnect.apple.com → **Users and Access** → **Integrations** → App Store
Connect API → `+`. Role **App Manager** is enough.

You get three things:

| | |
| --- | --- |
| Key ID | short string, not secret |
| Issuer ID | UUID, not secret |
| `AuthKey_XXXXXX.p8` | **downloadable exactly once** — a real credential |

Keep the `.p8` outside the repository. `~/.appstoreconnect/private_keys/` is the
conventional home and is where Apple's own tools look. It is gitignored here as
well, belt and braces.

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

Skip this if you would rather drag the exported `.ipa` into Apple's **Transporter**
app by hand. The key only automates that step.

---

## Every build

```bash
DEVELOPMENT_TEAM=A1B2C3D4E5 ./ios/scripts/release.sh --upload
```

That archives, exports and uploads. Version comes from `MARKETING_VERSION` in the
project; the build number is **`git rev-list --count HEAD`**, so it rises by itself
and the same commit always produces the same number. App Store Connect rejects a
repeated build number, which is exactly the mistake this avoids.

Without `--upload` it stops at an exported `.ipa` under `ios/build/DerivedData/export`.

To check the archive builds without a membership at all:

```bash
./ios/scripts/release.sh --unsigned
```

Processing in App Store Connect takes minutes, not seconds. It emails you when the
build is ready to distribute.

---

## TestFlight groups

Set both up once; they behave differently and you want each.

**Internal** — App Store Connect → TestFlight → Internal Testing. Up to 100
testers, **no review**, builds available as soon as processing finishes. Every
tester must be a *user on your App Store Connect account*, so keep this to
organisers. This is how you get a build onto your own phone in ten minutes.

**External** — TestFlight → External Testing → new group → enable the **public
link**. Up to 10,000 testers, no account access needed, and you hand out a URL.
**The first build of each new version number goes through Beta App Review**,
typically a day or two. Later builds of the same version usually clear quickly.

Practical consequence: do not bump `MARKETING_VERSION` the day before doors. A new
version restarts review; a new build of an existing version generally does not.

### What to send staff

> Install **TestFlight** from the App Store, then open this link on your iPhone:
> `<public link>`. Tap Install. You will get an email when there is an update —
> open TestFlight and tap Update. Sign in with the account and password the
> organisers gave you.

Requires iOS 17 or later, and an internet connection for the install itself.

---

## Later

**Core NFC** (iteration 3) needs the *Near Field Communication Tag Reading*
capability added to the App ID, and it only works on a physical device — which is
the other reason the membership unblocks the next iteration, not just this one.

**iPad.** `TARGETED_DEVICE_FAMILY = 1`, iPhone only. If reception is going to run
on an iPad, change it before the layouts are frozen — the design is portrait-only
and 66pt display type, and an iPad would want a pass over both.
