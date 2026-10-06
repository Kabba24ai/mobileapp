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
   completed report, hiding the lines this change keeps in the draft. A leg opens the
   report only once no pending draft remains for it; the Return gate is unchanged.

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
