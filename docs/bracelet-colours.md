# Wristband colours

Each pass type gets a different colour of wristband, so reception reaches for
the right pile and anybody can tell a Full Pass from a Party Pass across a room.
Organisers set the mapping; the terminals read it.

---

## Ten wristbands, written down

The festival prints ten piles of wristbands, and the Bracelets tab has one row
per pile, in this order:

```
Full Pass INT            Full Pass, Intermediate
Full Pass ADV            Full Pass, Advanced
Full Pass PRO            Full Pass, Pro
Full Pass Gold           Full Pass Gold, any level
Party Pass               Party Pass
Party Pass Plus          Party Pass Plus
Jazz Performance Track   Jazz Performance Track
Friday Evening           an evening ticket sold for the Friday
Saturday Evening         …the Saturday
Sunday Evening           …the Sunday
```

**Flat: no fallback row, no level nested under a pass type, nothing that appears
or disappears with the roster.** The list lives in `WRISTBANDS` in
`web-admin/src/schema.ts`, because it is a fact about the festival rather than
about code.

It used to be derived from whatever pass types people held, and both halves of
that were wrong for the job. A pass type nobody had bought yet had no row at
all, so the Jazz Performance Track could not be given a colour before the first
person bought one. And the pass types that split by level *also* had an "any
level" row above them, which read as a second, competing answer to a question
the level rows had already answered — somebody's way out of it was to set
`Full Pass` to white and call it "No color", which is the shape of a control
nobody could use.

What derivation bought was that nothing could be stranded, and that is kept, in
two places rather than by building the table out of the roster:

- **A colour matching none of the ten** is listed underneath, with its fields and
  its document id, and can be cleared. Not hidden: the apps read every colour
  document, so one nobody can see is still deciding somebody's colour on a phone.
- **People matching none of the ten** are counted and named — a Full Pass with no
  level, or one of the Sheet's free-text pass types like `Full Pass - 205 €
  (Upgrade from Party)`. Left unsaid, the first anybody would know is somebody
  standing at the desk with no colour on their screen.

```
braceletColours/full-pass-pro
  passType:  "Full Pass"        // verbatim, as it appears on a participant
  level:     "Pro"              // one of the four, or absent for any level
  colour:    "#1B1B1B"          // #RRGGBB, upper case
  name:      "Black"            // what staff call it out loud. Optional.

braceletColours/evening-friday
  passType:  "Evening Ticket"
  evening:   "friday"           // matched on the night, not the pass type
  colour:    "#6B4E9B"
  name:      "Purple"
