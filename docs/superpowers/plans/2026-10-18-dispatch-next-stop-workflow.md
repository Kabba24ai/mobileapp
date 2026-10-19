# Dispatch Next Stop Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the release-critical mobile Next Stop workflow so a driver completing a Delivery, Return, or Manual Dispatch can explicitly continue to another assigned mission or return to an active tenant shop without dropping out of the driver workday flow.

**Architecture:** Keep all existing Dispatch, completion, assignment, checklist, and Sync Engine rules intact. Add one small tenant-scoped durable shop-stop state, a programmatic Next Stop UI, and thin integration hooks at the three existing completion exits. Reuse the existing mixed Dispatch working set, existing mission-opening functions, the existing tenant-scoped store cache/API, and the existing Maps helper; do not build a second Dispatch source or add backend APIs.

**Tech Stack:** iOS UIKit / Swift, ObjectMapper, MMKV-backed existing reference caches, Foundation-only KabbaSyncCore, file-protected KabbaSync storage, XCTest / SwiftPM core tests, hosted XCTest, Xcode build/archive tooling.

**Spec:** `docs/superpowers/specs/2026-10-18-dispatch-next-stop-workflow-design.md`

## Global Constraints

- Phase 1 is release-critical. Driver Performance Intelligence is explicitly out of scope and must not delay this release.
- No Laravel/backend change is required: the existing authenticated `GET api/admin/v1/stores/` endpoint already returns active stores and the mobile app already caches it through `getStoreList()` / `kStoreList`.
- Preserve all existing Delivery/Return completion requirements, Driver Checklist rules, assignment locks, local-first behavior, Sync Engine operations, Needs Attention handling, Dispatch offline reconciliation, Manual Dispatch lifecycle, and tenant isolation.
- The new feature may make small call-site edits to existing completion files, but no broad refactor or unrelated UI redesign.
- Never delete, discard, rewrite, or auto-retry existing Needs Attention / pending field work as part of this feature.
- Never hard-code Bon Aqua or Waverly in shared logic. Use the existing active tenant store list and its canonical address.
- Selecting a shop must be durably persisted before Maps/navigation is launched.
- A mission selection uses the mission already owned by Dispatch; the Next Stop feature never creates or changes assignments.
- The Next Customer / Mission picker must use stable mission identities, not table indices that can become stale after reconciliation.
- Missing offline data must be described honestly; do not render an unavailable cache as an empty workday.
- New Sync/Core files are Foundation-only and must be added to both the SwiftPM/core build and the app target where required.
- TDD task by task: red test -> prove red -> minimum implementation -> focused green -> affected regression green -> commit.
- Work from the current canonical local release head. Do not reset to a stale remote head or discard unreleased work. If the canonical clone is ahead of `origin/main`, preserve that lineage.
- Expected next mobile candidate from current project context is 1.0.26 (1012), but verify current local release metadata / App Store state before reusing a version or build number. Never reuse an uploaded build number.
- No GPS/background-location tracking.
- No Phase 2 nightly analytics, performance scores, route optimizer, or UI-agent work.

## Review Focus

1. **Post-completion routing:** every valid Delivery, Return, Manual Dispatch completion enters Next Stop; no path silently falls back to the old pop-to-Dispatch behavior.
2. **Durability/offline:** shop selection is on disk before Maps opens; app background/relaunch and offline mode do not lose the selected shop.
3. **Mission truth:** the picker shows only current remaining Dispatch work and routes by stable identity; reassigned/completed work cannot be opened from stale indices.
4. **Tenant isolation/store truth:** only the signed-in tenant's active cached stores are shown; no Rent N King names/addresses are hard-coded.
5. **Non-interference:** completion gates, assignment rules, Sync Engine operations, Dispatch list behavior, Manual Dispatch state transitions, and existing cached field work remain unchanged.

---

## File Map

### New files

