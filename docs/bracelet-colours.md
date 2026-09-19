# Wristband colours

Each pass type gets a different colour of wristband, so reception reaches for
the right pile and anybody can tell a Full Pass from a Party Pass across a room.
Organisers set the mapping; the terminals read it.

---

## One document per pass type, and per level where it matters

```
braceletColours/full-pass
  passType:  "Full Pass"        // verbatim, as it appears on a participant
  level:     absent             // the fallback: anyone with this pass type
  colour:    "#1E6BB8"          // #RRGGBB, upper case
  name:      "Sky Blue"         // what staff call it out loud. Optional.

braceletColours/full-pass-pro
  passType:  "Full Pass"
  level:     "Pro"              // an override, for that class track only
  colour:    "#1B1B1B"
  name:      "Black"
```

**Level first, then the pass type's fallback.** Colour `Full Pass` once and
everybody with one is covered; add `Full Pass · Pro` and that track gets its own
band while everybody else keeps the first. Only Full Pass and Full Pass Gold
split in practice — the classes differ there and nowhere else — but nothing in
the code knows that. It is a fact about the festival, not a rule, so the panel
offers levels everywhere and the organiser colours what matters.

The four levels are `Intermediate`, `Advanced`, `Pro` and `Other`, pinned by the
rules. A fifth would match nobody and look like a colour that silently does
nothing.

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

## The pass-type list is derived, not hard-coded

The Bracelets tab reads the roster and counts the distinct `ticketType` values
actually in use, most people first, and beneath each one the levels anybody
actually holds. It does not work from a fixed list.

The Sheet's pass types are free text — `Full Pass - 205 € (Upgrade from Party -
135€ + 70€)` is a real value — and the importer keeps anything it does not
recognise verbatim rather than dropping it. A fixed list would silently leave
those people with no colour, and nobody would find out until somebody was at the
desk holding the wrong wristband. A pass type with a colour but nobody holding it
is still listed, so a mapping made before the first import does not vanish.

## `#RRGGBB`, upper case, or nothing

The rules pin the format with a regex, the panel normalises what the browser's
colour input returns (lower case) before writing, and both apps refuse anything
else.

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

- **102 iOS tests**, including the one that matters — `Full Pass Gold` starts with
  `Full Pass`, and anything doing prefix matching files every Gold holder under
  the wrong colour — plus the level fallback, levels not leaking across pass
  types, the contrast flip, and which pass types show a level at all.
- **94 rules tests**: every role can read, only an organiser can write, the
  `#RRGGBB` shape is enforced (`red`, `#f00` and lower case all refused), and a
  level outside the four is refused.
- **60 importer tests**, including that the level arrives as one word and the
  Sheet's paragraph never does.
- **End to end against the emulator**, 2026-09-20. Set `Full Pass` to `#1e6bb8`
  "Sky Blue" and `Full Pass · Pro` to `#1b1b1b` "Black" in the panel; both
  normalised to upper case through the real rules, the override carrying
  `level: "Pro"` and the base carrying no level field at all. The iOS app then
  showed Karol Chrząszcz (Full Pass, Pro) a **black** band and Amélie Roux
  (Full Pass, Advanced) a **sky blue** one — the override and the fallback, from
  the same pass type.

## Still open

- **Nothing is deployed or set in production.** The rules change is not live and
  no colour has been assigned, so every participant currently shows no band.
- **No production participant has a `level` yet.** It was an excluded column
  until now, so the 105 imported people have no such field. Until the roster is
  re-imported, every level lookup misses and everybody falls back to their pass
  type's colour — which is a safe failure and an invisible one, so it is worth
  doing the re-import in the same sitting as the deploy.
- **Android has none of this.**
- **Nobody checks the wristbands actually match.** The app reports what an
  organiser typed; whether the Gold pile is really gold is a question for the
  person holding it.
- **A colour is not shown anywhere but the participant screen.** The bar can
  read it and does not display it, and the check-in list does not either — the
  list would be the obvious next place if reception finds itself opening people
  just to see a colour.