```

**The night first, then the level, then the pass type.** Friday, Saturday and
Sunday are sold as one pass type and differ only in which door somebody came
through, so the night is the only thing that can tell those three wristbands
apart — a colour naming one is matched on the night alone and is deliberately
kept out of the pass-type lookup, where whichever loaded last would otherwise
colour every evening ticket there is. Then a level colour, then the pass type's
level-less one. `BraceletColourScheme.colour(for:)` holds the rule, and
`wristbandFor` in the panel makes the same decision in the same order, so the
**People** counts are what the phones will do rather than a second opinion.

The four levels are `Intermediate`, `Advanced`, `Pro` and `Other`, and the three
nights `friday`, `saturday`, `sunday`, all pinned by the rules. A fifth level or
a fourth night would match nobody and look like a colour that silently does
nothing, and a document claiming both a level and a night is refused outright.

```
allow read:            if canRead();     // every role, the bar included
allow create, update:  if isAdmin() && isWellFormedColour();
allow delete:          if isAdmin();
```

**Readable by everyone, unlike merch.** The colour is a function of
`ticketType`, which every terminal already reads off the participant, so
restricting it would protect nothing — and would produce a bar terminal that
silently shows no colour, which is the failure mode that cost an evening on the
merch feature.

**The apps match on `passType`, never on the document id.** The id is a slug,
derived for readability, and two long pass types could in principle slug to the
same key. Matching on the field means such a collision shows up in the panel as
one row overwriting another, rather than as a participant quietly being given
somebody else's colour.

Matching is case- and whitespace-insensitive. One side is typed into a web form,
the other comes out of a hand-maintained Google Sheet, and `"Full Pass "` failing
to match `"Full Pass"` would be invisible.

## Where the dance level comes from

`Level` was an excluded column — the Sheet's paragraph of class description
("Advanced - you have significant experience in Lindy Hop and…", one of them 300
characters long) has no business on a document every terminal can read. The
importer now keeps **only the leading word**, matched before the dash, so what
reaches Firestore is `Advanced` and nothing else. An unrecognised value becomes
empty rather than being kept verbatim: the opposite rule to pass types, because
a pass type is what somebody bought and must show even if it looks odd, while a
level is one of four.

It does land on the participant document, so the bar can read it. That was a
deliberate call, weighed against keeping it in a reception-only subcollection as
merch is: a dance level is on show in class anyway, and the alternative costs a
second read on every participant screen for something much less sensitive than a
phone number.

`Level` in this Sheet is **not** a permission, exactly as `Role` in this Sheet is
the dance role and not `StaffRole`. Same trap, two columns apart.

## The cost of a written-down list, and what pays it

The Sheet's pass types are free text — `Full Pass - 205 € (Upgrade from Party -
135€ + 70€)` is a real value — and the importer keeps anything it does not
recognise verbatim rather than dropping it. Ten written-down rows cannot cover a
string like that, and the old derived table could.

What pays for it is the count beside every row and the warning under the table.
Each row says how many people would be handed that wristband, computed by the
same rule the phones use, so a row reading **0** where you expected thirty is
visible in the tab rather than at the desk. Underneath, anybody the ten rows do
not cover is counted and named with their pass type and level. Nothing is
silent; it is just said in the panel instead of being implied by a row appearing.

## `#RRGGBB`, upper case, or nothing

The rules pin the format with a regex, the panel normalises what the browser's
colour input returns (lower case) before writing, and both apps refuse anything
else.

**Two ways into the same value: the picker, and a box to paste a hex into.**
Wristbands are ordered by hex and the supplier writes it in an email, so the
picker was the wrong end of the tool — matching `1E6BB8` by eye in a colour
wheel is not a thing anybody should be asked to do. `parseHexColour` takes it
with or without the `#`, in either case, with whitespace around it, and expands
`#fff` the way CSS does. Anything else is not a colour: the box says so and
**Save** stays disabled, rather than a guess being written. While the hex is
half-typed the swatch keeps showing the last colour it was, because a swatch is
what somebody compares against a physical wristband.

There is **no fallback colour anywhere**. A swatch of the wrong colour is worse
than no swatch, because somebody hands over a wristband on the strength of it. A
pass type with no mapping simply shows nothing, which is an ordinary outcome: a
festival can colour four pass types and leave the one-off upgrade strings alone.

## At the desk

A full-width band with the name written on it — **SKY BLUE BRACELET** — inside
the identity card, under the ticket line. Inside the card because it answers a
question about this person rather than about the festival, and reception is
reaching for a pile of wristbands while looking at that block.

It started as a 16pt square beside a label and that was too little colour to
judge: at arm's length across a desk it read as an icon rather than as the colour
itself. The thing being compared to a physical wristband should be the size of a
thing you compare.

The text on it **flips between dark and white by relative luminance**, because an
organiser can pick `#FFE24D` and white on that is unreadable in a bright foyer.
Luminance rather than an average of the channels: a naive `(r+g+b)/3` calls pure
green dark and pure blue light, which is backwards for both. A hairline border
keeps a near-white colour from dissolving into the card.

A colour with no spoken name falls back to its hex, so an unnamed colour looks
unnamed rather than blank — and a hex is at least something to read out over a
radio.

**The level is shown too, for Full Pass and Full Pass Gold only.** Under the
pass type on its own line when the guest is awaiting check-in, and on the
identity line once they are checked in — beside the pass type in both, because
that is what it qualifies. `Participant.levelForDisplay` holds the rule.

Not on the other pass types, where the Sheet's answer is mostly `Other` — the
form's way of saying "not applicable" — and printing it would be noise on the
one screen that has to stay scannable while somebody waits. A Party Pass holder
**with** a level recorded is one of the fixtures, so the suppression is
something anybody can see rather than only a test.