- `RentnKing/Sync/Core/NextStopState.swift` — pure Codable state and transition policy for a shop stop.
- `RentnKing/Sync/Core/NextStopStore.swift` — tenant-scoped protected file store under the KabbaSync root.
- `RentnKing/Sync/App/NextStopCoordinator.swift` — app-layer bootstrap/access to the store and the single routing entry point.
- `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Next Stop/NextStopViewController.swift` — “What are you doing next?” chooser, shop state/resume screen.
- `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Next Stop/NextMissionPickerViewController.swift` — programmatic list of remaining mixed Dispatch work using stable ids.
- `RentnKingTests/KabbaSyncCore/NextStopStateTests.swift` — state/transition tests.
- `RentnKingTests/KabbaSyncCore/NextStopStoreTests.swift` — persistence/tenant-isolation tests.
- `RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift` — post-completion and UIKit routing tests.

### Existing files touched narrowly

- `RentnKing/Sync/App/KabbaSync.swift` — construct/configure `NextStopStore` from the existing protected root.
- `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift` — expose stable mission lookup/open helpers and launch Next Stop over the existing mixed workload.
- `RentnKing/Modules/TABBAR/Home Model/Order Model/Order Details/OrderDetailsViewController.swift` — successful and Needs Attention completion exits route to Next Stop instead of directly ending at Dispatch.
- `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Manual Dispatch/ManualDispatchDetailViewController.swift` — Completed transition routes to Next Stop; all other status transitions remain unchanged.
- `RentnKing.xcodeproj/project.pbxproj` — add the new app/core files to the proper targets.
- Release metadata files already used by the repo for version/build and Settings > About release notes — update only after the feature is green and only after verifying the next unused version/build.

### Reused without redesign

- `RentnKing/Core/FileData Helper/EqupmentFile.swift` — existing `getStoreList()`, `getStoreListData()`, `CallAPIforStoreList()`.
- `RentnKing/Core/FileData Helper/kEnum.swift` — existing tenant-scoped `kStoreList`.
- `RentnKing/Sync/Core/DispatchOfflineWorkingSet.swift` — canonical local order mission presentation.
- `RentnKing/Sync/Core/DispatchWorkload.swift` — canonical mixed order/manual ordering.
- `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchModel.swift` — existing live/manual cache behavior.
- Existing `openAddressInMap(address:)` helper and existing mission workflows.

---

## Interfaces

### Core state

```swift
// RentnKing/Sync/Core/NextStopState.swift

struct NextStopShop: Codable, Equatable {
    let uniqueId: String
    let name: String
    let fullAddress: String
}

enum NextStopState: Codable, Equatable {
    case idle
    case shopSelected(shop: NextStopShop, selectedAt: Date)
    case arrivedAtShop(shop: NextStopShop, selectedAt: Date, arrivedAt: Date)

    var shop: NextStopShop? { get }
}

enum NextStopTransition {
    static func selectShop(_ shop: NextStopShop, at: Date) -> NextStopState
    static func arrive(_ state: NextStopState, at: Date) -> NextStopState
    static func finishShopStop(_ state: NextStopState) -> NextStopState
}
```

Rules:
- `arrive(.shopSelected)` -> `.arrivedAtShop`.
- `arrive(.idle)` and `arrive(.arrivedAtShop)` are no-ops.
- choosing a real Dispatch mission clears the shop-stop state to `.idle` immediately before routing into that mission.
- state stores device event times for future use, but Phase 1 has no analytics API.

### Durable store

```swift
// RentnKing/Sync/Core/NextStopStore.swift

enum NextStopStoreError: Error, Equatable {
    case noTenant
}

final class NextStopStore {
    init(rootDirectory: URL, tenantKey: @escaping () -> String?, fileManager: FileManager = .default) throws
    func load() -> NextStopState
    func save(_ state: NextStopState) throws
    func clear() throws
}
```

