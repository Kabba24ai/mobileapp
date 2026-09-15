# RentnKingTests

Two kinds of tests live here.

## 1. `KabbaSyncCore/` — Sync Engine core tests (EXECUTABLE today)

Unit tests for the offline Sync Engine core (`RentnKing/Sync/Core`, Foundation-only):
HTTP status classification, the canonical/legacy envelope parser, response
interpretation, the durable file store (save/relaunch/quarantine), operation-id
stability across retries, retry vs needs-attention dispositions, the 401 pause,
FIFO ordering, discard/prune, diagnostics sanitisation, and the installation id.

Phase 3 adds the canonical checklist contract: `ChecklistContractTests` decodes
the SHARED fixtures (`Fixtures/*.json`, copied from the Laravel repo by
`Scripts/sync-contract-fixtures.sh` — the same files Laravel's
`MobileContractFixturesTest` asserts the API produces); `ChecklistOperationTests`
covers one-operation-per-product, signature assets, multipart bracket fields,
prepare, replay convergence and assignment conflicts; `LegacyChecklistMigrationTests`
covers the legacy-queue conversion, quarantine reporting and the context cache.

Phase 4 adds Queue Line item-level orchestration and media / driver's-license
offline sync: `QueueLineOperationTests` (the durable `queue_line.mark_staged`
command — payload/identity, request, offline → relaunch → reconnect, replay,
409 conflict → Needs Attention, multi-line isolation, board overlay + freshness
line), `MediaOperationTests` (protected file import with a stable
`client_media_id`, multipart background-transfer request, offline/relaunch,
lost-response replay, rejection keeps the file, cleanup ONLY after
acknowledgment, discard), `ExternalTransferTests` (engine ↔ background
URLSession hand-off: hold, complete, release), `LegacyMediaMigrationTests`
(pure conversion of the legacy Core Data upload queue) and
`Phase4ContractTests` (decodes the six Phase 4 shared fixtures:
`queue_line_board_item`, `queue_line_mark_staged_success`,
`queue_line_mark_staged_conflict`, `media_upload_success`,
`media_upload_idempotent_replay`, `media_client_id_conflict`).

Run them from the repo root:

```sh
Scripts/test-sync-core.sh
```

- With the Xcode license accepted this is `swift test` against `Package.swift`
  (target `KabbaSyncCore`, test target `KabbaSyncCoreTests`).
- Without it (`xcodebuild`/`xcrun` blocked), the script compiles the same sources
  into an `.xctest` bundle with the Xcode toolchain's `swiftc` and runs it with
  `xctest`. Same tests, same assertions.

The tests use only the core module plus `FakeSyncHTTPClient` (`TestSupport.swift`),
so they need no simulator, no app host and no third-party package.

## 2. App-host tests (`OfflineQueueModelTests`, `PendingCheckListTests`, `QueueLineModelTests`)

These import the app module (`@testable import RentnKing`) and ObjectMapper, so they
need an Xcode **Unit Testing Bundle** target with the app as host. Since Phase 6A the
project has such a target — **RentnKingHostedTests** (`Hosted/`, see §"Hosted tests"
below) — but these three files are NOT members of it yet (they also need ObjectMapper
linked to the test target); until they are added in Xcode they are not compiled or
executed.

### One-time setup (in Xcode)

1. **File ▸ New ▸ Target… ▸ Unit Testing Bundle.**
   - Product Name: `RentnKingTests`
   - Target to be Tested: `RentnKing`
2. Xcode creates a `RentnKingTests` group with a stub file — you can delete the stub.
3. **Add the existing test files to the target:** right-click the `RentnKingTests`
   group ▸ *Add Files to "RentnKing"…* ▸ select the `.swift` files in this folder
   (including `KabbaSyncCore/`, which also runs fine inside the app host) ▸ make sure
   **Target membership = RentnKingTests** (and NOT the app target).
4. **Link ObjectMapper to the test target:** select the `RentnKingTests` target ▸
   *General ▸ Frameworks and Libraries ▸ +* ▸ add **ObjectMapper**.
5. Run with **⌘U**.

