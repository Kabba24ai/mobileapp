# Driver Delivery Process Flow — Design

**Date:** 2026-09-27 (amended the same day after review; decisions D1–D12 locked)
**Repositories:** `Kabba24ai/mobileapp` (iOS, worktree `mobileapp-dispatch-offline-p6`, branch `feature/dispatch-offline-phase-6`, design head `a341168` on product head `0278048`) + Kabba Laravel (worktree `kabba2_AI-dispatch-offline`, same branch name, head `27cc10ed9`)
**Status:** Approved architecture with locked business rules. No product code. Phase 6 physical acceptance is paused at Scenario A (PASS) until this flow is implemented. The implementation plan is `docs/superpowers/plans/2026-09-27-driver-delivery-process-flow.md`.
**Inputs:** the current local Phase 6 heads, including the Dispatch assigned-only filter and mis-flagged Return corrections (`718a1c3` / `27cc10ed9`); the Scenario A observations O1–O3 (`docs/superpowers/plans/2026-09-26-dispatch-offline-phase-6-physical-acceptance.md` §11); the requested canonical flow (§1); the locked decisions (§18).

Every claim in §2 comes from reading the code on those heads. Line numbers are as of those heads. Nothing here was reproduced on the phone unless the text says so.

---

## 0. Summary

The offline infrastructure holds (Scenario A synced eight operations cleanly). The workflow around it does not:

1. **Assembly Review is not on the driver's road.** Dispatch → Start Delivery always opens the Driver Checklist; the review is reachable only from the Queue Line board, the Orders list and Order Details (§2.2 RC1).
2. **Departure is barely gated.** Load Map & Go is enabled by the call-customer ticks alone; fuel and keys have silent defaults; choosing "No Answer" bypasses the ticks; nothing checks that the assembly was confirmed or that the assigned unit is the one on the truck (RC3). The server enforces nothing at all on this endpoint, by an approved 2026-07-23 decision that stays (RC4, D1).
3. **The road after Arrived leads back to the yard gate.** Order Details opens the delivery checklist *through* Assembly Review, and every checklist exit pops back to that review (RC5). Once Arrived has synced, the server reports the line as `equipment_delivered`, the review hides "Continue to Checklist" and locks its rows — the driver at the customer's site has no road to the checklist (RC6, verified by code reading, not yet reproduced physically). Offline, a cached review kept Scenario A out of that hole.
4. **The equipment assignment is not locked when the truck leaves.** Web Dispatch / Order Details / Schedules can reassign a unit while it is On My Way; the mobile Switch and Reset guards go blind after Arrived because `isInTransitForDelivery()` turns false once `hasBeenDelivered()` is true (RC9). No recall path clears `delivery_is_arrived` (RC10).
5. **Workflow state is scattered.** Trip stage, mini-checklist answers, assembly state, "checklist done", fuel and media each live in two or more stores with different scopes (§2.3). The stage itself is already well derived (`DriverStageOverlay`); what is missing is one derivation that covers the whole delivery, and routing that uses it.

The design keeps every durable store that exists and adds **no new workflow store**. It adds:

- one pure derivation (`DeliveryWorkflowStage`) and routing that reads it (§3.3, §5);
- a driver-origin mode for the existing Assembly Review screen with **Continue to Driver Checklist** (§6);
- an explicit, default-free Driver Checklist departure gate — Call Customer, Fuel = Full, Keys = With Machine, each only where the unit requires it, bound to the unit's identity on the phone **and** on the server (§7, D2, D3, D5, D11);
- a **departure lock** that is a core invariant on both sides: from the instant On My Way is effective until the delivery completes or the office recalls the trip, no ordinary writer may change the assignment, and every writer found by the audit — mobile and web — honors one shared server guard (§3.4, D9, D10);
- **Review Assembly**, reachable for the whole active Delivery: operational before departure, read-only after, from the Driver Checklist and from Main Order (§11, D8);
- Load Map & Go that records first and only then navigates, with a Service Offline state when there is no service (§8);
- stage-based customer-site routing with Main Order as the hub and one delivery-video policy (§10, D7).

---

## 1. The canonical flow and the responsibilities

```
Dispatch
  ↓ Start Delivery
Equipment Assembly Review         ← what is physically going: assignment = physical unit, options, explicit Available
  ↓ Continue to Driver Checklist   (only at GO)
Driver Checklist                  ← Call Customer, Fuel readiness, Key verification; the final departure gate
  ↓ Load Map & Go                  (recorded locally first; Apple Maps only when service exists)
Delivery On My Way                ← the equipment assignment LOCKS here
  ↓ Driver Arrived
Main Order                        ← the customer-site hub
  ↓ License / Terms / Equipment Checklist / Video   (each returns to Main Order, or to the next missing step)
Complete Delivery
```

| Screen | Responsibility |
|---|---|
| **Assembly Review** | establish what physical equipment is actually being delivered; ensure the canonical assignment matches the physical unit; verify required options; explicitly confirm the exact assigned unit **Available** |
| **Driver Checklist** | Call Customer; Fuel readiness where applicable; Key verification where applicable; the final departure gate |
| **Main Order** | customer-site workflow hub: License, Terms, Equipment Checklist, Video, Complete Delivery; Review Assembly as read-only reference |

Plus: resume at the effective stage; Review Assembly reachable while the delivery is active; one canonical equipment assignment episode, locked at departure; Available is a physical verification of *that* unit; all existing offline behavior preserved.

---

## 2. Current state and root causes

### 2.1 The roads today

```
QUEUE LINE card ─┐
ORDERS list ─────┼─► Assembly Review ─► Delivery Checklist (CLV) ─ Save ─► Video? ─► back to Assembly Review ─► Back ─► origin
ORDER DETAILS ───┘                      └─ Preview ─► Finalize (CLU) ─ Submit ───────► back to Assembly Review

DISPATCH card ─► Start Delivery ─► Driver Checklist (Screen 2) ─ Load Map & Go ─► (Maps) ─ Arrived ─► Order Details
                                                                                                        │
                                          License ─► pop │ Terms ─► pop │ Photo/Video ─► pop            │
                                          CheckList Deliv ─► Assembly Review ─► CLV … ─► back to review ◄┘
                                          Complete Delivery ─► requirements met? ─► Dispatch ; else override screen ─► Dispatch
```

Two disconnected sequences: a **yard preparation** sequence that owns Assembly Review, and a **driver** sequence that never sees it until the customer site, where it is the wrong screen.

### 2.2 Root causes

**RC1 — Start Delivery never opens Assembly Review.**
`DriverChecklistRouting.destination(isArrived:readyToGoAt:hasSavedProgress:)` returns `.driverChecklist` for every input (`RentnKing/Sync/Core/DriverChecklistLocalState.swift:31-49`, "routing is absolute", the 2026-09 correction). `DispatchListViewController.btnStatusCallClicked` pushes `DriverChecklistViewController` unconditionally (`…/Dispatch Model/DispatchListViewController.swift:1691-1717`). The only callers of `ChecklistEntry.openAssemblyReview` are the Queue Line board (`QueueLineViewController.swift:288-295`), the Orders list (`OrderListViewController.swift:1066-1072`) and Order Details (`OrderDetailsViewController.swift:1302-1306`).

**RC2 — Assembly Review's only forward action is the equipment checklist.**
"Continue to Checklist" builds `CheckListViewController` for one member (`AssemblyReviewViewController.swift:421-435`, `839-848`; `ChecklistEntry.makeChecklist` `ChecklistEntry.swift:69-84`). There is no road from the review to the Driver Checklist, and the review's header comment defines the flow as `entry point → Assembly Review → Delivery Checklist → Assembly Review → entry point` (`ChecklistEntry.swift:5-24`).

**RC3 — The Driver Checklist's departure gate is weak and partly inverted.**
`updateReadyToGoButton` (`DriverChecklistViewController.swift:746-763`):
```swift
let allChecked = … !callDeliveryCustomerChecks.contains(false)
let fuelFilled = !self.showFuelSegment || !(self.strDoubleCheck).…isEmpty
let keysFilled = !self.showKeysSegment || !(self.strKeys).…isEmpty
let callChecklistOK = isCallWithMachine || allChecked
var isEnabled = callChecklistOK && fuelFilled && keysFilled
```
- Fuel defaults to `"Not Full"` and keys to `"Missing"` at setup (`612-628`), so `fuelFilled`/`keysFilled` are always true: a machine recorded as not fuel-ready, or with its key missing, departs. Under the locked rules (D2, D11) both are integrity defects.
- The call segment defaults to "Confirmed" (`703-704`); index 1 is **"No Answer"**, but the property is named `isCallWithMachine` (`711`, a leftover of the keys control) and it *disables* the sub-checklist and *enables* departure (`713-720`, `752`). "No Answer" is a recorded call attempt (the server texts the customer on that transition, `DriverChecklistController.php:230-232`), so it legitimately completes the call requirement (D3) — but nothing today records that the driver chose it rather than the default.
- The fuel/keys segments are shown by `is_fuel`/`is_key` (`589-590`), which the server derives from `hasFuelData()`/`hasKeyData()` (any power source; key pad and pull cord count) — not from the yard's own "requires a sign-off" predicates `requiresFuelCheck()` (Diesel/Gas) and `requiresKeyCheck()` (1 or 2 physical keys) (`app/Models/MaintenanceManagement/Equipment.php:157-195`, `Equipment/ListResource.php:111-121`).
- Nothing on Screen 2 knows whether the assembly was confirmed or whether the row's unit is the one on the truck.

**RC4 — The server records; it does not gate.**
`POST orders/schedules/driver-checklist` (`app/Http/Controllers/Api/Admin/V1/Orders/Schedules/DriverChecklistController.php`) checks only the leg owner (`110-128`, 409 `DISPATCH_ASSIGNMENT_CHANGED`). It does not require On My Way before Arrived, a call outcome, fuel, keys, staging or availability; the comment at `136-142` records the approved rule: "Queue Line staging is INFORMATIONAL, not restrictive (2026-07-23)". On My Way writes `delivery_on_my_way_at` (+ back-fills `delivery_ready_to_go_at`); Arrived writes `delivery_arrived_at`, `delivery_is_arrived = true` **and `delivery_is_delivered = true`** (`161-190`). The request accepts no equipment identity (`DriverChecklistRequest.php:13-31`), so the server cannot tell which unit a fuel/keys answer described.

**RC5 — Every checklist exit returns to the Assembly Review beneath, whatever the origin.**
`ChecklistEntry.returnToReview` (`ChecklistEntry.swift:94-101`) pops to the last `AssemblyReviewViewController` on the stack; it is called by the staging Save (`CheckListViewController.swift:755-768`), the finalization Submit (`CheckListUpdateViewController.swift:582-598`) and the media upload (`ImageUploadViewController.swift:389`). The review's `viewDidAppear` then re-fetches from the server (`AssemblyReviewViewController.swift:121-126`). This is Scenario A's O2.