Storage:
- `<KabbaSync>/next-stop/<tenantKey>/state.json`
- protected with the same `FileSyncOperationStore.ensureProtectedDirectory` / `writeProtected` helpers as the other Sync/Core stores.
- signed out -> `load() == .idle`; writes throw `.noTenant`.
- another tenant can never read the current tenant's shop stop.

### App coordinator

```swift
// RentnKing/Sync/App/NextStopCoordinator.swift

enum NextStopCoordinator {
    static var store: NextStopStore? { get }
    static func configure(store: NextStopStore)
    static func state() -> NextStopState
    static func save(_ state: NextStopState) throws
    static func clear() throws
}
```

Keep this deliberately small. It is not a second sync engine and makes no network call.

### Stable mission handoff

Add to `DispatchListViewController`:

```swift
@discardableResult
func openOrderMission(orderProductUniqueId: String) -> Bool

@discardableResult
func openManualMission(taskUniqueId: String) -> Bool

func beginNextStopFlow()
func currentNextStopMissions() -> [NextStopMission]
```

Define app-layer UI DTO:

```swift
enum NextStopMissionIdentity: Equatable {
    case orderProduct(String)
    case manualTask(String)
}

struct NextStopMission: Equatable {
    let identity: NextStopMissionIdentity
    let kindLabel: String       // "Delivery", "Return", "Manual Dispatch"
    let primaryText: String     // customer/location/task
    let secondaryText: String   // product/order or manual description
    let sortKey: String
}
```

`currentNextStopMissions()` is derived from the Dispatch controller's already-reconciled `arrRows`, `arrDispatchList`, and rendered Manual Dispatch list. It does not refetch or build a new ordering system.

The picker stores only stable identities. On tap, it re-resolves against the controller's current arrays. If the mission disappeared because it completed/reassigned during the picker, show a short “This mission is no longer assigned here. Dispatch has been refreshed.” notice and refresh; never open a stale row index.

---

### Task 1: Preflight the current release head and record the baseline

**Files:**
- Read only at first: current local canonical clone, release metadata, `git status`, latest commits.
- Plan execution record: append a short preflight section to this plan if the implementation environment uses execution records.

- [ ] **Step 1: Inspect the canonical local repository without mutating it**

Run in the canonical mobile clone (expected `/Users/garyjezorski/Documents/mobileapp-canonical`, but use the actual active canonical clone if different):

```bash
git status --short --branch
git log --oneline -12
git remote -v
git rev-parse HEAD
git rev-parse origin/main
```

Expected: establish the real release head. Do **not** reset, stash, checkout away, or discard anything.

- [ ] **Step 2: Verify current version/build metadata**

Inspect `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, and the existing Settings > About release catalog. Record whether the working candidate is already 1.0.26 (1012) or something newer.

- [ ] **Step 3: Establish a safe implementation branch/worktree from the actual release head**

Create an isolated branch such as `feature/dispatch-next-stop-2026-10-18` from the current release head. If the canonical clone has uncommitted release work that cannot safely be represented in a worktree without guessing, this is one of the few legitimate stop conditions: report the exact files and why they block a safe branch.

- [ ] **Step 4: Run the fast baseline**

Run:
```bash
xcrun swift test
```

Then run the existing hosted Dispatch/driver-flow tests using the repository's current simulator destination/configuration. Record baseline pass counts and pre-existing failures before feature code.

- [ ] **Step 5: Commit nothing in this task unless an execution-record-only doc update is required.**

---

### Task 2: Core — durable tenant-scoped shop-stop state

**Files:**
- Create: `RentnKing/Sync/Core/NextStopState.swift`
- Create: `RentnKing/Sync/Core/NextStopStore.swift`
- Create: `RentnKingTests/KabbaSyncCore/NextStopStateTests.swift`
- Create: `RentnKingTests/KabbaSyncCore/NextStopStoreTests.swift`
- Modify: `RentnKing.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces exactly the `NextStopShop`, `NextStopState`, `NextStopTransition`, and `NextStopStore` interfaces defined above.
- No UIKit, MMKV, network, Dispatch controller, or backend dependency.

