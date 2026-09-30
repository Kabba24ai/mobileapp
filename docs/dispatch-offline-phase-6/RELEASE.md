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

## Final release review (2026-09-30)

Fresh whole-diff reviews of both repositories after integration. No Critical finding. Important findings and their disposition:

| Finding | Disposition |
|---|---|
| Offline Dispatch showed "Dispatch isn't downloaded" instead of the last live list while nothing was downloaded — permanent while the backend lacks the offline endpoints | Fixed (`bd542f6`): offline with nothing downloaded shows the feed snapshot, flagged not current |
| Dispatch card buttons (Call, Map, Assign Driver) could index past a replaced list and crash | Fixed (`bd542f6`): bounds-checked; reproduced red as a crash first |
| Orders list sync redraw could reload rows against an unseen row count | Fixed (`bd542f6`, refined in `d04e72d`): a mismatched table is left to the reload already on its way |
| Fix review: after an offline outcome on the snapshot fallback, reconnecting no longer reached the live feed | Fixed (`d04e72d`): offline the fallback keeps listening; the first online outcome hands the screen to the feed. A confirming review found no Critical or Important defect |
| Backend departure lock treated a bare arrival latch (left by production's old recalls) as departed, locking recalled lines | Fixed in the backend release branch: the latch counts only with its arrival time |
| Upgrade from 1.0.22 does not reuse 1.0.22's company caches (reference lists, order details, Assembly Review, Dispatch snapshot) | **By design** (Phase 4 Amendment B: unscoped legacy caches are never read because their company cannot be proven). Queued work survives the upgrade and drains. Mitigation: open the app once **online** after updating; the first online use rebuilds every cache |

Carried Minors from the fix reviews: a stale tag inside a replaced list of the same length still acts on a different row (bounds checks stop crashes only; match by unique id later); each offline outcome on the snapshot rebuilds the list (brief skeleton flash); the Driver Checklist's in-memory write-back to the snapshot is not persisted while the snapshot is shown (the saved checklist state still drives the card); the Orders redraw can show skeleton rows when a page load starts from exactly one page of rows; the snapshot slot is shared by the Pending, Completed and search answers (as in 1.0.22).

Carried Minors from the whole-diff review: the privacy manifest's file-timestamp reason is DDA9.1 where C617.1 describes the use (category declared, no submission risk); the Driver Checklist → Dispatch write-back is by row index (a short window can merge onto the wrong row until the next feed); each Dispatch open does a manifest round trip (404) before the feed while the backend is behind; one `as!` in the new users-list loader; Sync operations are not bound to a company (a terms.sign made before a company switch parks); a stale `stepIds` array must stay the length of the wizard steps.

**Outside this release, needs action:** an APNs auth key (`AuthKey_J9CRR5GHT3.p8`) is in the app target's Copy Bundle Resources and therefore inside every shipped IPA, including the live 1.0.22. Remove it from the target and revoke it in the Apple Developer account.

## Release

- Version **1.0.23 (1009)**. 1.0.22 has been live on the App Store since 2026-09-20, so a released version cannot take this build.
- Release mode **Manual release**. Neither the App Store release nor the backend deploy happens before the coordinated release is authorized.
- Recommended driver instruction with the release: update the app, then open it once **online** before the next route (see the upgrade note above).
- Coordinated release order: (1) release 1.0.23 on the App Store and let it reach drivers' phones; (2) deploy the backend release branch to production main; (3) enable silent wake only after its own preflight.