The mapping loads once with the drinks menu rather than per participant: a
handful of documents that change about twice a festival. It loads in its own
`do/catch` after the roster and the menu, so a colour read that fails cannot
report the catalogue as broken, and cannot raise an alert at sign-in about
wristband colours — which is a fine way to teach staff to dismiss alerts.

## Verified

- **141 iOS tests**, including the one that matters — `Full Pass Gold` starts with
  `Full Pass`, and anything doing prefix matching files every Gold holder under
  the wrong colour — plus the level fallback, levels not leaking across pass
  types, each night getting its own colour from one pass type, a night never
  reaching somebody who is not there for the night, the contrast flip, and which
  pass types show a level at all.
- **148 rules tests**: every role can read, only an organiser can write, the
  `#RRGGBB` shape is enforced (`red`, `#f00` and lower case all refused), a
  level outside the four is refused, a night outside the three is refused, and a
  document claiming both a level and a night is refused.
- **60 importer tests**, including that the level arrives as one word and the
  Sheet's paragraph never does.
- **End to end against the emulator**, 2026-09-20. Set `Full Pass` to `#1e6bb8`
  "Sky Blue" and `Full Pass · Pro` to `#1b1b1b` "Black" in the panel; both
  normalised to upper case through the real rules, the override carrying
  `level: "Pro"` and the base carrying no level field at all. The iOS app then
  showed Karol Chrząszcz (Full Pass, Pro) a **black** band and Amélie Roux
  (Full Pass, Advanced) a **sky blue** one — the override and the fallback, from
  the same pass type.
- **The hex box, against the emulator**, 2026-09-22. `73ff4d` pasted was written
  through the real rules as `#73FF4D`; `#fff` expanded to `#FFFFFF`; `red`,
  `#12345` and `#GG0011` left **Save** disabled with the swatch still showing the
  last real colour.
- **The ten rows, end to end from the panel to a phone**, 2026-09-22, against the
  emulator seeded with the colours production actually holds — including
  `full-pass` set to `#FFFFFF` and called "No color". The tab showed the ten in
  order; `full-pass`, `full-pass-gold-advanced` and `full-pass-gold-pro` fell
  into **Colours matching no wristband** and cleared from there; the Full Pass
  Gold row counted both Gold holders whatever their level; and the two people who
  match nothing — a Full Pass with no level, and `Full Pass - 205 EUR (Upgrade
  from Party)` — were named in the warning rather than left to the desk.
  `6b4e9b` "Purple" saved on **Friday Evening** wrote
  `{ passType: "Evening Ticket", evening: "friday" }`, and the iOS app then showed
  Ana Ivanova, a Friday ticket, a **PURPLE BRACELET** — while Boris Petrov, a
  Saturday ticket with no colour yet, showed **no band at all**, which is the
  failure the night-keyed lookup exists to prevent.

## Still open

- **Four of the ten are uncoloured in production, and three leftovers are
  waiting to be cleared.** Read back on 2026-09-22: Full Pass INT, ADV and PRO,
  Full Pass Gold, Party Pass and Party Pass Plus all carry a colour, and the
  Jazz Performance Track and the three evenings do not. `full-pass` (`#FFFFFF`,
  "No color"), `full-pass-gold-advanced` and `full-pass-gold-pro` match no row
  any more and sit under **Colours matching no wristband** — the last two are
  still live, so a Gold Advanced or Gold Pro is shown one of those yellows
  rather than the Gold row's until they are cleared.
- **The evening colours need a new iOS build to show.** The night is read by
  `BraceletColourScheme`, which TestFlight build 89 does not have: it was built
  before this change, so a Friday wristband set in the panel today shows nothing
  on the phones until the next release.
- **Android has none of this.**
- **Nobody checks the wristbands actually match.** The app reports what an
  organiser typed; whether the Gold pile is really gold is a question for the
  person holding it.
- **A colour is not shown anywhere but the participant screen.** The bar can
  read it and does not display it, and the check-in list does not either — the
  list would be the obvious next place if reception finds itself opening people
  just to see a colour.