- [ ] **Step 1: Write failing state-transition tests**

Tests:
- `testSelectShopCapturesShopAndTimestamp`
- `testArrivePromotesSelectedShopAndPreservesSelectedAt`
- `testArriveFromIdleIsANoop`
- `testFinishShopStopReturnsIdle`
- Codable round-trip for all states.

- [ ] **Step 2: Run the focused tests and prove red**

```bash
xcrun swift test --filter NextStopStateTests
```

Expected: FAIL because the new types do not exist.

- [ ] **Step 3: Implement `NextStopState.swift` minimally**

Use an explicit Codable representation stable enough for future app upgrades; do not rely on compiler-synthesized enum payload keys if existing project conventions prefer explicit keys.

- [ ] **Step 4: Run state tests green**

- [ ] **Step 5: Write failing store tests**

Tests:
- save/load round trip;
- `clear()` -> `.idle`;
- Tenant A state invisible to Tenant B;
- signed-out read -> `.idle`;
- signed-out write -> `.noTenant`;
- corrupted file -> `.idle` without touching Sync Engine operations;
- the file is under `next-stop/<tenant>/state.json`.

- [ ] **Step 6: Run store tests and prove red**

```bash
xcrun swift test --filter NextStopStoreTests
```

- [ ] **Step 7: Implement `NextStopStore.swift` with protected atomic writes**

Follow `ChecklistContextStore` / `TermsAgreementStore` patterns. Keep its directory entirely separate from operations, checklist contexts, terms, and Dispatch offline packages.

- [ ] **Step 8: Run focused + full core suite green**

```bash
xcrun swift test --filter "NextStopStateTests|NextStopStoreTests"
xcrun swift test
```

- [ ] **Step 9: Commit**

```bash
git add "RentnKing/Sync/Core/NextStopState.swift" "RentnKing/Sync/Core/NextStopStore.swift" "RentnKingTests/KabbaSyncCore/NextStopStateTests.swift" "RentnKingTests/KabbaSyncCore/NextStopStoreTests.swift" RentnKing.xcodeproj/project.pbxproj
git commit -m "Add durable tenant-scoped Next Stop state"
```

---

### Task 3: App coordinator and Dispatch stable mission adapter

**Files:**
- Create: `RentnKing/Sync/App/NextStopCoordinator.swift`
- Modify: `RentnKing/Sync/App/KabbaSync.swift`
- Modify: `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift`
- Create/extend tests: `RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift`

**Interfaces:**
- Consumes Task 2 state/store.
- Produces `NextStopCoordinator`, `NextStopMissionIdentity`, `NextStopMission`, `currentNextStopMissions()`, `openOrderMission(orderProductUniqueId:)`, `openManualMission(taskUniqueId:)`.

- [ ] **Step 1: Write failing hosted tests for mixed mission projection**

Pin:
- a remaining Delivery row becomes a `NextStopMission` with stable order-product id;
- a remaining Return row does the same with kind “Return”;
- a Manual Dispatch row becomes a stable manual-task mission;
- order/manual output preserves existing `sort_key` order;
- no new completed/reassigned item is synthesized — the function projects only the controller's current reconciled mixed rows.

- [ ] **Step 2: Write failing hosted tests for stable reopen**

Pin:
- order mission opens by current `orderProductUniqueId`, even if its array index moved;
- manual mission opens by current `unique_id`;
- missing identity returns false and does not open another mission.

- [ ] **Step 3: Run the focused hosted class and prove red**

Use the repo's current hosted test command/destination.

- [ ] **Step 4: Configure the store in `KabbaSync.bootstrap`**

Create `NextStopStore(rootDirectory: root, tenantKey: { KabbaTenantScope.currentKey })` beside the other tenant-scoped stores, then `NextStopCoordinator.configure(store:)`.

