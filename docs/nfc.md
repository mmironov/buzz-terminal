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

## The system draws its own sheet

Starting a tag session presents Apple's own "Ready to Scan" modal. It **cannot be
suppressed or restyled**. So the app's Modernist scan overlay is what an operator
sees *before* the session begins, and the system sheet covers it during the read.
`session.alertMessage` is the only copy we control there, which is why it carries
the instruction rather than a label.

A consequence worth remembering: a hardware read starts **on its own** when the
scan screen opens. The prototype panel waits for a tap; a chip does not.

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
hand. The app already helps: the log line `read chip <uid>` appears on every
successful read.

## Still open

- **125 kHz tags cannot be read at all.** If a future batch is low-frequency rather
  than 13.56 MHz ISO14443, no iPhone can scan it and the session simply never sees
  the tag. Worth confirming with any new supplier before ordering.
- **The offline queue.** A read resolves against Firestore immediately, so a scan
  with no connection still fails. That is the other half of iteration 3.
