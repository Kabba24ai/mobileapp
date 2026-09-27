# Driver Delivery Process Flow — Design

**Date:** 2026-09-27
**Repositories:** `Kabba24ai/mobileapp` (iOS, worktree `mobileapp-dispatch-offline-p6`, branch `feature/dispatch-offline-phase-6`, head `0278048`) + Kabba Laravel (worktree `kabba2_AI-dispatch-offline`, same branch name, head `27cc10ed9`)
**Status:** Architectural design for review. No product code. Phase 6 physical acceptance is paused at Scenario A (PASS) while this flow is settled.
**Inputs:** the current local Phase 6 heads, including the Dispatch assigned-only filter and mis-flagged Return corrections (`718a1c3` / `27cc10ed9`); the Scenario A observations O1–O3 (`docs/superpowers/plans/2026-09-26-dispatch-offline-phase-6-physical-acceptance.md` §11); the requested canonical flow (§1 below).

Every claim in §2 comes from reading the code on those heads. Line numbers are as of those heads. Nothing here was reproduced on the phone unless the text says so.

---

## 0. Summary

The offline infrastructure holds (Scenario A synced eight operations cleanly). The workflow around it does not:

1. **Assembly Review is not on the driver's road.** Dispatch → Start Delivery always opens the Driver Checklist; the review is reachable only from the Queue Line board, the Orders list and Order Details (§2.2 RC1).
2. **Departure is barely gated.** Load Map & Go is enabled by the call-customer ticks alone; fuel and keys have silent defaults; choosing "No Answer" bypasses the ticks; nothing checks that the assembly was confirmed or that the assigned unit is the one on the truck (RC3). The server enforces nothing at all on this endpoint, by an approved 2026-07-23 decision (RC4).
3. **The road after Arrived leads back to the yard gate.** Order Details opens the delivery checklist *through* Assembly Review, and every checklist exit (Save, Submit, Video) pops back to that review (RC5). Once Arrived has synced, the server reports the line as `equipment_delivered`, the review hides "Continue to Checklist" and locks its rows — the driver at the customer's site has no road to the checklist (RC6, verified by code reading, not yet reproduced physically). Offline, a cached review kept Scenario A out of that hole.
4. **Workflow state is scattered.** Trip stage, mini-checklist answers, assembly state, "checklist done", fuel and media each live in two or more stores with different scopes (§2.3). The stage itself is already well derived (`DriverStageOverlay`); what is missing is one derivation that covers the whole delivery, and routing that uses it.

The design keeps every durable store that exists and adds **no new workflow store**. It adds one pure derivation (`DeliveryWorkflowStage`), one routing rule per surface that reads it, an explicit Driver Checklist departure gate, a driver-origin mode for the existing Assembly Review screen, an explicit **Review Assembly** action, and stage-based customer-site routing. Server contract changes are optional and listed for approval (§18).

---

## 1. The requested canonical flow (restated, as the target)

```
Dispatch
  ↓ Start Delivery
Equipment Assembly Review        ← mandatory first gate; GO = every required line confirmed Available
  ↓ Continue to Driver Checklist
Driver Checklist                 ← pre-departure gate: Call Customer, Fuel (when required)
  ↓ Load Map & Go
Delivery On My Way               ← recorded locally first; Apple Maps only when service exists
  ↓ Driver Arrived
Main Order (Order Details)       ← the customer-site hub
  ↓ License / Terms / Equipment Checklist / Video   (each returns to Main Order, or to the next missing step)
Complete Delivery
```

Plus: resume at the effective stage; a visible **Review Assembly** action while the delivery is active and not delivered; one canonical equipment assignment; Available is a physical verification of *that* unit; all existing offline behavior preserved.

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
- Fuel defaults to `"Not Full"` and keys to `"Missing"` at setup (`612-628`), so `fuelFilled`/`keysFilled` are always true: no fuel verification is ever required.
- The call segment defaults to "Confirmed" (`703-704`); index 1 is **"No Answer"**, but the property is named `isCallWithMachine` (`711`, a leftover of the keys control) and it *disables* the sub-checklist and *enables* departure (`713-720`, `752`). Semantically "No Answer" is a recorded call attempt (the server texts the customer on that transition, `DriverChecklistController.php:230-232`), so treating it as "call completed" is defensible; but it is undocumented and mislabelled.
- Nothing on Screen 2 knows whether the assembly was confirmed or whether the row's unit is the one on the truck.

**RC4 — The server records; it does not gate.**
`POST orders/schedules/driver-checklist` (`app/Http/Controllers/Api/Admin/V1/Orders/Schedules/DriverChecklistController.php`) checks only the leg owner (`110-128`, 409 `DISPATCH_ASSIGNMENT_CHANGED`). It does not require On My Way before Arrived, a call outcome, fuel, staging or availability; the comment at `136-142` records the approved rule: "Queue Line staging is INFORMATIONAL, not restrictive (2026-07-23)". On My Way writes `delivery_on_my_way_at` (+ back-fills `delivery_ready_to_go_at`); Arrived writes `delivery_arrived_at`, `delivery_is_arrived = true` **and `delivery_is_delivered = true`** (`161-190`).

**RC5 — Every checklist exit returns to the Assembly Review beneath, whatever the origin.**
`ChecklistEntry.returnToReview` (`ChecklistEntry.swift:94-101`) pops to the last `AssemblyReviewViewController` on the stack; it is called by the staging Save (`CheckListViewController.swift:755-768`), the finalization Submit (`CheckListUpdateViewController.swift:582-598`) and the media upload (`ImageUploadViewController.swift:389`). The review's `viewDidAppear` then re-fetches from the server (`AssemblyReviewViewController.swift:121-126`). This is Scenario A's O2.

**RC6 — After Arrived, the review is the wrong screen and, online, a dead end.**
- Arrived fires `CompleteOnDispatchStart` → `QueueLineService::complete(VIA_DISPATCH_STARTED)` → `queue_line_items.completed_at` (`app/Listeners/QueueLine/CompleteOnDispatchStart.php:29-61`).
- `QueueLineLifecycle::stageFor` returns `equipment_delivered` when that latch is set or `hasBeenDelivered()` is true; `hasBeenDelivered()` includes `delivery_is_delivered || delivery_arrived_at !== null` (`app/Services/QueueLine/QueueLineLifecycle.php:67-85`, `app/Models/Orders/OrderProduct.php:494-505`). The mobile member payload carries it as `lifecycle_stage` (`QueueLineMobilePresenter.php:228`).
- The phone: `memberStage(serverStage: .equipmentDelivered …)` → `.equipmentDelivered` (`AssemblyReview.swift:743-752`); `hasLeftTheYard` is true (`:68`); the card renders **no Continue button** (`AssemblyReviewViewController.swift:426`), disables every availability row (`392`, `416`) and refuses an equipment change with "This delivery is complete…" (`672-679`, `PreparationLifecycle.swift:36-52`).
- Order Details still routes through the review, because its "delivered" test is the row-level `is_delivered`/status (`OrderDetailsViewController.swift:668-690`, `696-706`; served by `DispatchRowFields::isDelivered`, `OrderProducts/ListResource.php:87`), which Arrived does not set.

  Net effect online: **Arrived (synced) → Order Details → CheckList Deliv → Assembly Review showing "Equipment Delivered" with nothing to continue to.** Offline, the cached review plus `QueueLineLocalOverlay` promote the member only to In Transit (`QueueLineOperations.swift:233-237`; `completedLocally` needs a `delivery_checklist.complete`), so Scenario A still reached the checklist. This is the trap the mission describes, and it is worse online than offline. It is verified by code reading; it must be the first physical scenario of the next pass (§16 P7).

