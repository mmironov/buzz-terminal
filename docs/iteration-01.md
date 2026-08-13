# Iteration 1 — scaffold, design system, all screens

Goal: a running SwiftUI app that matches the Claude Design prototype screen for
screen, with the seams for Firebase and Core NFC already cut.

Result: builds clean, 13 screen states verified in the Simulator, 25 unit tests
green.

---

## 1. What changed, file by file

### `App/` — entry point and state

| File | What it does |
| --- | --- |
| `BuzzTerminalApp.swift` | `@main`. Creates the single `AppModel` and puts it in the environment. |
| `AppModel.swift` | The whole state machine: session, scanning, current bracelet, cart, receipt, and every transition. ~330 lines and the file to read first. |
| `RootView.swift` | Chrome + `switch` on `model.screen` + the scan overlay on top. |
| `LaunchOverrides.swift` | `#if DEBUG` port of the prototype's props panel — jump to any screen from a launch argument. |

### `DesignSystem/` — Modernist, transcribed

| File | What it does |
| --- | --- |
| `Tokens.swift` | Every colour, spacing step, radius and rule weight from `styles.css`. |
| `Typography.swift` | Archivo via its variable weight axis; the kicker; a CSS `line-height` bridge. |
| `Components.swift` | `SBButtonStyle` (primary/secondary/ghost/block/icon), `SBTextField`, `SBTag`, `SBDivider`, `SBBand`, `SBDetailRow`. |
| `Glyphs.swift` | The five line glyphs as SwiftUI `Shape`s, coordinates transcribed from the design's SVG. |

### `Domain/` — models and rules, no SwiftUI

| File | What it does |
| --- | --- |
| `Money.swift` | Integer-cents money type with exact arithmetic and the design's `"23.50 €"` format. |
| `Models.swift` | `StaffRole`, `Screen`, `BraceletID`, `Participant`, `WaitingGuest`, `Drink`, `Cart`, `Receipt`, plus the check-in search predicate. |
| `TopUpEntry.swift` | Keypad state and input rules, presets, display formatting. |
| `PaymentDecision.swift` | The four-way charge outcome, the rules behind it, and its copy. |
| `SampleData.swift` | The prototype's fixtures, kept verbatim for side-by-side comparison. |

### `Data/` — the seams

| File | What it does |
| --- | --- |
| `TerminalRepository.swift` | The protocol Firebase will implement, plus `TerminalError`. |
| `InMemoryTerminalRepository.swift` | An `actor` holding the fixtures, with fake latency. |
| `BraceletReader.swift` | Reader protocol + the simulated one. |

### `Features/` — one file per screen

`SignIn`, then `Reception/` (home, assign, participant, blocked, top-up),
`Bar/` (menu, cart, pay review), and `Shared/` (receipt, scan overlay, status
header). Each is a plain `View` reading `AppModel` from the environment; none of
them contain business logic.

---

## 2. Concepts in play

Things worth knowing why, not just that.

### `@Observable`, not `ObservableObject`

`AppModel` is annotated `@Observable` (the Observation framework, iOS 17+). Three
consequences:

- The app holds it with **`@State`**, not `@StateObject`. `@StateObject` is for
  the old `ObservableObject` protocol.
- Views receive it with **`@Environment(AppModel.self)`**, not
  `@EnvironmentObject`.
- No `@Published` anywhere. SwiftUI tracks which properties each view body
  actually *reads*, so mutating `search` does not invalidate the bar menu. With
  `ObservableObject`, every `@Published` change redrew every observer.

To get a `Binding` out of an environment object you re-declare it locally:

```swift
@Environment(AppModel.self) private var model

var body: some View {
    @Bindable var model = model      // now $model.search exists
    SBSearchField(text: $model.search)
}
```

That line looks redundant and isn't — it is the documented idiom.

### A state machine instead of `NavigationStack`

`Screen` is a flat enum and `RootView` switches on it. That is unusual for
SwiftUI, and the reason is in the design: no back chevrons, no swipe-back, no
titles, and several transitions must *replace* history rather than push (a
receipt should not be swipeable back into the payment it just committed). Kiosk
UIs are state machines; nav stacks are for browsing.

If this app later grows a settings area or a transaction history — things you
genuinely browse — those are the parts that should get a real `NavigationStack`.

### Protocol seams for untestable dependencies

