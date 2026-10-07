# Independent mobile checklist batches

Base: `92fbd1e64158842535fd257938553fe97d6e9680` (iOS 1.0.24 / 1010); ships as 1.0.25 (1011).

Every order product retains its own checklist execution, answers, employee, signature,
return location and sync operation. Combine shares employee/signature and return-store
convenience values only with entered checklists in the current batch. Untouched rows
do not participate; partly entered rows must pass validation. No backend changes.

The mobile correction also keeps unfinished siblings in the pending draft, merges
only submitted products into the completed cache, preserves the Combine setting and
shared selections when restoring a draft, and ignores untouched operational defaults
in Preview, Save and background progress. Preview uses detached note copies so Back
does not change the source notes. Error rows map back to their original sections.

## Verification so far

- Executable checks against extracted production Swift scope/signature methods:
  23 assertions pass. The original code failed 10 of the original 18 assertions.
  The portable runner uses lightweight model/UI stand-ins; it does not build UIKit.
- Swift syntax parsing of changed app and hosted test sources passed.
- `git diff --check` passed.
- Full `swift test` was attempted on the unchanged base; compilation is blocked in
  this Linux environment by the app core's Apple `CryptoKit` dependency.
- Xcode, simulator, hosted XCTest and device verification have **not** run here.

Portable reproduction:

```sh
python3 Scripts/test-checklist-batch-policy.py
```

## Mac validation before merge/release

Run `Scripts/test-sync-core.sh` and the `RentnKingHostedTests` scheme, including
`ChecklistBatchIsolationHostedTests` and `DispatchOfflineFieldBridgeHostedTests`.
Build the `RentnKing` app target. The new hosted tests are registered in the project.

On a three-equipment order, check Delivery and Return in both Combine modes:

1. Complete only A; Preview contains A, and B/C stay open with their own drafts.
2. Complete A+B; Preview contains A+B, and C stays open. In individual mode, sign
   A and B separately; Submit remains disabled until both are signed.
3. Complete all three; combined mode uses one employee selection/signature while
   still creating three independent operations.
4. Partially enter B; Preview refuses to discard it and points to B's missing row.
5. Leave everything untouched, including prefilled hours/fuel; no batch or prepare
   operation should be created. Selecting only a shared employee/store adds no row.
6. Back/cancel Preview and signature capture; other equipment's values stay intact.
7. Background/reopen a draft and finish a partial batch; the remaining rows and
   saved convenience selections survive, including the last single remaining row.
8. Reopen a completed report after a partial batch; it contains only the submitted
   products. Subsequent completed batches merge into that report by product ID.

No app version/build bump, upload, App Store submission or backend deployment is
part of this change.

## Mac validation (2026-10-06, Xcode 26.5 / 17F42, iPhone 17 simulator)

Found and fixed while validating on the Mac:

1. **Compile error** — `hasChecklistWork` compared the question's `selectFuleDelivery` /
   `selectFuleReturn` (`String?` in the app model) as a `String`; a nil fuel selection now
   counts as no input. The portable script's stand-in model now mirrors that optional type
   (the Linux run could not catch it).
2. **Portable script on macOS** — the generated Swift needs `import CoreGraphics` for
   `CGRect.zero` on macOS (Linux has it in Foundation).
3. **Reassignment re-enrolled a restarted line** — `discardLocalPreparation` cleared the
   line's input flag, then `callCheckListAPI` set it again. Only a FIRST unit selection is
   the line's own input now (marked by its caller); a reassignment leaves the flag cleared.
4. **Preview pointed nowhere for a missing unit / employee / location** — the batch
   (untouched lines removed) is mapped back to the screen section: the unit header for a
   line without a unit (the alert names it), the footer for employee/location (Combine:
   under the last line).
5. **Remaining lines hidden behind the completed report** — after a partial batch, Order
   Details and the Orders list treated the leg as finished (one line done) and opened the
   completed report, hiding the lines this change keeps in the draft. The first fix (a leg
   opens the report only while no pending draft remains) only worked on the phone holding
   the draft — superseded by the order-wide rule below.

Results: portable policy script 23/23 (Mac Swift), `Scripts/test-sync-core.sh` 679/679,
`RentnKingHostedTests` 168/168 (ChecklistBatchIsolationHostedTests 12, DispatchOfflineField-
BridgeHostedTests 16), app + extension build. Simulator UI smoke
(`ChecklistBatchIsolationUITests`, staging seed `RentnKingUITests/ChecklistBatchIsolation-
StagingSeed.php`) — Delivery and Return, Combine ON and OFF, server state checked per line:
untouched/shared-only refused; only the third line; one, two and all three lines across
partial batches; Back from Preview keeps every row; Save sends `prepare` for the entered
line only; background + cold relaunch restores the draft; the last remaining line (toggle
hidden) keeps the shared employee; per-line employees and signatures (distinct signature
media); partial line and no-unit line block and are pointed at; a return damage charge lands
only on its own line; no operation for any untouched line.