**RC7 — Post-departure availability rows are locked, even for a legitimate review.**
`enabled: !left` (`AssemblyReviewViewController.swift:392`, `416`) — Scenario A's O1. Correct for the yard gate (the server also refuses acknowledgements In Transit / delivered: `QueueLineAvailabilityService::assertAcknowledgeable`, `:381-407`), but the driver has no way to *look* at the assembly from the driver screens at all, locked or not.

**RC8 — "Complete Delivery" is a client-side gate, not an operation.**
`btnDeliveryComplatedClicked` evaluates `LegCompletionEvaluator`, shows the success overlay and pops to Dispatch; it sends nothing (`OrderDetailsViewController.swift:1005-1059`). The leg is completed by the checklist Submit (`delivery_checklist.complete`). Not a defect, but the spec must not describe "Complete Delivery" as a transition.

**RC9 — Server-side canonical-assignment gaps (backend, informational for this mission).**
- Web Dispatch, Order Details, Schedules, Schedule Assignment and Schedule Conflicts reassign through `Admin/OrderManagement/Schedules/AssignEquipmentController` (plain delete-then-create under a row lock, `:136-145`), not through `EquipmentReassignmentService`; they have no In Transit guard and rely on the lazy backstop in `ChecklistExecutionService::openExecution` (`:56-82`) to supersede a prepared cycle.
- `EquipmentReassignmentService::switch` / `ResetController` guard on `isInTransitForDelivery()` and hard assignment/Q&A rows (`EquipmentReassignmentService.php:87-119`, `ChecklistPreparationReset.php:64-69`); after Arrived `isInTransitForDelivery()` is false (`hasBeenDelivered()` is true), no hard `equipment_id` and no Q&A rows exist yet, so a Switch/Reset appears to be accepted between Arrived and the signed completion. The mobile `available_actions.switch_equipment` is false then, but that is UI only. Unverified by test; flagged in §18.

### 2.3 Duplicate or contradictory workflow state (inventory)

| # | Fact | Store A | Store B | Store C | Contradiction / risk |
|---|---|---|---|---|---|
| S1 | Trip stage (not started / On My Way / Arrived) | Engine ops `driver_checklist.update` with `equipment_driver_status` (durable, product × leg) | Server row `delivery_*_at`, `delivery_is_arrived`, `delivery_is_delivered` | Dispatch list's in-memory/persisted row copy mutated by `data_updateInCurrentDic` (sets `is_arrived`, `is_delivered = true`, `ready_to_go_at`; `DispatchListViewController.swift:1742-1760`, persisted at `1178-1187`) | A and B are reconciled by `DriverStageOverlay.effective` (`EffectiveFieldState.swift:342-369`) — the good pattern. C is a third, screen-owned copy that also renames `delivery_is_delivered` to `is_delivered` on the checklist block (`DispatchRowFields.php:111`), the same key the row uses for "leg delivered" (`:212`). |
| S2 | Driver mini-checklist answers (call, ticks, fuel, keys) | UserDefaults `driverChecklist_v2_<product>_<leg>` (`DriverChecklistLocalState.swift:84-86`) | Server `delivery_call_customer`, `_equipment_fuel`, `_equipment_key_location`, `dispatch_checklist.driver.delivery.checks` | Engine op payloads | Restore = local first, else server (`DriverChecklistViewController.swift:1015-1069`). No unit identity on any copy: fuel/keys survive an equipment change. |
| S3 | Assembly stage | Server `lifecycle_stage` (Arrived ⇒ `equipment_delivered`) | `QueueLineLocalOverlay` (`in_transit` from On My Way; `completed` only from `delivery_checklist.complete`; `QueueLineOperations.swift:183-253`) | — | **Online and offline disagree after Arrived** (RC6): server says delivered, phone says in transit. |
| S4 | "Delivery checklist done" | Engine evidence, product-scoped (`EffectiveFieldState.legSatisfied`) | MMKV marker `kCheckListOrderDetailsData_<Delivery/Return>_<orderUID>` written on Submit (`CheckListUpdateViewController.swift:570`), **order-scoped**, removed only by the legacy upload callback (`AppDelegate.swift:816-819`) | Server `is_delivered` (row) — and `checkCheckListStatus` reads only the **first** product (`OrderDetailsViewController.swift:680-688`) | A multi-line order reads every line as completed once one is submitted; with the Sync Engine the marker is never cleared. Order List keeps its own copy of the same function (`OrderListViewController.swift:1354-1376`). |
| S5 | Pending (prepared) draft | MMKV `kPendingCheckList_<type>_<orderUID>` (order-scoped, `CheckListFile.swift:20-60`) | Server execution `prepared` + `prepared_answers` | Engine `delivery_checklist.prepare` ops | Draft paints the Order Details tile amber separately from the evaluator (`OrderDetailsViewController.swift:587-603`). |
| S6 | Fuel | Driver Checklist "2. Fuel" Full/Not Full → `delivery_equipment_fuel` (never blocks) | Equipment checklist fuel row → `fuel_initial_reading` (`CheckListViewController.swift:2695-2714`) | `QueueLineFuelVerification` ledger + `QueueFuelVerificationService` (episode-bound; **no callers** in `app/Http`, Livewire, routes; board endpoints retired 2026-09) | Three representations; none gates departure. |
| S7 | Keys | Driver Checklist keys segment | `QueueLineKeyConfirmation` model (no callers) | — | Same as S6. |
| S8 | Delivery media requirement | Order Details: any photo or video, any product, any cycle, for the order (`LegCompletionRequirements.swift:219-221`, `235-243`) | Checklist smart route: a **video** for **this product** in the **current cycle** (`CheckListViewController.swift:798-838`, `EffectiveFieldState.deliveryVideoSatisfied`) | Media captured from Order Details carries no execution id (`OrderDetailsViewController.swift:1253-1277`) | Order Details can say "media done" while the checklist says "video missing". |
| S9 | Navigation origin | `ChecklistEntry.Origin` (`kind`, `selectIndex`, `fromCheckListScreen`) | Per-screen booleans: `isQueueLine`, `isOrderDetailsView`, `fromCheckListScreen`, `isOrderScreen`, `returnedToReview`, `completionLeg` | Stack inspection (`returnToReview`, `.first(where:)` pops that may skip Order Details when an Orders list sits beneath) | Destination depends on which screens happen to be on the stack, not on the workflow stage. |
| S10 | Terms Exempt | Tile greyed on `terms_status == "Exempt"` (`OrderDetailsViewController.swift:534-538`) | Handler returns on `status == "Exempt"` (`:980`) | — | Different fields (pre-existing nit). |

S1–S3 and S9 are what this design must resolve. S4–S8 and S10 are pre-existing; the design must stop *depending* on them for routing and names which ones to fix here (§17).

---

## 3. Canonical state and ownership model

### 3.1 Vocabulary

- **Mission** = `order_product_unique_id × leg` (Delivery here). Unchanged from the offline design.
- **Assignment episode** = one live `equipment_soft_assigns` row (hard `equipment_id` after delivery). Every writer delete-then-creates, so a change of unit — even back to the same unit — is a new episode (`EquipmentReassignmentService.php:135-140`; also the web `Schedules\AssignEquipmentController`).
- **Preparation cycle** = one `order_product_checklist_executions` row (`UNIQUE(order_product_id, leg, cycle)`); a unit change supersedes a prepared cycle (`ChecklistPreparationReset::supersede`) and the next context request mints the next one.
- **Confirmation (Available)** = one append-only `queue_line_availability_acknowledgements` row for a unit (`subject_type = unit`, keyed by the **episode id** and the equipment unique id) or an ordered option (`subject_type = option`, keyed by the frozen option key, no episode). Only a unit row whose episode equals the live episode counts (`QueueLineAvailabilityService::currentMap`, `:195-203`).

