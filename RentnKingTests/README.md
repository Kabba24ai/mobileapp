# RentnKingTests

Two kinds of tests live here.

## 1. `KabbaSyncCore/` — Sync Engine core tests (EXECUTABLE today)

Unit tests for the offline Sync Engine core (`RentnKing/Sync/Core`, Foundation-only):
HTTP status classification, the canonical/legacy envelope parser, response
interpretation, the durable file store (save/relaunch/quarantine), operation-id
stability across retries, retry vs needs-attention dispositions, the 401 pause,
FIFO ordering, discard/prune, diagnostics sanitisation, and the installation id.

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
need an Xcode **Unit Testing Bundle** target with the app as host. That target is
**not yet in `project.pbxproj`** (it must be created in Xcode — see below); until
then these three files are not compiled or executed.

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
- `OfflineQueueModelTests` — the LEGACY driver-checklist & delivery/pickup queue
  models, including the `attempts` counter and the `kMaxSyncAttempts` cap that now
  applies only to the delivery/pickup-inputs fallback queue (the driver checklist
  moved to the Sync Engine in Phase 2).
- `PendingCheckListTests` — the Pending (prepare-before-arrival) Delivery Checklist
  store. Runs against the app test host (uses `SDKUserDefault`).

## Next tests to add
- `DriverChecklistSyncHandler` request building (needs the app host or a small
  Foundation-only test once the handler's payload shaping is asserted end-to-end).
- Migration of `SyncDeliveryPickupInputs` and the customer checklist queue onto the
  Sync Engine (Phase 3+), with the same offline/relaunch/replay/rejection scenarios.
