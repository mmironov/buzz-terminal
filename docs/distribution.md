# Getting the app onto staff phones

Two platforms, two mechanisms, one idea: a link, no store listing, no device ids
collected.

**iOS — TestFlight**, external group, public link: staff tap a link, install
TestFlight, and get the app. Needs the paid membership. Everything down to
"The Android app" below is about this.

**Android — Firebase App Distribution**, in the same `swing-buzz` project the app
already authenticates against. Free, no Play account, no review. Testers get an
email; the link installs the APK.

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

A plain ⌘R install now talks to **production**, since Firestore is the default
backend. Add `-sbBackend memory` to the scheme's launch arguments for the offline
fixture version instead.

Note that the install you did on 2026-08-14 predates that change, so it ran the
fixtures: it exercised the design on real hardware, not the backend.

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

---

# The Android app

**Firebase App Distribution.** Chosen over the alternatives because it needs no
new account and no fee: the `swing-buzz` project already exists, the app already
talks to it, and `firebase-tools` is already how the rules get deployed. Google
Play's internal-testing track costs $25 once and adds an app record, a bundle, a
data-safety declaration and a review step — worth it only if you want staff
phones to auto-update through Play without anyone thinking about it. A plain
signed APK works too and is a fine fallback, but it has no update path.

No Gradle plugin for the upload: the Firebase CLI already has
`appdistribution:distribute`, and it authenticates with the `firebase login` you
already have. A plugin would have meant a service account and one more pinned
version for no gain.

## The one thing that will bite you

**The keystore is not recoverable.** Android identifies an app by its signing
key, so an update signed with a different key is refused — the only way out is
uninstalling from every phone, which takes the app's local data with it. There is
no Apple-style "revoke and reissue" here, and unlike Play App Signing there is no
copy held by Google.

So the `.jks` and its passwords need to live somewhere that is not one laptop.
Treat losing them as equivalent to losing the app.

The other trap is quieter: **`versionCode` must not go backwards.** A device
refuses an APK numbered lower than the one installed, and the failure looks like
"the install worked but nothing changed". It is derived from `git rev-list
--count HEAD`, so it rises by itself and the same commit always yields the same
number — as long as builds come from a checkout, not a zip.

## One-time setup

### 1. Create the signing key

Once, and never again for the life of the app:

```bash
keytool -genkeypair -v \
  -keystore android/swing-buzz-release.jks \
  -alias swing-buzz -keyalg RSA -keysize 4096 -validity 10000
```

10000 days is ~27 years. A key that expires mid-festival cannot sign an update,
and the number costs nothing, so make it absurd.

### 2. Point the build at it

`android/keystore.properties`, gitignored along with `*.jks`:

```properties
storeFile=swing-buzz-release.jks
storePassword=…
keyAlias=swing-buzz
keyPassword=…
```

`storeFile` is relative to `android/`. Without this file the release variant
still builds — it just comes out unsigned, which is what a fresh clone and CI
want, and Android refuses to install it so it cannot be mistaken for a real one.

### 3. Enable App Distribution

console.firebase.google.com → the `swing-buzz` project → **Release & Monitor →
App Distribution → Get started**. Then *Testers & Groups* → add a group. Name it
`staff` if you want the commands below to work unchanged.

Adding testers by email is enough; they do not need Google accounts tied to
anything, and they never see the Firebase console.

## Every build

```bash
./android/scripts/release.sh --distribute --group staff
```

Builds the signed APK, verifies it really is signed (`jarsigner -verify`, because
a filename proves nothing and an unsigned APK fails on the device rather than in
the script), and uploads it with the last commit subject as the release notes.

Useful variants:

```bash
./android/scripts/release.sh                    # build only, then adb install -r
./android/scripts/release.sh --unsigned         # compile check, no keystore needed
./android/scripts/release.sh --distribute --testers someone@example.fest
```

Uploading with neither `--group` nor `--testers` is legal and does nothing
visible — the build waits in the console for an audience. The script says so
rather than printing a tick.

### What to send staff

The email from Firebase has the link. On first install a phone will ask to allow
installs from whatever app opened it — that prompt is per-source and expected;
Android has required it since 8.0. The App Tester app is optional: it is worth
installing for people who will take several builds, because it notifies them,
but a link and a browser is enough for one.

## Where this currently stands

Verified on 2026-08-14:

| step | |
| --- | --- |
| Release variant compiles unsigned | ✅ `app-release-unsigned.apk` |
| `versionCode` from the commit count | ✅ 44, matching `git rev-list --count HEAD` |
| Signing config picks up `keystore.properties` | ✅ rehearsed with a throwaway key, since destroyed |
| Signed APK installs on a device | ✅ Pixel 10 Pro emulator |
| The installed release build reaches production | ✅ logs `Firebase configured for project swing-buzz`, no demo shortcuts offered |
| Upload to App Distribution | ⬜ needs the console side of step 3 |

The last row is the only one that needs you: everything up to it is proven, and
the upload itself is one command once the group exists.

## Later

**Play internal testing** stays available if auto-updating becomes worth $25.
Note that Play requires an app bundle rather than an APK, and that enrolling in
Play App Signing changes who holds the key — which fixes the unrecoverable-key
problem above, at the cost of Google holding it.

**NFC** (iteration 3) needs no manifest work yet, but `android.permission.NFC`
and a `<uses-feature>` will want deciding then: required, and the app will not
install on a phone without NFC hardware; optional, and it must degrade to the
simulator panel at runtime.
