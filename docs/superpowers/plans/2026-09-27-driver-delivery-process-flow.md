# Driver Delivery Process Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status: PLAN ONLY (2026-09-27). Not started. Do not begin Task 1 until Gary approves this plan.**
> Rules for execution: TDD task by task (failing test → prove the failure → minimum code → focused and regression tests → review the diff → local commit). Local only: no push, merge, deploy, publish, SSH, production data or contact, Dispatch Offline wake flag, production Terms audit, version/build bump, archive, App Store Connect upload, or Firebase production change. Neither `main` is touched. Laravel `main` auto-deploys production.

**Goal:** make the driver's Delivery workflow follow one canonical, resumable process — `Dispatch → Start Delivery → Equipment Assembly Review → Continue to Driver Checklist → Driver Checklist → Load Map & Go → On My Way → Arrived → Main Order → License / Terms / Equipment Checklist / Video → Complete Delivery` — with an explicit, default-free departure gate (assembly GO, call outcome, Fuel = Full, Keys = With Machine, each only where the unit requires it), a release-critical **departure lock** on the equipment assignment from effective On My Way through Arrived that every assignment writer honors, Review Assembly reachable for the whole active Delivery (operational before departure, read-only after), and customer-site routing that never returns the driver to the yard gate. No new workflow store; every existing offline mechanism preserved.

**Spec:** `docs/superpowers/specs/2026-09-27-driver-delivery-process-flow-design.md` (amended; decisions D1–D12 locked in §18). Section numbers below refer to it.

**Architecture (one paragraph):** the phone derives one pure `DeliveryWorkflowStage` from the durable stores it already has (leg completion, `DriverStageOverlay`, the cached Assembly Review + overlays, the v2 mini-checklist record) and routes every surface by it; the departure lock is `stage >= .onMyWay` on the phone and `DeliveryDepartureLock::isDeparted()` on the server (driver status ∈ {On My Way, Arrived} ∨ `delivery_is_arrived`), enforced by one shared guard that every assignment writer calls and one shared recall helper that every trip-recall path calls; machine-specific Driver Checklist answers (fuel, keys) carry the unit's identity on the phone and in the existing `dispatch_checklist` JSON on the server, so a replaced unit always starts unanswered on any phone; the Assembly Review screen gains a driver origin; the customer-site screens route through one pure router with Main Order as the hub and one delivery-video policy.

**Tech stack:** Laravel 11 (PHP 8.3, PHPUnit feature tests, MySQL test DB `rc_kabba_testing`); iOS UIKit app `RentnKing` (Swift, ObjectMapper models, storyboards) with the Foundation-only `KabbaSyncCore` SwiftPM target (`RentnKing/Sync/Core`, tests in `RentnKingTests/KabbaSyncCore` via `swift test`) and the hosted XCTest target `RentnKingHostedTests` (Simulator, `xcodebuild test`); shared contract fixtures under `tests/Fixtures/mobile-contract` (Laravel) synced to `RentnKingTests/KabbaSyncCore/Fixtures` by `Scripts/sync-contract-fixtures.sh`.

**Worktrees and starting heads (verified 2026-09-27):**
- Mobile: `/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6`, branch `feature/dispatch-offline-phase-6`, no upstream, product head `0278048` (docs head `a341168` + this plan).
- Backend: `/Users/garyjezorski/Documents/kabba2_AI-dispatch-offline`, branch `feature/dispatch-offline-phase-6`, no upstream, head `27cc10ed9`.

**Baseline to record in Task 0 (Phase 6 preflight, 2026-09-27):** backend Dispatch 599, Api 221, Mobile 15, Unit/Push 6, QueueLine 293, Terms 82, CustomerPortal 24 passing; Orders 23 and CustomerChecklists 11 failing by the same names as `docs/dispatch-offline-phase-6/baseline-known-failures.txt`; manifest 438/450 statements. Mobile core 546/546 (`swift test`), signed hosted 83/83, simulator build OK.

---

## Global constraints

- **TDD.** Every task starts with a red test that names the rule, proves it fails on the current head, then the minimum code, then the focused run, then the affected regression run, then a local commit. No task commits with a red focused test.
- **One backend test process at a time** (`rc_kabba_testing` is shared; two `migrate:fresh` look like a hang). Run directories one by one with `PHP_INI_SCAN_DIR=":/Users/garyjezorski/.config/kabba-php-ini"`.
- **No new workflow store.** New persisted data is limited to `equipmentUniqueId` in the v2 mini-checklist record (phone) and `equipment_unique_id` inside `dispatch_checklist.driver.<leg>` (server). No migration.
- **Preserve:** the Sync Engine and its per-order-product FIFO; the mission cache and bridge; local-first On My Way/Arrived; the checklist execution/cycle model and its supersede rules; Terms; the Queue Line preparation behavior (yard road, staging Save, board lanes, Arrived latch, Fast Track); Return behavior except §13's shared changes; finalized-checklist immutability.
- **Do not refactor** the web assignment writers into one service, the Queue Line board, Fast Track, Terms, the broader scheduling architecture, or the legacy checklist storage (S4/S5 markers). Only the lock is shared.
- **Contract changes are additive and current-version-only** (D5). No legacy-client shims.
- **New Swift files** under `RentnKing/Sync/Core` are compiled by both the SwiftPM target (path-based) and the app target: add each to the `RentnKing` target in `RentnKing.xcodeproj/project.pbxproj` (Xcode → File Inspector, or by editing the pbxproj as Phases 3–5 did). Core files import Foundation only. New test files go to `RentnKingTests` (core) or `RentnKingHostedTests` (hosted) targets.
- **Commits:** one commit per task, message in the repo's style (imperative subject; body says what rule the commit enforces and how it was verified), ending with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Stage by file name. Never stage `.DS_Store`, `vendor/`, `node_modules/`, media or `.env`.

## Review focus (for every task's diff review and the closing review)

1. **Assignment lock consistency** — can any path still change the assignment while On My Way or Arrived? Does every writer in the inventory call the guard? Is the guard's predicate free of `hasBeenDelivered()` / `isInTransitForDelivery()`?
2. **Fuel** — does any path pass with `Not Full` or unanswered?
3. **Keys** — any silent default or bypass?
4. **Equipment identity** — can any phone restore old Fuel/Keys against a replacement unit (local or server copy)?
5. **Offline FIFO** — can the server lock reject a legitimate `switch → availability → On My Way` drain? Does a parked op block the departure?
6. **Review Assembly** — reachable in every active state; operational only before departure; read-only On My Way / Arrived?
7. **Resume** — does any stage ≥ On My Way route to the yard gate?
8. **Customer-site routing** — does any exit return Checklist/Video to Assembly Review after departure?
9. **Return** — did a Delivery-only rule (assembly, fuel, keys, lock, Review Assembly) leak into Return?
10. **Scope** — any unrelated refactor?

---

## File map

### Backend — new files
| File | Purpose |
|---|---|
| `app/Services/Orders/DeliveryDepartureLock.php` | the shared predicate, guard and recall helper (§3.4.2–§3.4.4) |
| `app/Services/Orders/DeliveryDepartureLockedException.php` | `extends QueueLineOperationException`, code `DELIVERY_DEPARTED` |
| `tests/Feature/Orders/DeliveryDepartureLockTest.php` | predicate, every writer at On My Way and Arrived, completion of the locked unit, recalls, offline ordering |
| `tests/Feature/Orders/DeliveryDepartureLockWriterInventoryTest.php` | pins the set of soft-assign writer files |