**RC6 — After Arrived, the review is the wrong screen and, online, a dead end.**
- Arrived fires `CompleteOnDispatchStart` → `QueueLineService::complete(VIA_DISPATCH_STARTED)` → `queue_line_items.completed_at` (`app/Listeners/QueueLine/CompleteOnDispatchStart.php:29-61`).
- `QueueLineLifecycle::stageFor` returns `equipment_delivered` when that latch is set or `hasBeenDelivered()` is true; `hasBeenDelivered()` includes `delivery_is_delivered || delivery_arrived_at !== null` (`app/Services/QueueLine/QueueLineLifecycle.php:67-85`, `app/Models/Orders/OrderProduct.php:494-505`). The mobile member payload carries it as `lifecycle_stage` (`QueueLineMobilePresenter.php:228`).
- The phone: `memberStage(serverStage: .equipmentDelivered …)` → `.equipmentDelivered` (`AssemblyReview.swift:743-752`); `hasLeftTheYard` is true (`:68`); the card renders **no Continue button** (`AssemblyReviewViewController.swift:426`), disables every availability row (`392`, `416`) and refuses an equipment change with "This delivery is complete…" (`672-679`, `PreparationLifecycle.swift:36-52`).
- Order Details still routes through the review, because its "delivered" test is the row-level `is_delivered`/status (`OrderDetailsViewController.swift:668-690`, `696-706`; served by `DispatchRowFields::isDelivered`, `OrderProducts/ListResource.php:87`), which Arrived does not set.

  Net effect online: **Arrived (synced) → Order Details → CheckList Deliv → Assembly Review showing "Equipment Delivered" with nothing to continue to.** Offline, the cached review plus `QueueLineLocalOverlay` promote the member only to In Transit (`QueueLineOperations.swift:233-237`; `completedLocally` needs a `delivery_checklist.complete`), so Scenario A still reached the checklist. It is verified by code reading; it must be the first physical scenario of the next pass (§16 P7). The Queue Line semantics themselves stay (D6); the phone stops navigating by them after departure.

**RC7 — Post-departure availability rows are locked, even for a legitimate review.**
`enabled: !left` (`AssemblyReviewViewController.swift:392`, `416`) — Scenario A's O1. Correct for the yard gate and for the departure lock (§3.4), but the driver has no way to *look* at the assembly from the driver screens at all.

**RC8 — "Complete Delivery" is a client-side gate, not an operation.**
`btnDeliveryComplatedClicked` evaluates `LegCompletionEvaluator`, shows the success overlay and pops to Dispatch; it sends nothing (`OrderDetailsViewController.swift:1005-1059`). The leg is completed by the checklist Submit (`delivery_checklist.complete`). Not a defect; the spec never describes "Complete Delivery" as a transition.

**RC9 — The assignment is not locked at departure (core, in scope — D9/D10).**
The soft assignment (`equipment_soft_assigns`, one live row = one episode) has **no single writer**. Every writer and its current guard:

| Writer | Reached from | Guard today | Hole |
|---|---|---|---|
| `EquipmentReassignmentService::switch` (`app/Services/Equipment/EquipmentReassignmentService.php:87-160`) | mobile `POST queue-line/{uid}/switch-equipment`; Livewire `QueueLine/Board::confirmSwitch` | hard assignment / Q&A rows; `ChecklistPreparationReset::assertResettable` = `isInTransitForDelivery()` (`ChecklistPreparationReset.php:52-73`) | `isInTransitForDelivery()` is `status == On My Way && !hasBeenDelivered()`, and Arrived makes `hasBeenDelivered()` true ⇒ **Switch and Reset are accepted between Arrived and the signed completion** |
| `ChecklistPreparationReset::supersede` via `Checklists/ResetController` | mobile "Delete Checklist / Start Over" | same | same |
| `Admin\OrderManagement\Schedules\AssignEquipmentController` (`:60-150`) | web Dispatch, Schedules, Schedule Assignment, Schedule Conflicts, Order Details (`routes/admin/order_management/schedules/routes.php:14`) | `hasBeenDelivered()` before and inside the row lock | **On My Way is not delivered ⇒ a web reassignment of an en-route truck is accepted**; only Arrived refuses (`OrderDetailsEquipmentReassignmentTest::test_a_driver_arrival_signal_alone_locks_the_assignment`) |
| `Admin\OrderManagement\Orders\AssignEquipmentController` (`:30-190`) | Order Details "Assign Equipment" + admin override completion (`orders/routes.php:67`) | hard assignment set; rented unit | completes the delivery **with the chosen unit** through `completeDelivery()` without `requireCurrentAssignment` ⇒ an en-route/arrived line can be completed with a different unit |
| `Admin\OrderManagement\Orders\RemoveEquipmentController` (`:25-70`) | Order Details "Remove Equipment" (`orders/routes.php:68`) | `RentalFulfillmentService::assertEquipmentChangeAllowed` = `hasBeenDelivered()` | On My Way ⇒ the reservation of an en-route unit can be deleted |
| `AutoAssignDirectService::doAssign` (`:119-135`) | checkout; `OrderProductObserver::updated` when `delivery_date` changes and nothing is assigned (`app/Observers/OrderProductObserver.php:28-60`, `125-160`) | none beyond "nothing assigned" | a departed line with no unit (exception state) can be auto-assigned |
| `Orders\UpdateProductScheduleController` Reschedule branch (`:265-330`) / Pending branch (`:354-359`) | admin Order Details status change | `$wasCompleted` refuses Reschedule of a completed line | recall paths (see RC10), not ordinary writers |
| `RentalFulfillmentService::completeDelivery` (soft→hard, `:93-160`) / `reopenDelivery` (hard→soft + trip reset, `:225-300`) | every completion / the canonical Completed→Pending reset | `requireCurrentAssignment` only for checklist writers | completion is the intended end of the lock; reopen is a recall |
| `CustomerChecklists\RemoveController` (`:70-100`), `Dispatch\ReorderController` (`:425-445`), `OrderProduct` cascade | checklist removal; driver reassignment away from an en-route driver; order deletion | — | recall paths |

Availability acknowledgements already refuse In Transit and delivered (`QueueLineAvailabilityService::assertAcknowledgeable`, `:381-407`), but through the same two predicates.

**RC10 — No recall path clears `delivery_is_arrived`.**
It is set only by `DriverChecklistController` (`:166`, `:181`, `:192`) and cleared by nothing: `reopenDelivery` clears `delivery_is_delivered`, `delivery_arrived_at`, the status and the departure stamps (`RentalFulfillmentService.php:271-284`) but not `delivery_is_arrived`; `SyncOnScheduleUpdate::resetDeliveryTripState` clears only the status and the departure stamps (`app/Listeners/QueueLine/SyncOnScheduleUpdate.php:100-107`); `Dispatch\ReorderController` the same, and only for On My Way (`:430-437`); `CustomerChecklists\RemoveController` clears everything except `delivery_is_arrived` (`:70-90`). The dispatch feed's `is_arrived` therefore stays true after a legitimate recall until the next On My Way, and the phone's stage derivation reads it (`DriverStagePresentation.serverState`, `DispatchOfflineRowAdapter.swift:28-31`). Under D4 (Arrived ⇒ Main Order) that would resume a recalled delivery at Main Order. A Reschedule of an Arrived truck also leaves `hasBeenDelivered()` true.

### 2.3 Duplicate or contradictory workflow state (inventory)

| # | Fact | Store A | Store B | Store C | Contradiction / risk |
|---|---|---|---|---|---|
| S1 | Trip stage (not started / On My Way / Arrived) | Engine ops `driver_checklist.update` with `equipment_driver_status` (durable, product × leg) | Server row `delivery_*_at`, `delivery_is_arrived`, `delivery_is_delivered` | Dispatch list's in-memory/persisted row copy mutated by `data_updateInCurrentDic` (sets `is_arrived`, `is_delivered = true`, `ready_to_go_at`; `DispatchListViewController.swift:1742-1760`, persisted at `1178-1187`) | A and B are reconciled by `DriverStageOverlay.effective` (`EffectiveFieldState.swift:342-369`) — the good pattern. C is a third, screen-owned copy that also renames `delivery_is_delivered` to `is_delivered` on the checklist block (`DispatchRowFields.php:111`), the same key the row uses for "leg delivered" (`:212`). B is never fully reset on recall (RC10). |
| S2 | Driver mini-checklist answers (call, ticks, fuel, keys) | UserDefaults `driverChecklist_v2_<product>_<leg>` (`DriverChecklistLocalState.swift:84-86`) | Server `delivery_call_customer`, `_equipment_fuel`, `_equipment_key_location`, `dispatch_checklist.driver.delivery.checks` | Engine op payloads | Restore = local first, else server (`DriverChecklistViewController.swift:1015-1069`). No unit identity on any copy: fuel/keys survive an equipment change, on this phone and on any other phone that restores from the server. |
| S3 | Assembly stage | Server `lifecycle_stage` (Arrived ⇒ `equipment_delivered`) | `QueueLineLocalOverlay` (`in_transit` from On My Way; `completed` only from `delivery_checklist.complete`; `QueueLineOperations.swift:183-253`) | — | **Online and offline disagree after Arrived** (RC6): server says delivered, phone says in transit. |
| S4 | "Delivery checklist done" | Engine evidence, product-scoped (`EffectiveFieldState.legSatisfied`) | MMKV marker `kCheckListOrderDetailsData_<Delivery/Return>_<orderUID>` written on Submit (`CheckListUpdateViewController.swift:570`), **order-scoped**, removed only by the legacy upload callback (`AppDelegate.swift:816-819`) | Server `is_delivered` (row) — and `checkCheckListStatus` reads only the **first** product (`OrderDetailsViewController.swift:680-688`) | A multi-line order reads every line as completed once one is submitted; with the Sync Engine the marker is never cleared. Order List keeps its own copy of the same function (`OrderListViewController.swift:1354-1376`). |
| S5 | Pending (prepared) draft | MMKV `kPendingCheckList_<type>_<orderUID>` (order-scoped, `CheckListFile.swift:20-60`) | Server execution `prepared` + `prepared_answers` | Engine `delivery_checklist.prepare` ops | Draft paints the Order Details tile amber separately from the evaluator (`OrderDetailsViewController.swift:587-603`). |
| S6 | Fuel | Driver Checklist "2. Fuel" Full/Not Full → `delivery_equipment_fuel` (defaulted, never blocks) | Equipment checklist fuel row → `fuel_initial_reading` (`CheckListViewController.swift:2695-2714`) | `QueueLineFuelVerification` ledger + `QueueFuelVerificationService` (episode-bound; **no callers** in `app/Http`, Livewire, routes; board endpoints retired 2026-09) | Three representations; none gates departure. **Resolved by D2:** the Driver Checklist answer is canonical for departure; the ledger stays retired; the checklist row stays a customer-site reading. |
| S7 | Keys | Driver Checklist keys segment (defaulted) | `QueueLineKeyConfirmation` model (no callers) | — | **Resolved by D11:** the Driver Checklist answer is canonical and mandatory where the unit has a physical key. |
| S8 | Delivery media requirement | Order Details: any photo or video, any product, any cycle, for the order (`LegCompletionRequirements.swift:219-221`, `235-243`) | Checklist smart route: a **video** for **this product** in the **current cycle** (`CheckListViewController.swift:798-838`, `EffectiveFieldState.deliveryVideoSatisfied`) | Media captured from Order Details carries no execution id (`OrderDetailsViewController.swift:1253-1277`) | Order Details can say "media done" while the checklist says "video missing". **Resolved by D7.** |
| S9 | Navigation origin | `ChecklistEntry.Origin` (`kind`, `selectIndex`, `fromCheckListScreen`) | Per-screen booleans: `isQueueLine`, `isOrderDetailsView`, `fromCheckListScreen`, `isOrderScreen`, `returnedToReview`, `completionLeg` | Stack inspection (`returnToReview`, `.first(where:)` pops that may skip Order Details when an Orders list sits beneath) | Destination depends on which screens happen to be on the stack, not on the workflow stage. |
| S10 | Terms Exempt | Tile greyed on `terms_status == "Exempt"` (`OrderDetailsViewController.swift:534-538`) | Handler returns on `status == "Exempt"` (`:980`) | — | Different fields (pre-existing nit). |

S1–S3, S6, S7, S8 and S9 are what this design resolves. S4, S5 and S10 are pre-existing; the design stops *depending* on them for routing and leaves their other uses alone (§17).

---

## 3. Canonical state and ownership model

### 3.1 Vocabulary

