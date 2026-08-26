# Reading bracelets

Core NFC, `NFCTagReaderSession`, polling `.iso14443`. Verified against real
festival wristbands on 2026-08-20: a chip read as `1D:94:9D:D4:11:10:80`.

---

## What it takes to build

Three things, all in place:

| | |
| --- | --- |
| `BuzzTerminal.entitlements` | `com.apple.developer.nfc.readersession.formats = ["TAG"]` |
| `Info.plist` | `NFCReaderUsageDescription` — without it, starting a session traps |
| App ID capability | Near Field Communication Tag Reading, added by Xcode when signing |

`TAG` rather than `NDEF`: a wristband's identity is its **UID**, not anything
written onto it, so nothing has to be programmed into a bracelet for it to work.
Xcode added the capability to the App ID by itself during a signed archive — the
profile now grants `NDEF, TAG, PACE`.

It only runs on a physical iPhone 7 or later. Everything is behind
`NFCTagReaderSession.readingAvailable`, so a Simulator build still compiles and
falls back to `SimulatedBraceletReader`. `-sbScanner simulated` forces that
fallback on a device, for rehearsing a flow with no bracelet to hand.

## Android reads chips differently, and better

Android uses **reader mode** (`NfcAdapter.enableReaderMode`), not the
foreground-dispatch intent system. Two reasons, and the second is the one that
matters: dispatch would deliver tags as Intents and mean routing a scan through
`onNewIntent` and back into a suspend function, and reader mode **suppresses the
platform's own tag animation and sound** — so the Modernist overlay stays on screen
for the whole read.

`FLAG_READER_SKIP_NDEF_CHECK` is set deliberately. The identity is the UID, so
reading NDEF would delay every scan for data the app never looks at.

`Tag.getId()` is the UID for every technology polled, so there is no per-technology
branching — unlike Core NFC, where the identifier hangs off a per-family associated
value. The one Kotlin-specific trap is in `BraceletID.fromNfcId`: `Byte` is signed,
so without `toInt() and 0xFF` the byte `0xB4` formats as `FFFFFFB4` and every id
read from a real chip is wrong. There is a test named after it.

The manifest declares `android.hardware.nfc` as **not required**, so a phone without
NFC still installs and falls back to the prototype chip panel. `required="true"`
would hide the app from those devices in the Play Store, which is a distribution
decision nobody asked for.

## iOS draws its own sheet, and cannot be told not to

Starting a tag session presents Apple's own "Ready to Scan" modal. It **cannot be
suppressed or restyled**. So the app's Modernist scan overlay is what an operator
sees *before* the session begins, and the system sheet covers it during the read.
`session.alertMessage` is the only copy we control there, which is why it carries
the instruction rather than a label.

A consequence worth remembering: a hardware read starts **on its own** when the
scan screen opens. The prototype panel waits for a tap; a chip does not.

## Why the UID and not the vendor's serial

The bracelets carry an NDEF URL — `https://nfclink.me/n/1000004222` — and the
vendor says the trailing number is unique and consecutive within a batch. It is
still not the identity, and the inspector settled why: **the NDEF area reports
read/write**.

Anyone who can touch a bracelet can rewrite that URL with a free phone app,
including to another bracelet's serial. Keyed on the serial, that is a two-minute
theft of somebody else's balance with no special hardware. A UID is burned in at
manufacture and cannot be changed that way.

So the serial is not captured anywhere in the app. Doing so would have cost a rules
change, a field on `bracelets/{uid}`, and an NDEF read on every scan, to produce a
label that cannot be trusted in precisely the situation it would be reached for — a
guest disputing a charge.

It keeps one honest use: **stock-taking a box before the festival**, where
consecutive numbering makes a gap or a repeat obvious at a glance. That needs no
code.

Two consequences of read/write NDEF worth knowing:

- A rewritten URL is a **guest-facing** risk, not an app one: the terminal never
  reads NDEF, but a guest tapping their own bracelet with a phone opens whatever URL
  is on it. Worth asking the vendor whether they can ship the batch NDEF-locked.
