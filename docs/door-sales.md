# Selling at the door

Not everybody buys in advance. Reception sells passes at the desk all weekend, and
those buyers have no row in the registrations Sheet — so the terminal creates the
participant itself. That is the one hole in *"the roster belongs to the Sheet"*,
and this is what it looks like.

## The order of the questions

Pick the pass · take the buyer's details · **look at who you are about to sell
to** · scan the wristband · land on their participant screen.

The chip used to be read first, on the grounds that a pass is minted *onto* a
bracelet in a single write and there is nothing to sell until there is a
wristband to sell it on. True of the write and wrong for the desk: it put a scan
in front of a conversation that had not happened yet, and left an operator
holding somebody's wristband while they decided which pass they wanted and
spelled their name.

So the order now matches checking somebody in: decide who and what first, pair
the bracelet last, as the final irreversible act. The write is still one batch —
only the order of the questions changed. Nothing is stored until the chip is
read, and cancelling the scan keeps the draft, so a wristband from the wrong pile
costs one tap rather than a re-typed name.

The second-to-last step is the **same awaiting-check-in screen a check-in
uses**, and deliberately so: a pairing is permanent, and the screen that asks
"is this the right person?" should be the same one whichever way the desk got
there. It is built from the draft rather than from a document, because there is
no document yet — `AppModel.previewDoorSale` makes a provisional `Participant`
with a sentinel id, the merch and free-shirt reads are skipped, and **Back**
returns to the form with every field still filled in.

It ends on the participant screen rather than a receipt, because that is the
screen with **Add money** on it and a door buyer almost always loads the
wristband in the same conversation. The price was in front of the operator the
whole way — on the pass list, on the buyer form, on the scan sheet itself.

There are two shapes, and the catalogue decides which one a sale takes.

| | Evening ticket | Door pass |
|---|---|---|
| Who | A named guest | A named buyer |
| Asked for | Name and which night | Name, dance role, level, email |
| Then | Confirm, then scan the wristband | Confirm, then scan the wristband |
| Document id | `ev-friday-14` | `door-7` |
| `source` | `evening` | `door` |
| Lives for | That evening | The whole festival |

### The evening ticket used to be anonymous

It carried a generated label — `name: "Evening #14"` — and the rules pinned that
string, so there was nowhere to put a person even if a terminal had tried. The
festival decided it wants to know who holds one, so `name` is now the guest's and
the rules bound it rather than dictate it.

Nothing else was reopened. The `hasOnly` list still refuses a country, an email, a
phone, a dance role and a level on an evening ticket, and a rules test asserts each
of those refusals beside the name that is now allowed. One night at a door asks one
question.

The number the night is reconciled by did not go anywhere: it is still the document
id (`ev-friday-14`) and still `ticketRef` (`EV-FRIDAY-14`), both pinned. What did
change is where the desk can find it — searching "14" used to match because the
*name* contained it, so `Participant.matches` now also searches `ticketRef`, which
is what the search field has claimed to do since the first iteration.

## The catalogue

`doorPasses/{slug}` is what reception may sell, owned by organisers in the admin
panel's **Door passes** tab — the same arrangement as the drinks menu, for the
same reason: a price is an organiser decision and no terminal writes one.

```
doorPasses/full-pass-gold
  name:      "Full Pass Gold"    // written onto the buyer as their ticketType
  price:     25900               // cents
  sortOrder: 4
  isActive:  true
  kind:      "pass" | "evening"

doorPasses/evening-ticket
  price:     4500                // the fallback for a night with no price
  prices:    { friday: 4500, saturday: 5000, sunday: 4000 }
  kind:      "evening"
```

### An evening ticket is priced per night

Friday, Saturday and Sunday can cost different amounts, so the evening row
carries a `prices` map as well as the flat `price`. A night missing from the map
falls back to `price`, which means a festival charging the same on two nights
writes one entry rather than three — and every document written before this
existed keeps quoting exactly what it always did.

**The number lives beside the nights, not on the list of passes.** On the picker
the evening row shows "Priced per night" and no figure at all: it could only be
one of three there, and a desk reading it out as if it were *the* price is the
mistake that costs somebody five euros. The evening screen lists all three, and
the header follows whichever night is selected.

The panel's evening row has three price boxes instead of one, seeded from the
flat price so an organiser opening it the first time sees what is already being
charged rather than three blanks.

The festival's prices seed with `npm run seed-passes -- --apply`, and are edited
in the panel from then on. The evening ticket is seeded **unpriced**, because
nobody has said what it costs; the panel shows "No price set" beside it and the
terminal shows the same in place of a number, rather than reading "0.00 €" to
somebody holding cash.

