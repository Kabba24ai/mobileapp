# RentnKingTests — setup

These files are the starting unit-test suite (Phase 5 / A1). They are plain
`.swift` files on disk and are **not yet wired into an Xcode target**, so they
don't affect the app build until you add the target below.

## One-time setup (in Xcode)

1. **File ▸ New ▸ Target… ▸ Unit Testing Bundle.**
   - Product Name: `RentnKingTests`
   - Target to be Tested: `RentnKing`
2. Xcode creates a `RentnKingTests` group with a stub file — you can delete the stub.
3. **Add the existing test files to the target:** right-click the `RentnKingTests`
   group ▸ *Add Files to "RentnKing"…* ▸ select this folder's `.swift` files ▸
   make sure **Target membership = RentnKingTests** (and NOT the app target).
4. **Link ObjectMapper to the test target:** select the `RentnKingTests` target ▸
   *General ▸ Frameworks and Libraries ▸ +* ▸ add **ObjectMapper**.
   (`@testable import RentnKing` imports the app module, but the test target must
   link ObjectMapper itself to use `Mappable`/`Mapper`.)
5. Run with **⌘U**.

## What's covered
- `QueueLineModelTests` — Queue Line item + nested product/equipment mapping,
  empty-payload safety, completed-item detection.
- `OfflineQueueModelTests` — driver-checklist & delivery/pickup queue models,
  including the `attempts` retry counter and the `kMaxSyncAttempts` dead-letter cap.
- `PendingCheckListTests` — the Pending (prepare-before-arrival) Delivery Checklist
  store: save persists order + other data, Save does NOT set the completed marker,
  repeated Save updates in place (no duplicates), Delivery/Return isolation,
  empty/nil-input guards, and clear-on-finalization. Runs against the app test host
  (uses `SDKUserDefault`).

## Next tests to add (once the target compiles)
- `Url` endpoint building (set `UserDefaults.standard.baseURL`, assert `absoluteString`).
- `MachineModel` mapping.
- The checklist queue append / dead-letter logic (needs a small storage seam to
  make `SDKUserDefault` injectable).