No handler is added to `SyncEngine`; this state is local workflow state, not a queued server operation.

- [ ] **Step 5: Add the thin stable-identity Dispatch helpers**

Reuse:
- `arrRows`;
- `orderIndexForRow` / `manualJobForRow`;
- `openMission(at:)`;
- the existing Manual Dispatch detail construction.

Do not duplicate `DeliveryWorkflowStage` or mission routing.

- [ ] **Step 6: Run focused hosted tests green, then core suite green**

- [ ] **Step 7: Commit**

```bash
git add "RentnKing/Sync/App/NextStopCoordinator.swift" "RentnKing/Sync/App/KabbaSync.swift" "RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift" "RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift" RentnKing.xcodeproj/project.pbxproj
git commit -m "Expose the current Dispatch workday to Next Stop"
```

---

### Task 4: Next Stop UI — next mission or return to an active shop

**Files:**
- Create: `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Next Stop/NextStopViewController.swift`
- Create: `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Next Stop/NextMissionPickerViewController.swift`
- Modify: `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift`
- Extend: `RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift`
- Modify: `RentnKing.xcodeproj/project.pbxproj`

**Interfaces:**
- `DispatchListViewController.beginNextStopFlow()` pushes/presents `NextStopViewController`.
- `NextStopViewController` receives a weak Dispatch controller or closures for mission projection/opening; it does not own Dispatch truth.
- Stores come from existing `getStoreList()` and tenant-scoped cache.

- [ ] **Step 1: Write failing hosted tests for the initial screen**

Pin:
- title/copy includes “What are you doing next?”;
- exactly two primary paths: Next Customer / Mission and Return to Shop;
- opening the screen does not change any Sync Engine operation or mission assignment.

- [ ] **Step 2: Write failing tests for the mission picker**

Pin:
- Delivery, Return, and Manual Dispatch cards can render;
- tapping a stable identity calls the correct Dispatch open helper;
- successful mission selection clears any persisted shop state first;
- a mission that disappeared before tap produces the “no longer assigned” notice and refreshes instead of routing a stale index;
- empty real workday says no remaining missions;
- unavailable/not-downloaded offline source is not mislabeled as an empty workday.

- [ ] **Step 3: Write failing tests for the shop path**

Using injected store loader/map opener seams:
- cached active stores render immediately;
- the loader may refresh online without clearing the cached list first;
- the code uses each `StoreModel`'s canonical name/address from `getStoreList()`;
- selecting a store writes `.shopSelected` **before** the map opener is called;
- if Maps cannot open/geocode, state remains selected and the screen remains usable;
- on foreground/reappearance with `.shopSelected`, show “Arrived at [Store]”;
- tapping Arrived writes `.arrivedAtShop`;
- `.arrivedAtShop` shows “Choose Next Mission”;
- no cached stores while offline gives a factual “stores are not downloaded” state and still allows the Next Customer path.

- [ ] **Step 4: Run focused hosted tests and prove red**

- [ ] **Step 5: Implement the two programmatic controllers**

Match existing Dispatch visual conventions; no storyboard changes unless the existing project target tooling makes a storyboard materially simpler.

For shop data, call the existing `getStoreList()` helper. Do not add or call a new backend endpoint.

- [ ] **Step 6: Implement `beginNextStopFlow()`**

The existing Dispatch controller is the anchor under the new flow. Avoid a visible “dump back to Dispatch, then ask” sequence: pop/set the navigation stack to the existing Dispatch controller and immediately push/present Next Stop as one transition.

- [ ] **Step 7: Run focused hosted tests green, then full hosted + core tests green**

- [ ] **Step 8: Commit**

```bash
git add "RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Next Stop/NextStopViewController.swift" "RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Next Stop/NextMissionPickerViewController.swift" "RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift" "RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift" RentnKing.xcodeproj/project.pbxproj
git commit -m "Add the continuous Next Stop driver workflow"
```