`TerminalRepository` and `BraceletReader` exist because of two hard constraints:
Firebase needs a console project that does not exist yet, and Core NFC does not
exist on the Simulator at all. Rather than stub those inline and rewrite later,
the protocols are written to the shape of the *eventual* implementation:

```swift
func topUp(bracelet: BraceletID, amount: Money) async throws -> Participant
```

`async` (Firestore is a network round trip), `throws` (it can fail), and it
returns the new `Participant` rather than `Void` — because the client should
never be the authority on a balance. Every call site already awaits and already
has an error path, so iteration 2 changes one file.

`InMemoryTerminalRepository` is an `actor`, which is the interesting choice:
its mutable dictionary is safe from any thread without locks, and — more
usefully — callers are *forced* to `await`, so the call sites already look
exactly like the Firebase ones will.

### Money as integer cents

The prototype had `balance: 23.5` and `n.toFixed(2)`. Fine for a mock, wrong for
money: `0.1 + 0.2 != 0.3` in binary floating point, and a bracelet that gets
topped up and charged forty times over a weekend accumulates visible error.
`Money` wraps an `Int` of cents, is `Comparable` and `Sendable`, and only becomes
a string at the edge. `MoneyTests` includes the drift cases.

### Variable fonts, the part that bites

Modernist is "set entirely in Archivo", and Google Fonts ships Archivo only as a
**variable** font now. The obvious approach fails silently:

```swift
Font.custom("Archivo-ExtraBold", size: 32)   // ← renders Helvetica
```

CoreText does not expose most named instances of that file by PostScript name,
and the fallback is quiet. What works is setting the `wght` variation axis on a
descriptor directly:

```swift
UIFontDescriptor(fontAttributes: [
    .name: "Archivo",
    kCTFontVariationAttribute as UIFontDescriptor.AttributeName: [
        2003265652: 800        // 'wght'
    ],
])
```

`2003265652` is the four-character tag `wght` as an integer. `SBFont` wraps this,
also turns on tabular figures (`kMonospacedNumbersSelector` — the design sets
`font-feature-settings:'tnum'` on every price and balance), and falls back to the
system face if the font is missing rather than to Helvetica.

### Translating CSS the design system actually specifies

A few conversions that recur:

| CSS | SwiftUI |
| --- | --- |
| `letter-spacing: .14em` at 9.5px | `.tracking(0.14 * 9.5)` — tracking is points, not em |
| `line-height: 1` | `.lineSpacing((1.0 - 1.25) * size)` — `lineSpacing` *adds* to natural leading |
| `color-mix(… var(--color-text) 60%, transparent)` | `.sbInk(0.6)` |
| `border-radius: 0` | `.clipShape(Rectangle())`, never `.cornerRadius` |
| `:active` | `configuration.isPressed` in a `ButtonStyle` |
| `:hover` | nothing — there is no hover on iOS |

Colour tokens are declared on `extension ShapeStyle where Self == Color`, not on
`Color`. That is what makes leading-dot syntax work in both positions
(`.foregroundStyle(.sbAccent)` *and* `let c: Color = .sbAccent`). Declaring them
on `Color` only gets you the second; declaring on both is a redeclaration error.

### The one design rule that is easy to get backwards

> "Button labels are flush left — a button wider than its label starts the text
> at the left padding edge, never centered."

So `SBButtonStyle`'s `block` variant aligns `.leading`. That is the opposite of
the iOS default, and it is the most visible thing to get wrong in this system.

---

## 3. Deliberate deviations from the prototype

Two, both flagged in the code:

1. **Money type** — see above.
2. **The Sign in button is never disabled on an empty field.** The prototype
   validates on submit and shows the inline error; a greyed-out primary action on
   first launch reads as a broken app. (I built it disabled first, screenshotted
   it, and it looked broken — so it changed.)

And one thing I kept even though it is "wrong": the offline toggle mutates state
locally and bumps a counter without any real queue. It exists so the offline
banner, queue label and "Approved · offline" receipt band are all built and
reviewed now, ready for the real write-behind queue in iteration 3.

---

## 4. Verification

Not "it compiles" — actually run and looked at.

- `./scripts/build.sh` — clean build, no warnings from project code.
  Three rounds of fixes got there:
  - colour tokens declared on `Color` would not resolve in `ShapeStyle`
    position, so they moved to `extension ShapeStyle where Self == Color`;
  - `GENERATE_INFOPLIST_FILE = NO` meant Xcode injected no `CFBundleIdentifier`
    and the app would not install at all — it is `YES`, which *merges* the
    generated keys into the hand-written `Info.plist` rather than replacing it;
  - interpolating `Money` into a `Text("…")` hits a deprecated
    `LocalizedStringKey` path; those sites now interpolate `.description`.