### Backend — existing files touched
| File | Change |
|---|---|
| `app/Services/Checklists/ChecklistPreparationReset.php` | `assertResettable` calls the guard (replaces the `isInTransitForDelivery()` branch) |
| `app/Services/QueueLine/QueueLineAvailabilityService.php` | `assertAcknowledgeable` calls the guard (replaces its in-transit branch) |
| `app/Http/Controllers/Api/Admin/V1/QueueLine/Concerns/RespondsWithQueueLineEnvelope.php` | `DELIVERY_DEPARTED` → 409 + corrective action |
| `app/Http/Controllers/Admin/OrderManagement/Schedules/AssignEquipmentController.php` | guard before the transaction and on the locked re-read; 409 JSON |
| `app/Http/Controllers/Admin/OrderManagement/Orders/AssignEquipmentController.php` | guard at the top when the chosen unit differs from the live assignment; 409 JSON |
| `app/Services/Orders/RentalFulfillmentService.php` | `assertEquipmentChangeAllowed` calls the guard; `completeDelivery` refuses an explicit non-current unit when departed; `reopenDelivery` uses `recallFields()` |
| `app/Services/AutoAssignDirectService.php` | `doAssign` skips a departed line |
| `app/Http/Controllers/Admin/OrderManagement/Orders/UpdateProductScheduleController.php` | Reschedule branch applies `recallFields()` before clearing the assignment |
| `app/Listeners/QueueLine/SyncOnScheduleUpdate.php` | `resetDeliveryTripState` uses `recallFields()` |
| `app/Http/Controllers/Api/Admin/V1/Orders/CustomerChecklists/RemoveController.php` | uses `recallFields()` |
| `app/Http/Controllers/Admin/OrderManagement/Dispatch/ReorderController.php` | uses `recallFields()` (same On My Way-only condition) |
| `app/Http/Requests/Api/Admin/V1/Orders/Schedules/DriverChecklistRequest.php` | `equipment_unique_id` rule |
| `app/Http/Controllers/Api/Admin/V1/Orders/Schedules/DriverChecklistController.php` | stores `equipment_unique_id` beside `checks` |
| `app/Http/Resources/Api/Admin/V1/OrderProducts/DispatchRowFields.php` | `equipment_unique_id` in both checklist blocks |
| `app/Http/Resources/Api/Admin/V1/Equipment/ListResource.php` | `requires_fuel_check`, `requires_key_check` in `dispatchCardFields` |
| `app/Services/Dispatch/Offline/DispatchOfflineMissionSerializer.php` | the same two fields in `dispatch.equipment` |
| `docs/mobile-integration/MOBILE_API_CONTRACT.md` | driver-checklist and dispatch equipment additions; `DELIVERY_DEPARTED` |
| `tests/Fixtures/mobile-contract/dispatch_list_mixed.json`, `dispatch_offline_packages.json` | regenerated |
| `tests/Feature/Api/Mobile/QueueLine/ChecklistPreparationResetTest.php`, `tests/Feature/QueueLine/QueueLineAvailabilityTest.php`, `tests/Feature/Api/Mobile/Checklists/DriverChecklistPartialStateTest.php`, `tests/Feature/Dispatch/Mobile/DispatchOfflineRowParityTest.php`, `tests/Feature/Dispatch/Mobile/DispatchContractFixturesTest.php`, `tests/Feature/Orders/OrderDetailsEquipmentReassignmentTest.php`, `tests/Feature/Orders/EquipmentLockAndReopenTest.php` | extended |

### Mobile — new files
| File | Purpose |
|---|---|
| `RentnKing/Sync/Core/DeliveryWorkflowStage.swift` | `DeliveryWorkflowStage`, `DeliveryWorkflowInputs`, `DeliveryWorkflowRouting`, the evidence rule (§3.3) |
| `RentnKing/Sync/Core/DriverChecklistGate.swift` | the departure gate (§7.2) and the fuel/keys "applies" predicates |
| `RentnKing/Sync/Core/CustomerSiteRouter.swift` | §10.1 |
| `RentnKing/Sync/Core/MediaRequirementPolicy.swift` | §10.3 |
| `RentnKing/Sync/Core/LoadMapAndGoDecision.swift` | §8 outcomes and the Service Offline wording |
| `RentnKingTests/KabbaSyncCore/DeliveryWorkflowStageTests.swift`, `DriverChecklistGateTests.swift`, `CustomerSiteRouterTests.swift`, `MediaRequirementPolicyTests.swift`, `LoadMapAndGoDecisionTests.swift` | core tests |
| `RentnKingTests/Hosted/DriverDeliveryFlowHostedTests.swift` | Dispatch routing, Driver Checklist, Order Details, checklist exits, Return band |

### Mobile — existing files touched
| File | Change |
|---|---|
| `RentnKing/Sync/Core/DriverChecklistLocalState.swift` | `equipmentUniqueId`; unit-checked restore; `DriverChecklistRouting` retired |
| `RentnKing/Sync/Core/EffectiveFieldState.swift` | `DriverStageServerState` arrived requires both flags (§3.3.2) |
| `RentnKing/Sync/Core/PreparationLifecycle.swift` | `block(for:tripStage:)`, `mayRestartChecklist(_:hasLocalAnswers:tripStage:)`; `EquipmentCandidate` from the warmed list |
| `RentnKing/Sync/Core/AssemblyReview.swift` | `AssemblyPolicy.driverReadOnly(stage:memberStage:)`; gate helper for one member |
| `RentnKing/Sync/Core/LegCompletionRequirements.swift` | `.deliveryMedia` and `.deliveryChecklist` inputs via the policy / product-scoped evidence |
| `RentnKing/Sync/App/DriverChecklistSyncHandler.swift` | `equipmentUniqueId` in the payload |
| `RentnKing/Core/FileData Helper/SyncDriverChecklist.swift` | `saveDriverChecklistLocally(… equipment_unique_id:)` |
| `RentnKing/Modules/TABBAR/Home Model/Schedule Model/Schedule List/ScheduleListModel.swift` | `CheckListResponeData.equipment_unique_id` |
| `RentnKing/Modules/TABBAR/Equipment Model/MachineProfile/MachineProfileModel.swift` | `requires_fuel_check`, `requires_key_check` |
| `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift` | Start Delivery by stage; row copy no longer written for stage |
| `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchOfflineRowAdapter.swift` | `serverState` arrived rule |
| `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/Driver Checklist/DriverChecklistViewController.swift` | explicit segments, gate, unit header, Review Assembly, lock, D5 payload, Load Map & Go online/offline |
| `RentnKing/Modules/TABBAR/Home Model/Queue Line Model/ChecklistEntry.swift` | `Origin.Kind.driver(...)` |
| `RentnKing/Modules/TABBAR/Home Model/Queue Line Model/AssemblyReviewViewController.swift` | driver origin action, read-only mode, offline candidates + warning |
| `RentnKing/Modules/TABBAR/Home Model/Order Model/Order Details/OrderDetailsViewController.swift` | header (trip status, unit, Review Assembly); CheckList Deliv direct after departure; media buttons pass execution ids; evaluator inputs |
| `RentnKing/Modules/TABBAR/Home Model/Order Model/Check List/CheckListViewController.swift` | trip-stage-aware picker/restart; Save exit via the router |
| `RentnKing/Modules/TABBAR/Home Model/Order Model/Check List/CheckListUpdateViewController.swift` | Submit exit via the router |
| `RentnKing/Modules/TABBAR/Home Model/Order Model/Image Upload/ImageUploadViewController.swift` | exit via the router |
| `RentnKing/Modules/TABBAR/Home Model/Order Model/License Upload/LicenseUploadViewController.swift`, `LicenseTypeViewController.swift` | exit via the router (pop to the pushing Order Details) |
| `RentnKing/Modules/TABBAR/Home Model/Place Order Model/Payment Model/TermsAndConditionViewController.swift` | exit via the router |
| `RentnKing/Modules/TABBAR/Home Model/Order Model/Order Details/OrderDetailsViewController.swift` (`openAddressInMap`) | reports geocode failure |
| `RentnKingTests/KabbaSyncCore/DriverChecklistLocalStateTests.swift`, `EffectiveFieldStateTests.swift`, `PreparationLifecycleTests.swift`, `AssemblyReviewTests.swift`, `LegCompletionEvaluatorTests.swift`, `SyncEngineTests.swift` | extended |
| `RentnKingTests/Hosted/AssemblyReviewPresentationTests.swift`, `DispatchOfflineRowAdapterTests.swift` | extended |
| `RentnKingTests/KabbaSyncCore/Fixtures/dispatch_list_mixed.json`, `dispatch_offline_packages.json` | synced from Laravel |
| `docs/dispatch-offline-phase-6/PHYSICAL_ACCEPTANCE.md` | P1–P16 appended (Task 15) |

Not touched: storyboards (new controls are built in code like the existing segments), `EquipmentPicker.swift` (commented out), `MachineHoursViewController`, the Queue Line board, `QueueLineLifecycle`, `CompleteOnDispatchStart`.

---

## Interfaces between tasks (exact)