## Order-wide checklist entry (after e00c452)

**Defect (reproduced on e00c452, fresh simulator install = another phone):** Order Details
opened the completed report when *any* line of the leg was complete and this phone had no
draft; the Orders list used the order-level cached report or the first product's flag. An
order with A delivered and B/C open (or B returned and A/C open) opened the report from both
tiles, and the unfinished equipment could not be reached (`testN0…`, REPRO true/true).

**Rule (`RentnKing/Sync/Core/ChecklistLegCompletion.swift`, one evaluator for every entry):**
per order product, for the current leg and rental cycle, a line is complete when Laravel's
leg flag says so (`is_delivered` / `is_returned` — the server reopens a leg exactly when the
flag is false, so it speaks for the current cycle) **or** a durable local completion
operation exists for that product and leg that belongs to the line's current cycle (the
current execution when known; never a cycle this phone discarded by substitution/restart;
never a SYNCED completion that an order copy asked *after* Laravel acknowledged it still
reports open — the leg was reopened since). Retail lines are not eligible; Return is owed
only for delivered lines. The completed report opens only when every eligible line is
complete; otherwise the entry opens the checklist flow. Drafts, the order-level cached
report, "any line done" and the first line's flag never decide it.

Wired into: Order Details (`legOpensCompletedReport`, Return gate, mission inputs without a
focus product), the Orders list tiles, the checklist screen (`dropLinesAlreadyComplete`: only
owed lines are listed — a line completed elsewhere is never re-enrolled) and Assembly Review
(`QueueLineLocalOverlay.owingLinesReopenedOnServer`: a line this phone delivered that the
office has since reopened gets its Continue to Checklist back). Each screen records when its
order copy was asked of Laravel (`orderCopyAsOf` / `reviewAsOf` — the live request time or the
offline ledger's `observedAt`); unknown age keeps the local completion as the offline bridge.
Product-specific mission navigation is unchanged. No backend or contract change.

### Validation (2026-10-06/07, Xcode 26.5 / 17F42, iPhone 17 simulator, staging = production backend code)

| Check | Result |
|---|---|
| `python3 Scripts/test-checklist-batch-policy.py "$(xcrun --find swift)"` | 24/24 |
| `Scripts/test-sync-core.sh` | 690/690 (ChecklistLegCompletionTests 11) |
| `RentnKingHostedTests` (full scheme) | 175/175 (ChecklistBatchIsolationHostedTests 18, AssemblyReviewPresentationTests 36) |
| `RentnKing`, `RentnKinExtension` build, `RentnKingUITests` build-for-testing | succeeded, no new warnings |
| `ChecklistBatchIsolationUITests`, one pass on a fresh seed (base 9420) | 12/12: N0, N1, N2, N3a, N3b, D1, D2, D2b, D3, D4, R1, R2 |
| `PreparationLifecycleUITests` (`PreparationLifecycleStagingSeed.php`) | test02, A, B, C, E, D, H1, H2, H3 passed |

Server state was checked after every UI scenario:
- **N1:** only Charlie's completion was sent.
- **N2:** only Alpha's and Charlie's returns were sent; Bravo's earlier return stands.
- **N3a:** the photo is recorded on Bravo's line only; A, B and C were delivered in cycle 1.
- **N3b:** after the office reopened Alpha (`RentalFulfillmentService::reopenDelivery`), Alpha alone was delivered again, as cycle 2 with cycle 1 superseded. Bravo and Charlie stayed untouched.
- **D/R scenarios:** as in the earlier run, with hour-tracked units (prefilled hours on every line).

Observations and follow-ups:
- **C and H3 flaked once.** Each failed once on the first fixture and passed on a fresh one, on identical code.
  - C: after switching a STAGED line the checklist header still showed the old unit. The context reload (unit hint) reached Laravel in the same second as the switch POST, so the conflict retry returned the old assignment. This code path is unchanged from `main`.
  - H3: the reopened checklist's unit header was not exposed to XCUITest.
- **Untouched prefilled hours are not sent.** A prefilled hours value that is never edited goes out as empty, so `start_hours`/`end_hours` become null. This is identical on `main`. Production never pre-fills these on an open leg: Laravel writes them only at completion and clears them on reopen or removal. The same fixture-only prefill shows "Delete Checklist / Start Over" on an untouched line.
- **The Queue Line board's lanes** still trust a synced delivery after an office reopen, until the card's feed catches up. Assembly Review and every order-wide entry now owe the line again.