---

### Task 5: Wire Delivery and Return completion into Next Stop

**Files:**
- Modify: `RentnKing/Modules/TABBAR/Home Model/Order Model/Order Details/OrderDetailsViewController.swift`
- Extend: `RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift`

**Interfaces:**
- Replaces only the current post-completion navigation destination.
- Leaves `LegCompletionEvaluator`, warning override, success overlay, and Needs Attention semantics intact.

- [ ] **Step 1: Write failing tests for successful completion**

Pin both legs:
- Delivery `decision.canProceed == true` + no Needs Attention -> existing success treatment -> Next Stop.
- Return same.
- incomplete work still opens the existing `WarningViewController` and never shows Next Stop.

- [ ] **Step 2: Write failing tests for Needs Attention**

Pin:
- `completeLegWithSyncAttention` still shows the Sync status toast;
- then it enters Next Stop instead of stopping at Dispatch;
- the parked operation remains in the Sync Engine unchanged.

- [ ] **Step 3: Run focused tests and prove red**

- [ ] **Step 4: Replace only the final routing helpers**

Factor a small helper such as:

```swift
private func continueToNextStop()
```

It locates the existing `DispatchListViewController` in the navigation stack and asks it to `beginNextStopFlow()`.

Do not alter completion evaluation or checklist state.

- [ ] **Step 5: Run focused tests green; run existing DriverDeliveryFlowHostedTests and core completion evaluator tests**

- [ ] **Step 6: Commit**

```bash
git add "RentnKing/Modules/TABBAR/Home Model/Order Model/Order Details/OrderDetailsViewController.swift" "RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift"
git commit -m "Continue completed Delivery and Return work into Next Stop"
```

---

### Task 6: Wire Manual Dispatch completion into Next Stop

**Files:**
- Modify: `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Manual Dispatch/ManualDispatchDetailViewController.swift`
- Modify narrowly: `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift`
- Extend: `RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift`

**Interfaces:**
- Preserve `ManualDispatchSyncHandler.enqueue` and status lifecycle.
- Only `Completed` changes the post-enqueue navigation.

- [ ] **Step 1: Write failing tests**

Pin:
- Assigned -> On My Way unchanged;
- On My Way -> Arrived unchanged;
- Arrived -> Completed durably enqueues the existing `manual_dispatch.update_status` Completed operation and then opens Next Stop;
- Cancelled does not open Next Stop;
- a durable enqueue failure still shows the existing error and does not falsely advance.

- [ ] **Step 2: Run focused tests and prove red**

- [ ] **Step 3: Add one completion callback / route**

The Dispatch list sets the detail's completion callback to refresh current work and start Next Stop. Do not introduce a second manual-dispatch status writer.

- [ ] **Step 4: Run focused tests green; run existing Manual Dispatch / Dispatch workload regressions**

- [ ] **Step 5: Commit**

```bash
git add "RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Manual Dispatch/ManualDispatchDetailViewController.swift" "RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift" "RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift"
git commit -m "Continue completed Manual Dispatch work into Next Stop"
```

---

### Task 7: Offline, relaunch, reassignment, and non-interference regression

**Files:**
- Primarily tests; implementation files only if a test exposes a defect.
- Extend: `RentnKingTests/KabbaSyncCore/NextStopStoreTests.swift`
- Extend: `RentnKingTests/Hosted/NextStopWorkflowHostedTests.swift`

- [ ] **Step 1: Add the release-critical regression cases**

Pin:
- shop selected online -> app object recreated -> selected shop reloads;
- shop selected offline -> state persists; Maps failure never clears it;
- another tenant -> state invisible;
- mission row moves after Dispatch rebuild -> stable identity still opens correct mission;
- mission reassigned away while picker open -> tap refuses and refreshes;
- completed-on-phone mission already filtered from working set does not reappear;
- existing Needs Attention count/operations unchanged by Next Stop;
- existing Dispatch filter/list code outside the post-completion flow renders as before;
- Return gets no Delivery-only Assembly/Fuel/Keys change;
- Manual Dispatch cancellation unchanged.

