# Every action starts on purpose

Three things the desk does, three ways to start, all of them chosen by name on
the home screen:

| | |
| --- | --- |
| **Read bracelet** | whose is this — and nothing else |
| **Check in new participant** | search the roster, then pair a chip |
| **Sell evening ticket** | read a fresh chip, then pick the evening |

Admins see the same screen. `StaffRole(claim:)` maps the `admin` claim to
`.reception`, because that is exactly what the rules grant an organiser, so there
is no separate admin home to keep in step.

The shape of this is one rule: **nothing pairs a bracelet unless the operator
said they were pairing a bracelet.** Pairing is permanent — the rules allow
`create` on `bracelets/{uid}` and never `update`, deliberately — so it must never
be something somebody arrives at, only something they chose.

---

## Reading a bracelet is a question, not a flow

Reading an unowned chip used to drop straight into the check-in list. That made a
permanent pairing reachable by scanning a wristband off the wrong pile, two taps
from a scan nobody meant as a check-in.

Now it is a dead end. `UnassignedBraceletView` states the fact, names the chip,
and offers **Done** — the same shape as `BlockedBraceletView`, for the same
reason: the screen answers the question that was asked, and the next move belongs
somewhere the operator picks deliberately.

It plays the *problem* tone rather than the success one. An operator scanning a
wristband expecting a balance and getting nobody has hit a snag, and the sound
should say so.

## Selecting a name does not pair anything either

Tapping a row used to call `assignBracelet` immediately — one tap, in a scrolling
list of a hundred-odd similar-looking names, committing something **nobody at the
desk can undo**. A mis-tap meant the wrong guest owned that wristband for the
festival and the fix was an organiser deleting a document.

Now a tap opens the guest. The pairing needs a second, deliberate action on a
screen showing the name at 32pt, the ticket reference, and a sentence saying it
cannot be undone.

## The participant screen asks `CheckInAction`

```swift
static func decide(for participant: Participant) -> CheckInAction {
    participant.isAwaitingCheckIn ? .scanAndAssign : .topUp
}
```

| State | Button |
| --- | --- |
| Already paired | **Add money** |
| Awaiting | **Scan and assign bracelet** |

There was a third case, `assignInHand`, which paired a chip that had already been
read without scanning twice. Reading a chip no longer leads to the check-in list,
so no route puts a bracelet in hand before a guest is chosen, and the case was
deleted rather than left unreachable — the point of the flat `Screen` enum is
that the states in this app are the ones it can actually be in.

A thin rule for a type, but it keeps the button label and the footnote copy out
of a `ViewBuilder` and under test, and offering *Add money* to somebody with no
bracelet would take cash for an account nothing can spend from.

## Door sales scan first

An evening ticket is minted **onto** a bracelet in a single write: there is no
ticket to sell until there is a wristband to put it on. So *Sell evening ticket*
reads a chip, then shows the evening picker, with tonight preselected.

This used to hang off the bottom of the check-in list, which only worked because
that list was reached by scanning. Once reading a chip stopped leading there, the
button would have been unreachable and door sales would have quietly vanished
from the app — worth stating, because nothing would have failed loudly.

A chip that already belongs to somebody is refused during that scan, by name.
Minting an anonymous ticket onto an owned wristband would either be refused by
the rules or, worse, hand a guest's balance to a door sale.

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

1. **Name first.** Home → *Check in new participant* → *Select* Nina Kowalski →
   accent *Awaiting check-in* band, her ticket ref and country, and *Scan and
   assign bracelet*. A fresh chip paired; the receipt named her, the ticket and
   the bracelet.
2. **Refusal on check-in.** Presenting Marta's chip was refused by name, the
   screen stayed on Nina, and the button stayed *Scan and assign bracelet* —
   nothing left in hand.
3. **Reading a paired chip** resolved to Marta, checked in, green band, her
   balance, *Add money*.
4. **Reading an unpaired chip** showed *Not assigned · Nobody has this bracelet*
   with the chip id and a single *Done*. **No list, no check-in.**
5. **Door sale.** Home → *Sell evening ticket* → fresh chip → evening picker with
   Saturday preselected → *Assign · Saturday* → receipt: `Evening #1`, valid
   Saturday, on that bracelet.
6. **Refusal on a door sale.** Presenting Marta's chip was refused by name and
   returned to home with nothing in hand.
7. **Back** from a participant returns to the check-in list with the search text
   intact.

## Still open

- **Android is unchanged.** It still pairs on the row tap and still leads from an
  unpaired chip into the list — both behaviours this replaced. `CheckInAction` is
  pure and should port to `:domain` more or less mechanically, as `SyncState` did.
- **Never run against production**, on either platform. The refusal paths in
  particular resolve through the reverse-lookup collection, which behaves
  differently offline than the fixtures do.
- **The search only covers people awaiting check-in.** Looking up a guest who is
  already checked in still means reading their bracelet. That is fine at the desk
  and wrong the moment somebody loses a wristband.
- **An evening ticket sale cannot be started from a chip already in hand.** The
  operator taps *Sell evening ticket* and scans; if they scanned first out of
  habit, they read the same wristband twice. Cheap to fix by offering the sale on
  the unassigned-bracelet screen, and deliberately not done — that screen exists
  to be a dead end, and putting an action on it starts eroding the rule.