- **Mission** = `order_product_unique_id × leg` (Delivery here). Unchanged from the offline design.
- **Assignment episode** = one live `equipment_soft_assigns` row (hard `equipment_id` after delivery). Every writer delete-then-creates, so a change of unit — even back to the same unit — is a new episode (`EquipmentReassignmentService.php:135-140`; also the web `Schedules\AssignEquipmentController`).
- **Preparation cycle** = one `order_product_checklist_executions` row (`UNIQUE(order_product_id, leg, cycle)`); a unit change supersedes a prepared cycle (`ChecklistPreparationReset::supersede`) and the next context request mints the next one.
- **Confirmation (Available)** = one append-only `queue_line_availability_acknowledgements` row for a unit (`subject_type = unit`, keyed by the **episode id** and the equipment unique id) or an ordered option (`subject_type = option`, keyed by the frozen option key, no episode). Only a unit row whose episode equals the live episode counts (`QueueLineAvailabilityService::currentMap`, `:195-203`).
- **Effective trip state** = the driver's trip stage for the mission as the phone derives it (`DriverStageOverlay.effective`: durable local step ∨ server row) and as the server stores it (`delivery_equipment_driver_status`, `delivery_is_arrived`). **Departed** = On My Way or Arrived.
- **Departure lock** = the rule that the assignment episode of a departed, not-yet-completed Delivery cannot be changed by any ordinary writer (§3.4).
- **Trip recall** = an authorized office workflow that returns a departed Delivery to a pre-departure trip state (§3.4.4).

### 3.2 Ownership (who writes, who derives)