- [ ] **Step 2: Break-a-rule probes**

Temporarily invert and prove tests fail for:
- clearing shop state before write/map order;
- opening by stale index instead of stable identity;
- omitting tenant isolation;
- old successful completion pop-to-Dispatch;
- Completed Manual Dispatch old pop behavior.

Restore each change.

- [ ] **Step 3: Run the full core suite**

```bash
xcrun swift test
```

- [ ] **Step 4: Run the full hosted suite**

Use the current repository destination. Zero new failures/skips.

- [ ] **Step 5: Run simulator build**

```bash
xcodebuild build -project RentnKing.xcodeproj -scheme RentnKing -destination '<current simulator destination>' CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 6: Whole-diff review**

Review only for the five Review Focus categories. Fix Critical/Important findings before release prep.

- [ ] **Step 7: Commit any review-only fixes**

Message: `Next Stop workflow: release review fixes`.

---

### Task 8: Release preparation and fastest safe launch path

**Files:**
- Existing Xcode version/build settings.
- Existing Settings > About release catalog / release notes.
- Release record if the repository has one for the current mobile release.

- [ ] **Step 1: Confirm the next unused version/build**

Expected from current project context: **1.0.26 (1012)**. Verify against the canonical local project and App Store Connect if accessible.

Rules:
- if 1.0.26 (1012) is already the in-progress not-yet-uploaded candidate, keep it and include Next Stop in that candidate;
- if 1012 has already been uploaded, use the next valid build/version according to current release policy;
- never downgrade or overwrite a newer local release state.

- [ ] **Step 2: Add concise release notes**

Include:
- Continuous Next Stop after Delivery/Return/Manual Dispatch.
- Choose next customer/mission or return to an active shop.
- Shop choice survives app/background/offline state.
- No Driver Performance report in this release.

Preserve any existing unreleased release-note entries (for example DEF work) already in the candidate.

- [ ] **Step 3: Run final verification after the version/build change**

Core, hosted, simulator Release build; then archive validation using the same signing/export flow used for the last successful submission.

- [ ] **Step 4: Commit the release metadata**

Message in repo style, e.g. `Release 1.0.26 (1012)` only if that is the verified candidate.

- [ ] **Step 5: Push the feature/release branch and open/update the PR**

No intermediate approval is required for branch push or PR preparation.

- [ ] **Step 6: Final independent review**

Fresh whole-branch review against this spec and plan. Fix Critical/Important findings, rerun affected tests, and push.

- [ ] **Step 7: Proceed as far through release as the environment and safety gate allow**

If repository policy permits, merge the mobile branch after green review. Then archive/export/validate/upload the iOS build using the established release process.

Do **not** touch Laravel production for this feature.

If App Store submission itself requires a human confirmation in the execution environment, stop only at that final confirmation with:
- exact branch/commit;
- version/build;
- test/build/archive/validation results;
- upload state;
- the single remaining action.

Otherwise, complete the established upload/submission flow and report the App Store Connect result.

---

## Self-Review Result

- **Spec coverage:** Phase 1 acceptance criteria are covered by Tasks 2–8. Phase 2 analytics is explicitly separated and does not enter the release path.
- **Type consistency:** state/store/coordinator and stable mission identities are defined once above and consumed by later tasks.
- **Review focus coverage:** each of the five listed failure classes has at least one explicit test in Tasks 4–7.
- **Scope:** no backend work, no GPS, no performance report, no shop load/unload wizard.
- **Release risk:** the only broad risk is building from a stale remote head; Task 1 explicitly preserves the canonical local unreleased lineage and forbids reset/discard.