## What's covered by the app-host files
- `QueueLineModelTests` — Queue Line item + nested product/equipment mapping,
  empty-payload safety, completed-item detection.
- `QueueLinePresentationTests` (target **RentnKingHostedTests**, runs inside the app on a
  Simulator/device) — Queue Line board presentation: Truck → `icon_delivery_pending` +
  "Delivery", Store → `icon_store` + "In Store" from ONE rule (icon and label can never
  disagree; both assets resolve in the app bundle), and the card's single Update button
  (solid at rest → hollow + disabled the instant it is tapped; highlight never undoes
  that; reset restores solid). The rapid double-tap → ONE checklist push is covered by
  `PreparationLifecycleUITests/testQueueLineBoardPresentation`.
- `QueueLineFilterTests` (target **RentnKingHostedTests**) — Queue Line filters: Type uses the
  card-icon predicate, Store AND Type, the active-filter line and empty-scope wording, the
  remembered Delivery Store resolving against the live store list (missing → All, forgotten;
  unknown list → kept and named from the feed/memory), same-name stores told apart by id, and
  the UserDefaults round trip where All is an explicit remembered choice. The sheet, the sticky
  store across reopen/relaunch and the stale-store fallback are covered end to end by
  `PreparationLifecycleUITests/testQueueLineFilters` and `…/testARememberedStoreThatNoLongerExistsFallsBackToAll`.
