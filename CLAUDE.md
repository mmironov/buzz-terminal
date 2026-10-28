# Swing Buzz — staff terminal

A festival cashless-bar system: three clients against one Firebase project
(`swing-buzz`). `ios/` SwiftUI terminal (reception + bar) · `web-admin/` React
organiser panel, live at https://swing-buzz.web.app · `android/` Compose, stale ·
`backend/` security rules, the Google Sheet importer, the rules test harness.

**Picking this up cold? Read `HANDOFF.md` first** — current state, the open items,
and where the local secrets live. Then `README.md` and `docs/`.

## The one that cannot be undone

**Never run `npm run reset` against production.** It deletes ledger entries
permanently — the Admin SDK bypasses the append-only rule — and **there is no
backup**: Firestore point-in-time recovery and scheduled backups are both disabled.
The September 2026 festival's entire record (1109 ledger entries, 185 participants)
exists only in that database. The emulator is fair game; production is not.

Ask before any write to production. Read it back after every write that lands.

## Money and measures

- **Money is integer cents. Stock is integer millilitres. Never floats** — `0.1 + 0.2`
  is not `0.3`, and a balance that drifts is worse than no balance.
- **A balance moves only alongside a ledger entry written in the same batch.**
  Reception may credit, the bar may debit, nobody may edit history. The rules enforce
  it; don't invent a path around them.
- Consumption and takings are **derived** from the ledger, never stored precomputed.

## Privacy and credentials

- `backend/import-roster/serviceAccountKey.json` is a real admin credential that
  bypasses every security rule. Never commit it, never put it in an app, never paste
  it into a chat. Same for `GoogleService-Info.plist`, `google-services.json`,
  `AuthKey_*.p8`.
- Only Sheet rows with `Status = paid` are imported.
- The Sheet's `Role` column is the **dance** role. Never map it to `role` — that is
  the authorisation claim the rules read.
- Email, phone, comments, partner details and receipts must never reach a participant
  document: every field there is readable by every terminal, including the bar.

## Two traps that have already bitten

- **A collection-group query needs its own rule.** A nested `match` does not authorise
  one and the failure is *silent* — the table simply never appears.
- **Drink document ids no longer match their names**: `water` sells "Beer - Lager",
  `gt` sells "Wine", `run-coke` sells "Gin", `beer` sells "Beer - Craft". Group bar
  analytics by the ledger's snapshotted **name**, never by `drinkId`.

## Verify by executing

| | |
| --- | --- |
| `ios/scripts/test.sh` | 180 Swift tests |
| `backend/rules-tests/test.sh` | 210 rules tests (needs the Homebrew JDK) |
| `cd backend/import-roster && npm test` | 100 importer tests |
| `cd web-admin && npm test && npx tsc --noEmit` | 14 tests + typecheck |

`xcode-select` points at the Command Line Tools, so bare `xcodebuild` refuses to run —
the wrappers in `ios/scripts/` set `DEVELOPER_DIR` themselves. Drive the simulator with
`xcrun simctl`; `-sbScreen <name>` jumps straight to any screen (see `LaunchOverrides`).

## Working style

Commit in small steps with the reasoning in the message — the repo's history is
documentation. Never commit and push in one action; push only when asked.