| Fact | Canonical owner (server) | Phone durable record | Derived on the phone by | Screen state allowed |
|---|---|---|---|---|
| Unit assignment | `equipment_soft_assigns` via `EquipmentReassignmentService` (mobile) and the web writers in RC9, all under `DeliveryDepartureLock` | `queue_line.switch_equipment` op (retained) | `AssemblyPolicy.effectiveEquipment` (feed unit overlaid by the phone's own switch) | none |
| Unit / option Available | acknowledgements ledger, under the lock | `queue_line.availability` op | `AssemblyPolicy.unitState/optionState` (episode-aware: a decision counts only for the unit it named) | none |
| Assembly gate (GO/STOP) | derived server-side (`gateFor`), never stored | — | `AssemblyPolicy.gate` over the cached review + overlays | none |
| Trip stage | `delivery_equipment_driver_status`, `delivery_*_at`, `delivery_is_arrived` via `driver-checklist`; cleared only by the shared recall (§3.4.4) | `driver_checklist.update` ops | `DriverStageOverlay.effective` | none (Dispatch's row copy becomes display-only) |
| **Departure lock** | `DeliveryDepartureLock::isDeparted(row)` = status ∈ {On My Way, Arrived} ∨ `delivery_is_arrived` (§3.4.2) | the same ops | `DeliveryWorkflowStage >= .onMyWay` | none |
| Mini-checklist answers | `delivery_call_customer`, `_equipment_fuel`, `_equipment_key_location`, `dispatch_checklist.driver.<leg>.{checks, equipment_unique_id}` (D5) | UserDefaults v2 state incl. `equipmentUniqueId` (+ partial-save ops) | restore local-first, unit-checked (§7.3) | the controls themselves |
| Checklist cycle + answers | executions | `*_checklist.prepare/complete/reset` ops, `ChecklistContextStore` | `ChecklistContextFallbackPolicy`, `EffectiveFieldState` | draft (existing) |
| Media | `order_media` anchored to the execution | `delivery_media.upload` ops | one `MediaRequirementPolicy` over `EffectiveFieldState.deliveryVideoSatisfied` (D7) | none |
| Terms | order terms status / signed record | `terms.sign` / `terms.accept` ops | `EffectiveFieldState.termsSatisfied` | none |
| Leg completion | `is_delivered` / status Completed | `delivery_checklist.complete` op | `EffectiveFieldState.legSatisfied` | none |
| **Delivery workflow stage** | — (never stored anywhere) | — | **`DeliveryWorkflowStage.resolve` (new, pure, Sync Core)** | none |

Rule: **no screen may hold a workflow flag that another screen reads.** Booleans that today decide destinations (S9) become inputs to one router (§10) or disappear.

### 3.3 `DeliveryWorkflowStage` (the one derivation)

```swift
enum DeliveryWorkflowStage: Int, Comparable {
    case assemblyReview     // gate STOP, or nothing durable yet for this driver
    case driverChecklist    // gate GO and the driver has durable mini-checklist evidence
    case onMyWay
    case arrived
    case delivered
}

struct DeliveryWorkflowInputs {
    let legCompleted: Bool                         // EffectiveFieldState.legSatisfied (server ∨ complete op)
    let trip: DriverTripStage                      // DriverStageOverlay.effective(…).stage
    let assemblyGate: AssemblyPolicy.LocalGate?    // nil = no review on this phone (see §6.4)
    let hasDriverChecklistEvidence: Bool           // §3.3.1
}

static func resolve(_ i: DeliveryWorkflowInputs) -> DeliveryWorkflowStage {
    if i.legCompleted { return .delivered }
    if i.trip == .arrived { return .arrived }
    if i.trip == .onMyWay { return .onMyWay }
    guard let gate = i.assemblyGate, gate.ready else { return .assemblyReview }
    return i.hasDriverChecklistEvidence ? .driverChecklist : .assemblyReview
}
```

Precedence is physical truth first (delivered > arrived > on my way), then the yard gate, then the driver's own progress.

**Invariant (locked):** once the effective stage is On My Way or Arrived, a stale or later assembly STOP **never rewinds** the driver. The assignment is locked (§3.4) and the driver continues at the physical trip stage. The only way back before On My Way is a trip recall (§3.4.4), which the phone sees as the server row no longer departed, observed after its local step (existing `serverObservedAt` rule).

**3.3.1 "Driver checklist evidence"** (what makes a second Start Delivery skip the review): any of
- a `DriverChecklistLocalState` record under the v2 key for this product × leg (the Driver Checklist writes one when it is first shown through the driver road — see §4 step 5 — and on every mutation today);
- a retained `driver_checklist.update` op for this product × leg (partial or transition);
- server mini-checklist state on the row (`driver_checks`, `call_customer`, `equipment_fuel`, `equipment_key_location`, `equipment_unique_id`) — present, not merely non-default.

All three exist today (the last gains one field under D5); none is new. This satisfies "first start goes through the review" and "do not restart from the review every time" without a new store. Cost: a driver who taps Continue, enters nothing, and force-quits before Screen 2 wrote its record sees the review once more (GO, one tap). Acceptable.

**3.3.2 Arrived on the server is trusted only when it is whole.** `DriverStagePresentation.serverState` reads arrived as `is_arrived && arrived_at present`. With the shared recall clearing both (§3.4.4) this is belt-and-braces against RC10-style partial resets on rows written before this change.

### 3.4 Canonical equipment assignment and the departure lock (core invariant)

> For one active mission there is exactly one live assignment episode. Queue Line Assembly Review, the driver's Assembly Review, the Driver Checklist display and the equipment checklist all reflect that episode (feed unit overlaid by this phone's own unacknowledged switch) and change it only through a writer that honors the departure lock. **From the instant On My Way is the effective trip state until the delivery is completed or the office recalls the trip, the episode is locked.**

**3.4.1 Before departure** (effective stage < On My Way):
- the unit may be assigned or switched by the permitted preparation surfaces: Assembly Review (yard or driver origin), the equipment checklist's picker, the web assignment pages;
- Available may be confirmed or reversed; options confirmed;
- preparation Reset / Start Over may occur where the existing pre-departure policy permits it;
- every reassignment creates the canonical new episode ⇒ the prior unit's Available no longer counts (server: episode key; phone: `unitKey(equipmentUniqueId)` decisions + `fromLocalSwitch` ⇒ unconfirmed, `AssemblyReview.swift:797-807`) ⇒ unit-specific state is invalidated per the existing cycle rules (supersede; `supersededExecutionIds` / `lastDiscardAt`) ⇒ Fuel and Keys return to unanswered (§7.3) ⇒ the replacement must be confirmed Available before departure.

**3.4.2 The lock point and its predicate.** The server predicate is explicit and never derived from the Queue Line or delivery shortcuts:

```php
DeliveryDepartureLock::isDeparted(OrderProduct $row): bool
    = $row->delivery_equipment_driver_status ∈ { On My Way, Arrived }
      || (bool) $row->delivery_is_arrived
```

It deliberately does **not** consult `isInTransitForDelivery()` (false after Arrived) or `hasBeenDelivered()` (true for reasons that have nothing to do with the trip). Both On My Way and Arrived are covered by name. After the signed completion the row keeps its Arrived status, so the lock stays engaged; the existing "delivered" guards (hard assignment, Q&A rows, `hasBeenDelivered()`) also apply and are untouched.

On the phone the same lock is `DeliveryWorkflowStage >= .onMyWay` (derived from the durable On My Way / Arrived steps ∨ the server row), so an offline phone locks the moment it records On My Way, before the server knows.

**3.4.3 While locked** (On My Way or Arrived, not completed, not recalled):
- no ordinary equipment Assign, no Switch / Substitution, no preparation Reset / Start Over that would change the episode, no Available / Not Available change — refused by one shared server guard (`DeliveryDepartureLock::assertAssignmentMutable`, code `DELIVERY_DEPARTED`, 409 on the mobile envelope) invoked by **every** writer in RC9 (§3.4.5), and hidden or disabled on every mobile surface (§6, §11, §10.2);
- Assembly Review is read-only (§11);
- the customer-site equipment checklist documents the locked unit and exposes no functioning reassignment or restart action (§10.2);
- completion of the delivery is permitted only for the locked unit: `completeDelivery()` refuses an explicit unit that is not the live assignment whenever the lock is engaged (a lock-aware form of the existing `requireCurrentAssignment`). A departed line with **no** unit at all (an exception state reachable only by web/legacy departures, never by this flow) may still be completed with the submitted unit, as today.

If somebody discovers at the customer site that the physical machine is wrong, that is an operational exception handled by the office (a trip recall, §3.4.4), not a late reassignment.

**3.4.4 Legitimate trip recall** (releases the lock). The unit is never permanently immutable because On My Way once occurred. The existing recall workflows remain the only unlock, and each of them clears the **whole** trip set through one shared helper (`DeliveryDepartureLock::recall` / `recallFields()`): `delivery_equipment_driver_status`, `delivery_on_my_way_at`, `delivery_ready_to_go_at`, `delivery_arrived_at`, `delivery_is_arrived`, `delivery_is_delivered` — fixing RC10:
- `RentalFulfillmentService::reopenDelivery` (Completed → Pending, from Order Details or `dispatch/update-status`);
- `CustomerChecklists\RemoveController` (removing the checklist);
- `Orders\UpdateProductScheduleController` Reschedule branch, together with `SyncOnScheduleUpdate::resetDeliveryTripState` (Reschedule / Completed→Pending requeue). **Implementation finding (2026-09-27, Task 4 review):** the web schedule editor's pre-existing reversal rule counts the driver's Arrived as completion (`delivery_is_delivered` is set by Arrived), so Reschedule is accepted at On My Way but refused at Arrived (422), and the API status doors cannot send Reschedule at all. The recall for an Arrived, not-yet-completed truck is therefore **Delivery Status → Pending** — the canonical `reopenDelivery`, offered by all three status doors — after which Reschedule is free (see A3);
- `Dispatch\ReorderController` (reassigning a delivery away from an en-route driver — On My Way only, as today; an Arrived truck is not recalled by a driver change. The other driver-reassignment doors — the schedule editor's driver field, the API assign-driver endpoint, draft publish, AI apply — leave the truck On My Way under the new driver, so the lock simply stays engaged).

After a recall: the lock is off; `DeliveryWorkflowStage` resolves to `.assemblyReview` or `.driverChecklist` (§3.3); the assignment can be corrected; the current unit must be confirmed Available again if its episode changed; the Driver Checklist prerequisites apply again before another On My Way. The Reschedule branch also clears the arrival latches (a stale `delivery_is_arrived` on an On My Way line), and the Queue Line listener releases a completion latch written by the driver's Arrived on the Pending reopen **once the row is no longer departed** — otherwise the replacement unit could never be confirmed Available again (rule 7 of §3.5) and the yard would still see "Equipment Delivered"; a truck still on the road keeps its latch. Small, deliberate behavior changes (D9); the latch write at Arrived itself is untouched (D6).

**3.4.5 Every writer honors the lock** (D10). The enforcement is one shared guard, not a copied test per controller:

| Writer | How it honors the lock |
|---|---|
| `ChecklistPreparationReset::assertResettable` (⇒ `EquipmentReassignmentService::switch`, mobile Switch, Livewire Board switch, mobile Reset) | calls `assertAssignmentMutable`; the old `isInTransitForDelivery()` branch is replaced by it |
| `Schedules\AssignEquipmentController` (web Dispatch, Schedules, Schedule Assignment, Schedule Conflicts, Order Details) | calls `assertAssignmentMutable` before the transaction and again on the row re-read under lock; 409 JSON with the lock message |
| `Orders\AssignEquipmentController` (assign-and-complete / admin override) | calls the guard **at the top, before its own `softAssignment()->delete()` and checklist-row writes**, whenever the chosen unit differs from the live assignment (that controller runs those writes outside any outer transaction, so a later refusal would strand the line without a unit); the lock-aware `completeDelivery` rule is the backstop; the same unit still completes |
| `Orders\RemoveEquipmentController` | via `RentalFulfillmentService::assertEquipmentChangeAllowed`, which calls the guard |
| `AutoAssignDirectService::doAssign` | returns `skipped` when departed |
| `QueueLineAvailabilityService::assertAcknowledgeable` | calls the guard (replaces its `isInTransitForDelivery()` branch; keeps the delivered branch) |
| recall paths (§3.4.4) | are not ordinary writers; they release the lock through the shared helper before or as they change the assignment |
| `RentalFulfillmentService::completeDelivery` | the intended end of the lock: soft→hard for the locked unit |

A writer-inventory test pins the set of files that write `equipment_soft_assigns` (create/delete), so a future writer fails the suite until it is added to the inventory and to the lock tests (§15).

**3.4.6 Offline FIFO and the lock.** The phone's Sync Engine sends operations that share an ordering key (the order product) strictly in capture order (`SyncOperation.orderingKey`, `SyncEngine.nextEligible`: only the earliest **pending** op per key is eligible). A switch, an availability confirmation and an On My Way captured offline in that order therefore reach the server as `switch → availability → On My Way`; the server is not yet departed when the switch and the confirmation arrive, so the lock cannot refuse them, and the departure is recorded afterwards. A **parked** (Needs Attention) op is not pending and does not block the ops behind it: a switch the server refuses (e.g. the office reassigned meanwhile) parks, the availability then fails `QUEUE_ASSIGNMENT_CHANGED` and parks, and the On My Way is still recorded (D1). The mismatch is an operational exception surfaced on the Sync Issues board, never a lost departure. §15 pins both orders with a backend test and a core test.

### 3.5 Available confirmation and invalidation rules

1. **Available** = "I physically verified this exact, currently assigned unit is present, correct and prepared for this delivery." It is per unit per episode. Options are per frozen option (they survive a unit change).
2. **A unit change never completes anything.** The replacement starts unconfirmed on every surface (server: new episode; phone: `unitState` returns nil for a `fromLocalSwitch` unit until a decision names it). The gate returns to STOP until the new unit is confirmed. Required sequence: `old assignment → switch → new episode → old confirmation invalid → replacement unconfirmed → employee taps Available → Assembly GO`.
3. **A unit change never inherits** the old unit's Available, its Fuel answer, its Keys answer, or the unit-specific checklist context / answers / media the existing cycle rules supersede.
4. **Who may confirm**: the yard technician or the driver, on either Assembly Review entry, with the signed-in employee as `performed_by` (P4-D5). The driver's confirmation is the same op and the same ledger row as the yard's.
5. **When a confirmation stops being possible**: once departed (the lock, §3.4) or delivered. Unchanged in effect (O1 stays), now stated through the one predicate.
6. **Not Available** reverses (append-only) and, on a staged line, unstages it. Unchanged.
7. **After a recall** the current unit must be confirmed again only if its episode changed (a recall that keeps the same reservation keeps its Available); the Driver Checklist prerequisites always apply again.

---

## 4. First-start flow (complete)

Preconditions: the mission is on the Dispatch card with a driver assigned; Phase 4 has bridged its package (context + order details + assembly + terms) or the phone is online.

1. **Dispatch → Start Delivery.** `DispatchListViewController` resolves `DeliveryWorkflowStage` for the row (inputs from the engine snapshot, the presented row, the cached review, the v2 key). First start ⇒ `.assemblyReview`.
2. **Assembly Review (driver origin).** Opened by `ChecklistEntry.openAssemblyReview(… origin: .driver(mission, enteredFrom: .assemblyReview))` focused on the mission's member (`focusOrderProductUniqueId`), showing the member's assembly (the whole dependent assembly when the line is a base or child). Same screen, same cache-then-fetch, same overlays, same Available / Assign / Change controls.
   - Primary action for this origin: **"Continue to Driver Checklist"**, enabled only when `AssemblyPolicy.gate(for: group).ready` (every required unit/option Available, members that left the yard excluded). The equipment "Continue to Checklist" button is **not** shown for the driver origin.
   - Changing the unit: existing `changeEquipment` (candidates → picker → confirmation → reason → `queue_line.switch_equipment`), plus the offline candidate source (§6.3). After a change the row shows the replacement unconfirmed and the gate is STOP.
   - No unit assigned: the existing Assign row; the gate is STOP until assigned and confirmed.
3. **Continue to Driver Checklist** pushes `DriverChecklistViewController` (the review stays beneath, so Back returns to it).
4. **Driver Checklist** shows the effective unit identity ("Name · #TAG"), the call section with **no** preselected outcome, the fuel and keys segments with **no** preselected answer where the unit requires them (§7), **Review Assembly** (§11) and Load Map & Go, disabled until §7.2's gate is met.
5. On first appearance through the driver road the screen persists its state record (§3.3.1), so the next Start Delivery resumes here.
6. **Load Map & Go** (§8): records On My Way locally — the assignment locks — opens Maps when service exists, shows the trip status; Kabba stays on Screen 2 in the On My Way state.
7. **Arrived** (§9): records Arrived locally and pushes **Main Order**.
8. **Main Order** (§10): License → Terms → Equipment Checklist → Video in any order the driver chooses, each returning to Main Order or to the next missing step; Review Assembly (read-only) from the header; then **Complete Delivery** (existing gate + override screen), which pops to Dispatch.

Yard entries are unchanged: Queue Line card / Orders list / Order Details **before departure** still open Assembly Review with "Continue to Checklist", and the checklist's Save/Submit/Video still return to that review (the preparation workflow).

---

## 5. Resume flow (complete)

Every Start Delivery (and every reopen after a force-quit, relaunch, or app update) runs the same resolution. There is no "resume mode"; the stage *is* the resume point.

| Effective stage | Start Delivery opens | Notes |
|---|---|---|
| `.assemblyReview` (STOP, or no evidence) | Assembly Review (driver origin) | Includes "yard confirmed everything, driver never opened Screen 2" (GO, one tap), "a switch or Not Available put it back to STOP before departure" (re-confirm; call answers kept, fuel/keys reset if the unit changed) and "the office recalled the trip" (§3.4.4). |
| `.driverChecklist` | Driver Checklist, restored | Existing restore (local first, else server), unit-checked (§7.3). The review is not pushed beneath it; **Review Assembly** on Screen 2 covers the revisit (§11). |
| `.onMyWay` | Driver Checklist in the On My Way state (Arrived button) | Existing `getReadyToGo_ArrivedStatus` behavior. Review Assembly available, read-only. A STOP arriving now (e.g. the review re-fetch shows a web change) changes nothing: the lock holds and the driver continues. |
| `.arrived` | **Main Order** directly (D4) | The old Arrived/Continue screen is not shown again. Back from Main Order goes to Dispatch (existing). |
| `.delivered` | Nothing — the card leaves the working list (existing `CompletionOverlay`) | The Completed tab's card opens the read-only finalized checklist as today. |

Rules:
- Local durable evidence outranks the row's server copy exactly as today (`DriverStageOverlay`, `serverObservedAt`). A recalled trip is honored only when a row observed after the confirmation shows it (existing rule).
- Resume never replays a transition: On My Way and Arrived are recorded once (`recordsDeparture` / `recordsArrival`, existing).
- No stage ≥ On My Way is ever routed to the yard gate. `DeliveryWorkflowRouting.destination(for:)` is total over the enum and pinned by test.
- The Dispatch card label stays as it is (D12); a stage-aware label is allowed only if it falls out of the routing work at no cost.

`DriverChecklistRouting` is replaced by `DeliveryWorkflowRouting.destination(for stage:)`, and the test that pins "every combination routes to the Driver Checklist" (`DriverChecklistLocalStateTests.testEveryPriorStateCombinationRoutesToTheDriverChecklist`) is replaced by the matrix in §15. This reverses the 2026-09 "routing is absolute" rule deliberately: that rule existed because the old shortcut trusted a stale server `is_arrived`; the new routing trusts the *effective* stage, which is the local-first derivation that same correction introduced, with the RC10 fix and §3.3.2 closing the stale-`is_arrived` case.

---

## 6. Assembly Review as the driver's first gate

### 6.1 One screen, two roles

`ChecklistEntry.Origin.Kind` gains `.driver(orderProductUniqueId, enteredFrom: DeliveryWorkflowStage, isRevisit: Bool)`. The review's rendering differs only in the forward action and in what the lock allows:

| Origin | Forward action | Enabled when | Rows and unit change |
|---|---|---|---|
| `.queueLine`, `.orderList`, `.orderDetails` (yard, pre-departure) | Continue to Checklist (equipment) | gate GO (existing) | editable while `!hasLeftTheYard` (existing) |
| `.driver`, first start / STOP (stage `.assemblyReview`) | **Continue to Driver Checklist** (push) | gate GO | editable; change/assign through the canonical switch |
| `.driver`, revisit from Screen 2 before departure (stage `.driverChecklist`) | **Back to Driver Checklist** (pop) | always | editable; a change puts the gate at STOP and Screen 2 disables Load Map & Go until re-confirmed |
| `.driver`, revisit after departure (stage ≥ `.onMyWay`, from Screen 2 or Main Order) | Back | always | **read-only**: rows disabled, no Assign / Change, the lock explanation on tap |

Read-only is decided by `AssemblyPolicy.driverReadOnly(stage:memberStage:)` = `stage >= .onMyWay || memberStage.hasLeftTheYard`: the phone's own durable On My Way locks the screen before the server knows, and the server's in-transit/delivered lifecycle still locks it when the phone has no local step (another phone departed).

### 6.2 What GO means for a multi-member assembly

The gate is the assembly's (`AssemblyPolicy.gate(for: group)`): every member's unit and every frozen option Available, members that left the yard excluded. The driver's mission is one member; the whole assembly must be confirmed because it travels together. Unchanged from the yard rule.

### 6.3 Offline

The review is bridged from the mission package (`assembly` section, delivery only — `DispatchOfflineFieldBridge.swift:12`, `DispatchOfflineOrderBridge.swift:36-42`). Confirmations, reversals and switches are durable ops and render immediately from the overlays (existing). The candidates list for a switch is a live GET today (`AssemblyReviewViewController.swift:723-749`), so offline substitution from the review is not possible today. **Bounded design (locked):** when the candidates request fails offline, the review offers the warmed reference equipment list (`DispatchOfflineReferenceWarmup` already refreshes `equipment` and `categories`), scoped by the current unit's category, through the same picker; `PreparationPolicy.switchReasonRequired` decides the reason prompt (the rule the checklist picker already mirrors); the switch is recorded durably through the existing `queue_line.switch_equipment` op; the replacement must be confirmed Available before departure. **The phone warns clearly at switch time** when the replacement's customer-site checklist context is not cached (`ChecklistContextFallbackPolicy.canServeOffline` refuses a superseded cycle): the driver can depart and arrive, and the equipment checklist for the replacement waits for service. No preloading of every possible replacement's context is built to remove that edge.

### 6.4 No review on the phone

If the package had no `assembly` section (a pre-Phase-4 server, `notProvided`) or it failed and the phone is offline, `assemblyGate == nil` ⇒ `.assemblyReview` with the existing "Offline · no saved Assembly Review for this order yet. Reconnect and pull to refresh." note; Continue to Driver Checklist is disabled. Online, the fetch fills it. There is no silent bypass: the phone's gate is the only departure gate (D1), so it must not have a hole.

---

## 7. Driver Checklist: the final pre-departure gate

### 7.1 Requirements (locked)

| Requirement | Applies | Completed when | Store |
|---|---|---|---|
| Assembly Review GO | Delivery | the mission's assembly gate is GO as the phone knows it at tap time | derived (§3.3) |
| Call Customer | always (Delivery and Return) | **Delivery (Call Customer wizard, 2026-09-29):** the three guided steps are verified with the customer — **Delivery Address**, **Equipment Order** (product + Product Options; the former "attachments" tick), **Unloading Situation** (one of easy access / unload on street / alternate location / address inaccurate / other + note) — and **Confirmed is derived** from them (never tapped), **or No Answer** is recorded (explicit; clears the steps). **Return:** an explicit **Confirmed** with every required sub-check ticked, **or No Answer** (D3) | v2 local state (`address_verified`, `equipment_verified`, `unloading_situation`, `unloading_note`, `call_customer`; Return: `checks`) + `driver_checklist.update` (the same four keys, stored in `dispatch_checklist.driver.delivery`; the server derives `delivery_call_customer`; Return: `call_customer`, `driver_checks`) |
| Fuel | Delivery, when the current unit **requires fuel verification** | an **explicit** answer **Full / Ready** for **this unit**. **Not Full / Not Ready does not satisfy** (D2) | v2 local state (`fuel`, `equipmentUniqueId`) + `equipment_fuel` + `equipment_unique_id` (D5) |
| Keys | Delivery, when the current unit **requires key verification** | an **explicit** answer **With Machine** for **this unit**. Missing / not ready does not satisfy (D11) | v2 local state (`keys`, `equipmentUniqueId`) + `equipment_key_location` + `equipment_unique_id` (D5) |

"Requires fuel verification" = the unit's `requires_fuel_check` (server `Equipment::requiresFuelCheck()`: Diesel or Gas); "requires key verification" = `requires_key_check` (`requiresKeyCheck()`: 1 or 2 physical keys). Both are additive fields on the Dispatch row's equipment block and the offline `dispatch.equipment` block (D5); a cached package that predates them falls back to `is_fuel` / `is_key` (shown ⇒ required). If the unit requires neither, that requirement does not participate in the gate. A departed-then-recalled unit, or a replaced unit, starts unanswered.

**No required field may pass because a default was silently pre-populated:** the three controls have no preselected segment; an unanswered control is a blocker.

### 7.2 Gate expression (locked)

```
Load Map & Go enabled =
      Assembly Review GO                                     (Delivery only)
  AND Call Customer complete                                 (Delivery: all three wizard steps verified, or No Answer;
                                                              Return: Confirmed + all sub-checks, or No Answer)
  AND (Fuel not required  OR Fuel == Full/Ready  for the current unit)
  AND (Keys not required  OR Keys == With Machine for the current unit)
```

Return: Call Customer only. The button shows the first blocker as plain text, so the driver never guesses:
- "Confirm the assembly on Review Assembly before departing." (STOP)
- "Complete the customer call: verify the delivery address, the equipment order and the unloading situation — or record No Answer." (Delivery)
- "Record the customer call: Confirmed with every check, or No Answer." (Return)
- "Fuel is not ready. Equipment recorded as not fuel-ready must not leave the yard — fuel it, or choose a different unit on Review Assembly."
- "The key is not with the machine. Locate it and record With Machine before departing."

When the assembly gate goes STOP while the driver is on Screen 2 before departure (a web reassignment created a new episode; another phone reversed a confirmation), Load Map & Go is disabled and **Review Assembly** is highlighted with the gate's first blocker sentence. The phone learns of it from the review re-fetch (online) or from its own overlays (offline); Screen 2 recomputes on appear and on `.kabbaSyncQueueChanged`.

### 7.3 Fuel and keys are bound to the unit — on the phone and on the server (D5, D11)

- `DriverChecklistLocalState` gains `equipmentUniqueId`: the effective unit when the fuel/keys answers were given. `driver_checklist.update` carries `equipment_unique_id` (§7.4). The server stores it beside the ticks in `dispatch_checklist.driver.<leg>.equipment_unique_id` and the Dispatch row's checklist block returns it (live and offline).
- **Restore rule** (local copy first, else the server copy — on this phone or any other): if the recorded `equipment_unique_id` equals the current effective unit, Fuel/Keys restore normally; if it differs or is absent while a unit is assigned, Fuel and Keys return to **unanswered**; Call Customer's outcome and sub-checks restore regardless (they belong to the customer interaction). A fresh install or a reassigned driver therefore never inherits Fuel/Keys recorded for a replaced unit.
- The effective unit on Screen 2 = the row's equipment (hard ?? soft, as the feed resolves it) overlaid by this phone's own unacknowledged switch (`QueueLineLocalOverlay.pendingEquipment`).
- Server side, `equipment_unique_id` is stored as stated (validated to exist), never used to reject a departure (D1): a stale identity is an exception the office sees, not a lost trip.

### 7.4 The contract (additive, current-version-only)

`POST orders/schedules/driver-checklist` gains `equipment_unique_id` (nullable, must exist). Stored in the existing `dispatch_checklist` JSON beside `checks` (merged, web-board keys untouched), so no migration. `deliveryChecklist()` / `pickupChecklist()` gain `equipment_unique_id`; the Dispatch equipment blocks gain `requires_fuel_check` and `requires_key_check`. The offline package revision already hashes `dispatch.row`, so a changed identity invalidates the cached package. No legacy-client compatibility is kept (the fleet updates as one). Documented in `docs/mobile-integration/MOBILE_API_CONTRACT.md` and the shared fixtures.

### 7.5 Return leg

Same screen, no fuel/keys (`checklistType == "pickup"` hides them today), no assembly gate. Call Customer becomes explicit for Return too because it is the same control (§13).

---

## 8. Load Map & Go

Order of operations (the first two are unchanged in mechanism):

1. Guard: `recordsDeparture` (never twice) and the §7.2 gate, re-evaluated at tap time.
2. **Record On My Way locally**: `saveDriverChecklistLocally(… equipment_driver_status: "On My Way", equipment_unique_id: <effective unit> …)` → durable `driver_checklist.update` op; toast "Saved on this phone · Pending Sync → Synced"; the screen flips to the On My Way state; the Dispatch card's stage follows through the overlay. **The assignment is now locked on this phone** (`DeliveryWorkflowStage` ≥ `.onMyWay`), and on the server once the op lands. Identical online and offline.
3. **Navigation**:
   - **Online** (`NetworkReachabilityManager()?.isReachable == true`, the app's existing check): open the destination in Apple Maps, separately; Kabba remains on Screen 2 in the On My Way state. Today's helper geocodes first (`openAddressInMap`, `OrderDetailsViewController.swift:1639-1660`); a geocode failure is silent. The design keeps the helper but makes it report failure, so a failed geocode shows the same Service Offline state instead of nothing. (Implementation option: `maps://?daddr=<address>` needs no geocode on the phone; decided at implementation, not here.)
   - **Offline**: do not call Maps and never pretend it is available. Show the **Service Offline** state: an alert in the app's existing offline language (the amber "Offline · …" freshness lines and the sync toasts; there is no component literally named "Service Offline" today) reading: *"Service Offline — Navigation needs cellular or Wi-Fi service. Your On My Way status is saved on this phone and will sync automatically."* One button: OK. The map button stays, so the driver can retry Maps once service returns.
4. Nothing else changes: no second store, no blocking, no retry loop.

---

## 9. Driver Arrived → Main Order

Unchanged mechanics: `btnArrivedClicked` records Arrived (durable op, once, carrying `equipment_unique_id`) and `pushOrderDetails()` pushes `OrderDetailsViewController` with `fromCheckListScreen`, `completionLeg` and `strProductID` (`DriverChecklistViewController.swift:1113-1196`). Additions:

- Main Order is reached by this push or by the `.arrived` resume (§5). It never re-derives the leg from the feed (existing `completionLeg` rule).
- Main Order's header shows the trip status ("Arrived 04:51 PM"), the effective unit identity, and a **Review Assembly** action that opens the review read-only (§11).
- Back from Main Order → Dispatch (existing `OrderDetailsViewController.swift:194-211`).

Server side, Arrived keeps setting `delivery_is_delivered` and latching the Queue Line item (D6). The design does not change that; it removes every mobile dependency on `lifecycle_stage` after departure and it keeps the lock engaged (§3.4.2).

---

## 10. Customer-site routing matrix

### 10.1 The router

One pure function replaces stack inspection and the S9 booleans for the delivery leg:

```swift
enum CustomerSiteRoute { case mainOrder, video, checklist, assemblyReview }

static func afterStep(_ step: CustomerSiteStep,          // .license, .terms, .checklistPrepared, .checklistCompleted, .video
                      stage: DeliveryWorkflowStage,     // ≥ .onMyWay ⇒ the customer-site rules below
                      videoRequirementMet: Bool,        // §10.3
                      checklistComplete: Bool) -> CustomerSiteRoute
```

For `stage < .onMyWay` (yard) the router returns `.assemblyReview`, which means today's `returnToReview` rule with its fallbacks, untouched. "Go to X" means **pop to X if it is on the stack, else push it**, so the stack stays finite: Main Order → Checklist → Video → (pop) Checklist → Submit → (pop) Main Order.

### 10.2 The matrix (stage ≥ On My Way)

| Step completed | Today | Target |
|---|---|---|
| Add Driver License (saved / queued) | pop once, or `popToViewController(.first(where: OrderList ∨ OrderDetails))` (`LicenseUploadViewController.swift:263-284`, `LicenseTypeViewController.swift:233-240`) | **Main Order** (the instance that pushed it) |
| Sign Terms (signed on phone / hosted accepted) | pop once (`TermsAndConditionViewController.swift:182-195`, `303-341`) | **Main Order** |
| Equipment Checklist — Save (prepare) | Video if a delivery video is missing, else back to Assembly Review (`CheckListViewController.swift:708-727`, `755-768`) | Video if the video requirement is unmet, else **Main Order** |
| Equipment Checklist — Submit (complete) | back to Assembly Review, else Order Details / Orders (`CheckListUpdateViewController.swift:582-598`) | Video if unmet, else **Main Order** |
| Video / Photo upload | back to Assembly Review at Submit, else pop (`ImageUploadViewController.swift:367-403`, `511-527`) | **Checklist** if this product's checklist is not complete (durable complete op ∨ server), else **Main Order** |
| Complete Delivery | requirements met → Dispatch; else override screen → Dispatch (`OrderDetailsViewController.swift:1005-1059`) | unchanged |

Order Details' **CheckList Deliv** button, for stage ≥ On My Way, opens the equipment checklist **directly** (focused on the mission's product, with the existing context/draft restore) — never Assembly Review. That single change removes RC6. Before departure (Orders/Schedule entry at the yard) it keeps today's review sequencing. The same stage rule applies whichever screen reached Order Details.

**The locked unit on the customer-site checklist.** For stage ≥ On My Way the equipment checklist shows the locked unit's identity and offers **no** functioning reassignment or restart: `PreparationPolicy.block(for: context, tripStage:)` returns `.inTransit` from the phone's effective trip stage before it consults the cached context (whose `in_transit` may be stale offline), so the picker (`btnMachineIdClicked`), the "Delete Checklist / Start Over" footer and `EquipmentAssignmentFlow.Target.block` all refuse with the existing In Transit explanation. The one exception is a departed line with no unit at all (§3.4.3), where the checklist's "select a unit" path stays so completion remains possible. Checklist completion never returns to Assembly Review after departure; the review is available separately, read-only (§11).

Loop check: each hop consumes a requirement (Save → Video → Checklist(prepared, not complete) → Submit → Main Order; Submit → Video → complete ⇒ Main Order). Back always pops. No cycle can repeat without the driver choosing it.

### 10.3 One delivery-video requirement (D7)

**Delivery requires a video.** One `MediaRequirementPolicy` is used by the Order Details tiles, the Complete gate and the checklist's smart route: delivery media is satisfied when a **video** for **this product** in the **current cycle** exists (`EffectiveFieldState.deliveryVideoSatisfied` with the active execution id whenever it is known; server `delivery_video_present` for the cycle). Ordinary photos never satisfy it on their own. Order-scoped legacy evidence (a video op with no cycle id) counts only when no cycle is known for the product. Media captured from Main Order carries the active execution id (the Photo/Video buttons pass `checklistExecutionIds` like the checklist's smart route does), so it lands in the right cycle. Main Order and the checklist can no longer disagree.

### 10.4 "What remains" on Main Order

`LegCompletionEvaluator` stays the one evaluator for tiles and the Complete gate. Its checklist input drops the order-scoped marker (S4) in favor of the product-scoped effective state for the mission's product; its media input uses §10.3; the marker keeps its other legacy uses until removed separately (§17).

---

## 11. Review Assembly (manual revisit — always reachable while the Delivery is active, D8)

- **Where**: a visible **Review Assembly** action on the Driver Checklist in every state it shows (not started, On My Way) **and** on Main Order after Arrived (header action). It exists until the leg is delivered.
- **What it opens**: the same Assembly Review, origin `.driver(mission, enteredFrom: currentStage, isRevisit: true)`, focused on the mission's member.
- **Capabilities follow the stage** (server rules mirrored, nothing new):
  - **before departure** (stage < On My Way): operational — assign / change the unit through the canonical switch (the established reassignment path, including the offline candidate source of §6.3), confirm or reverse Available, confirm required options; a unit change invalidates the old unit's Available and the replacement must be explicitly confirmed; the gate goes STOP and Screen 2's Load Map & Go stays disabled until it is GO again;
  - **after departure** (On My Way or Arrived): **read-only** — the driver inspects the locked unit identity, the assembly, the options and the prior confirmations; rows disabled; no Assign / Change; no Available reversal; no preparation restart; tapping a disabled control shows the lock explanation.
- **Return**: Back (or "Back to Driver Checklist") pops to the screen it came from — Screen 2 or Main Order. It never re-runs Start Delivery, never re-records a transition, never clears the call answers (only fuel/keys reset if the unit changed before departure, §7.3). Entering it manually is never a rewind.
- **Nav guard**: one review at a time (existing `topViewController` check).

---

## 12. Offline / local-first behavior (preserved and extended)

| Capability | Status under this design |
|---|---|
| Local-first On My Way / Arrived (`driver_checklist.update`, `DriverStageOverlay`) | preserved; the stage derivation (§3.3) and the phone-side lock sit on top of it |
| Durable Sync Engine, per-order-product FIFO (`SyncOperation.orderingKey`, `nextEligible`) | preserved; a switch still precedes any availability, prepare or departure captured after it; a parked op never blocks the ops behind it (§3.4.6) |
| Cached mission package (context, order details, assembly, terms) | preserved; the assembly section now also serves the driver's first gate |
| Offline Order Details / Assembly Review / checklist context / Terms | preserved |
| Pending Sync / Synced / Needs Attention | preserved; a Needs Attention op still counts as durable workflow evidence (work stands) |
| order product × leg × cycle identity; substitution/reset invalidation; finalized-checklist immutability | preserved; the router only *reads* `EffectiveFieldState` |
| Offline availability confirmation / reversal | preserved (durable op, employee = signed-in user) |
| Offline unit substitution from Assembly Review, pre-departure | **new, bounded** (§6.3): warmed equipment list as candidates; durable op; replacement must be confirmed; explicit warning when the replacement's context needs service |
| Offline Load Map & Go | **new** behavior: On My Way recorded (locks), Service Offline state, no Maps call (§8) |
| Offline first start | works when the package is bridged (assembly present); otherwise the gate is honestly STOP with the existing offline note (§6.4) |
| Offline ordering guarantee | `switch → availability → On My Way` captured offline drains in that order and is accepted; the server lock cannot refuse the legitimate pre-departure work (§3.4.6, pinned by tests) |

No second workflow store: the only new persisted field is `equipmentUniqueId` inside the existing v2 mini-checklist record (and its server twin inside the existing `dispatch_checklist` JSON).

---

## 13. Delivery-only versus Return

The mission scopes the redesign to Delivery. Shared components force these Return touches, each listed for separate review:

| Change | Delivery | Return | Why Return is touched |
|---|---|---|---|
| Stage derivation + resume routing (§3.3, §5) | yes | yes (stages `driverChecklist / onMyWay / arrived / delivered`; no assembly gate) | same Dispatch button, same Screen 2; a Return that resumes at Arrived lands on Main Order too |
| Assembly Review gate (§6) | yes | **no** (Return has no Assembly Review; `notApplicable` in the bridge) | — |
| Explicit Call Customer, no default (§7.1) | yes | yes | same control |
| Fuel / keys gate, unit binding (§7) | yes | **no** (hidden today; must stay hidden) | — |
| Departure lock (§3.4) | yes | **no** (the Return leg has no assignment episode) | — |
| Load Map & Go offline state (§8) | yes | yes | same button |
| Customer-site router (§10) | yes | yes for the Return checklist / Return media exits (they pop to Order Details today, so the target is the same "Main Order" and the Video ↔ Checklist hop applies with the Return media rule) | shared checklist/media screens |
| Review Assembly (§11) | yes | no | — |

Nothing else in the Return workflow changes; a test pins that no Delivery-only Assembly / Fuel / Keys / lock rule leaks into Return (§15). The Return-specific product questions from Phase 6 (drifted Returns N1, online All fallback N2) are untouched.

---

## 14. Failure and recovery behavior

| Situation | Behavior |
|---|---|
| Leg reassigned on the web while the driver's steps were offline | server 409 `DISPATCH_ASSIGNMENT_CHANGED` → op parked Needs Attention, work stands (existing); the card leaves this driver's list on the next reconcile; the stage on this phone still shows the driver's evidence until then (existing rule). |
| Unit switched on the web while the driver is on Screen 2 **before** departure (new episode) | next review fetch (online) shows the replacement unconfirmed ⇒ STOP ⇒ Load Map & Go disabled, Review Assembly highlighted; fuel/keys reset for the new unit. Offline the phone cannot know until it reconnects; it departs on its last knowledge and the server records the departure (D1) — the office's change happened before the lock engaged on the server, so the FIFO-drained switch/availability from the phone may then be refused (`QUEUE_ASSIGNMENT_CHANGED`) and park as Needs Attention; the On My Way still records; the mismatch is resolved by the office. |
| Any writer tries to change the assignment while On My Way or Arrived | refused with `DELIVERY_DEPARTED` (mobile 409 / web 409 JSON / Livewire error / auto-assign skipped); the assignment is unchanged; the trip is unaffected. |
| Switch op rejected by the server (Needs Attention) | `pendingEquipment` is cleared for a rejected switch (`QueueLineOperations.swift:200-210`); the review reverts to the server's unit and its confirmation state; the gate recomputes; fuel/keys reset if the unit differs from the one they were answered for. |
| Availability op rejected | the row shows "Sync Issue" with the server's reason (existing overlay); the gate treats the subject as unconfirmed. |
| No assembly section on the phone, offline | STOP with the existing offline note; no bypass (§6.4). |
| Load Map & Go tapped offline | On My Way recorded (lock engaged on the phone); Service Offline state; retry Maps later from the map button. |
| Geocode failure online | same Service Offline state as offline (today: silent nothing). |
| Arrived synced, then the driver reopens Order Details → CheckList Deliv | opens the checklist directly (stage ≥ On My Way); the review is never consulted (RC6 closed). |
| The office recalls the trip (reopen, checklist removal, reschedule, driver reassignment away from an en-route driver) | the shared recall clears the whole trip set (RC10 closed); the lock releases; the phone, once it observes the recalled row after its local step, resolves the stage below On My Way and the driver re-enters at Assembly Review or the Driver Checklist; the current unit must be re-confirmed if its episode changed; prerequisites apply again. |
| Wrong physical machine discovered at the customer site | operational exception: the office recalls the trip; no late reassignment on the phone (§3.4.3). |
| Force-quit / relaunch at any point | resume table (§5); no transition replayed. |
| App update mid-delivery | the v2 key, the ops and the caches are all versioned stores that already survive updates; the stage is recomputed from them. |
| A row written before this change still has a stale `delivery_is_arrived` with no `arrived_at` | the phone reads it as not arrived (§3.3.2); the next recall or trip write normalizes it. |

---

## 15. Expected automated tests

**Mobile — Sync Core (`swift test`)**
- `DeliveryWorkflowStageTests`: the full input matrix (legCompleted × trip × gate GO/STOP/nil × evidence) → stage; precedence (departed trip beats STOP; delivered beats everything); a STOP after On My Way / Arrived never lowers the stage.
- `DeliveryWorkflowRoutingTests`: stage → destination, total over the enum; Arrived → Main Order; nothing ≥ On My Way routes to the review (replaces `testEveryPriorStateCombinationRoutesToTheDriverChecklist`).
- `DriverChecklistGateTests`: **Fuel Full/Ready required when the unit requires fuel; Fuel Not Ready keeps Load Map & Go disabled; unanswered fuel keeps it disabled; Keys required and valid (With Machine) when the unit requires keys; missing / unanswered keys keep it disabled**; Call Customer: unset blocks, Confirmed with a missing tick blocks, Confirmed with all ticks passes, No Answer passes; assembly STOP blocks Delivery only; **Return ignores fuel, keys and the assembly gate**; no default ever passes; blocker text order.
- `DriverChecklistLocalStateTests`: `equipmentUniqueId` round trip; **an equipment change resets Fuel + Keys but preserves Call Customer** (restore against a different unit, from the local copy and from a server-seeded copy); same unit restores fully; an absent identity with a unit assigned restores nothing for fuel/keys; the evidence rule counts a record with no answers.
- `EffectiveFieldStateTests`: `DriverStageServerState` arrived requires both flags; overlay unchanged otherwise.
- `PreparationLifecycleTests`: `block(for:tripStage:)` returns `.inTransit` at `.onMyWay` and `.arrived` regardless of the cached context; `mayRestartChecklist` false after departure; **the post-departure checklist exposes no usable reassignment action** (Target.block set).
- `AssemblyReviewTests`: `driverReadOnly` — **On My Way makes the review read-only; Arrived makes it read-only**; pre-departure editable; server `hasLeftTheYard` also locks; gate STOP after departure does not change the stage (input to §3.3 tests).
- `CustomerSiteRouterTests`: the §10.2 matrix, both stage bands (< On My Way keeps the review rule), the Video ↔ Checklist hop terminates; Return exits.
- `MediaRequirementPolicyTests`: video required; photos never satisfy; product + cycle scoping; legacy evidence only when no cycle is known; Order Details and the checklist route agree on every fixture.
- `LoadMapAndGoDecisionTests`: online → maps + status; offline → status + Service Offline; geocode failure → Service Offline; the departure op carries `equipment_unique_id`.
- `SyncEngineTests`: three ops on one order product (`switch`, `availability`, `driver_checklist.update` On My Way) drain in capture order; a parked switch does not block the On My Way behind it.
- Existing suites stay green: `AssemblyReviewTests`, `DispatchOfflineFieldBridgeTests`, `DispatchOfflineReconcilerTests`, `ChecklistFinalizationPresentationTests`, `LegCompletionEvaluatorTests`, `TermsSignOperationsTests`, `DispatchWorkloadTests`, `DispatchOfflineWorkingSetTests`, `QueueLineOperationTests`, contract fixture tests.

**Mobile — Hosted (`RentnKingHostedTests`)**
- Dispatch Start Delivery per stage with a stubbed engine snapshot (review / Screen 2 / Screen 2 On My Way / Main Order).
- Driver Checklist: no preselected call/fuel/keys; the unit header; the gate per §7.2; Review Assembly present in every state; Load Map & Go enqueues `equipment_unique_id`.
- Assembly Review driver origin: Continue to Driver Checklist only at GO; no equipment Continue; read-only at On My Way and Arrived (rows disabled, no Change/Assign); revisit pops back.
- **Main Order can open Review Assembly read-only** after Arrived; header shows trip status and unit.
- Order Details CheckList Deliv after Arrived opens `CheckListViewController`, not the review; before departure opens the review.
- Checklist after departure: picker and restart footer refuse; CLU Submit on the driver path pops to the pushing Order Details (not `.first(where:)`); Video hop when unmet; Video → Checklist when incomplete.
- Return: Start Return → Screen 2 shows no fuel/keys, no Review Assembly; call outcome explicit; exits land on Order Details.
- Extend `AssemblyReviewPresentationTests`, `DispatchOfflineRowAdapterTests` (`equipment_unique_id`, `requires_*` fields; the Dispatch row copy no longer written for stage).

**Backend (`php artisan test`, one directory at a time)**
- `DeliveryDepartureLockTest` (new): the predicate at each state (pending, ready to go, **On My Way**, **Arrived**, completed, recalled); **mobile Switch allowed pre-departure; Switch rejected On My Way; Switch rejected Arrived; Reset rejected On My Way; Reset rejected Arrived**; availability rejected On My Way and Arrived; **each known web assignment writer rejects/blocks reassignment On My Way and Arrived** — `Schedules\AssignEquipmentController` (all five pages post here), `Orders\AssignEquipmentController` with a different unit, `Orders\RemoveEquipmentController`, `AutoAssignDirectService` (skipped); the same unit still completes through `Orders\AssignEquipmentController`, `dispatch/update-status` and the mobile checklist completion; **an authorized legitimate trip reset back to pre-departure makes reassignment possible again** for every recall path (reopen, checklist removal, Reschedule, driver reassignment away from an en-route driver), and each clears all six trip fields incl. `delivery_is_arrived`; the lock is proven at Arrived with `hasBeenDelivered()` true and `isInTransitForDelivery()` false.
- `DeliveryDepartureLockWriterInventoryTest` (new): the set of `app/` files writing `equipment_soft_assigns` equals the audited inventory.
- **Offline ordering** (`DeliveryDepartureLockTest` or `ChecklistPreparationResetTest`): `switch → availability → driver-checklist On My Way` in that order, all with past `captured_at`, all accepted, assignment = replacement, no Needs Attention; then a further switch is refused; the reverse order (`On My Way → switch`) is refused for the switch only.
- `DriverChecklistPartialStateTest`: **`driver-checklist` accepts and restores the equipment identity for machine-specific Fuel/Keys state** — stored per leg beside the ticks, returned by the feed and the offline row, web-board keys untouched, absent field changes nothing, unknown id rejected (422).
- `MobileDispatchParityTest` / `DispatchContractFixturesTest` / `DispatchOfflineRowParityTest`: `equipment_unique_id`, `requires_fuel_check`, `requires_key_check` present live and offline; fixtures regenerated.
- Existing: `ChecklistPreparationResetTest::test_in_transit_refuses_both_substitution_and_restart` updated to the `DELIVERY_DEPARTED` code and joined by the Arrived twin; `OrderDetailsEquipmentReassignmentTest`, `EquipmentLockAndReopenTest`, `EquipmentAssignmentIndependenceTest`, `QueueLineAvailabilityTest`, `QueueLineGuardCoverageTest` green (the last still proves releases are not gated: D1).
- Regression gates from Phase 6 preflight: `tests/Feature/Dispatch`, `Api`, `Mobile`, `QueueLine`, `Terms`, `CustomerPortal`, `Orders` (baseline 23 known failures), `CustomerChecklists` (baseline 11), manifest budget ≤ 450 statements.

---

## 16. Physical acceptance scenarios (to append to the Phase 6 matrix after implementation)

Same rules as `docs/dispatch-offline-phase-6/PHYSICAL_ACCEPTANCE.md` (test server only, never the Login screen, evidence under `~/Documents/kabba-dispatch-offline-p6-evidence/`).

| # | Scenario | Pass condition |
|---|---|---|
| P1 | First start, online: Start Delivery → Assembly Review (STOP) → confirm unit + options → Continue to Driver Checklist → explicit call / Fuel Full / Keys With Machine → Load Map & Go (Maps opens, On My Way toast) → Arrived → Main Order → License → Terms → Checklist → Video → Complete Delivery | every hop lands as §4/§10 says; nothing preselected on Screen 2; server: On My Way, Arrived, completion, media, terms each once; `equipment_unique_id` stored |
| P2 | Resume at every stage: force-quit after (a) review GO, (b) Screen 2 with answers, (c) On My Way, (d) Arrived; reopen from Dispatch | (a) review once more then Screen 2; (b) Screen 2 restored; (c) Screen 2 On My Way; (d) **Main Order directly**; no transition replayed |
| P3 | Unit change in the driver's Assembly Review before departure (direct and non-direct match) | replacement unconfirmed, STOP, reason prompt only for non-direct; confirm → GO; Screen 2 Fuel and Keys unanswered, call kept; server new episode, old ack retired, cycle superseded |
| P4 | Review Assembly from Screen 2 before departure, change nothing, Back; then after On My Way (read-only); then from Main Order after Arrived (read-only) | returns to the same screen; no new ops; rows disabled after departure with the lock explanation |
| P5 | Fully offline first start (mission never opened online): review from the package → confirm → Screen 2 → Load Map & Go offline | Service Offline state; On My Way pending; all ops drain once on reconnect |
| P6 | **Offline ordering**: offline switch → confirm replacement Available → Load Map & Go → reconnect | drain order switch → availability → On My Way; all accepted, no Needs Attention; server assignment = replacement; the "context needs service" warning shown at switch time; after reconnect the replacement's context loads |
| P7 | **The RC6 trap, online**: Arrived (synced) → Main Order → CheckList Deliv | the checklist opens directly; the review is never shown; complete the checklist → Video → Main Order → Complete |
| P8 | Call outcomes (2026-09-29 wizard, P8-A…H in PHYSICAL_ACCEPTANCE): untouched; address only; address + equipment; all three → Confirmed derived; review pages; No Answer on a fresh mission; offline partial wizard across a force-quit; completed call across an equipment substitution | the first three stay disabled; the third step confirms by itself; reviews never clear it; No Answer enables (with the other requirements met) and the SMS is recorded once on the test server (outbound disabled); the offline steps survive and sync once each; the call survives the switch while fuel / keys follow the replacement |
| P9 | Fuel / Keys blockers: Not Full; Full + Missing; Full + With Machine; a unit that requires neither | only the third departs; the last shows neither control and departs on call alone |
| P10 | Web reassignment while the driver is on Screen 2 **before** departure (test-server admin surfaces) | after refresh: STOP, Load Map & Go disabled, Review Assembly highlighted; confirm the new unit → fuel/keys re-asked → GO |
| P11 | Return regression (M2-style): Start Return → Screen 2 (no fuel/keys/Review Assembly, explicit call) → Load Map & Go → Arrived → Main Order → Return checklist → Video → Complete | Return unchanged except explicit Call Customer and the Main Order returns |
| P12 | **Assignment lock after On My Way**: establish the assignment, confirm Available, satisfy call/fuel/keys, Load Map & Go; then attempt reassignment from every still-reachable mobile surface (Review Assembly from Screen 2, the checklist picker via Order Details, the Queue Line card, the Orders list) | every change is absent or refused; the canonical assignment is unchanged on the test server |
| P13 | **Assignment lock after Arrived**: repeat P12 from Main Order and its Review Assembly | same; Review Assembly reachable and read-only |
| P14 | **Web writer lock**: while the mission is On My Way, attempt reassignment from Dispatch, Order Details (assign, remove, assign-and-complete with a different unit), Schedules, Schedule Assignment and Schedule Conflicts on the test server; repeat at Arrived | each refused; assignment unchanged; assign-and-complete with the **same** unit still completes |
| P15 | **Legitimate recall** (approved test-server office reset): recall the trip to pre-departure; verify Assembly Review is operational again; change the assignment; confirm the replacement Available; answer fuel/keys; depart again | lock released; `is_arrived` cleared on the feed; the second On My Way recorded once |
| P16 | Yard regression: Queue Line card → Assembly Review → Continue to Checklist → Save → Video → back to the review | unchanged |

---

## 17. Scope boundaries

**In scope (this design → the implementation plan)**
- Mobile: `DeliveryWorkflowStage` + routing; Assembly Review driver origin and read-only lock mode; Driver Checklist explicit call/fuel/keys gate, unit binding, unit identity, Review Assembly; Main Order Review Assembly entry; Load Map & Go online/offline; customer-site router and Order Details post-departure checklist entry; checklist reassignment/restart disabled after departure; one delivery-video policy; offline candidates for the review; Dispatch row copy stops writing stage; the D5 client contract; tests in §15.
- Backend: the shared `DeliveryDepartureLock` guard and recall helper; every assignment writer in RC9 honoring it; availability under the same guard; the lock-aware completion rule; the D5 `driver-checklist` contract and the `requires_*` equipment fields; contract doc and fixtures; tests in §15.
- Docs: the physical acceptance additions (§16) after implementation.

**Out of scope (named so they are not silently pulled in)**
- A general refactor of the duplicate web assignment writers (routing them all through `EquipmentReassignmentService`); only the lock is shared.
- The Return workflow beyond §13.
- The Queue Line web board, its lanes and semantics (D6), and the Fast Track policy (D1).
- Reviving the fuel-verification / key-confirmation ledgers (S6/S7).
- Removing the order-scoped completed-checklist marker and draft (S4/S5) everywhere; only the router stops depending on them.
- The `MachineHoursViewController` (unreachable today) and `EquipmentPicker.swift` (commented out).
- Terms Exempt field mismatch (S10), the unbounded media save retry — recorded, not fixed here.
- The Phase 6 open items N1–N4, the deferred debug-login credentials and the Firebase-without-config wake crash.
- Any push, merge, deploy, flag, version/build, archive, upload, App Store Connect, Firebase production change or production contact.

---

## 18. Locked decisions and how they trace through the design

| # | Decision (locked) | Where it lands |
|---|---|---|
| D1 | The server stays non-restrictive for departure recording: the phone enforces the sequence; the server records On My Way / Arrived and never rejects a valid offline-captured departure because prerequisite ops have not arrived | §3.4.6, §7.3, §8, §14; `QueueLineGuardCoverageTest` stays |
| D2 | Fuel is a mandatory blocker where fuel applies: the Driver Checklist's explicit answer is canonical; no default; Full/Ready satisfies; Not Full/Not Ready does not; the fuel ledger stays retired | §2.3 S6, §7.1–§7.3, §15, §16 P9 |
| D3 | No Answer satisfies Call Customer; Confirmed needs every sub-check; no silent default | §7.1, §7.2, §15, §16 P8 |
| D4 | Arrived resumes at Main Order | §5, §9, §16 P2 |
| D5 | Bind machine-specific Driver Checklist state to the equipment identity now, on phone and server (`equipment_unique_id`, additive, current-version-only); restore across phones | §3.2, §7.3–§7.4, §15 |
| D6 | Preserve the Queue Line Arrived latch; mobile routing stops using `lifecycle_stage` after departure | §2.2 RC6, §9, §10.2 |
| D7 | Delivery requires a video; photos never satisfy it alone; product/current-cycle evidence; Main Order and the checklist agree | §10.3, §15 |
| D8 | Review Assembly reachable for the whole active Delivery: operational before departure, read-only after, from Screen 2 and from Main Order | §6.1, §9, §11, §16 P4/P12/P13 |
| D9 | **Core invariant:** the assignment locks at effective On My Way and stays locked through Arrived; explicit predicate over the driver status and `delivery_is_arrived`, never `hasBeenDelivered()`; legitimate recall releases it | §3.4, §14, §15 |
| D10 | Every assignment writer honors the lock through the smallest shared enforcement; no general writer refactor | §2.2 RC9, §3.4.5, §15, §16 P14 |
| D11 | Keys are a mandatory blocker where the unit has a physical key: explicit, With Machine required, unit-bound, reset on unit change | §7.1–§7.3, §15, §16 P9 |
| D12 | The Dispatch stage label stays cosmetic and unchanged unless it falls out for free | §5 |

**Remaining ambiguities (recorded, not blocking):**
- A1. The `requires_fuel_check` / `requires_key_check` predicates (Diesel/Gas; 1–2 physical keys) are the yard's existing sign-off rules and narrower than today's `is_fuel` / `is_key` display flags (any power source; key pad / pull cord). The design adopts the yard rules for "applies". If Gary wants battery/electric units or key-pad units to answer too, the predicate is the only thing that changes.
- A2. Whether `Not Full` should be *recordable* at all (it is: the driver may record it and cannot depart; the office sees it) versus forcing a re-fuel before any answer. Recordable is chosen so the state is visible.
- A3. **Resolved by implementation; decision recorded for Gary.** A Reschedule of an Arrived truck is refused by the schedule editor's pre-existing reversal rule (the driver's Arrived sets `delivery_is_delivered`, which that rule counts as completion; the API status doors cannot send Reschedule). So the Arrived recall is Delivery Status → Pending (the canonical reopen, which recalls the trip and releases the Queue Line latch), and Reschedule recalls at On My Way — implemented as-is (option a), pinned by `test_reschedule_is_refused_at_arrived_and_the_lock_holds`. The alternative (option b) is to narrow the editor's `$wasCompleted` so a bare driver Arrived no longer counts as completion, which would make Reschedule-at-Arrived a direct recall; it changes a reversal rule the three status doors share, so it is not done silently.
- A4. The mobile `QUEUE_ITEM_IN_TRANSIT` code becomes `DELIVERY_DEPARTED` for switch/reset/availability after departure (the phone does not branch on the code; it parks on any terminal 4xx and shows the server's message).

---

## 19. Self-review (contradiction checks)

1. **Assignment lock consistency.** Every writer in RC9 is either under `assertAssignmentMutable`, under the lock-aware completion rule, or a recall path that releases the lock first; the inventory test pins the set. On the phone every reassignment surface (review, checklist picker, restart, Target.block) reads the effective stage. No path changes equipment On My Way or Arrived except a legitimate recall. ✔
2. **Fuel.** The gate accepts only `Full`; the default is gone; the blocker text says why; Return never asks. ✔
3. **Keys.** Only `With Machine` passes; no default; hidden only when the unit has no physical key. ✔
4. **Equipment identity.** Fuel/keys are stored with `equipment_unique_id` locally and on the server; restore compares to the effective unit on any phone; a replaced unit yields unanswered. ✔
5. **Offline FIFO.** Per-key capture order sends switch → availability → On My Way; the server is not departed until the last one; a parked op does not block; pinned by tests on both sides. ✔
6. **Review Assembly.** Reachable from Screen 2 in every state and from Main Order after Arrived; operational only below On My Way; read-only at On My Way and Arrived by `driverReadOnly`. ✔
7. **Resume.** `resolve` puts physical truth first; no stage ≥ On My Way routes to the review; a STOP after departure changes nothing; a recall lowers the stage only through the observed server row. ✔
8. **Customer-site routing.** For stage ≥ On My Way the router never returns `.assemblyReview`; CheckList Deliv opens the checklist directly; Save/Submit/Video go to Video/Checklist/Main Order only. ✔
9. **Return.** The gate has a Return band with call only; fuel/keys/assembly/lock/Review Assembly are Delivery-only by construction and pinned. ✔
10. **Scope.** No writer refactor, no board or Fast Track change, no ledger revival, no new store; the D5 contract is additive. ✔

---

## Appendix A — Index of inspected code (heads `0278048` / `27cc10ed9`)

Mobile (`RentnKing/`): `Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift` (534-548, 611-620, 1178-1187, 1636-1717, 1742-1760); `…/Dispatch Model/Driver Checklist/DriverChecklistViewController.swift` (83-99, 155-196, 305-331, 576-628, 690-763, 876-943, 985-1111, 1113-1196); `…/Dispatch Model/DispatchOfflineRowAdapter.swift` (26-52); `…/Dispatch Model/Warning Checklist/WarningViewController.swift`; `Modules/TABBAR/Home Model/Queue Line Model/ChecklistEntry.swift`; `…/Queue Line Model/AssemblyReviewViewController.swift` (113-126, 314-438, 672-802, 839-848); `…/Queue Line Model/QueueLineViewController.swift` (265-300); `Modules/TABBAR/Home Model/Order Model/Order Details/OrderDetailsViewController.swift` (160, 194-211, 521-522, 587-603, 668-706, 774-783, 956-1059, 1253-1340, 1639-1660); `…/Order Model/Check List/CheckListViewController.swift` (130-175, 584-780, 798-869, 1849-1896, 2695-2714, 2773-2948); `…/Order Model/Check List/CheckListUpdateViewController.swift` (487-500, 553-605); `…/Order Model/Check List/EquipmentAssignmentFlow.swift` (33-47, 539-641); `…/Order Model/Image Upload/ImageUploadViewController.swift` (367-403, 511-527); `…/Order Model/License Upload/LicenseUploadViewController.swift` (263-284), `LicenseTypeViewController.swift` (233-240); `…/Order Model/OrderListViewController.swift` (1055-1085, 1354-1376); `Modules/TABBAR/Home Model/Place Order Model/Payment Model/TermsAndConditionViewController.swift` (76-79, 182-195, 303-341); `Modules/TABBAR/Home Model/Schedule Model/Schedule List/ScheduleListModel.swift` (127-155); `Modules/TABBAR/Equipment Model/MachineProfile/MachineProfileModel.swift` (28-50); `Sync/Core/DriverChecklistLocalState.swift`; `Sync/Core/EffectiveFieldState.swift`; `Sync/Core/AssemblyReview.swift`; `Sync/Core/PreparationLifecycle.swift`; `Sync/Core/QueueLineOperations.swift`; `Sync/Core/ChecklistContext.swift`; `Sync/Core/ChecklistContextFallbackPolicy.swift`; `Sync/Core/LegCompletionRequirements.swift` (60-65, 219-296); `Sync/Core/DispatchOfflineFieldBridge.swift` (1-90); `Sync/Core/DispatchOfflineContract.swift` (230-300); `Sync/Core/DispatchOfflineReferenceWarmup.swift`; `Sync/Core/SyncOperation.swift` (185-191); `Sync/Core/SyncEngine.swift` (482-497); `Sync/App/DriverChecklistSyncHandler.swift`; `Sync/App/AssemblySyncHandlers.swift`; `Sync/App/PreparationSyncHandlers.swift`; `Sync/App/QueueLineSyncHandler.swift`; `Sync/App/DispatchOfflineOrderBridge.swift`; `Sync/App/KabbaSync.swift` (33-100); `Core/FileData Helper/SyncDriverChecklist.swift` (50-200); `Core/FileData Helper/CheckListFile.swift`; `Core/FileData Helper/OrderDetailsFile.swift`; `Core/FileData Helper/kEnum.swift` (55-63); `AppDelegate.swift` (795-830); `Package.swift`; `Scripts/sync-contract-fixtures.sh`.

Backend (`app/`): `Http/Controllers/Api/Admin/V1/Orders/Schedules/DriverChecklistController.php`; `Http/Requests/Api/Admin/V1/Orders/Schedules/DriverChecklistRequest.php`; `Enums/Orders/EquipmentDriverStatus.php`; `Enums/Equipments/EquipmentKeyStartingMechanism.php`; `Listeners/QueueLine/CompleteOnDispatchStart.php`; `Listeners/QueueLine/SyncOnScheduleUpdate.php`; `Observers/OrderProductObserver.php`; `Services/QueueLine/QueueLineLifecycle.php`; `Services/QueueLine/QueueLineService.php`; `Services/QueueLine/QueueLineAssembly.php` (100-128); `Services/QueueLine/QueueLineAssemblyPresenter.php`; `Services/QueueLine/QueueLineMobilePresenter.php` (150-300, 362-384); `Services/QueueLine/QueueLineAvailabilityService.php`; `Services/QueueLine/QueueLineChecklistStaging.php`; `Services/QueueLine/QueueFuelVerificationService.php`; `Services/QueueLine/QueueLineOperationException.php`; `Services/Equipment/EquipmentReassignmentService.php`; `Services/AutoAssignDirectService.php`; `Services/Checklists/ChecklistPreparationReset.php`; `Services/Checklists/ChecklistExecutionService.php`; `Services/Orders/RentalFulfillmentService.php`; `Services/Dispatch/Offline/DispatchOfflineMissionSerializer.php`; `Http/Resources/Api/Admin/V1/OrderProducts/DispatchRowFields.php`; `Http/Resources/Api/Admin/V1/OrderProducts/ListResource.php`; `Http/Resources/Api/Admin/V1/Equipment/ListResource.php` (111-121); `Http/Controllers/Api/Admin/V1/QueueLine/Concerns/RespondsWithQueueLineEnvelope.php`; `Http/Controllers/Admin/OrderManagement/Schedules/AssignEquipmentController.php`; `Http/Controllers/Admin/OrderManagement/Orders/AssignEquipmentController.php`; `Http/Controllers/Admin/OrderManagement/Orders/RemoveEquipmentController.php`; `Http/Controllers/Admin/OrderManagement/Orders/UpdateProductScheduleController.php`; `Http/Controllers/Admin/OrderManagement/Dispatch/ReorderController.php`; `Http/Controllers/Api/Admin/V1/Orders/CustomerChecklists/RemoveController.php`; `Http/Controllers/Api/Admin/V1/Dispatch/UpdateStatusController.php`; `Livewire/QueueLine/Board.php` (235-295); `Models/Orders/OrderProduct.php` (138-195, 470-524); `Models/MaintenanceManagement/Equipment.php` (150-195); `routes/api/admin/v1/queue_line/routes.php`; `routes/api/admin/v1/orders/routes.php`; `routes/admin/order_management/schedules/routes.php`; `routes/admin/order_management/orders/routes.php`; `tests/Fixtures/mobile-contract/`.