- `AssemblyReviewPresentationTests` (target **RentnKingHostedTests**) — the Assembly Review
  screen rendered from the shared `queue_line_assembly` fixture (dependent-assembly model,
  2026-09-14): every frozen Product Option by its stored label (including "No Bucket"), the ONE
  affirmative control (red X + hollow Available → green check + filled Available, no Not
  Available button), the derived STOP/GO badge, Continue hollow-and-inactive at STOP and
  filled at GO, the removed redundancies (no unit-status badge, item-availability summary,
  checklist line, blocker paragraph, customer header, instructions, Unbundle), focus on the
  tapped entity, and the board's one-card-per-entity grouping in the least-advanced lane
  (`QueueLineBoardAssembly`; independent same-order lines stay separate). End to end on
  staging: `PreparationLifecycleUITests/testDependentAssemblyIsStopUntilEveryRequirementIsConfirmedThenGo`,
  `…/testIndependentLineProceedsAndItsFocusedSaveStagesOnlyItself`,
  `…/testNoBucketIsConfirmedLikeAnyOptionAndAnUnassignedDependentMemberHoldsStop` and
  `…/testBundleFocusedSaveThenReversalUnstagesAndConfirmingNeverRestages`
  (seed: scratchpad `seed_assembly.php` with persisted related/bundle edges, line ids via
  `TEST_RUNNER_KABBA_QLA_*`). `openCard` now passes through the review (confirm all → Continue).
  **Universal entry (2026-09-14)** — the same file also pins `ChecklistEntry`, the ONE helper every
  entry point uses: Queue Line card, Orders list and Order Details all open Assembly Review first
  (a second tap for the same order pushes nothing), the review builds the focused Delivery
  Checklist for every origin (only the origin flags differ), Save / finalization Submit / media
  upload return to the review FIRST and the origin stays beneath it, and an In Transit member
  still offers Continue (the driver completes the same checklist at the customer) while delivered
  equipment does not. End to end on staging:
  `PreparationLifecycleUITests/testOrderDetailsEntersTheDeliveryChecklistThroughAssemblyReviewAndReturnsToOrderDetails`
  (order 9305, one line, no options: STOP → GO → checklist → Save → review → Order Details) and
  `…/testTheOrdersListEntersThroughAssemblyReviewShowingEachEntityOfTheOrderAndReturnsToTheList`
  (order 9301 unfocused: two entities, two gates, back to the list). The Return leg is inbound and
  keeps its direct path; a completed checklist's record view (`CheckListUpdateViewController`,
  `isUpdateData`) is not a checklist entry and is untouched.
  **Assignment from the review (2026-09-14)** — the machine reads "Name · #TAG" (never the tag alone)
  and the identity is the affordance for changing it; an unassigned member shows "No equipment
  selected" + **Assign** and no Available control; In Transit / delivered members are not
  reassignable. Both Assign and the identity tap run `EquipmentAssignmentFlow` — the checklist's
  own picker (status sections, "Select Equipment ID", Cancel / Select), status triage, "start over"
  confirmation and Laravel's reason picklist, ending in the ONE canonical `queue_line.switch_equipment`
  operation — so there is exactly one selector and one service (`EquipmentReassignmentService`, first
  assignment and reassignment alike). `AssemblyReviewTests` (KabbaSyncCore) pins the local rules: a
  switch recorded on this phone shows the replacement by name and tag before the feed catches up
  (`QueueLineLocalOverlay.pendingEquipment`), a unit decision is keyed by the unit it named so the old
  machine's Available never carries onto the replacement, assignment alone leaves STOP, a rejected
  switch changes nothing. `PreparationLifecycleTests` pins `EquipmentIdentity`, `EquipmentPickTriage`
  and the informational identity on the switch payload. On staging:
  `PreparationLifecycleUITests/testUnassignedMemberIsAssignedFromTheReviewThenReassignedAndEachNewUnitStartsUnconfirmed`
  (9303: Assign → direct spare, no reason; identity tap → non-direct spare, reason sheet; option
  confirmations stand; board reads the new unit) and
  `…/testVReassigningInsideTheChecklistReturnsTheReviewToStopWithTheNewUnit` (9302: GO → checklist →
  the checklist's substitution → the review shows the new unit unconfirmed, STOP · 1 of 2).
  **Known automation-only limitation (not a product defect, 2026-09-15)** — in the OLDER
  checklist-driven-staging suite, `testB_partialThenSubstitute` fails identically on the simulator
  and on the physical phone: after the answer picker / hours keyboard has been used, the checklist
  product header cell is exposed to the XCUITest harness as ONE opaque element (identifier
  "Mini Excavator * 1"), so the harness cannot read the "<name>    ||    <code>" Equipment ID row
  even though the screen renders and works correctly. C, D, E, F1–F3 cascade from B (they assume
  B's substitution happened). `testR2_outOfBandReassignment` fails at its board-card precondition
  ("#EXC-A under Staged") in every environment although the server state after the raw swap is
  verified correct via tinker; the cause is not isolated. Checklist accessibility was deliberately
  NOT redesigned to satisfy the harness. Passing in the same suite: 02, A, G, H1–H3, board
  presentation, filters, remembered-store fallback, substitution reason.
- `AssemblyReviewTests` (KabbaSyncCore) — the Assembly Review contract decode (a dependent
  assembly derived from a persisted related-product edge, the gate, the dependency block), the
  ONE durable operation `queue_line.availability` (payload / identity / request / FIFO with the
  line's own checklist ops; a reversal is the same operation with `not_available`), the local
  overlay (latest confirmation wins, a reversal demotes a Staged member until a later Save,
  Delivered / In Transit never demoted), and the pure policy: least-advanced aggregation,
  effective availability, the derived STOP/GO gate over every member, refusal wording.
- `PreparationLifecycleTests` (KabbaSyncCore) also covers the switch **reason** policy — required
  unless the replacement's assigned product IS the ordered product, Laravel's picklist — and the
  attribution rule (the checklist's employee before the login account); the on-device reason
  sheet is exercised by `…/testASubstitutionAsksForAReasonWhenTheUnitIsNotADirectMatch`.
- `OfflineQueueModelTests` — the LEGACY driver-checklist & delivery/pickup queue
  models, including the `attempts` counter and the `kMaxSyncAttempts` cap that now
  applies only to the delivery/pickup-inputs fallback queue (the driver checklist
  moved to the Sync Engine in Phase 2).
- `PendingCheckListTests` — the Pending (prepare-before-arrival) Delivery Checklist
  store. Runs against the app test host (uses `SDKUserDefault`).

## Running through Xcode (Phase 6A)
`RentnKing.xcodeproj` now has a real unit-test bundle target, **KabbaSyncCoreTests** (shared
scheme of the same name): a logic-test bundle that compiles `RentnKing/Sync/Core/*.swift`
together with every file in this directory and copies `Fixtures/*.json` into the bundle root.
No app host is needed.

    xcodebuild test -project RentnKing.xcodeproj -scheme KabbaSyncCoreTests \
        -destination 'platform=iOS Simulator,name=iPhone 15'

`Scripts/test-sync-core.sh` (direct swiftc + xctest runner) keeps working as before; both
paths run the same sources and assertions. The Xcode target was added by script and has not
yet been executed on this Mac (Xcode license not accepted) — the first `xcodebuild test`
run is part of the Phase 6A operator checklist.

## Hosted tests — `RentnKingHostedTests` (Phase 6A)
A second unit-test bundle target, **hosted by the app** (`TEST_HOST = RentnKing.app`, shared scheme
`RentnKingHostedTests`; also a Testable of the `RentnKing` scheme, so ⌘U runs both bundles). It runs
inside the signed app, on the Simulator or a real iPhone, with the app's real entitlements — which is
the only way to exercise the Keychain access group for real:

    xcodebuild test -project RentnKing.xcodeproj -scheme RentnKingHostedTests \
        -destination 'id=<iPhone UDID>' -allowProvisioningUpdates      # phone must be unlocked
    xcodebuild test -project RentnKing.xcodeproj -scheme RentnKingHostedTests \
        -destination 'platform=iOS Simulator,name=iPhone 17'

`Hosted/KabbaSessionKeychainDeviceTests` — the Security framework's own semantics on the device
(the app group is usable as a keychain access group under the signed entitlements; an
access-group-less `SecItemDelete` reaches the shared-group item) and the App-layer adapter end to
end (write → immediate read-back, one copy in the shared group, rewrite, remove, the `KeychainStatus`
constants match `errSec*`). Uses throwaway probe keys only, never the token key. On an environment
whose app group is not a keychain group the group-specific cases are skipped and the app-private
fallback is what gets proven.

The policy those tests exercise — delete every copy (unqualified) BEFORE the shared write, duplicate
→ update in place, entitlement failure → app-private fallback, read-back after every write,
sanitized diagnostics — is unit-tested without a device in `SharedKeychainCredentialStoreTests`
against a fake backend that models Apple's access-group semantics (an unqualified query spans all
reachable groups). That file also replays the Phase 5 ordering to show it erases the token it just
wrote — the Phase 6A device blocker.

## Phase 5 — authentication lifecycle + version enforcement
`SessionStateTests` (session record from the login response, offline rule, protected persistence,
one-time credential migration into the shared Keychain — pure logic over `SessionCredentialStore`),
`ReleasePolicyTests` (426 / `app/release` / login `release` decoding, `X-Mobile-Update` header advice,
`BuildNumber`, the persisted Update Required verdict surviving relaunch and clearing on a compatible
build), `AuthRecoveryTests` (401 pauses the engine and keeps every operation and file, re-login resumes
the SAME operation ids; relaunch without a session; 426 pauses incompatible sync and `appUpdated()`
resumes; a persisted verdict pauses before the first drain; logout keeps the queue),
`DeprecatedEndpointGuardTests` (the engine parks any migrated workflow that targets a retired route,
only the legacy-queue adapter may; structural scan that no Sync source names a retired route literal
and that the `oldAPI` URL family is gone from the client), `Phase5ContractTests` (shared fixtures
`auth_login_success`, `auth_unauthenticated_expired`, `app_update_required`, `route_retired`,
`app_release_no_policy`). The Keychain access group is exercised on device by `RentnKingHostedTests`
(above); the share extension's request headers are exercised on device, not here.

## Next tests to add
- `DriverChecklistSyncHandler` request building (needs the app host or a small
  Foundation-only test once the handler's payload shaping is asserted end-to-end).
- Migration of `SyncDeliveryPickupInputs` and the customer checklist queue onto the
  Sync Engine (Phase 3+), with the same offline/relaunch/replay/rejection scenarios.