**Backend**
```php
// app/Services/Orders/DeliveryDepartureLock.php
final class DeliveryDepartureLock
{
    public const CODE = 'DELIVERY_DEPARTED';
    public const MESSAGE = 'This equipment is already on its way to the customer or has arrived. Its assignment is locked until the delivery is completed or the office recalls the trip.';

    /** On My Way or Arrived by the driver status, or the arrival latch. Never consults hasBeenDelivered() / isInTransitForDelivery(). */
    public static function isDeparted(OrderProduct $row): bool;

    /** @throws DeliveryDepartureLockedException */
    public static function assertAssignmentMutable(OrderProduct $row): void;

    /** The six trip fields every recall clears (status, on_my_way_at, ready_to_go_at, arrived_at, is_arrived, is_delivered — delivery leg). */
    public static function recallFields(): array;
}
// app/Services/Orders/DeliveryDepartureLockedException.php
class DeliveryDepartureLockedException extends \App\Services\QueueLine\QueueLineOperationException { /* code DELIVERY_DEPARTED */ }
```
- `RentalFulfillmentService::completeDelivery(...)`: existing signature; new rule inside — if `DeliveryDepartureLock::isDeparted($orderProduct)` and `$equipment` is given and a current unit exists and differs → `RentalFulfillmentException(DeliveryDepartureLock::MESSAGE)`.
- `driver-checklist` request: `equipment_unique_id` (`nullable|string|max:255|exists:equipment,unique_id`); stored at `dispatch_checklist.driver.<leg>.equipment_unique_id` when present; feed blocks `delivery_checklist.equipment_unique_id` / `pickup_checklist.equipment_unique_id` (string|null).
- Equipment blocks (`dispatchCardFields`, offline `dispatch.equipment`): `requires_fuel_check: bool`, `requires_key_check: bool` (from `Equipment::requiresFuelCheck()` / `requiresKeyCheck()`).

**Mobile core**
```swift
// DeliveryWorkflowStage.swift
enum DeliveryWorkflowStage: Int, Comparable { case assemblyReview = 0, driverChecklist, onMyWay, arrived, delivered }
struct DeliveryWorkflowInputs { let legCompleted: Bool; let trip: DriverTripStage; let assemblyGate: AssemblyPolicy.LocalGate?; let hasDriverChecklistEvidence: Bool }
extension DeliveryWorkflowStage { static func resolve(_ inputs: DeliveryWorkflowInputs) -> DeliveryWorkflowStage }
enum DeliveryWorkflowRouting {
    enum Destination: Equatable { case assemblyReview, driverChecklist, mainOrder, none }
    static func destination(for stage: DeliveryWorkflowStage, isDeliveryLeg: Bool) -> Destination   // Return: never .assemblyReview
}
enum DriverChecklistEvidence {
    static func exists(localRecord: DriverChecklistLocalState?, serverChecklist: DriverChecklistServerCopy?, operations: [SyncOperation], orderProductUniqueId: String, leg: String) -> Bool
}
struct DriverChecklistServerCopy: Equatable { var callCustomer: String?; var fuel: String?; var keys: String?; var checks: [Int]?; var equipmentUniqueId: String? }

// DriverChecklistLocalState.swift (additions)
public var equipmentUniqueId: String            // "" = unknown; dictionary key "equipment_unique_id"
public static func restore(local: DriverChecklistLocalState?, server: DriverChecklistServerCopy?, effectiveUnit: String?) -> DriverChecklistLocalState?
    // call/checks always kept; fuel/keys kept only when the recorded unit == effectiveUnit (or no unit is assigned)

// DriverChecklistGate.swift
enum CallOutcome: Equatable { case unset, confirmed(ticks: [Bool]), noAnswer }
enum FuelAnswer: String { case full = "Full", notFull = "Not Full" }
enum KeysAnswer: String { case withMachine = "With Machine", missing = "Missing" }
struct DriverChecklistGateInputs { let isDeliveryLeg: Bool; let call: CallOutcome; let fuelRequired: Bool; let fuel: FuelAnswer?; let keysRequired: Bool; let keys: KeysAnswer?; let assemblyReady: Bool? }
struct DriverChecklistGateDecision: Equatable { let enabled: Bool; let blockers: [String] }
enum DriverChecklistGate {
    static func evaluate(_ i: DriverChecklistGateInputs) -> DriverChecklistGateDecision
    static func fuelRequired(requiresFuelCheck: Bool?, isFuel: Bool?) -> Bool      // requires_* wins; fallback: is_* != false
    static func keysRequired(requiresKeyCheck: Bool?, isKey: Bool?) -> Bool
    static let blockerAssembly, blockerCall, blockerFuel, blockerKeys: String       // the §7.2 sentences
}

// PreparationLifecycle.swift (additions)
static func block(for context: ChecklistContext, tripStage: DriverTripStage) -> PreparationLifecycle.Block?   // .inTransit when tripStage >= .onMyWay, else the existing rule
static func mayRestartChecklist(_ context: ChecklistContext, hasLocalAnswers: Bool, tripStage: DriverTripStage) -> Bool

// AssemblyReview.swift (additions)
extension AssemblyPolicy {
    static func driverReadOnly(stage: DeliveryWorkflowStage?, memberStage: AssemblyStage) -> Bool     // (stage ?? .assemblyReview) >= .onMyWay || memberStage.hasLeftTheYard
    static func gate(forMission orderProductUniqueId: String, in review: AssemblyReview?, queue: QueueLineLocalOverlay, overlay: AssemblyLocalOverlay) -> LocalGate?   // nil when no review
}

// CustomerSiteRouter.swift
enum CustomerSiteStep { case license, terms, checklistPrepared, checklistCompleted, video }
enum CustomerSiteRoute: Equatable { case mainOrder, video, checklist, assemblyReview }
enum CustomerSiteRouter { static func afterStep(_ step: CustomerSiteStep, stage: DeliveryWorkflowStage, isDeliveryLeg: Bool, videoRequirementMet: Bool, checklistComplete: Bool) -> CustomerSiteRoute }

// MediaRequirementPolicy.swift
enum MediaRequirementPolicy {
    static func deliveryVideoSatisfied(serverHasVideoForCycle: Bool, operations: [SyncOperation], orderProductUniqueId: String, activeExecutionId: String?, legacyOrderEvidence: Bool) -> Bool
}

// LoadMapAndGoDecision.swift
enum LoadMapAndGoDecision {
    enum Outcome: Equatable { case openMaps, serviceOffline }
    static func outcome(reachable: Bool) -> Outcome
    static let serviceOfflineTitle = "Service Offline"
    static let serviceOfflineMessage = "Navigation needs cellular or Wi-Fi service. Your On My Way status is saved on this phone and will sync automatically."
}
```
- `DriverChecklistSyncHandler.enqueue(... equipmentUniqueId: String? ...)` adds `"equipment_unique_id"` to the payload when non-empty; `saveDriverChecklistLocally(... equipment_unique_id: String)` passes it.
- `ChecklistEntry.Origin.Kind` gains `case driver(orderProductUniqueId: String, enteredFrom: DeliveryWorkflowStage, isRevisit: Bool)`.
- `DriverStagePresentation.serverState(_:)` returns `isArrived: (is_arrived ?? false) && !(arrived_at ?? "").isEmpty`.

---

## Tasks

Backend first (the contract the phone consumes and the lock the phone relies on), then mobile core, then mobile screens, then the closing gate. Each task ends with a local commit.

### Task 0 — Baseline and guard rails (both repos)

- [ ] Verify the heads: `git -C /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 log --oneline -1` (docs head on `0278048`), `git -C /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline log --oneline -1` (`27cc10ed9`); both `git status --short` clean apart from Finder `.DS_Store` files, which are never staged.
- [ ] Backend baseline (one process at a time): `cd /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline && PHP_INI_SCAN_DIR=":/Users/garyjezorski/.config/kabba-php-ini" php artisan test tests/Feature/Orders` and `tests/Feature/CustomerChecklists`; confirm the failing names equal `docs/dispatch-offline-phase-6/baseline-known-failures.txt` (mobile repo). Record the counts in the execution record (§ Execution record below).
- [ ] Mobile baseline: `cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 && xcrun swift test` (expect 546 passing) and the signed hosted suite (command in Task 15) (expect 83).
- [ ] No commit (nothing changed) unless the execution record is started in the plan; if so, commit the plan edit only.

### Task 1 — Backend: `DeliveryDepartureLock` (predicate, guard, recall helper) and the envelope code