- Locking is irreversible. Do not lock tags in bulk on a whim, and note the app
  gains nothing from it — this is about protecting guests, not the till.

## The UID is the identity

The chip's UID becomes the `BraceletID`, formatted as upper-case hex pairs joined
by colons — the same shape the design always used, and a legal Firestore document
id.

Two deliberate non-rules in `BraceletID(nfcIdentifier:)`:

- **Length is not validated.** 4-byte MIFARE and 7-byte NTAG UIDs are both real.
- **Nothing is truncated.** Every NXP chip opens with the same `0x04` manufacturer
  byte, so cutting a 7-byte UID to 4 could map two guests onto one document — two
  people sharing a balance, invisible until it happens.

Note the real bracelets read `1D:…`, not `04:…`. `04` is NXP; `1D` is not a
standard NXP prefix, so these are non-NXP or clone chips. Harmless in itself — a UID
only has to be unique and stable — but it makes the two checks below worth doing
rather than assuming.

## Before trusting a batch of bracelets

**Stability — ✅ verified 2026-08-20.** One bracelet scanned repeatedly returned the
same UID every time. This was the check that could have sunk the design: some tags,
MIFARE Classic in random-UID mode especially, report a fresh UID per read, and
against those a paired bracelet would read as an unknown chip at the bar. These do
not.

**Uniqueness — spot-checked 2026-08-20, worth repeating per batch.** Two different
bracelets gave two different UIDs. Re-check about ten from each box when the
festival order arrives.

The vendor's assurance is not the same assurance. They promised "unique consecutive
ids", and NFC UIDs are neither consecutive nor vendor-assigned: NXP burns them in at
manufacture and they look random. A consecutive run therefore describes something
else — a printed serial, a QR code, or a value programmed onto the tag — and says
nothing about the UID this app keys on. It also implies programmable chips, which
are duplicable, and two boxes could each begin their run at the same number.

Guessability does not matter: every read and write needs a signed-in staff account
with a role claim, enforced by rules. Duplicates are the only real risk.

**What a duplicate would actually do**, since it cannot be ruled out by inspection:
the rules allow `create` on a `bracelets/{uid}` document and never `update`, so the
*second* guest's check-in is refused rather than silently sharing the first guest's
balance. `assignBracelet` confirms the document exists before blaming the chip, and
reports "This bracelet is already paired to somebody. Use a fresh one." A confusing
message when the guest is holding an unused wristband — but it fails safe, which is
the part that matters.

Neither can be checked from a Mac, and both are five minutes with the bracelets in
hand.

### Two DEBUG-only tools for exactly this

Both hang off the sign-in screen, need no account, and are absent from a release
build — verified by symbol, not assumed.

**Inspect a tag.** One chip, everything it will say: UID, `GET_VERSION`, NDEF status
and records, and raw pages. This is what established that these tags are non-NXP and
that their NDEF is read/write.

**Audit a box.** Chip after chip from a single session, keeping Apple's scan sheet up
between reads and restarting automatically when Core NFC's 60-second ceiling
expires. It lists each distinct UID in the order seen and flags any that repeats.

The instruction on that screen is load-bearing: **scan from one pile into another**,
so a bracelet is only ever presented once. Without a physical process a repeat is
ambiguous — the same wristband scanned twice looks exactly like two wristbands
sharing a UID, which is the same ambiguity the check-in flow has and cannot resolve
either.

A chip still sitting in the field is deliberately silent rather than reported: Core
NFC re-detects a tag that has not moved, and an operator who learns to ignore the
warning has lost the only warning that matters. `BraceletAudit` is pure and carries
that rule, with tests.

## Still open

- **125 kHz tags cannot be read at all.** If a future batch is low-frequency rather
  than 13.56 MHz ISO14443, no iPhone can scan it and the session simply never sees
  the tag. Worth confirming with any new supplier before ordering.
- **The offline queue.** A read resolves against Firestore immediately, so a scan
  with no connection still fails. That is the other half of iteration 3.
