# Dispatch Offline Phase 6 — release record

Closed 2026-09-30. Physical acceptance ended by product-owner decision. The next validation phase is controlled real-world operational use, not further staging scenarios.

## Physical acceptance status

| Scenario | Status |
|---|---|
| P1 Golden Delivery | PASS |
| P2 Resume testing | PASS |
| P3 Equipment substitution | PASS |
| P5 Fully offline first start | PASS |
| P6 Offline FIFO: switch → Available → On My Way | PASS |
| P7 Arrived / customer-site routing regression | PASS |
| P8 Redesigned Call Customer wizard | FULL PASS |
| P9 Fuel / Keys gating | PASS |
| P10 Office reassignment before departure | PASS, including automatic Superseded handling |
| P11 Return regression | PASS — Return's call behaviour intentionally retained |

**Deferred / waived for this release (not failures):** driver-flow P4 (Review Assembly before and after departure) and P12–P16 (departure lock after Load Map & Go and after Arrived, office writers refused, legitimate recall, yard unchanged); the original offline set A–P and the battery / background windows; G (real background push) — silent push stays disabled. These are covered by automated tests and move to operational validation.

## Observations carried as release notes (not fixed in this release)

1. `switch-equipment` is not tracked in `mobile_operations` (the controller documents it as naturally idempotent). P6.
2. Eight checklist-context requests in one second at Arrived. P6.
3. The phone's reference fleet list refreshes only when empty or older than 12 hours (`DispatchOfflineReferenceWarmup.maxAge`) — product note.
4. An office-made unit change is not an assignment-episode boundary on the phone; the phone converges through the refreshed row. Since P10 a stale Available the server refuses with QUEUE_ASSIGNMENT_CHANGED is retired automatically as Superseded.
5. After an office switch the server keeps the previous unit's Fuel answer until the next save names the new unit; the phone never applies it to the new unit.
6. Call wizard: a stale sender can regress the server's call until the next save; the legacy MMKV fallback queue drops the steps; no row lock on the `dispatch_checklist` read-modify-write.
7. The queue-line envelope carries no `server_received_at` (clock-skew note for episode judgement).
8. A driver-checklist save for another driver's leg is refused with DISPATCH_ASSIGNMENT_CHANGED and parks as Needs Attention (order #6009) — undecided.
9. Superseded handling: its trigger wiring is proven physically (P10) rather than by an automated test; a double move A→B→C after a verdict naming B stays parked until a Retry.

## Rollout order — app first, backend second

The backend derives the delivery call's Confirmed from the three wizard fields. **Old pre-wizard app → new backend is not acceptable**: a successful call from the old app would be stored as not confirmed. The new app must be live on drivers' phones before the backend deploys.

### Compatibility gate: new app → current production backend (PASS, 2026-09-30)

Mobile `e1c56bf` against production backend code (origin/main `3d2b7a970`), served locally over a throwaway copy of the staging database. Writes went through the app's own API client, Sync Engine, handlers and builders; reads through its own response models, Core rules and the real Driver Checklist screen. Evidence: `kabba-dispatch-offline-p6-evidence/release/compat/`.

| Flow | Production accepts | The new app reads it back |
|---|---|---|
| Available (unit) | 200, acknowledged on the live episode | Review decodes; unit available; gate GO |
| Call wizard — three partial saves | 200 each | Same phone: call confirmed (local record) |
| Fuel Full + Keys With Machine | 200, stored | Same phone: both kept |
| On My Way | 200, `ready_to_go_at` set | The trip shows its On My Way state |
| Arrived | 200, arrival latched | Arrived |
| No Answer (+ Fuel Full) | 200, stored; the no-answer text runs once, on the transition only | No Answer on any phone; call satisfied |
| Stale Available after an office switch | 409 QUEUE_ASSIGNMENT_CHANGED with `current_equipment` | Retired as Superseded (server-verdict proof); new unit needs its own Available |
| Terms | GET 404 | Falls back to the hosted signing page (today's behaviour) |
| Offline manifest / packages | 404 | Dispatch falls back to the live feed (end-to-end on the simulator) |
| Installation registration | 404 | Ignored; never a queued operation |

Nothing parked; production's operation ledger recorded every write once.

**Degradations while the app is ahead of the backend** (all fail safe; they end when the backend deploys):
- Production stores the call's Confirmed but not the three wizard steps, and does not echo the unit that Fuel and Keys were bound to. On the same phone nothing changes. On **another phone or after a reinstall**, before departure, the call reads as not yet verified and Fuel / Keys are asked again.
- Production has no yard fuel / key predicates; the app falls back to the display flags the live app uses (Keys asked for any key mechanism, Fuel for any power source).
- Offline mission packages, offline Terms signing, installation registration and the departure lock are inactive until the backend deploys.

## Release

- Version **1.0.23 (1009)**. 1.0.22 has been live on the App Store since 2026-09-20, so a released version cannot take this build.
- Submitted for App Review with **Manual release**. Neither the App Store release nor the backend deploy happens before the coordinated release is authorized.
- Coordinated release order: (1) release 1.0.23 on the App Store and let it reach drivers' phones; (2) deploy the backend release branch to production main; (3) enable silent wake only after its own preflight.