`kind` is a behaviour, not a label. `evening` routes the terminal to the numbered
flow, which asks for a name and a night; anything else asks for the full buyer
details. Matching on the name instead would
break the moment somebody renamed a row.

### The price is shown, never charged

Nothing in this system takes the money for a pass. The desk does — in cash, or on
the card machine — and the number on screen is what they ask for.

That is deliberate and it is the same line the evening ticket has always held. The
ledger is what is **on a bracelet**: top-ups in, rounds at the bar out, every entry
balanced against a balance the rules verify. A pass is not on a bracelet. Writing
a 205 € "sale" into that ledger would make the reconciliation footer in the admin
panel — the one that says whether the entries add up to the balance — permanently
wrong by exactly the price of every pass sold.

So door takings are counted the way they were always going to be: by counting them.
If that ever needs to live in the app, it is a new thing to build, with its own
collection, not a number to smuggle into this one.

## What a sale writes

One batch, three documents, all or nothing:

```
participants/door-7
  source:      "door"
  passId:      "full-pass-gold"      // which catalogue entry
  ticketType:  "Full Pass Gold"      // its name, copied
  doorNumber:  7
  ticketRef:   "DOOR-7"
  name:        "Jana Novak"
  nameLower, searchTokens            // so the desk can find them again
  danceRole:   "leader" | "follower"
  level:       "Advanced" | ""       // Full Pass and Full Pass Gold only
  country:     ""
  braceletId, checkedInAt, balance: 0, isBlocked: false, createdBy

participants/door-7/contact/details
  email:   "jana@example.com"        // or "" — see below
  addedBy, addedAt

bracelets/04:A1:9C:7E                // the reverse lookup, same batch
  participantId: "door-7", staffUid, pairedAt
```

**The id is the sequence number**, exactly as with evening tickets: two desks
selling at the same moment collide on `door-7`, and the loser retries with 8.
Deduplication by construction rather than by a counter document nobody can lock.

One sequence for the whole festival rather than one per pass type. The number
identifies a sale; it is not a count of Full Passes, and per-type sequences would
mean another one to seed every time an organiser adds a row to the catalogue.

### The email is not on the participant

Every signed-in terminal reads participant documents — **the bar included**. Name,
pass type and level are already exposed that way for all 109 people from the Sheet,
so a door buyer is no more visible than anybody else. An address is different, and
a bartender has no business holding a mailing list.

So it goes to `contact/details`, which `firestore.rules` opens to reception and the
organiser claim and nobody else. The same arrangement as preordered merch, for the
same reason, and the rules refuse a participant document with an `email` on it
outright rather than trusting the app to leave it off.

It is written even when blank, so "asked, and they declined" and "never asked" are
the same absent value rather than two states somebody has to tell apart later. The
admin panel shows it under a person's row, because a field nobody can read is a
field that should not have been collected.

`danceRole`, never `role`. `role` is the staff claim the security rules authorise
on, and the Sheet's own "Role" column means the dance one — a collision worth
keeping a permanent distance from.

## What the rules still guarantee

This widened what reception can create, and it is worth being plain about what was
given up. The rule used to say reception "cannot invent a Full Pass Gold for a
friend". It now can: a 259 € pass sold on the night is a real thing the desk does.

What survives is everything that protects the money:

- **Only what an organiser priced.** `isWellFormedDoorPass` reads
  `doorPasses/{passId}` as the sale is written and checks the name matches, so a
  pass type that exists nowhere in the festival cannot be minted, and a withdrawn
  one cannot be sold.
- **No balance.** A sale starts at zero. A terminal that could create a
  participant holding 500 € would be a mint.
- **No ledger entry, no block state, no overwriting** an existing document.
- **Paired in the same batch**, with the reverse lookup agreeing, or the whole
  thing is refused.

### One thing the rules cannot check

`nameLower` is **not** verified against `name`. It was, for about an hour, and it
would have refused half this festival: rules' `.lower()` is ASCII-only. Measured
against the emulator rather than assumed — a document naming "Łukasz" was accepted
only while `nameLower` still held the capital Ł, and the correctly lowercased
"łukasz" that Swift and every search box produce was refused. Polish, Czech and
Bulgarian names are most of this roster.

What that check protected against — a trusted reception account filing its own sale
under a name the panel does not show — is a much smaller problem than a queue at
the door. `backend/rules-tests/rules.test.mjs` has a test that sells to
"Łukasz Ćwik", "Карол Chrząszcz" and friends, which is what stops somebody
reinstating it.