- Bundle checked, not assumed: `Archivo.ttf` lands at the bundle root (Copy
  Bundle Resources flattens folders), `UIAppFonts` matches, and there is exactly
  one `Info.plist` in the product.
- 13 screen states captured from the running app and compared against the design.
  Two mismatches found and fixed: the `⌫` character fell back to a system face
  at a lighter weight (now a drawn Lucide-style glyph), and the top-up confirm
  button was pinned to the bottom of the screen instead of sitting under the
  keypad. A suspected third — a tint inside the scan target — turned out to be a
  screenshot-scaling artifact; the pixels are `#F3F2F2` inside and out.
- `./scripts/test.sh` — 25 tests, `Money` suite green, the 19 failures are the
  three exercises.

One caveat on this machine: `xcodebuild test` prints a stray
`xcrun: error: unable to find utility "simctl"` during teardown *after* the
results. It is a side effect of `xcode-select` pointing at the Command Line
Tools and goes away once you run the `sudo xcode-select` line from the README.

---

## 5. The three exercises — done

All implemented, all green. Worth recording what each one actually cost, because
the defects were the useful part:

**`TopUpEntry.press(_:)`** — four passes.
1. The leading-zero branch replaced the text and then *also* appended, so `0`
   then `5` gave `"55"`.
2. A newly-added integer cap was nested inside the decimal check, so it gated
   every digit — once the euros hit the cap you could not type cents at all.
   `1234.50 €` was unreachable. Fixed by making the two rules alternatives
   (`else if`), which also made the branch read as the question it asks: *which
   side of the separator am I on?*
3. The doc comment claimed a 9999 € ceiling while the constant said 3 digits.
4. Green.

The good call in this one was reaching for `components(separatedBy:)` rather than
`split(separator:)`. `"12.".split(separator: ".")` drops the trailing empty piece
and yields `["12"]`; `components` keeps it as `["12", ""]`, which is exactly what
lets the two-decimal rule see "zero decimals typed so far".

**`WaitingGuest.matches(query:)`** — two passes. First version matched `name`
only, never `pass`. Note that the `city not searched` test passed the whole time
and proved nothing until there were two clauses to deliberately exclude a third
from. Final version collapsed a `guard … else { return false }` / `return true`
pair into a direct `return` of the boolean.

**`PaymentDecision.evaluate(…)`** — one pass, correct first time, including the
`>=` on the exact-balance case and the block-before-funds ordering.

It also correctly *ignored* the hint suggesting `Money.clampedToZero` for the
`short` calculation. Because the `guard` guarantees `balance < total`, the
subtraction cannot be negative and the clamp would have been dead code. Knowing
when not to take the hint is the better instinct.

## 6. What is next

Iteration 1 is closed: every screen matches the design, the domain logic is
covered, and the two seams for the real backend are in place.

**Iteration 2 — Firebase.** Blocked on one thing only: a Firebase project has to
be created in the console, and `GoogleService-Info.plist` dropped into
`BuzzTerminal/Resources/` (already gitignored). Then:

- `FirebaseTerminalRepository` implementing the existing protocol. No view
  changes — that is the whole point of how the protocol was shaped.
- Firebase Auth replacing the `reception*` / `bar*` prefix check, with the role
  as a custom claim rather than something the client decides.
- Firestore collections for participants, waiting guests and the drinks menu.
- Balance changes as **transactions**, not read-then-write. Two reception desks
  topping up the same bracelet at once must not lose a payment.
- Security rules: a bar account must be able to debit a balance but never credit
  one, and no client should be able to lift a block. `PaymentDecision` running on
  the phone is a courtesy to the operator, never the authority.

**Iteration 3 — Core NFC and a real offline queue.** Needs a physical device and
the NFC entitlement; `NFCReaderUsageDescription` goes into `Info.plist` at that
point. The offline queue becomes a real write-behind log with conflict handling,
and the cosmetic `isOffline` toggle is replaced by actual reachability.

**Iteration 4 — Android.** Jetpack Compose against the same Firestore schema.
`Domain/` is the part worth porting deliberately rather than translating line by
line; the design system maps onto Compose theming fairly directly, though
Modernist's zero-radius, flush-left, 2dp-rule language will need the same kind of
discipline there as it did here.