**Red tests** (`tests/Feature/Orders/DeliveryDepartureLockTest.php`, new; extend `QueueLineTestCase` or the Dispatch offline base for factories):
- [ ] `test_a_pending_or_ready_to_go_line_is_not_departed` — status null / `Ready to Go` ⇒ `isDeparted()` false; `assertAssignmentMutable()` does not throw.
- [ ] `test_on_my_way_is_departed` — status `On My Way` ⇒ true; guard throws `DeliveryDepartureLockedException` with `errorCode === 'DELIVERY_DEPARTED'`.
- [ ] `test_arrived_is_departed_even_though_has_been_delivered_is_true_and_in_transit_is_false` — status `Arrived`, `delivery_arrived_at`, `delivery_is_arrived`, `delivery_is_delivered` set; assert `hasBeenDelivered()` true and `isInTransitForDelivery()` false and `isDeparted()` true.
- [ ] `test_a_bare_arrival_latch_counts_as_departed` — status null but `delivery_is_arrived = 1`.
- [ ] `test_recall_fields_clear_every_trip_field` — apply `recallFields()` to an Arrived row; assert the six fields are null/false and `isDeparted()` false.
- [ ] `test_the_mobile_envelope_maps_delivery_departed_to_409` — `RespondsWithQueueLineEnvelope::statusForOperationCode('DELIVERY_DEPARTED') === 409` and a corrective-action string exists.
- [ ] Run: `PHP_INI_SCAN_DIR=":/Users/garyjezorski/.config/kabba-php-ini" php artisan test tests/Feature/Orders/DeliveryDepartureLockTest.php` → expect failures "Class not found".

**Code**
- [ ] Create `app/Services/Orders/DeliveryDepartureLockedException.php` and `app/Services/Orders/DeliveryDepartureLock.php` per the interface. `isDeparted()` reads the enum-cast status (`instanceof EquipmentDriverStatus` or `tryFrom`) and `delivery_is_arrived`; nothing else.
- [ ] `RespondsWithQueueLineEnvelope`: add `'DELIVERY_DEPARTED'` to the 409 list and a corrective action ("This equipment has already left the yard — the assignment is locked until the delivery completes or the office recalls the trip.").
- [ ] Run the focused test → green. Run `tests/Feature/QueueLine` → unchanged counts.
- [ ] Commit: `Add the delivery departure lock: predicate, guard and recall fields`.

### Task 2 — Backend: the lock on the canonical mobile paths (switch, reset, availability) and the offline ordering proof

**Red tests**
- [ ] Extend `tests/Feature/Api/Mobile/QueueLine/ChecklistPreparationResetTest.php`: change `test_in_transit_refuses_both_substitution_and_restart` to expect `error.code === 'DELIVERY_DEPARTED'` (409); add `test_arrived_refuses_both_substitution_and_restart` (drive the line to Arrived through `POST orders/schedules/driver-checklist`, then switch and reset → 409 `DELIVERY_DEPARTED`, nothing moved); add `test_switch_is_allowed_before_departure` if not already covered by `test_a_pending_line_can_substitute_an_eligible_replacement_unit`.
- [ ] Extend `tests/Feature/QueueLine/QueueLineAvailabilityTest.php`: acknowledgement at On My Way and at Arrived → `DELIVERY_DEPARTED` (409); pre-departure still accepted.
- [ ] `DeliveryDepartureLockTest::test_an_offline_drain_switch_then_availability_then_on_my_way_is_accepted_in_order` — three API calls in that order with `captured_at` timestamps 10, 9 and 8 minutes in the past and distinct `X-Operation-Id`s: all 200; assignment = replacement; the unit acknowledgement counts for the new episode; the row is On My Way; no `mobile_sync_issues` (or the parity table the suite uses) rows. Then a fourth call (another switch) → 409 `DELIVERY_DEPARTED`.
- [ ] `DeliveryDepartureLockTest::test_a_switch_arriving_after_the_departure_is_refused_but_the_departure_stands` — On My Way first, then switch → 409; the departure is untouched.
- [ ] Run the three files one by one → expect red on the new/changed assertions.

**Code**
- [ ] `ChecklistPreparationReset::assertResettable`: keep the delivered guard; replace the `isInTransitForDelivery()` block with `DeliveryDepartureLock::assertAssignmentMutable($orderProduct)`.
- [ ] `QueueLineAvailabilityService::assertAcknowledgeable`: keep the delivered/completed guard; replace the in-transit block with the same call.
- [ ] Run the focused files → green; run `tests/Feature/QueueLine` and `tests/Feature/Api` one at a time → counts equal baseline + the new tests; `QueueLineGuardCoverageTest` still green (releases are not gated).
- [ ] Commit: `Refuse switch, reset and availability once the delivery has departed`.

### Task 3 — Backend: the lock on every web assignment writer, the completion rule and the writer inventory

