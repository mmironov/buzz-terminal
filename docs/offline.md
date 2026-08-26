# When the wifi goes

A festival's network fails at the worst moment, and the bar cannot stop selling. So
sales are accepted, queued, and reconciled afterwards — a decision taken knowingly,
with a cost written down below.

---

## The queue is Firestore's, not ours

Firestore already has a durable, ordered write queue: it persists across app
restarts, replays on reconnect, and applies writes to the local cache immediately so
reads reflect them. Building a second queue on top would have duplicated all of that,
badly.

What was actually missing was four things, and those are what got built:

| | |
| --- | --- |
| Not blocking the till on a server acknowledgement | `commit` races a 3-second grace period |
| A **real** pending count | `SyncCenter`, fed by the repository |
| Real connectivity | Firestore's own `metadata.isFromCache` |
| Noticing a **refused** replay | `FailedWrite`, persisted, with a screen |

### The grace period is the interesting bit

`WriteBatch.commit`'s completion fires only when the **server** acknowledges. Offline
it never fires, so awaiting it hangs the till. But firing and forgetting would be
worse in the common case: a write the server refuses *while online* must fail in
front of the operator, who can retry before the guest walks away.

So the two race. Answer within three seconds → normal behaviour, errors thrown as
before. Silence → the write is reported as queued, and Firestore owns it from there.

A write refused **after** being reported as queued becomes a `FailedWrite`. A write
refused **while somebody was still waiting** does not: they saw the error, nothing was
served, and a reconciliation list that fills with problems somebody already handled
is a list nobody reads.

### Connectivity is Firestore's opinion, not `NWPathMonitor`'s

A phone can hold a perfectly good association to a venue access point that routes
nowhere — which is exactly what a festival produces. `metadata.isFromCache` on a
snapshot listener answers the question that matters: is this data coming from the
server, or from our own pocket. The listener starts after sign-in, because the rules
refuse an unauthenticated one.

---

## The cost, stated plainly

An offline charge computes the new balance from a cached read. The rules verify
`balanceAfter == balanceBefore + amount` server-side, so **if anything else moved
that balance meanwhile, the replay is refused** — and the drink is already poured.

That is the accepted trade: service never stops, and some revenue may need chasing.
The alternative was refusing sales while offline, which closes the bar mid-Saturday
because of one dead spot.

Top-ups are safer in the same situation: a refused credit means the cash is already
in the till and the guest is owed the balance, so the fix is to credit again.

`FailedWrite` therefore records who, how much, when, which till, the transaction id,
and the server's verbatim complaint — and says what to do, differently per kind,
because a refused charge and a refused top-up fail in opposite directions.

It is **persisted**, and that is the whole point of the type: a refused charge has to
survive a force-quit, a dead battery and a shift change. Settling one keeps the
record and takes it off the list — what an organiser did about missing money is part
of the audit, so nothing is deleted.

---

## Verified end to end

Against the emulator on 2026-08-20, driving the real UI. The network toggle in the
status header disables Firestore's transport, which is the only practical way to
rehearse this — airplane mode also kills the debugger, and bad venue wifi cannot be
summoned on demand.

**The happy path**

1. Check in while online → acknowledged inside the grace period, no banner.
2. Toggle offline → listener reports it: *"Offline — sales are being queued"*.
3. Top up 20 € → approved, receipt says it will sync, banner reads *1 transaction
   waiting to sync*, balance reflects the pending write.
4. Server checked directly: **balance 0, zero ledger entries.** The write really was
   only local.
5. Toggle online → replayed. Balance `2000`, one ledger entry, `lastTxId` set. The
   rules **accepted** it, so batch atomicity and the `getAfter()` check survive a
   replay.
6. Banner cleared.

**The refusal path**, which is the one the feature exists for

1. Check in Nina Kowalski while online.
2. Toggle offline, queue a 10 € top-up — approved locally.
3. While the app was offline, block her from the Admin SDK, exactly as an organiser
   would from the panel.
4. Toggle online. The rules refuse the replay: a blocked bracelet may not take money.

```
write refused: topUp 10.00 € participant 1043 tx 04294CA2-…
```

5. Banner turned alarming: *"1 transaction failed to sync — show an organiser"*, with
   a **View** action.
6. The screen showed: `Top-up 10.00 € — Nina Kowalski`, `19:25`, *"The money was
   taken but not recorded. Top the guest up again for this amount."*, the terminal
   id, the transaction id, and the raw rules rejection.
7. Server checked: her balance still `0`, still blocked, **no ledger entry**. The
   refusal was real, not cosmetic.

---

## Android

The same design, sharing `SyncState` and `FailedWrite` from `:domain` — the
arithmetic and the banner copy are one implementation, tested once, used twice.

Two places the platforms differ in mechanism rather than behaviour:

- **The grace period is `withTimeoutOrNull`.** The Swift twin has to race two
  continuations by hand and guard against resuming twice; Kotlin expresses the whole
  thing in one expression, and the Task keeps running after the timeout gives up,
  which is exactly what is wanted.
- **Persistence is hand-written JSON** into `SharedPreferences` via `org.json`.
  `:domain` has no serialisation dependency and gains nothing from one for six
  fields, so `FailedWrite` stays annotation-free and `SyncCenter` does the encoding.
  Amounts are stored as integer cents, never a decimal — the same rule as the Swift
  `Codable` conformance. A test pins the wire strings of `FailedWrite.Kind`, because
  renaming one would silently drop every stored failure on the next launch.

Not yet verified on Android: the queued and refused paths have been exercised end to
end on iOS only. The code path is shared in `:domain` but the Firestore plumbing is
not, so this is worth repeating on a device.

## Still open

- **A charge has never been refused on replay in a real test.** The mechanism is
  shared with the top-up above, so it is the same code path, but the specific
  scenario — two terminals spending the same balance while one is offline — has not
  been staged.
- **The pending count does not survive a relaunch.** Firestore's queue does, so a
  write can be acknowledged that this run never saw enqueued; the count is clamped at
  zero for exactly that reason. A count restored from disk would be more honest.
- **Nothing caps offline exposure.** A till could queue an unbounded number of
  charges in a long outage. Capping was considered and rejected as a rule staff would
  have to understand mid-shift, but it remains the obvious lever if a real outage ever
  produces a long list.