### 3.2 Ownership (who writes, who derives)

| Fact | Canonical owner (server) | Phone durable record | Derived on the phone by | Screen state allowed |
|---|---|---|---|---|
| Unit assignment | `equipment_soft_assigns` via `EquipmentReassignmentService` (mobile) | `queue_line.switch_equipment` op (retained) | `AssemblyPolicy.effectiveEquipment` (feed unit overlaid by the phone's own switch) | none |
| Unit / option Available | acknowledgements ledger | `queue_line.availability` op | `AssemblyPolicy.unitState/optionState` (episode-aware: a decision counts only for the unit it named) | none |
| Assembly gate (GO/STOP) | derived server-side (`gateFor`), never stored | — | `AssemblyPolicy.gate` over the cached review + overlays | none |
| Trip stage | `delivery_*` columns via `driver-checklist` | `driver_checklist.update` ops | `DriverStageOverlay.effective` | none (Dispatch's row copy becomes display-only, §3.4) |
| Mini-checklist answers | `delivery_call_customer` etc. | UserDefaults v2 state (+ partial-save ops) | restore local-first | the controls themselves |
| Checklist cycle + answers | executions | `*_checklist.prepare/complete/reset` ops, `ChecklistContextStore` | `ChecklistContextFallbackPolicy`, `EffectiveFieldState` | draft (existing) |
| Media | `order_media` anchored to the execution | `delivery_media.upload` ops | `EffectiveFieldState.deliveryVideoSatisfied` | none |
| Terms | order terms status / signed record | `terms.sign` / `terms.accept` ops | `EffectiveFieldState.termsSatisfied` | none |
| Leg completion | `is_delivered` / status Completed | `delivery_checklist.complete` op | `EffectiveFieldState.legSatisfied` | none |
| **Delivery workflow stage** | — (never stored anywhere) | — | **`DeliveryWorkflowStage.resolve` (new, pure, Sync Core)** | none |

Rule: **no screen may hold a workflow flag that another screen reads.** Booleans that today decide destinations (S9) become inputs to one router (§10) or disappear.

### 3.3 `DeliveryWorkflowStage` (the one derivation)

```swift
enum DeliveryWorkflowStage: Comparable {
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

Precedence is physical truth first (delivered > arrived > on my way), then the yard gate, then the driver's own progress. A trip that has departed is never sent back to the yard gate: the server refuses yard changes In Transit anyway.

**3.3.1 "Driver checklist evidence"** (what makes a second Start Delivery skip the review): any of
- a `DriverChecklistLocalState` record under the v2 key for this product × leg (the Driver Checklist writes one when it is first shown through the driver road — see §4 step 5 — and on every mutation today);
- a retained `driver_checklist.update` op for this product × leg (partial or transition);
- server mini-checklist state on the row (`driver_checks`, `call_customer`, `equipment_fuel`, `equipment_key_location` — `DriverChecklistLocalState.serverHasProgress`, widened to "present", not "non-default").

All three exist today; none is new. This satisfies "first start goes through the review" and "do not restart from the review every time" without a new store. Cost: a driver who taps Continue, enters nothing, and force-quits before Screen 2 wrote its record sees the review once more (GO, one tap). Acceptable.

### 3.4 Canonical equipment-assignment invariant

> For one mission there is exactly one live assignment episode. Queue Line Assembly Review, the driver's Assembly Review, the Driver Checklist header and the equipment checklist all read that episode (feed unit overlaid by this phone's own unacknowledged switch) and change it only through `queue_line.switch_equipment` → `EquipmentReassignmentService`.

Consequences the design relies on (all existing):
- a switch creates a new episode → the previous unit's Available no longer counts (server: episode key; phone: `unitKey(equipmentUniqueId)` decisions + `fromLocalSwitch` ⇒ unconfirmed, `AssemblyReview.swift:797-807`);
- a switch supersedes the prepared cycle → old answers/media never satisfy the replacement (server supersede; phone `supersededExecutionIds` / `lastDiscardAt`);
- completion refuses a unit that is not the live assignment (`ChecklistExecutionService::validateCanonicalSubmission` `:651-665`; `RentalFulfillmentService::completeDelivery` `:104-121`).

Two things the design **adds** for the driver surfaces:
- the Driver Checklist header shows the effective unit as "Name · #TAG" (the yard's identity line, `EquipmentIdentity.line`) — today it shows only the store name (`DriverChecklistViewController.swift:305-331`);
- the Driver Checklist's fuel/keys answers are bound to the episode's unit (§7.3).

The Dispatch list's row copy (S1 store C) stops being written for stage: `data_updateInCurrentDic` keeps only what the card needs for display and never sets `is_delivered`; the card already reads the effective stage through `presentedRow` (`DispatchListViewController.swift:611-615`).

### 3.5 Available confirmation and invalidation rules

Unchanged in substance; restated so the driver role is covered:

1. **Available** = "I physically verified this exact, currently assigned unit is present, correct and prepared for this delivery." It is per unit per episode. Options are per frozen option (they survive a unit change).
2. **A unit change never completes anything.** The replacement starts unconfirmed on every surface (server: new episode; phone: `unitState` returns nil for a `fromLocalSwitch` unit until a decision names it). The gate returns to STOP until the new unit is confirmed. Required sequence: change → new episode → unconfirmed → tap Available.
3. **Who may confirm**: the yard technician or the driver, on either Assembly Review entry, with the signed-in employee as `performed_by` (P4-D5). The driver's confirmation is the same op and the same ledger row as the yard's.
4. **When a confirmation stops being possible**: once the trip has departed (`in_transit`) or the line is delivered (`hasBeenDelivered`, which includes Arrived) — server `assertAcknowledgeable`, phone `hasLeftTheYard`. Unchanged (O1 stays as-is by design).
5. **Not Available** reverses (append-only) and, on a staged line, unstages it. Unchanged.
6. **Invalidation on reassignment from the web** (RC9): the web writers create a new episode too, so the ledger rule still invalidates; what they skip is the cycle supersede/unstage (lazy backstop). Not changed by this design; listed in §18.

---

## 4. First-start flow (complete)

Preconditions: the mission is on the Dispatch card with a driver assigned; Phase 4 has bridged its package (context + order details + assembly + terms) or the phone is online.

1. **Dispatch → Start Delivery.** `DispatchListViewController` resolves `DeliveryWorkflowStage` for the row (inputs from the engine snapshot, the presented row, the cached review, the v2 key). First start ⇒ `.assemblyReview`.
2. **Assembly Review (driver origin).** Opened by `ChecklistEntry.openAssemblyReview(… origin: .driver(mission))` focused on the mission's member (`focusOrderProductUniqueId`), showing the member's assembly (the whole dependent assembly when the line is a base or child). Same screen, same cache-then-fetch, same overlays, same Available/Assign/Change controls.
   - Primary action for this origin: **"Continue to Driver Checklist"**, enabled only when `AssemblyPolicy.gate(for: group).ready` (every required unit/option Available, members that left the yard excluded). The equipment "Continue to Checklist" button is **not** shown for the driver origin (the equipment checklist belongs to the yard at this point and to Main Order after arrival).
   - Changing the unit: existing `changeEquipment` (candidates → picker → confirmation → reason → `queue_line.switch_equipment`), blocked In Transit / delivered (existing). After a change the row shows the replacement unconfirmed and the gate is STOP.
   - No unit assigned: the existing Assign row; the gate is STOP until assigned and confirmed.
3. **Continue to Driver Checklist** pushes `DriverChecklistViewController` (the review stays beneath, so Back returns to it).
4. **Driver Checklist** shows the effective unit identity, the call section, fuel/keys where required (§7), **Review Assembly** (§11) and Load Map & Go (disabled until §7's gate is met).
5. On first appearance through the driver road the screen persists its state record (§3.3.1), so the next Start Delivery resumes here.
6. **Load Map & Go** (§8): records On My Way locally, opens Maps when service exists, shows the trip status; Kabba stays on Screen 2 in the On My Way state.
7. **Arrived** (§9): records Arrived locally and pushes **Main Order**.
8. **Main Order** (§10): License → Terms → Equipment Checklist → Video in any order the driver chooses, each returning to Main Order or to the next missing step; then **Complete Delivery** (existing gate + override screen), which pops to Dispatch.

Yard entries are unchanged: Queue Line card / Orders list / Order Details **before departure** still open Assembly Review with "Continue to Checklist", and the checklist's Save/Submit/Video still return to that review (the preparation workflow).

---

## 5. Resume flow (complete)

Every Start Delivery (and every reopen after a force-quit, relaunch, or app update) runs the same resolution. There is no "resume mode"; the stage *is* the resume point.

| Effective stage | Start Delivery opens | Notes |
|---|---|---|
| `.assemblyReview` (STOP, or no evidence) | Assembly Review (driver origin) | Includes "yard confirmed everything, driver never opened Screen 2" (GO, one tap) and "a later switch/Not Available put it back to STOP" (must re-confirm; mini-checklist answers are kept, fuel/keys reset if the unit changed). |
| `.driverChecklist` | Driver Checklist, restored | Existing restore (local first, else server). The review is not pushed beneath it; **Review Assembly** on Screen 2 covers the revisit (§11). |
| `.onMyWay` | Driver Checklist in the On My Way state (Arrived button) | Existing `getReadyToGo_ArrivedStatus` behavior. Review Assembly available, read-only. |
| `.arrived` | **Main Order** directly | The Driver Checklist's Arrived screen only offered "Continue" to Main Order; skipping it removes a dead hop. Back from Main Order goes to Dispatch (existing). See §18 D4 for the alternative. |
| `.delivered` | Nothing — the card leaves the working list (existing `CompletionOverlay`) | The Completed tab's card opens the read-only finalized checklist as today. |

Rules:
- Local durable evidence outranks the row's server copy exactly as today (`DriverStageOverlay`, `serverObservedAt`). A recalled trip (office reset) is honored only when a row observed after the confirmation shows it (existing rule).
- Resume never replays a transition: On My Way and Arrived are recorded once (`recordsDeparture` / `recordsArrival`, existing).
- The Dispatch card label may reflect the stage ("Start Delivery" / "Resume Delivery" / "Arrived — Complete Delivery"); optional, display only, decided at implementation.

`DriverChecklistRouting` is replaced by `DeliveryWorkflowRouting.destination(stage:)`, and the test that pins "every combination routes to the Driver Checklist" (`DriverChecklistLocalStateTests.testEveryPriorStateCombinationRoutesToTheDriverChecklist`) is replaced by the matrix in §15. This reverses the 2026-09 "routing is absolute" rule deliberately: that rule existed because the old shortcut trusted a stale server `is_arrived`; the new shortcut trusts the *effective* stage, which is the local-first derivation that same correction introduced.

---

## 6. Assembly Review as the driver's first gate

### 6.1 One screen, two origins

`ChecklistEntry.Origin.Kind` gains `.driver` (carrying the mission's `orderProductUniqueId` and the stage it was entered from, for §11). The review's rendering differs only in the forward action:

| Origin | Forward action | Enabled when | Rows editable when |
|---|---|---|---|
| `.queueLine`, `.orderList`, `.orderDetails` (pre-departure) | Continue to Checklist (equipment) | gate GO (existing) | `!hasLeftTheYard` (existing) |
| `.driver`, stage `.assemblyReview` (first start / STOP) | **Continue to Driver Checklist** | gate GO | `!hasLeftTheYard` |
| `.driver`, entered manually from Screen 2 (§11) | **Back to Driver Checklist** (or plain Back) | always | pre-departure: yes; after departure: read-only |

"Continue to Driver Checklist" is a push on the first start and a pop on a manual revisit; the screen knows which from the origin.

### 6.2 What GO means for a multi-member assembly

The gate is the assembly's (`AssemblyPolicy.gate(for: group)`): every member's unit and every frozen option Available, members that left the yard excluded. The driver's mission is one member; the whole assembly must be confirmed because it travels together. Unchanged from the yard rule.

### 6.3 Offline

The review is bridged from the mission package (`assembly` section, delivery only — `DispatchOfflineFieldBridge.swift:12`, `DispatchOfflineOrderBridge.swift:36-42`). Confirmations, reversals and switches are durable ops and render immediately from the overlays (existing). The candidates list for a switch is a live GET today (`AssemblyReviewViewController.swift:723-749`), so **offline substitution from the review is not possible today**; the design adds the warmed reference equipment list (`DispatchOfflineReferenceWarmup` already refreshes `equipment` and `categories`) as the offline candidate source, scoped by the unit's category, with `PreparationPolicy.switchReasonRequired` deciding the reason prompt (the same rule the checklist picker mirrors). The replacement's checklist context still needs a connection (`ChecklistContextFallbackPolicy.canServeOffline` refuses a superseded cycle) — the driver can depart and arrive, but the customer-site checklist for the replacement waits for service. This limitation is stated on screen at switch time.

### 6.4 No review on the phone

If the package had no `assembly` section (a pre-Phase-4 server, `notProvided`) or it failed and the phone is offline, `assemblyGate == nil` ⇒ `.assemblyReview` with the existing "Offline · no saved Assembly Review for this order yet. Reconnect and pull to refresh." note; Continue to Driver Checklist is disabled. Online, the fetch fills it. There is no silent bypass (§18 D1 keeps the server non-restrictive, so the phone's gate is the only gate; it must not have a hole).

---

## 7. Driver Checklist: pre-departure gate

### 7.1 Requirements

| Requirement | Applies | Completed when | Store |
|---|---|---|---|
| Call Customer | always (Delivery and Return) | an **explicit** outcome is recorded: **Confirmed** with every sub-item ticked, or **No Answer** | v2 local state + `driver_checklist.update` (`call_customer`, `driver_checks`) |
| Fuel | Delivery, when the effective unit has fuel data (`is_fuel`; absent flag ⇒ required) | an **explicit** selection (Full / Not Full) for **this unit** | v2 local state (+ `equipmentUniqueId`) + `equipment_fuel` |
| Keys | Delivery, when the unit has key data (`is_key`) | an explicit selection for this unit | same |
| Assembly gate | Delivery | GO as known to the phone at tap time | derived (§3.3) |

Changes from today: the three segments have **no default** (today "Confirmed", "Not Full", "Missing" are pre-selected, RC3); "No Answer" is the recorded call attempt and *does* satisfy the call requirement (it disables the sub-items as today) — see §18 D3 for the alternative; the misnamed `isCallWithMachine` is renamed. Whether "Not Full" should block departure is a business rule not stated in the request (§18 D2).

### 7.2 Gate expression

```
loadMapAndGoEnabled =
      callCompleted
   && (!fuelRequired || fuelAnswered(forUnit: effectiveUnit))
   && (!keysRequired || keysAnswered(forUnit: effectiveUnit))
   && (leg == .return || assemblyGate?.ready == true)
```

When the assembly gate is STOP while the driver is on Screen 2 (a web reassignment created a new episode; another phone reversed a confirmation), Load Map & Go is disabled and **Review Assembly** is highlighted with the gate's first blocker sentence. The phone learns of it from the review re-fetch (online) or from its own overlays (offline); Screen 2 recomputes on appear and on `.kabbaSyncQueueChanged`.

### 7.3 Fuel and keys are unit-specific

`DriverChecklistLocalState` gains `equipmentUniqueId` (the effective unit when the answer was given). On restore, if the effective unit differs, fuel and keys reset to unanswered; the call outcome and ticks are kept (they are about the customer, not the machine). The server copy (`delivery_equipment_fuel`) has no episode binding and stays informational; the phone's gate is the enforcement (§18 D5 offers an optional server field).

### 7.4 Return leg

Same screen, no fuel/keys (`checklistType == "pickup"` hides them today), no assembly gate. Call Customer becomes explicit for Return too because it is the same control (§13).

---

## 8. Load Map & Go

Order of operations (the first two are unchanged):

1. Guard: `recordsDeparture` (never twice) and the §7.2 gate.
2. **Record On My Way locally**: `saveDriverChecklistLocally(… equipment_driver_status: "On My Way" …)` → durable `driver_checklist.update` op; toast "Saved on this phone · Pending Sync → Synced"; the screen flips to the On My Way state; the Dispatch card's stage follows through the overlay. Identical online and offline.
3. **Navigation**:
   - **Online** (`NetworkReachabilityManager()?.isReachable == true`, the app's existing check): open the destination in Apple Maps, separately; Kabba remains on Screen 2 in the On My Way state. Today's helper geocodes first (`openAddressInMap`, `OrderDetailsViewController.swift:1639-1660`); a geocode failure is silent. The design keeps the helper but makes it report failure, so a failed geocode shows the same Service Offline alert instead of nothing. (Implementation option: `maps://?daddr=<address>` needs no geocode on the phone; decided at implementation, not here.)
   - **Offline**: do not call Maps. Show the **Service Offline** state: an alert (or an inline amber band, in the app's existing offline language — the "Offline · showing the saved …" freshness lines and the sync toasts; there is no component literally named "Service Offline" today) reading: *"Service Offline — Navigation needs cellular or Wi-Fi service. Your On My Way status is saved on this phone and will sync automatically."* One button: OK. The screen also keeps the existing map button, so the driver can retry Maps once service returns.
4. Nothing else changes: no second store, no blocking, no retry loop.

---

## 9. Driver Arrived → Main Order

Unchanged mechanics: `btnArrivedClicked` records Arrived (durable op, once) and `pushOrderDetails()` pushes `OrderDetailsViewController` with `fromCheckListScreen`, `completionLeg` and `strProductID` (`DriverChecklistViewController.swift:1113-1196`). Additions:

- Main Order is reached **only** by this push or by the `.arrived` resume (§5). It never re-derives the leg from the feed (existing `completionLeg` rule).
- Main Order's header shows the trip status ("Arrived 04:51 PM") and the effective unit identity, so the driver never needs Screen 2 again for information.
- Back from Main Order → Dispatch (existing `OrderDetailsViewController.swift:194-211`).

Server side, Arrived keeps setting `delivery_is_delivered` and latching the Queue Line item (RC6). The design does not change that (§18 D6); it removes every mobile dependency on `lifecycle_stage` after departure.

---

## 10. Customer-site routing matrix

### 10.1 The router

One pure function replaces stack inspection and the S9 booleans for the delivery leg:

```swift
enum CustomerSiteRoute { case mainOrder, video, checklist }

static func afterStep(_ step: CustomerSiteStep,          // .license, .terms, .checklistPrepared, .checklistCompleted, .video
                      stage: DeliveryWorkflowStage,     // ≥ .onMyWay ⇒ the customer-site rules below
                      videoRequirementMet: Bool,        // §10.3
                      checklistComplete: Bool) -> CustomerSiteRoute
```

For `stage < .onMyWay` (yard) the existing `returnToReview` rule stands untouched. "Go to X" means **pop to X if it is on the stack, else push it**, so the stack stays finite: Main Order → Checklist → Video → (pop) Checklist → Submit → (pop) Main Order.

### 10.2 The matrix (stage ≥ On My Way)

| Step completed | Today | Target |
|---|---|---|
| Add Driver License (saved / queued) | pop once, or `popToViewController(.first(where: OrderList ∨ OrderDetails))` (`LicenseUploadViewController.swift:263-284`, `LicenseTypeViewController.swift:233-240`) | **Main Order** (the instance that pushed it) |
| Sign Terms (signed on phone / hosted accepted) | pop once (`TermsAndConditionViewController.swift:182-195`, `303-341`) | **Main Order** |
| Equipment Checklist — Save (prepare) | Video if a delivery video is missing, else back to Assembly Review (`CheckListViewController.swift:708-727`, `755-768`) | Video if the video requirement is unmet, else **Main Order** |
| Equipment Checklist — Submit (complete) | back to Assembly Review, else Order Details / Orders (`CheckListUpdateViewController.swift:582-598`) | Video if unmet, else **Main Order** |
| Video / Photo upload | back to Assembly Review at Submit, else pop (`ImageUploadViewController.swift:367-403`, `511-527`) | **Checklist** if this product's checklist is not complete (durable complete op ∨ server), else **Main Order** |
| Complete Delivery | requirements met → Dispatch; else override screen → Dispatch (`OrderDetailsViewController.swift:1005-1059`) | unchanged |

Order Details' **CheckList Deliv** button, for stage ≥ On My Way, opens the equipment checklist **directly** (focused on the mission's product, with the existing context/draft restore) — never Assembly Review. That single change removes RC6. Before departure (Orders/Schedule entry at the yard) it keeps today's review sequencing.

Loop check: each hop consumes a requirement (Save → Video → Checklist(prepared, not complete) → Submit → Main Order; Submit → Video → complete ⇒ Main Order). Back always pops. No cycle can repeat without the driver choosing it.

### 10.3 One media requirement

S8 is resolved by one policy used by both surfaces: **delivery media is satisfied when a video for this product in the current cycle exists** (`EffectiveFieldState.deliveryVideoSatisfied` with the active execution id when known), with the order-scoped legacy evidence accepted only when no cycle is known (never-opened offline first open). Order Details' `.deliveryMedia` requirement adopts it, and media captured from Main Order carries the active execution id (the Photo/Video buttons pass `checklistExecutionIds` like the checklist's smart route does). Whether a photo alone may satisfy it is §18 D7.

### 10.4 "What remains" on Main Order

`LegCompletionEvaluator` stays the one evaluator for tiles and the Complete gate. Its checklist input drops the order-scoped marker (S4) in favor of the product-scoped effective state for the mission's product; the marker keeps its other legacy uses until removed separately (§17).

---

## 11. Review Assembly (manual revisit)

- **Where**: a visible **Review Assembly** action on the Driver Checklist in every not-yet-delivered state the screen shows (not started, On My Way). After Arrived the driver is on Main Order, which shows the unit identity instead; the review is read-only by then anyway (§18 D8).
- **What it opens**: the same Assembly Review, origin `.driver(mission, enteredFrom: currentStage)`, focused on the mission's member.
- **Capabilities follow the stage** (server rules mirrored, nothing new):
  - before departure: confirm / reverse Available, assign / change unit — the real thing, not a read-only copy; a change re-opens the gate (STOP) and the Driver Checklist's Load Map & Go stays disabled until confirmed again (§7.2);
  - after departure (On My Way / Arrived): read-only (rows disabled, `hasLeftTheYard`), no change action, the existing In Transit / delivered explanation on tap.
- **Return**: Back (or "Back to Driver Checklist") pops to the screen it came from. It never re-runs Start Delivery, never re-records a transition, never clears mini-checklist answers (only fuel/keys reset if the unit changed, §7.3). Not a rewind.
- **Nav guard**: one review at a time (existing `topViewController` check).

---

## 12. Offline / local-first behavior (preserved and extended)

| Capability | Status under this design |
|---|---|
| Local-first On My Way / Arrived (`driver_checklist.update`, `DriverStageOverlay`) | preserved; the stage derivation (§3.3) sits on top of it |
| Durable Sync Engine, per-order-product FIFO (`SyncOperation.orderingKey`) | preserved; a switch still precedes any prepare for the replacement |
| Cached mission package (context, order details, assembly, terms) | preserved; the assembly section now also serves the driver's first gate |
| Offline Order Details / Assembly Review / checklist context / Terms | preserved |
| Pending Sync / Synced / Needs Attention | preserved; a Needs Attention op still counts as durable workflow evidence (work stands) |
| order product × leg × cycle identity; substitution/reset invalidation; finalized-checklist immutability | preserved; the router only *reads* `EffectiveFieldState` |
| Offline availability confirmation / reversal | preserved (durable op, employee = signed-in user) |
| Offline unit substitution from Assembly Review | **new** (warmed equipment list as candidates, §6.3); the replacement's context still needs service |
| Offline Load Map & Go | **new** behavior: On My Way recorded, Service Offline alert, no Maps call (§8) |
| Offline first start | works when the package is bridged (assembly present); otherwise the gate is honestly STOP with the existing offline note (§6.4) |

No second workflow store: the only new persisted field is `equipmentUniqueId` inside the existing v2 mini-checklist record.

---

## 13. Delivery-only versus Return

The request scopes the redesign to Delivery. Shared components force these Return touches, each listed for separate review:

| Change | Delivery | Return | Why Return is touched |
|---|---|---|---|
| Stage derivation + resume routing (§3.3, §5) | yes | yes (stages `driverChecklist / onMyWay / arrived / delivered`; no assembly gate) | same Dispatch button, same Screen 2; a Return that resumes at Arrived lands on Main Order too |
| Assembly Review gate (§6) | yes | **no** (Return has no Assembly Review; `notApplicable` in the bridge) | — |
| Explicit Call Customer (§7.1) | yes | yes | same control |
| Fuel / keys gate (§7) | yes | no (hidden today) | — |
| Load Map & Go offline alert (§8) | yes | yes | same button |
| Customer-site router (§10) | yes | yes for the Return checklist / Return media exits (they pop to Order Details today, so the target is the same "Main Order" and the Video ↔ Checklist hop applies) | shared checklist/media screens |
| Review Assembly (§11) | yes | no | — |

Nothing else in the Return workflow changes. The Return-specific product questions from Phase 6 (drifted Returns N1, online All fallback N2) are untouched.

---

## 14. Failure and recovery behavior

| Situation | Behavior |
|---|---|
| Leg reassigned on the web while the driver's steps were offline | server 409 `DISPATCH_ASSIGNMENT_CHANGED` → op parked Needs Attention, work stands (existing); the card leaves this driver's list on the next reconcile; the stage on this phone still shows the driver's evidence until then (existing rule). |
| Unit switched on the web while the driver is on Screen 2 (new episode) | next review fetch (online) shows the replacement unconfirmed ⇒ STOP ⇒ Load Map & Go disabled, Review Assembly highlighted; offline the phone cannot know until it reconnects — the driver departs on the phone's last knowledge, the server records it (§18 D1). |
| Switch op rejected by the server (Needs Attention) | `pendingEquipment` is cleared for a rejected switch (`QueueLineOperations.swift:200-210`); the review reverts to the server's unit and its confirmation state; the gate recomputes. |
| Availability op rejected | the row shows "Sync Issue" with the server's reason (existing overlay); the gate treats the subject as unconfirmed. |
| No assembly section on the phone, offline | STOP with the existing offline note; no bypass (§6.4). |
| Load Map & Go tapped offline | On My Way recorded; Service Offline alert; retry Maps later from the map button. |
| Geocode failure online | same alert as offline (today: silent nothing). |
| Arrived synced, then the driver reopens Order Details → CheckList Deliv | opens the checklist directly (stage ≥ On My Way); the review is never consulted (RC6 closed). |
| Switch/Reset accepted by the server between Arrived and completion (RC9) | the driver's completion would hit `EQUIPMENT_ASSIGNMENT_CONFLICT`; the op parks as Needs Attention; §18 D9 proposes closing the server gap. |
| Force-quit / relaunch at any point | resume table (§5); no transition replayed. |
| App update mid-delivery | the v2 key, the ops and the caches are all versioned stores that already survive updates; the stage is recomputed from them. |
| Server later recalls the trip (office reset to Pending / Reschedule) | `resetDeliveryTripState` clears the row; the phone honors it only from a row observed after the local confirmation (existing `serverObservedAt` rule). |

---

## 15. Expected automated tests

**Mobile — Sync Core (`swift test`)**
- `DeliveryWorkflowStageTests`: the full input matrix (legCompleted × trip × gate GO/STOP/nil × evidence) → stage; precedence (departed trip beats STOP; delivered beats everything).
- `DeliveryWorkflowRoutingTests`: stage → destination (replaces `testEveryPriorStateCombinationRoutesToTheDriverChecklist`).
- `DriverChecklistGateTests`: call explicit outcomes (Confirmed + all ticks / No Answer / unset), fuel/keys required-by-flag and answered-for-unit, assembly gate STOP disables; Return ignores fuel/keys/gate.
- `DriverChecklistLocalStateTests`: `equipmentUniqueId` round trip; restore resets fuel/keys on a different unit and keeps call/ticks; evidence rule counts a record with defaults.
- `CustomerSiteRouterTests`: the §10.2 matrix, both stages (< On My Way keeps the review rule), the Video ↔ Checklist hop terminates.
- `MediaRequirementPolicyTests`: one policy for Order Details and the checklist; legacy evidence only when no cycle is known.
- `AssemblyReviewDriverOriginTests`: driver origin never offers the equipment Continue; offers Continue to Driver Checklist only at GO; manual revisit returns without replaying.
- `LoadMapAndGoDecisionTests`: online → maps + status; offline → status + Service Offline; geocode failure → alert.
- Existing suites stay green: `EffectiveFieldStateTests`, `AssemblyReviewTests`, `PreparationLifecycleTests`, `DispatchOfflineFieldBridgeTests`, `DispatchOfflineReconcilerTests`, `ChecklistFinalizationPresentationTests`, `LegCompletionEvaluatorTests`, `TermsSignOperationsTests`, `DispatchWorkloadTests`, `DispatchOfflineWorkingSetTests`.

**Mobile — Hosted (`RentnKingHostedTests`)**
- Dispatch Start Delivery per stage with a stubbed engine snapshot (review / Screen 2 / Screen 2 On My Way / Main Order).
- Order Details CheckList Deliv after Arrived opens `CheckListViewController`, not the review; before departure opens the review.
- CLU Submit on the driver path pops to the pushing Order Details (not `.first(where:)`), Video hop when unmet.
- Assembly Review driver origin: buttons and row enablement per stage.
- Extend `AssemblyReviewPresentationTests`, `DispatchOfflineRowAdapterTests` (Dispatch row copy no longer written for stage).

**Backend (no contract change required; add only if §18 approves)**
- D9: `EquipmentReassignmentService` / `ResetController` refuse after Arrived (`QueueLineSwitchEquipmentTest`, `ChecklistResetTest`).
- D5: `driver-checklist` accepts and stores `equipment_unique_id` (`DispatchMobileParity`, request test).
- Regression gates from Phase 6 preflight: `tests/Feature/Dispatch`, `Api`, `Mobile`, `QueueLine`, `Terms`, `CustomerPortal`, `Orders` (baseline 23 known failures), `CustomerChecklists` (baseline 11), manifest budget.

---

## 16. Physical acceptance scenarios (to append to the Phase 6 matrix after implementation)

Same rules as `docs/dispatch-offline-phase-6/PHYSICAL_ACCEPTANCE.md` (test server only, never the Login screen, evidence under `~/Documents/kabba-dispatch-offline-p6-evidence/`).

| # | Scenario | Pass condition |
|---|---|---|
| P1 | First start, online: Start Delivery → Assembly Review (STOP) → confirm unit + options → Continue to Driver Checklist → explicit call/fuel/keys → Load Map & Go (Maps opens, On My Way toast) → Arrived → Main Order → License → Terms → Checklist → Video → Complete Delivery | every hop lands as §4/§10 says; server: On My Way, Arrived, completion, media, terms each once |
| P2 | Resume at every stage: force-quit after (a) review GO, (b) Screen 2 with answers, (c) On My Way, (d) Arrived; reopen from Dispatch | (a) review once more then Screen 2; (b) Screen 2 restored; (c) Screen 2 On My Way; (d) Main Order; no transition replayed |
| P3 | Unit change in the driver's Assembly Review before departure (direct and non-direct match) | replacement shows unconfirmed, STOP, reason prompt only for non-direct; confirm → GO; Screen 2 fuel/keys reset, call kept; server new episode, old ack retired, cycle superseded |
| P4 | Review Assembly from Screen 2 before departure, change nothing, Back; then after On My Way (read-only) | returns to the same Screen 2 state; no new ops; rows disabled after departure with the In Transit explanation |
| P5 | Fully offline first start (mission never opened online): review from the package → confirm → Screen 2 → Load Map & Go offline | Service Offline alert; On My Way pending; all ops drain once on reconnect |
| P6 | Offline unit substitution from the review; reconnect later | switch precedes prepare in the drain; replacement's checklist needs service message shown; after reconnect the new cycle's context loads |
| P7 | **The RC6 trap, online**: Arrived (synced) → Main Order → CheckList Deliv | the checklist opens directly; the review is never shown; complete the checklist → Video → Main Order → Complete |
| P8 | No Answer path | departure enabled by No Answer; SMS recorded once on the test server (outbound disabled); Confirmed with a missing tick stays disabled |
| P9 | Web reassignment while the driver is on Screen 2 (test server admin UI) | after refresh: STOP, Load Map & Go disabled, Review Assembly highlighted; confirm the new unit → GO |
| P10 | Return regression (M2-style): Start Return → Screen 2 → Load Map & Go → Arrived → Main Order → Return checklist → Video → Complete | Return unchanged except explicit Call Customer and the Main Order returns |
| P11 | Yard regression: Queue Line card → Assembly Review → Continue to Checklist → Save → Video → back to the review | unchanged |

---

## 17. Scope boundaries

**In scope (this design → next implementation plan)**
- Mobile: `DeliveryWorkflowStage` + routing; Assembly Review driver origin; Driver Checklist gate, explicit answers, unit-bound fuel/keys, unit identity, Review Assembly; Load Map & Go online/offline; customer-site router and Order Details post-departure checklist entry; one media policy; offline candidates for the review; Dispatch row copy stops writing stage; tests in §15.
- Backend: none required. Optional D5/D9 if approved.
- Docs: the physical acceptance additions (§16) after implementation.

**Out of scope (named so they are not silently pulled in)**
- The Return workflow beyond §13.
- The Queue Line web board, web Dispatch/Order Details reassignment paths (RC9 first bullet), and the Fast Track policy.
- Reviving the fuel-verification / key-confirmation ledgers (S6/S7), unless D2 chooses them.
- Removing the order-scoped completed-checklist marker and draft (S4/S5) everywhere; only the router stops depending on them.
- The `MachineHoursViewController` (unreachable today) and `EquipmentPicker.swift` (commented out).
- Terms Exempt field mismatch (S10), the license `.first(where:)` pop, the unbounded media save retry — recorded, not fixed here.
- The Phase 6 open items N1–N4, the deferred debug-login credentials and the Firebase-without-config wake crash.
- Any push, merge, deploy, flag, version/build, archive, upload, App Store Connect or production activity.

---

## 18. Conflicts with the requested flow, and decisions requiring approval

**Conflicts / tensions found (with the recommended resolution)**

- **C1 — "First start goes through Assembly Review" vs "do not restart from the review every time".** Resolved by the evidence rule (§3.3.1): the review is shown until the driver has any durable Driver Checklist record; afterwards the stage skips it. No new store.
- **C2 — The review's existing forward action is the equipment checklist, not the Driver Checklist.** Resolved by an origin-specific primary action on the same screen (§6.1). The yard workflow keeps its road.
- **C3 — Arrived means "Equipment Delivered" to the Queue Line (server latch, by design since 2026-09).** The requested flow ends at Complete Delivery. Resolved on the phone by never consulting `lifecycle_stage` after departure; the review's chip will read "Equipment Delivered" between Arrived and the signed completion on a read-only revisit. Wording only; see D6.
- **C4 — "Checklist completion must not return to Assembly Review" vs the yard's "back to the review first" rule (2026-09-14).** Resolved by stage: after departure → Main Order/Video; before departure → the review (yard preparation). Both keep working.
- **C5 — Departure prerequisites live on the phone; the server is non-restrictive by an approved decision.** Not changed; see D1.
- **C6 — "Fuel completed where required" has three candidate sources (S6).** See D2.

**Decisions requiring Gary's approval**

| # | Decision | Recommendation |
|---|---|---|
| D1 | Should the server start refusing On My Way (or Arrived) without assembly GO / a call outcome? | **No.** Keep 2026-07-23 "informational, not restrictive": a refusal of an offline-captured, physically true departure would park it as Needs Attention; the phone is the gate, the server records and badges Fast Track. Revisit only if an older app version or the web can create departures that must be blocked. |
| D2 | Canonical "Fuel completed" source | **The Driver Checklist's explicit Full/Not Full answer**, required when the unit has fuel data (existing endpoint, offline-capable). Not the orphaned Queue Line fuel-verification ledger (no callers; would need a new mobile endpoint + op type) and not the equipment checklist's fuel reading (a customer-site value). Sub-question: does "Not Full" block departure? Recommend no; it is recorded and visible. |
| D3 | Does "No Answer" satisfy Call Customer? | **Yes** (a recorded attempt; the customer is texted on sync). Alternative: require a second attempt or a note. |
| D4 | Resume at Arrived lands on | **Main Order directly** (Dispatch → Main Order; Back → Dispatch). Alternative: Screen 2 in the Arrived state with a Continue button, as today. |
| D5 | Add `equipment_unique_id` to the `driver-checklist` payload so fuel/keys are episode-bound on the server too | Optional, additive. Recommend **yes, later**; the phone-side binding is sufficient for the gate. |
| D6 | Keep Arrived ⇒ Queue Line "completed" latch and `hasBeenDelivered()` including `delivery_arrived_at` | **Keep** (web board semantics, Fast Track badge, refund closer depend on it). Only the mobile routing stops depending on it. |
| D7 | Delivery media requirement: video required (existing smart-route rule) or any photo/video | **Video required for Delivery**, photos optional; one policy for tiles, Complete gate and the Video hop. |
| D8 | Review Assembly also from Main Order after Arrived | **No**; Main Order shows the unit identity; the review is read-only then anyway. |
| D9 | Backend hardening: refuse Switch/Reset once `hasBeenDelivered()` (Arrived) so a unit cannot change under a driver completing at the customer's site (RC9) | **Yes, small, separate backend commit** with a test; not required for the mobile flow. |
| D10 | Route web Dispatch/Order Details reassignment through `EquipmentReassignmentService` (In Transit guard, immediate supersede/unstage) | Separate backend mission; recorded, not part of this flow. |
| D11 | Explicit (no-default) keys answer, like fuel | **Yes** for consistency; low cost. |
| D12 | Dispatch card label by stage (Start / Resume / Arrived) | Cosmetic; decide at implementation. |

---

## 19. Self-review (contradiction checks)

- **Changing equipment after Available.** New episode ⇒ the old confirmation is retired on the server (episode key) and on the phone (decision keyed by unit id; `fromLocalSwitch` ⇒ nil) ⇒ STOP ⇒ Continue/Load Map & Go disabled ⇒ confirm again. Fuel/keys reset because they are unit-bound; call/ticks stay. No path leaves an old unit's confirmation counting. ✔
- **Resumed deliveries.** Every reopen recomputes the stage from durable stores; the only new evidence is a record the Driver Checklist already writes; transitions are guarded by `recordsDeparture`/`recordsArrival`. A STOP after progress sends the driver to the review with answers intact — a gate, not a rewind. ✔
- **Entering Assembly Review manually.** Origin carries the stage it came from; the forward action is a pop; nothing is replayed; capabilities follow the stage exactly as the server allows. ✔
- **Offline substitution.** Durable op, FIFO before any prepare; candidates from the warmed list; the replacement's context honestly needs service, stated at switch time; departure is not blocked by it. ✔ (Limitation acknowledged, not hidden.)
- **Checklist cycle invalidation.** Untouched: the router reads `EffectiveFieldState`; media/video evidence is cycle-scoped; the one media policy adopts the stricter, cycle-correct rule. ✔
- **Navigation loops.** Every "go to" pops to an existing instance when present; each hop consumes a requirement; Back always pops; the review is pushed at most once. Verified against the sequences in §10.2. ✔
- **Online/offline agreement.** After departure no surface reads `lifecycle_stage`; before departure both read the same gate over the same overlays; the S3 divergence no longer affects routing. ✔
- **No second workflow store.** New persisted data = one field in the existing v2 record. ✔

---

## Appendix A — Index of inspected code (heads `0278048` / `27cc10ed9`)

Mobile (`RentnKing/`): `Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift` (534-548, 611-620, 1178-1187, 1636-1717, 1742-1760); `…/Dispatch Model/Driver Checklist/DriverChecklistViewController.swift` (83-99, 155-196, 305-331, 576-628, 690-763, 876-943, 985-1111, 1113-1196); `…/Dispatch Model/DispatchOfflineRowAdapter.swift` (26-52); `…/Dispatch Model/Warning Checklist/WarningViewController.swift`; `Modules/TABBAR/Home Model/Queue Line Model/ChecklistEntry.swift`; `…/Queue Line Model/AssemblyReviewViewController.swift` (113-126, 314-438, 672-802, 839-848); `…/Queue Line Model/QueueLineViewController.swift` (265-300); `Modules/TABBAR/Home Model/Order Model/Order Details/OrderDetailsViewController.swift` (160, 194-211, 521-522, 587-603, 668-706, 774-783, 956-1059, 1253-1340, 1639-1660); `…/Order Model/Check List/CheckListViewController.swift` (130-175, 584-780, 798-869, 1849-1896, 2695-2714, 2773-2948); `…/Order Model/Check List/CheckListUpdateViewController.swift` (487-500, 553-605); `…/Order Model/Check List/EquipmentAssignmentFlow.swift` (539-641); `…/Order Model/Image Upload/ImageUploadViewController.swift` (367-403, 511-527); `…/Order Model/License Upload/LicenseUploadViewController.swift` (263-284), `LicenseTypeViewController.swift` (233-240); `…/Order Model/OrderListViewController.swift` (1055-1085, 1354-1376); `Modules/TABBAR/Home Model/Place Order Model/Payment Model/TermsAndConditionViewController.swift` (76-79, 182-195, 303-341); `Sync/Core/DriverChecklistLocalState.swift`; `Sync/Core/EffectiveFieldState.swift`; `Sync/Core/AssemblyReview.swift`; `Sync/Core/PreparationLifecycle.swift`; `Sync/Core/QueueLineOperations.swift`; `Sync/Core/ChecklistContext.swift`; `Sync/Core/ChecklistContextFallbackPolicy.swift`; `Sync/Core/LegCompletionRequirements.swift` (60-65, 219-296); `Sync/Core/DispatchOfflineFieldBridge.swift` (1-90); `Sync/Core/DispatchOfflineContract.swift` (230-300); `Sync/Core/DispatchOfflineReferenceWarmup.swift`; `Sync/Core/SyncOperation.swift` (185-191); `Sync/App/DriverChecklistSyncHandler.swift`; `Sync/App/AssemblySyncHandlers.swift`; `Sync/App/PreparationSyncHandlers.swift`; `Sync/App/QueueLineSyncHandler.swift`; `Sync/App/DispatchOfflineOrderBridge.swift`; `Sync/App/KabbaSync.swift` (73-100); `Core/FileData Helper/SyncDriverChecklist.swift` (120-200); `Core/FileData Helper/CheckListFile.swift`; `Core/FileData Helper/OrderDetailsFile.swift`; `Core/FileData Helper/kEnum.swift` (55-63); `AppDelegate.swift` (795-830).

Backend (`app/`): `Http/Controllers/Api/Admin/V1/Orders/Schedules/DriverChecklistController.php`; `Http/Requests/Api/Admin/V1/Orders/Schedules/DriverChecklistRequest.php`; `Enums/Orders/EquipmentDriverStatus.php`; `Listeners/QueueLine/CompleteOnDispatchStart.php`; `Listeners/QueueLine/SyncOnScheduleUpdate.php`; `Services/QueueLine/QueueLineLifecycle.php`; `Services/QueueLine/QueueLineService.php`; `Services/QueueLine/QueueLineAssembly.php` (100-128); `Services/QueueLine/QueueLineAssemblyPresenter.php`; `Services/QueueLine/QueueLineMobilePresenter.php` (150-300); `Services/QueueLine/QueueLineAvailabilityService.php`; `Services/QueueLine/QueueLineChecklistStaging.php`; `Services/QueueLine/QueueFuelVerificationService.php`; `Services/Equipment/EquipmentReassignmentService.php`; `Services/Checklists/ChecklistPreparationReset.php`; `Services/Checklists/ChecklistExecutionService.php`; `Services/Orders/RentalFulfillmentService.php`; `Services/Dispatch/Offline/DispatchOfflineMissionSerializer.php`; `Http/Resources/Api/Admin/V1/OrderProducts/DispatchRowFields.php`; `Http/Resources/Api/Admin/V1/OrderProducts/ListResource.php`; `Http/Controllers/Admin/OrderManagement/Schedules/AssignEquipmentController.php`; `Models/Orders/OrderProduct.php` (470-524); `routes/api/admin/v1/queue_line/routes.php`; `routes/api/admin/v1/orders/routes.php`.