**Red tests** (`DeliveryDepartureLockTest`)
- [ ] `test_the_schedules_assign_equipment_page_refuses_on_my_way_and_arrived` — `postJson(route('admin.order-management.schedules.assign-equipment'), …)` at On My Way → 409 with the lock message; at Arrived → 409; assignment unchanged; before departure → 200 (guards the five pages that post here).
- [ ] `test_order_details_assign_and_complete_with_a_different_unit_is_refused_while_departed` — `route('admin.order-management.orders.assign-equipment')` with a different unit at On My Way and at Arrived → 409 with the lock message, `delivery_status` still Pending, no hard assignment, **the soft reservation of the locked unit still present and no checklist question rows created** (the refusal happens before that controller's writes); **with the same unit → completes** (delivery Completed, hard `equipment_id` = locked unit).
- [ ] `test_order_details_remove_equipment_is_refused_while_departed` — `route('admin.order-management.orders.remove-equipment')` at On My Way and Arrived → 409; the soft row survives.
- [ ] `test_auto_assign_skips_a_departed_line` — a departed line with no soft assignment; `AutoAssignDirectService::assignSingle()` returns `status = skipped`, reason `delivery_departed`; no soft row created.
- [ ] `test_dispatch_update_status_completed_still_completes_the_locked_unit` — `POST dispatch/update-status` Completed at Arrived → 200; hard assignment = locked unit.
- [ ] `test_the_mobile_checklist_completion_of_the_locked_unit_still_completes` — the existing `EquipmentLockAndReopenTest::test_delivery_with_the_currently_assigned_unit_still_completes_normally` pattern at Arrived.
- [ ] `tests/Feature/Orders/DeliveryDepartureLockWriterInventoryTest.php`: scan `app/` for `softAssignment()->create(` and `softAssignment()->delete(`; assert the file set equals exactly: `Services/Equipment/EquipmentReassignmentService.php`, `Http/Controllers/Admin/OrderManagement/Schedules/AssignEquipmentController.php`, `Http/Controllers/Admin/OrderManagement/Orders/AssignEquipmentController.php`, `Http/Controllers/Admin/OrderManagement/Orders/RemoveEquipmentController.php`, `Services/AutoAssignDirectService.php`, `Http/Controllers/Admin/OrderManagement/Orders/UpdateProductScheduleController.php`, `Services/Orders/RentalFulfillmentService.php`, `Models/Orders/OrderProduct.php` (cascade). The test's docblock says: a new writer must call `DeliveryDepartureLock::assertAssignmentMutable()` or be a recall path, and must be added to `DeliveryDepartureLockTest`.
- [ ] Run → red.

**Code**
- [ ] `Schedules\AssignEquipmentController`: after the `hasBeenDelivered()` guard, `try { DeliveryDepartureLock::assertAssignmentMutable($orderProduct); } catch (DeliveryDepartureLockedException $e) { return response()->json(['success' => false, 'message' => $e->getMessage()], 409); }`; inside the transaction, after the locked re-read, call it again (throw the same exception; catch it beside `EquipmentAlreadyDelivered`).
- [ ] `RentalFulfillmentService::assertEquipmentChangeAllowed`: after the delivered check, call the guard and rethrow as `RentalFulfillmentException(DeliveryDepartureLock::MESSAGE)`.
- [ ] `Orders\AssignEquipmentController`: **before** its `softAssignment()->delete()` and the checklist-row writes (they run outside any outer transaction), when the chosen unit differs from the live assignment (hard ?? soft), `try { DeliveryDepartureLock::assertAssignmentMutable($orderProduct); } catch (DeliveryDepartureLockedException $e) { return response()->json(['success' => false, 'message' => $e->getMessage()], 409); }` — the same unit passes through to completion.
- [ ] `RentalFulfillmentService::completeDelivery`: at the top of the transaction, if `DeliveryDepartureLock::isDeparted($orderProduct) && $equipment` and a current unit exists and differs → throw `RentalFulfillmentException(DeliveryDepartureLock::MESSAGE)` (independent of `$requireCurrentAssignment`) — the backstop for every completion writer.
- [ ] `AutoAssignDirectService::doAssign` (or `assignSingle` before the passes): `if (DeliveryDepartureLock::isDeparted($orderProduct)) return ['status' => 'skipped', 'reason' => 'delivery_departed'];`.
- [ ] Run the focused files → green; then `tests/Feature/Orders` (expect baseline 23 failures by name + new passes), `tests/Feature/OrderManagement`, `tests/Feature/QueueLine` (`EquipmentAssignmentIndependenceTest` green — none of its cases are departed).
- [ ] Commit: `Every equipment assignment writer honors the departure lock`.

### Task 4 — Backend: legitimate recall releases the lock (all four recall paths, RC10)

**Red tests** (`DeliveryDepartureLockTest`)
- [ ] `test_completed_to_pending_reopen_releases_the_lock_and_clears_is_arrived` — deliver a line (Arrived → completion), `reopenDelivery` via `POST dispatch/update-status` Pending; assert all six trip fields cleared incl. `delivery_is_arrived`, `isDeparted()` false, and a Schedules assign-equipment post now succeeds.
- [ ] `test_checklist_removal_releases_the_lock` — `CustomerChecklists/RemoveController` on an Arrived+completed line; same assertions.
- [ ] `test_reschedule_releases_the_lock_and_no_longer_reads_as_delivered` — `UpdateProductScheduleController` Reschedule on an Arrived (not completed) line: six fields cleared, `hasBeenDelivered()` false, `QueueLineLifecycle::stageFor()` not `equipment_delivered`, `queue_line_items.completed_at` null (requeue).
- [ ] `test_reassigning_the_driver_away_from_an_en_route_truck_recalls_the_trip` — `Dispatch/ReorderController` with a new driver at On My Way: six fields cleared (arrival ones already null), `isDeparted()` false; at Arrived the driver change does **not** recall (existing rule).
- [ ] `test_a_recalled_line_departs_again_and_locks_again` — after recall: switch OK → availability OK → On My Way OK → switch refused.
- [ ] Run → red (is_arrived assertions fail on the current code).

**Code**
- [ ] `RentalFulfillmentService::reopenDelivery`: replace the inline trip fields with `...DeliveryDepartureLock::recallFields()` (keeps every other field).
- [ ] `CustomerChecklists\RemoveController`: same.
- [ ] `SyncOnScheduleUpdate::resetDeliveryTripState`: `->update(DeliveryDepartureLock::recallFields())`.
- [ ] `UpdateProductScheduleController` Reschedule branch: apply `recallFields()` to the model before `softAssignment()->delete()` (assign the attributes so the same save persists them).
- [ ] `Dispatch\ReorderController`: inside the existing On My Way condition, assign `recallFields()` instead of the three-field list.
- [ ] Run the focused file → green; then `tests/Feature/Orders` (`EquipmentLockAndReopenTest` all green), `tests/Feature/QueueLine` (`QueueLineGuardCoverageTest::test_reschedule_removes_the_item_from_the_queue_and_requires_restaging`, `QueueLineScheduleLifecycleTest`), `tests/Feature/Dispatch`.
- [ ] Commit: `Every trip recall clears the whole trip state and releases the departure lock`.

### Task 5 — Backend: D5 contract — equipment identity on the driver checklist, `requires_*` on the dispatch equipment blocks, docs and fixtures

**Red tests**
- [ ] `DriverChecklistPartialStateTest`: `test_fuel_and_keys_are_stored_with_the_equipment_identity` (payload with `equipment_unique_id`, fuel, keys → `dispatch_checklist.driver.delivery.equipment_unique_id` stored; web-board keys untouched); `test_the_feed_returns_the_equipment_identity_per_leg` (`delivery_checklist.equipment_unique_id` on `GET` dispatch feed; pickup leg isolated); `test_an_unknown_equipment_identity_is_rejected` (422); `test_a_payload_without_the_identity_leaves_the_stored_identity_alone`; `test_departure_is_recorded_even_when_the_identity_is_stale` (identity ≠ current soft unit → still 200, status On My Way; D1).
- [ ] `DispatchOfflineRowParityTest`: the offline `dispatch.row.delivery_checklist.equipment_unique_id` equals the live feed's; `dispatch.equipment.requires_fuel_check` / `requires_key_check` present and equal to `Equipment::requiresFuelCheck()` / `requiresKeyCheck()` (Diesel → true, Batteries → false; 1 key → true, pull cord → false); `ListResource::dispatchCardFields` carries the same two.
- [ ] `DispatchContractFixturesTest`: shape assertions include the new keys.
- [ ] Run → red.

**Code**
- [ ] `DriverChecklistRequest`: `'equipment_unique_id' => 'nullable|string|max:255|exists:equipment,unique_id'` + body parameter doc.
- [ ] `DriverChecklistController::execute`: when `array_key_exists('equipment_unique_id', $validated)` merge it into `$checklist['driver'][$typePrefix]['equipment_unique_id']` (alongside the `driver_checks` merge; when only the identity is sent, still merge it and keep `checks`).
- [ ] `DispatchRowFields::deliveryChecklist/pickupChecklist`: `'equipment_unique_id' => data_get($row->dispatch_checklist, "driver.<leg>.equipment_unique_id")`.
- [ ] `Equipment\ListResource::dispatchCardFields` and `DispatchOfflineMissionSerializer` equipment block: add `requires_fuel_check`, `requires_key_check`.
- [ ] `docs/mobile-integration/MOBILE_API_CONTRACT.md`: document the request field, the two feed fields, the two equipment fields, and `DELIVERY_DEPARTED` (409) on switch/reset/availability.
- [ ] Regenerate fixtures: `WRITE_CONTRACT_FIXTURES=1 php vendor/bin/phpunit --filter DispatchContractFixturesTest` (as the fixture test's header prescribes) → `tests/Fixtures/mobile-contract/dispatch_list_mixed.json`, `dispatch_offline_packages.json` updated.
- [ ] Run the focused files → green; then `tests/Feature/Dispatch` (manifest budget test still ≤ 450), `tests/Feature/Api`, `tests/Feature/Mobile`.
- [ ] Commit: `Driver checklist: bind fuel and keys to the equipment identity; expose the yard's fuel/key predicates`.

### Task 6 — Backend closing gate for this mission's server side

- [ ] Run, one at a time: `tests/Feature/Dispatch`, `tests/Feature/Api`, `tests/Feature/Mobile`, `tests/Unit/Push`, `tests/Feature/QueueLine`, `tests/Feature/Terms`, `tests/Feature/CustomerPortal`, `tests/Feature/Orders`, `tests/Feature/CustomerChecklists`, `tests/Feature/OrderManagement`. Expected: every previously green directory green with the new tests added; Orders 23 / CustomerChecklists 11 failures identical by name to the baseline file; manifest ≤ 450.
- [ ] Sync fixtures to the phone: `cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 && Scripts/sync-contract-fixtures.sh /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline` (the mobile commit lands with Task 8).
- [ ] Record counts in the execution record. No commit unless the record is edited.

### Task 7 — Mobile core: `DeliveryWorkflowStage`, routing, the evidence rule, the whole-arrival server rule

**Red tests** (`RentnKingTests/KabbaSyncCore/DeliveryWorkflowStageTests.swift`, new; extend `EffectiveFieldStateTests.swift`, `DriverChecklistLocalStateTests.swift`)
- [ ] The matrix: for every `legCompleted ∈ {t,f}` × `trip ∈ {notStarted, onMyWay, arrived}` × `gate ∈ {nil, STOP, GO}` × `evidence ∈ {t,f}` assert the §3.3 result; explicitly: `trip == .onMyWay` with gate STOP → `.onMyWay`; `trip == .arrived` with gate STOP → `.arrived`.
- [ ] `DeliveryWorkflowRouting.destination`: `.assemblyReview → .assemblyReview`, `.driverChecklist → .driverChecklist`, `.onMyWay → .driverChecklist`, `.arrived → .mainOrder`, `.delivered → .none`; for the Return leg `.assemblyReview` maps to `.driverChecklist` (no yard gate); assert no stage ≥ `.onMyWay` yields `.assemblyReview`.
- [ ] `DriverChecklistEvidence.exists`: true for a local record with only defaults; true for a retained `driver_checklist.update` op (pending, synced, needsAttention) for the product+leg and false for another product/leg; true when the server copy has any of `call_customer`, `fuel`, `keys`, `checks`, `equipment_unique_id`; false otherwise.
- [ ] `DriverStageServerState`: `isArrived` requires `is_arrived && arrived_at` (test the presentation helper's inputs through a small pure function in Core, e.g. `DriverStageServerState.init(isArrivedFlag:arrivedAt:readyToGoAt:)`).
- [ ] Delete `testEveryPriorStateCombinationRoutesToTheDriverChecklist` and `testProgressNeverChangesTheRoute` (their rule is replaced) — the build must fail until `DriverChecklistRouting` is removed.
- [ ] Run: `cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 && xcrun swift test --filter "DeliveryWorkflowStageTests|DriverChecklistLocalStateTests|EffectiveFieldStateTests"` → red (types missing).

**Code**
- [ ] Create `RentnKing/Sync/Core/DeliveryWorkflowStage.swift` per the interface; add to the app target.
- [ ] `DriverChecklistLocalState.swift`: remove `DriverChecklistRouting` and its header paragraph; add `equipmentUniqueId` (dictionary round trip; empty string when absent) — the restore rule comes in Task 8 but the field lands here so the file changes once for identity.
- [ ] `EffectiveFieldState.swift`: add the whole-arrival initializer; `DispatchOfflineRowAdapter.DriverStagePresentation.serverState` uses it (app change, tiny, same commit).
- [ ] Run the filter → green; run `xcrun swift test` → all green (count = 546 − 2 + new).
- [ ] Commit: `Derive the delivery workflow stage from durable evidence and route by it`.

### Task 8 — Mobile core: the departure gate and unit-bound fuel/keys (D2, D3, D5, D11)

**Red tests** (`DriverChecklistGateTests.swift`, new; extend `DriverChecklistLocalStateTests.swift`; fixtures synced in Task 6)
- [ ] Gate matrix (Delivery): unset call → disabled + `blockerCall`; Confirmed with one tick false → disabled; Confirmed all ticks → passes the call term; No Answer → passes; fuel required + nil → disabled + `blockerFuel`; fuel required + `.notFull` → disabled + `blockerFuel`; fuel required + `.full` → passes; fuel not required + nil → passes; keys required + nil / `.missing` → disabled + `blockerKeys`; keys required + `.withMachine` → passes; keys not required → passes; `assemblyReady == false` or `nil` → disabled + `blockerAssembly` (first); everything satisfied → enabled, no blockers; blocker order = assembly, call, fuel, keys.
- [ ] Gate matrix (Return): only the call term matters; fuel/keys/assembly inputs ignored even when set to failing values.
- [ ] `fuelRequired(requiresFuelCheck:isFuel:)`: `true/…` → true; `false/…` → false; `nil/true` → true; `nil/nil` → true; `nil/false` → false. Same for keys.
- [ ] `DriverChecklistLocalState.restore`: local record for unit A, effective unit A → fuel/keys restored; effective unit B → fuel/keys `""`, call and ticks kept; no local record, server copy for unit A with effective B → fuel/keys dropped, call kept; server copy without identity while a unit is assigned → fuel/keys dropped; no unit assigned at all → restored as recorded.
- [ ] `hasProgress` treats an explicit `confirmed` call outcome as progress (the default is now unset).
- [ ] Contract: decode `dispatch_list_mixed.json` → the delivery checklist block exposes `equipment_unique_id` (add to the Core contract test that decodes it, e.g. `DispatchOfflineContractTests`/`Phase4ContractTests`).
- [ ] Run the filter → red.

**Code**
- [ ] Create `RentnKing/Sync/Core/DriverChecklistGate.swift`; add to the app target.
- [ ] `DriverChecklistLocalState`: `restore(local:server:effectiveUnit:)`, `DriverChecklistServerCopy`, `hasProgress` update; `callCustomer` documented as `""` = unset.
- [ ] `DriverChecklistSyncHandler.enqueue(... equipmentUniqueId:)` and `saveDriverChecklistLocally(... equipment_unique_id:)`; `CheckListResponeData.equipment_unique_id`; `MachineModel.requires_fuel_check/requires_key_check` (ObjectMapper mappings).
- [ ] Commit the synced fixtures with this task.
- [ ] Run the filter → green; `xcrun swift test` → green.
- [ ] Commit: `Driver checklist gate: explicit call, fuel Full and keys With Machine, bound to the unit`.

### Task 9 — Mobile core: lock-side policies, the customer-site router, the media policy and the Load Map & Go decision

**Red tests** (`CustomerSiteRouterTests.swift`, `MediaRequirementPolicyTests.swift`, `LoadMapAndGoDecisionTests.swift`, new; extend `PreparationLifecycleTests.swift`, `AssemblyReviewTests.swift`, `LegCompletionEvaluatorTests.swift`, `SyncEngineTests.swift`)
- [ ] `PreparationPolicy.block(for:tripStage:)`: a context with `in_transit == false` and `tripStage == .onMyWay` → `.inTransit`; `.arrived` → `.inTransit`; `.notStarted` → the existing rule; `mayRestartChecklist(... tripStage: .onMyWay)` false.
- [ ] `AssemblyPolicy.driverReadOnly`: `(.onMyWay, .pending)` true; `(.arrived, .pending)` true; `(.driverChecklist, .pending)` false; `(nil, .inTransit)` true; `(.assemblyReview, .staged)` false. `gate(forMission:in:…)` nil without a review.
- [ ] `CustomerSiteRouter.afterStep`: the §10.2 matrix for `stage ∈ {.onMyWay, .arrived}`; `stage < .onMyWay` → `.assemblyReview` for every step; Return: license/terms never occur, checklist/video follow the same Video ↔ Checklist rule; a sequence test proves `checklistPrepared → video → checklist(incomplete) → checklistCompleted → mainOrder` terminates.
- [ ] `MediaRequirementPolicy.deliveryVideoSatisfied`: photo-only ops → false; a video op for the product in the active cycle → true; a video for another product / the Return leg / a superseded cycle → false; legacy order evidence counts only when `activeExecutionId == nil`; server cycle flag → true.
- [ ] `LegCompletionEvaluator`: `.deliveryMedia` now driven by the policy (a photo-only order is incomplete; a video in the active cycle completes); `.deliveryChecklist` uses product-scoped evidence for the focus product (an order-scoped marker alone no longer satisfies) — adjust the existing tests that relied on the old rules and say so in their names.
- [ ] `LoadMapAndGoDecision.outcome(reachable:)`: true → `.openMaps`; false → `.serviceOffline`; the wording constants match §8.
- [ ] `SyncEngineTests`: enqueue `queue_line.switch_equipment`, `queue_line.availability`, `driver_checklist.update` (On My Way) for one order product in that order; drain with a recording transport → requests in the same order; park the switch (terminal 4xx) → the availability and the On My Way are still sent.
- [ ] Run the filter → red.

**Code**
- [ ] `PreparationLifecycle.swift`, `AssemblyReview.swift`, `LegCompletionRequirements.swift` per the interface; create `CustomerSiteRouter.swift`, `MediaRequirementPolicy.swift`, `LoadMapAndGoDecision.swift`; add to the app target.
- [ ] Run the filter → green; `xcrun swift test` → green.
- [ ] Commit: `Lock-aware preparation policy, one customer-site router, one delivery-video policy`.

### Task 10 — Mobile app: Dispatch Start Delivery by stage; the Driver Checklist screen (gate, unit, Review Assembly, lock, D5 payload, Load Map & Go)

**Red tests** (`RentnKingTests/Hosted/DriverDeliveryFlowHostedTests.swift`, new; pattern: build the VC un-loaded like `DispatchOfflineRowAdapterTests`, stub the engine snapshot through the existing test seams, assert the pushed VC type / control state)
- [ ] Dispatch: a row with no evidence and a cached GO review → `AssemblyReviewViewController` pushed with `origin.kind == .driver`; STOP review → the same; evidence + GO → `DriverChecklistViewController`; an On My Way op → `DriverChecklistViewController` in the On My Way state; an Arrived op → `OrderDetailsViewController` with `fromCheckListScreen`, `completionLeg == .delivery`; Return rows never push the review.
- [ ] Driver Checklist (Delivery, unit requires fuel + keys): `callCustomerSegment.selectedSegmentIndex == UISegmentedControl.noSegment`, same for fuel and keys; Load Map & Go disabled with `blockerAssembly`/`blockerCall` text; selecting Not Full keeps it disabled with `blockerFuel`; Full + Missing disabled with `blockerKeys`; Full + With Machine + Confirmed all ticks + GO → enabled; No Answer instead of Confirmed → enabled.
- [ ] Driver Checklist (unit requires neither): fuel/keys columns absent; call alone enables (with GO).
- [ ] Driver Checklist (Return): no fuel/keys, no assembly term, no Review Assembly button.
- [ ] The header shows "Name · #TAG" of the effective unit; a pending local switch changes it.
- [ ] Review Assembly button present in the not-started and On My Way states; tapping pushes the review with `isRevisit == true` and `enteredFrom == current stage`.
- [ ] Load Map & Go: the enqueued op payload carries `equipment_unique_id` and `equipment_driver_status == "On My Way"`; with `reachable == false` (inject the decision) the Service Offline alert is presented and no Maps call is made; after the tap the screen is in the On My Way state and `driverReadOnly` is true for its review.
- [ ] Restore: a stored v2 record for unit A with the row now on unit B → fuel/keys unanswered, call restored.
- [ ] The Dispatch row copy is not mutated for stage by `data_updateInCurrentDic` (delivery_checklist `is_delivered` untouched).
- [ ] Run: `xcodebuild test -project RentnKing.xcodeproj -scheme RentnKingHostedTests -destination 'id=15352B6A-C2E3-4027-BEA1-74DDCFFAB55E' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/kabba-p6-hosted -only-testing:RentnKingHostedTests/DriverDeliveryFlowHostedTests` → red.

**Code**
- [ ] `DispatchListViewController.btnStatusCallClicked`: build `DeliveryWorkflowInputs` (leg completion via `EffectiveFieldState.legSatisfied`, trip via `DriverStageOverlay`, gate via `AssemblyPolicy.gate(forMission:in: KabbaAssemblySync.cached(...)?.data …)`, evidence via `DriverChecklistEvidence.exists`) → `DeliveryWorkflowRouting.destination` → push the review (`ChecklistEntry.openAssemblyReview(… origin: .driver(...))`), Screen 2, or Order Details (the same push `pushOrderDetails` performs, moved to a shared helper). `data_updateInCurrentDic` keeps only display fields.
- [ ] `DriverChecklistViewController`: segments start unselected (`selectedSegmentIndex = UISegmentedControl.noSegment`); `updateReadyToGoButton` → `DriverChecklistGate.evaluate` (inputs from the controls, the unit's `requires_*`/`is_*`, the review gate); a blocker label under the button; `Review Assembly` button built in code beside the status line (all states); the unit identity line in the header; `restoreChecklistState` → `DriverChecklistLocalState.restore(local:server:effectiveUnit:)`; every `saveDriverChecklistLocally` call passes `equipment_unique_id`; `btnReadytoGo_Action` re-evaluates the gate, records, then `LoadMapAndGoDecision.outcome(reachable:)` → Maps or the Service Offline alert; `openAddressInMap` gains a completion that reports geocode failure → the same alert; rename `isCallWithMachine` → `isNoAnswer`; recompute the gate on `.kabbaSyncQueueChanged` and in `viewWillAppear`.
- [ ] Run the focused hosted test → green; run the full hosted suite and `xcrun swift test` → green; simulator build OK.
- [ ] Commit: `Start Delivery routes by stage; the Driver Checklist enforces the explicit departure gate and records the unit`.

### Task 11 — Mobile app: Assembly Review driver origin, read-only lock mode, offline candidates

**Red tests** (extend `RentnKingTests/Hosted/AssemblyReviewPresentationTests.swift`)
- [ ] Driver origin at STOP: no "Continue to Checklist"; "Continue to Driver Checklist" present, disabled; at GO enabled; tapping (first start) pushes `DriverChecklistViewController`; on a revisit (`isRevisit`) the button reads "Back to Driver Checklist" and pops.
- [ ] Driver origin with an On My Way op in the engine (server member still `pending`): every availability row disabled, no Change/Assign action, the Continue button absent, tapping a row shows the lock explanation; the same with an Arrived op; the same with a `pending` phone state but a server `in_transit` member.
- [ ] Yard origins unchanged (the existing tests).
- [ ] Offline candidates: with the candidates request failing and a warmed equipment list present, `changeEquipment` opens the picker with the category-scoped warmed list; a pick that supersedes a cached context shows the "needs service" warning before enqueueing; the op is enqueued; the row shows the replacement unconfirmed and the gate STOP.
- [ ] Run → red.

**Code**
- [ ] `ChecklistEntry.Origin.Kind.driver(...)`; `openAssemblyReview` unchanged in signature.
- [ ] `AssemblyReviewViewController`: compute `stage` for the driver origin (same inputs as Dispatch, via a small shared builder in `Sync/App`); `readOnly = AssemblyPolicy.driverReadOnly(...)` for driver origins (yard origins keep `!left`); render the driver forward action per §6.1; `changeEquipment` falls back to the warmed list (`getEquipmentList`-style read scoped by the unit's category, wrapped as `EquipmentCandidate`s) when `loadCandidates` fails; warn when `ChecklistContextFallbackPolicy.canServeOffline` would refuse the replacement's cached context.
- [ ] Run the focused hosted tests → green; full hosted + core → green.
- [ ] Commit: `Assembly Review: driver origin with Continue to Driver Checklist, read-only after departure, offline candidates`.

### Task 12 — Mobile app: Main Order hub, post-departure checklist entry, Review Assembly from Main Order, customer-site exits, locked checklist

**Red tests** (`DriverDeliveryFlowHostedTests.swift`)
- [ ] Order Details reached with an Arrived op: header shows the trip status and the unit; a Review Assembly action pushes the review read-only; `btnCheckListDelivClicked` pushes `CheckListViewController` (not the review) focused on `strProductID`; before departure (no ops, yard entry) it pushes the review as today.
- [ ] Order Details media buttons pass `checklistExecutionIds` for the active cycle; the tiles and the Complete gate use `MediaRequirementPolicy` (a photo-only order shows the video tile incomplete; the override screen lists Video).
- [ ] Checklist after departure: `btnMachineIdClicked` shows the In Transit block even with a stale cached context; the restart footer is absent; `EquipmentAssignmentFlow.Target.block == .inTransit`; a departed line with no unit still opens the picker.
- [ ] Exits: CLV Save with the video unmet → `ImageUploadViewController` pushed; with it met → pops to the pushing `OrderDetailsViewController`; CLU Submit → Video when unmet else Order Details (never the review after departure); IU done with the checklist incomplete → pops to the existing `CheckListViewController`; else → Order Details; License and Terms → the pushing Order Details (with an Orders list beneath, Order Details is still the target).
- [ ] Before departure the same screens keep `returnToReview` behavior (regression cases from `AssemblyReviewPresentationTests` / existing flows).
- [ ] Run → red.

**Code**
- [ ] `OrderDetailsViewController`: header additions; `btnCheckListDelivClicked` branches on the mission's stage (≥ `.onMyWay` → direct `CheckListViewController` with `focusOrderProductUniqueId`, `queueLineFocusedStaging = true`, `fromCheckListScreen`); media buttons carry execution ids; `legCompletionInputs` use the policy and product-scoped checklist evidence; a `reviewAssemblyTapped` action.
- [ ] `CheckListViewController`: pass `tripStage` (from the engine) to `PreparationPolicy.block/mayRestartChecklist`; `popAfterSave` and the smart route use `CustomerSiteRouter` (stage ≥ On My Way) with "pop to existing else push" helpers.
- [ ] `CheckListUpdateViewController` Submit, `ImageUploadViewController` completion, `LicenseUploadViewController`/`LicenseTypeViewController` and `TermsAndConditionViewController` exits: route through the router; the yard band unchanged.
- [ ] Run the focused hosted tests → green; full hosted + core → green; simulator build OK.
- [ ] Commit: `Main Order is the customer-site hub: direct checklist entry after departure, read-only Review Assembly, one exit router`.

### Task 13 — Mobile: Return regression and shared-component corrections (§13)

**Red tests** (`DriverDeliveryFlowHostedTests.swift`, core)
- [ ] Start Return with an Arrived op → Order Details (`completionLeg == .return`); with an On My Way op → Screen 2 On My Way; otherwise Screen 2 (never the review).
- [ ] Return Screen 2: no fuel/keys columns, no assembly term, no Review Assembly button; call outcome explicit (unset disables; No Answer enables).
- [ ] Return checklist/media exits: Save/Submit → Video when the Return media requirement is unmet, else Order Details; IU → checklist when incomplete else Order Details; never the review.
- [ ] A core test pins that `DriverChecklistGate.evaluate` for `isDeliveryLeg == false` ignores fuel/keys/assembly and that `DeliveryWorkflowRouting` never returns `.assemblyReview` for Return.
- [ ] Run → red where the app still differs; green tests document the preserved behavior.

**Code**
- [ ] Only what the red tests require (expected: the Return band of the router and the Screen 2 call control; no new Return behavior).
- [ ] Commit: `Return keeps its own band: explicit call outcome, Main Order exits, no Delivery-only rules`.

### Task 14 — Mobile: break-a-rule probes and diff review

- [ ] Temporarily invert each of these one at a time and confirm a test fails, then restore: the fuel term (`.notFull` passes); the keys term; the assembly term; `driverReadOnly` at `.onMyWay`; `resolve` with STOP after `.onMyWay`; the router returning `.assemblyReview` after departure; `restore` keeping fuel for a different unit; `block(for:tripStage:)` ignoring the trip stage; `DriverStageServerState` trusting `is_arrived` alone; `equipment_unique_id` dropped from the departure payload. Record the ten probes and their failing test names in the execution record.
- [ ] Review the whole mobile diff against the Review Focus list. Fix, re-run, amend the relevant task commit or add a small fix commit.
- [ ] Commit (if any): `Driver delivery flow: review fixes`.

### Task 15 — Closing gate, physical-acceptance preparation, independent review

- [ ] Backend, one directory at a time (same list as Task 6): all green except the two baseline directories with identical failing names; manifest ≤ 450.
- [ ] Mobile: `xcrun swift test` all green; signed hosted `xcodebuild test -project RentnKing.xcodeproj -scheme RentnKingHostedTests -destination 'id=15352B6A-C2E3-4027-BEA1-74DDCFFAB55E' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/kabba-p6-hosted` all green; simulator build `xcodebuild build -project RentnKing.xcodeproj -scheme RentnKing -destination 'id=15352B6A-C2E3-4027-BEA1-74DDCFFAB55E' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/kabba-p6-sim CODE_SIGNING_ALLOWED=NO` OK; the existing no-polling grep gate clean.
- [ ] Contract parity: the synced fixtures equal `tests/Fixtures/mobile-contract` (`diff -r`).
- [ ] Append the P1–P16 scenarios of spec §16 to `docs/dispatch-offline-phase-6/PHYSICAL_ACCEPTANCE.md` in Gary's step-by-step style (offline steps say "stay offline until Claude says"; P6 lists the exact drain check; P14 lists the five admin pages; P15 names the test-server recall action to use). Add the mission's execution record (heads, counts, probes) to this plan's § Execution record.
- [ ] Fresh independent review of both diffs against the Review Focus list; Critical/Important findings fixed and re-reviewed.
- [ ] Commit: `Driver delivery flow: physical acceptance scenarios and execution record`.
- [ ] Stop and report: heads, counts, the review verdict, and the exact device build to install for the physical pass. Nothing is pushed or deployed.

---

## Backend lock architecture (the release-critical part, in one place)

**Writers found by the audit (§2.2 RC9) and how each is proven:**

| Writer | Enforcement | Proof (test) |
|---|---|---|
| `EquipmentReassignmentService::switch` (mobile switch endpoint, Livewire Board) | `ChecklistPreparationReset::assertResettable` → guard | `ChecklistPreparationResetTest` On My Way + Arrived; `DeliveryDepartureLockTest` ordering |
| `ResetController` → `ChecklistPreparationReset` | same | same |
| `Schedules\AssignEquipmentController` (Dispatch, Schedules, Schedule Assignment, Schedule Conflicts, Order Details) | guard before and inside the row lock | `test_the_schedules_assign_equipment_page_refuses_on_my_way_and_arrived` |
| `Orders\AssignEquipmentController` (assign-and-complete) | guard at the top before its own writes (different unit); `completeDelivery` departed rule as backstop | `test_order_details_assign_and_complete_with_a_different_unit_is_refused_while_departed` |
| `Orders\RemoveEquipmentController` | `assertEquipmentChangeAllowed` → guard | `test_order_details_remove_equipment_is_refused_while_departed` |
| `AutoAssignDirectService::doAssign` | skipped when departed | `test_auto_assign_skips_a_departed_line` |
| `QueueLineAvailabilityService::acknowledge` | guard | `QueueLineAvailabilityTest` On My Way + Arrived |
| `UpdateProductScheduleController` (Reschedule / Pending), `RentalFulfillmentService::reopenDelivery`, `CustomerChecklists\RemoveController`, `Dispatch\ReorderController`, `SyncOnScheduleUpdate` | recall paths: release first via `recallFields()` | Task 4 tests |
| `RentalFulfillmentService::completeDelivery` | the intended end: same unit only while departed | Task 3 completion tests |
| `OrderProduct` cascade delete/restore | not an ordinary writer (order deletion) | inventory test lists it |
| new writers | `DeliveryDepartureLockWriterInventoryTest` fails until the writer is added and tested | — |

**Where the rule lives:** `App\Services\Orders\DeliveryDepartureLock` (predicate + guard + recall fields) — one class, no controller-local copies. The exception is a `QueueLineOperationException` subclass so every existing `InvalidArgumentException` catch (Livewire) and the mobile envelope keep working; web JSON controllers catch it explicitly and answer 409.

**How legitimate office recall removes the lock:** every recall path applies `recallFields()` (six fields, incl. `delivery_is_arrived`), so `isDeparted()` is false afterwards; the Reschedule branch does it before it clears the assignment, so the recall itself is never refused. Recall paths are enumerated and each tested (Task 4).

**Why it cannot regress at Arrived:** `isDeparted()` checks the driver status for `On My Way` **and** `Arrived` by name plus `delivery_is_arrived`; it never calls `isInTransitForDelivery()` (false after Arrived) or `hasBeenDelivered()`; `test_arrived_is_departed_even_though_has_been_delivered_is_true_and_in_transit_is_false` pins exactly that state, and every writer test runs at Arrived as well as On My Way.

**Why the offline FIFO is safe:** the phone sends one order product's operations strictly in capture order and a parked op does not block the ones behind it (`SyncEngine.nextEligible`); the server therefore sees `switch → availability → On My Way`, is not departed for the first two, and locks on the third; pinned by `test_an_offline_drain_switch_then_availability_then_on_my_way_is_accepted_in_order` and the `SyncEngineTests` ordering case.

## Mobile assignment surfaces (in one place)

| Surface | Before departure | After On My Way / Arrived |
|---|---|---|
| Assembly Review, driver origin (Screen 2 first start / revisit) | Assign / Change via the canonical switch (online candidates, offline warmed list), Available / Not Available, options | read-only: rows disabled, no Assign/Change, lock explanation on tap (`AssemblyPolicy.driverReadOnly`) |
| Assembly Review from Main Order | n/a (Main Order is post-Arrived on the driver road) | read-only, same rule |
| Assembly Review, yard origins (Queue Line, Orders, Order Details pre-departure) | unchanged | unchanged (`hasLeftTheYard` from the server) |
| Equipment checklist picker (`btnMachineIdClicked`) | unchanged (`PreparationPolicy` rules) | refused with the In Transit explanation from the effective trip stage, regardless of the cached context; except a departed line with no unit |
| Checklist "Delete Checklist / Start Over" | unchanged | absent (`mayRestartChecklist(... tripStage:)` false) |
| `EquipmentAssignmentFlow.Target.block` | nil / existing | `.inTransit` |
| Driver Checklist header | shows the effective unit; a switch elsewhere reflects on return | shows the locked unit |

## Scope boundaries (restated from spec §17)

In scope: everything in the file map. Out of scope: the web writer refactor, the Queue Line board, Fast Track, Terms, the fuel/key ledgers, the S4/S5 markers beyond the router, `MachineHoursViewController`, `EquipmentPicker.swift`, S10, the media retry loop, Phase 6 N1–N4, the debug-login credentials, the Firebase-without-config wake crash, and any production, push, merge, deploy, flag, version, archive or upload activity.

## Execution record

_(filled task by task: date, task, commit SHA, focused test result, regression counts, probes, review notes)_
