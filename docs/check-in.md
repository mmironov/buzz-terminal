# Check-in has two ways in

Reception's day has two shapes. A guest walks up with a wristband already on and
wants to know what is on it, or top it up. Or a guest walks up with nothing and
needs to be checked in. Those start differently, so the home screen offers both:

| | |
| --- | --- |
| **Read bracelet** | chip first — the app finds out who it belongs to |
| **Check in new participant** | name first — search the roster, then pair a chip |

Admins see the same screen. `StaffRole(claim:)` maps the `admin` claim to
`.reception`, because that is exactly what the rules grant an organiser, so there
is no separate admin home to keep in step.

---

## Selecting a name does not pair anything

This is the change that mattered. Tapping a row used to call `assignBracelet`
immediately — one tap, in a scrolling list of a hundred-odd similar-looking
names, committing a pairing that **cannot be undone by anybody at the desk**. The
rules allow `create` on `bracelets/{uid}` and never `update`, deliberately, so a
mis-tap meant the wrong guest owned that wristband for the festival and the fix
was an organiser deleting a document.

Now a tap opens the guest. The pairing needs a second, deliberate action on a
screen showing the name at 32pt, the ticket reference, and a sentence saying it
cannot be undone.

## One list, one participant screen

Both entry points land on the same two screens, because they are the same job.
The differences are small and derived, never duplicated:

- The **list** changes its title and subtitle, and hides *Assign evening ticket*
  when no chip has been read — an evening ticket is minted onto a bracelet in one
  write, so with nothing in hand that button opens a screen whose confirm would
  silently do nothing.
- The **participant screen** asks `CheckInAction` what to offer.

```swift
static func decide(for participant: Participant, braceletInHand: BraceletID?) -> CheckInAction {
    guard participant.isAwaitingCheckIn else { return .topUp }
    guard let braceletInHand else { return .scanAndAssign }
    return .assignInHand(braceletInHand)
}
```

Three outcomes, and the order matters:

| State | Button |
| --- | --- |
| Already paired | **Add money** |
| Awaiting, chip already read | **Assign bracelet 04:A1:9C:7E** |
| Awaiting, nothing read | **Scan and assign bracelet** |

`assignInHand` is why the chip-first route did not become a double scan. It also
names the chip on the button, which is the operator's last chance to notice they
are holding the wrong wristband.

The first line is the one worth keeping: a guest who **already** has a bracelet
gets a top-up even when a different chip is in hand. Offering to re-point it would
be promising a write the server refuses — and, if it somehow succeeded, silently
moving somebody's balance.

## A chip that belongs to somebody else

`pairScannedChip` reads the reverse lookup before writing anything. If the chip is
already somebody's, the pairing is refused and the message names the holder, so a
wristband can go back in the right pile:

```
This bracelet already belongs to Marta Lindqvist. Use a fresh one.
```

Scanning the *same* guest's own chip says so instead, rather than accusing them of
holding someone else's.

The chip is **not** left "in hand" after any failure. Keeping it would offer a
one-tap retry of a pairing the server has already refused — most often because the
chip is a duplicate UID, which retrying cannot fix. The button falls back to
*Scan and assign bracelet*, forcing a fresh read.

## Naming the guest on Apple's sheet

iOS draws its own "Ready to Scan" modal and covers the app completely during a
hardware read, so `session.alertMessage` is the only copy an operator sees at the
moment of the scan. For a participant-first check-in it carries the name:

> Hold a fresh bracelet to the top of the phone to pair it with Nina Kowalski.

`BraceletReader.read` therefore takes a `prompt`, defaulted via a protocol
extension so the other call sites are unchanged. `SimulatedBraceletReader` ignores
it — there is no system sheet to put it on — and the app's own dark overlay shows
the equivalent sentence instead.

---

## Verified

Driven through the real UI on the Simulator against fixtures, 2026-09-19:

1. **Name first.** Home → *Check in new participant* → search → *Select* Nina
   Kowalski → the screen shows an accent *Awaiting check-in* band, her ticket ref
   and country, and *Scan and assign bracelet*.
2. **Refusal.** Presenting Marta's chip was refused by name, the screen stayed on
   Nina, and the button stayed *Scan and assign bracelet* — nothing left in hand.
3. **Happy path.** A fresh chip paired; the receipt named her, the ticket and the
   bracelet.
4. **Reading it back** resolved to Nina, checked in, green band, *Add money*.
5. **Chip first.** Home → *Read bracelet* → fresh chip → *Who is this?* with the
   chip in the subtitle and the door-ticket button present → *Select* Sofia
   Ferreira → **no second scan**: the button read *Assign bracelet 04:A1:9C:7E*
   and paired on one tap.
6. **Back** from a participant returns to the list with the search text intact.

## Still open

- **Android is unchanged.** It still pairs on the row tap, which is the behaviour
  this replaced. `CheckInAction` is pure and should port to `:domain` more or less
  mechanically, as `SyncState` did.
- **Never run against production**, on either platform. The refusal path in
  particular resolves through the reverse-lookup collection, which behaves
  differently offline than the fixtures do.
- **The search only covers people awaiting check-in.** Looking up a guest who is
  already checked in still means reading their bracelet. That is fine at the desk
  and wrong the moment somebody loses a wristband.
