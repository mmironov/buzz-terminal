# Replacing a lost wristband

Somebody loses their wristband on the dance floor, or a clasp snaps. Reception
issues a new one, the old one stops working, and the guest keeps their balance.

---

## The one thing that had to stay true

A pairing used to be permanent in both directions: `braceletId` could only go
**null → chip**, and `bracelets/{chipUid}` was create-only. That rule exists
because **a chip changing owner would silently hand somebody else's balance
over** — the money lives on the person, and the chip is only how you find them.

Replacing a wristband relaxes exactly one half of that. A person's *active* chip
may now change; **a chip still never changes owner**. Both halves happen in one
write, and `firestore.rules` checks them against each other:

```
participants/tkt-10432   braceletId: 04:A1:9C:7E → 92:72:C6:D7

bracelets/04:A1:9C:7E    invalidatedAt, invalidatedBy, reason   // retired
bracelets/92:72:C6:D7    participantId, staffUid, pairedAt      // minted
                         replacementFee, replacementMethod      // if charged
```

- the new chip is **created**, so a `create` on a document that already exists
  fails — a chip that belongs to somebody cannot be taken over;
- the old chip is invalidated **in the same write**, so a wristband cannot stop
  being somebody's while still resolving, which is what a finder would spend
  from;
- an invalidation on its own is refused too. Partly so nobody is left holding a
  dead chip with a balance behind it, and partly because the replacement branch
  requires the invalidation to be *this* write: a chip killed on its own could
  never be replaced afterwards, and the participant would be stuck for the rest
  of the festival.

**Nothing is deleted.** The retired document keeps pointing at its owner, so the
chip that turns up on Sunday still says whose it was, and it cannot be quietly
re-issued to somebody else. A guest who loses two wristbands has three
documents, two of them invalidated — which is the history, for free.

## The fee is not a balance

The guest pays for a replacement at the desk, in cash or on the card machine,
and it is recorded **on the wristband that was issued** — not taken off their
balance:

```
bracelets/92:72:C6:D7
  replacementFee:    100        // cents
  replacementMethod: "cash"     // or "card"
```

Taking it off the balance was considered and rejected. The ledger is what is
*on a bracelet*: top-ups in, rounds at the bar out, every entry balanced against
a balance the rules verify. A festival charge in there would put "they owe us a
euro for a wristband" into the record of what somebody drank, and it would mean
reception — which may only credit — gaining the power to debit. It also would
not have collected the euro: somebody who never tops up again never pays it.

**Waiving is the absence of a fee, not a zero.** A snapped clasp is the
festival's fault, so the desk leaves the box unticked, and the takings cannot be
read as "somebody paid nothing".

The amount is one number in `settings/bracelets`, set by an organiser in the
panel's Bracelets tab. A festival that sets none gets a desk with no fee to
offer. The rules bound the shape but do **not** pin the recorded fee to the
configured one — the same reasoning as a door sale's `pricePaid`: a phone
holding a five-minute-old number must not have the write refused with somebody's
money already on the desk.

## At the desk

**Replace a bracelet** on the reception home screen — the third button, and the
rarest. It is not behind a scan because the wristband is the thing that is
missing: the only way to the guest is by name.

1. **The list of people who have one.** The mirror image of the check-in list,
   which is everybody who has none. Each row shows the chip they are about to
   lose, because two guests with the same name is exactly when the desk needs to
   be sure which record it is changing.
2. **Their own screen**, with the balance and the identity card unchanged, plus
   two things: *why it is being replaced*, and whether to charge the fee. The
   button that would say **Add money** says **Scan and replace** instead.
3. **The fresh chip, last.** Nothing is written until it is read, so a change of
   mind costs a tap rather than a wristband. A chip that belongs to somebody is
   refused, and the reason and the fee survive — the next chip out of the box
   finishes the same replacement.

The reason is required, by the screen and by the rules. "There is a new
wristband and nobody wrote down why" is the state this exists to prevent.

The special-session block is hidden on this screen: it takes money, and a second
thing taking money on a screen whose button says *Scan and replace* is how a
desk ends up doing the wrong one.

## What a found wristband does

Nothing. It resolves for nobody, at either terminal, and gets its own screen
rather than an error alert — **No longer valid · This bracelet was replaced**.
At the bar on a Saturday night this is an ordinary thing to happen, not a fault,
and "Something went wrong" is the wrong sentence to put in front of a guest who
has picked a wristband up off the floor.

**It does not say whose it was.** The database knows, and reception can look it
up; whoever is holding it now is not necessarily its owner.

## In the panel

The Bracelets tab, under the colours: the fee at the top, and every replacement
underneath — guest, reason, the retired chip, when, and what was taken for the
new one, with cash and card totalled.

## Verified

- **187 rules tests**, including: a replacement that leaves the old chip working
  is refused, an invalidation with no new wristband is refused, a reason is
  required, moving to a chip that already belongs to somebody is refused,
  invalidating twice is refused, reviving or deleting a retired chip is refused,
  the bar cannot replace anything, a fee must say how it was paid, a fee on
  somebody's *first* wristband is refused, and — the one that matters — a
  replacement that also moves the balance is refused.
- **163 iOS tests**, including that nothing is replaced without a reason, a fee
  needs a method, waiving is the absence of a fee, and the screen offers a scan
  rather than a top-up.
- **End to end against the emulator**, 2026-09-23. Replaced Amélie Roux's
  wristband from the desk with the reason "Lost it on the dance floor" and the
  1 € fee in cash: the write landed through the real rules as three documents,
  her balance stayed at 23.50 € with no ledger entry, the old chip then refused
  to resolve at the **bar** — *No longer valid* — and the panel listed the
  replacement with the fee and totalled it.

## Still open

- **Nothing is in production.** The rules are not deployed and no fee is set;
  until `settings/bracelets` exists the desk replaces wristbands for nothing.
- **A mis-tap needs an organiser.** A replacement cannot be undone from a
  terminal — the old chip is dead for good. That is deliberate, and it means
  replacing the wrong person's wristband is a database job.
- **Android has none of this.**
