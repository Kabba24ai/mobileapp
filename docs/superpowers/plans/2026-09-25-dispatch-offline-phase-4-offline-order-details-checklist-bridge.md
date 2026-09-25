# Dispatch Offline Phase 4 — Offline Order Details + Canonical Checklist Context Bridge — Implementation Plan

> **Status: PLAN ONLY — awaiting Gary's review.** No product code is written. The decisions in §3 (P4-D1–P4-D11) need approval, and the two backend gaps in §2.2 (B1, B2) need approval **before** any backend change.
> Rules for execution after approval: TDD task by task (failing test → prove the failure → minimum code → focused and regression tests → review the diff → local commit). Local only: no push, merge, deploy, SSH, production data, feature flag, version/build bump, archive, or App Store upload.
> **Phase 4 closes only after all of these pass (proposed, §9):**
> - B1/B2 parity, revision-completeness and performance tests;
> - every Phase 4 scenario in §7, including the automated acceptance scenario;
> - the complete affected backend regression (§9);
> - the complete mobile core suite and the signed hosted suite;
> - the simulator build and the no-polling gate;
> - a fresh independent reviewer reporting no Critical or Important issues.
>
> Then stop before Phase 5.

**Goal:** A mission that was **never opened while online** supports, with the iPhone **completely offline**:

`cached Dispatch → Driver Checklist → Order Details → equipment checklist`

This is the locked Phase 3 decision D2. The flow uses the existing screens, and the checklist uses the same canonical checklist context and the same local-first Sync Engine path as a checklist that was opened online.

**Spec:** `docs/superpowers/specs/2026-09-22-dispatch-offline-mission-cache-design.md`: §8 (Checklist, Product/equipment), §13, §14, §16, §17 (iOS: "checklist context is available when offline without ever opening the checklist while connected"), §18 step 4.

**Builds on (local branches, no upstream; `main` untouched):**
- Backend `feature/dispatch-offline-phase-4`, cut from Phase 3 HEAD `6d652cf15`, in worktree `/Users/garyjezorski/Documents/kabba2_AI-dispatch-offline`. It has no commits yet; it is needed only if B1/B2 are approved.
- Mobile `feature/dispatch-offline-phase-4`, cut from Phase 3 HEAD `db3a47e`, in worktree `/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p4`. This plan is its first commit.

**Baseline (Phase 3 final):**
- Mobile core `swift test`: 452/452.
- Hosted, signed: 56/56.
- Simulator build: OK.
- Backend `tests/Feature/Dispatch`: 580 passed.

---

## 0. What the inspection found

### 0.1 The acceptance path today, for a never-opened mission with the phone offline

| # | Screen | What it reads | Offline today, never opened online |
|---|---|---|---|
| 1 | Dispatch card | Phase 3 durable cache (`dispatch.row`) | ✅ Works (Phase 3). |
| 2 | Driver Checklist (Screen 2) | The row plus Sync Engine stage (`DriverStageOverlay`). No network reads (`DriverChecklistViewController`). | ✅ Works (Phase 3 F2). |
| 3 | **Order Details** (Screen 3) | The MMKV key `kOrderDetailData_<order uid>` (`OrdersListModel`), then `POST orders/details {unique_id}` (`OrderDetailsModel.swift:123-175`). Only this screen writes the key, and only after an online open. | ❌ **The skeleton shimmers forever.** The failure branch only hides the indicator (ODM:170-172). Three crash hazards when there is no model: "+View Billing" (ODVC:240), Return Photo/Video (`ImageUploadViewController.swift:42,148`), Add Note when a users list is cached (ODVC:872). |
| 4a | **Delivery checklist entry = Assembly Review** | UserDefaults `kQueueLineAssembly_<order uid>`, then `GET queue-line/orders/{uid}/assembly` (`AssemblyReviewViewController.swift:113-166`). Only a successful online open writes it. | ❌ **Dead end:** "Offline · no saved Assembly Review for this order yet". There is no way to continue to the checklist. |
| 4b | Return checklist entry | Order Details pushes `CheckListViewController` directly; there is no Assembly Review. | (see 5) |
| 5 | **Equipment checklist** (`CheckListViewController`) | Reference lists (cache-first), then `kOrderDetailsData_<order uid>` (**`OrdersModel`**, a different key and model) via `getOrderDetails` (`OrderDetailsFile.swift:12-24`). Nothing renders without it. Then, for **every** line, `ChecklistContextClient.load`: network first, falling back to the store only on a transport failure or 5xx (`ChecklistContextClient.swift:32-82`). | ❌ **Never renders** without `kOrderDetailsData_`. Even with it, a never-opened line has no stored context, so it falls back to legacy questions and a legacy submit. |
| 6 | T&C | A WKWebView of `terms_page`, loaded only when reachable (`TermsAndConditionViewController.swift:71-83`). | ❌ Blank page. This is **Phase 5** scope (§4.7 defines the Phase 4 boundary). |
| 7 | Complete – Next Mission | Local `LegCompletionEvaluator`, then `WarningViewController` override (Sync Engine). | ✅ Local-first already. |

### 0.2 The package's `checklist_context` is the canonical context
- **Same builder as the online endpoint.**
  - The package builder runs `buildContext()`, reloads the row, and ships `contextSnapshot()` plus `employee` and `server_time` from the build (backend `DispatchOfflineMissionPackageBuilder.php:32-58`).
  - The online `GET orders/checklists/context/{opuid}/{leg}` returns `contextPayload()` (backend `ChecklistExecutionService.php:266-409`).
  - The key sets are **identical at every nesting level**: top level, identity, equipment, template, requirements, questions, answers, category, operational, server_state, stage_blockers and employee. This was checked against the shared `delivery_checklist_context.json` / `return_checklist_context.json` fixtures. The type differences all sit in `JSONValue?` or `Double` fields.
  - It should decode through `ChecklistContext.decode(envelopeData:)` via the bare-object branch (`ChecklistContext.swift:258-264`). **No test proves this yet** (gap closed in M0).
- **Semantic differences:**
  - `employee` is the user who downloaded it, not necessarily the one signed in now (see P4-D5).
  - `server_time` is the download time.
  - A package **never** carries `assignment: "selected"`, because it never sends a requested unit. An unassigned delivery therefore ships equipment `none` and no questions. Choosing any unit offline is impossible (P4-D4).
  - Downloading a package runs `buildContext()`, which may mint, refresh or supersede the execution.

### 0.3 `ChecklistContextStore` today, and the offline identity gaps
- **The store:**
  - One file per (order product × leg), at `<KabbaSync>/checklist-contexts/<opuid>__<leg>.json` (`ChecklistContextStore.swift:21-39`).
  - There is **no cycle, execution or tenant in the key**.
  - The only writer is a successful (2xx) `ChecklistContextClient.load`, and each write simply replaces the previous one.
  - It is never pruned and never cleared, and it is **not tenant-scoped**.
- **Gaps that already exist and matter to Phase 4**, found by reading `CheckListViewController`:
  - **G-A. An offline substitution reverts the unit.**
    - `reloadChecklistContext(hint: replacement)` gets a transport failure and is handed the cached **superseded** context.
    - `applyChecklistContext` then sees a different unit and resets `objMachine` to the **old unit** (`CheckListViewController.swift:2891-2908, 2983-3035`).
    - Later prepares target the superseded execution.
  - **G-B. An offline restart reuses the superseded execution id**, because the cached context still names it.
  - **G-C. The cache fallback ignores the unit hint** (`ChecklistContextClient.swift:46-47,66-67`).
  - **G-D. `ChecklistContextError.unavailableOffline` is declared but never produced**, and there is no "needs a connection" state anywhere.
- **Invalidation that already works and is reused as-is:**
  - `EffectiveFieldState.supersededExecutionIds` and `lastDiscardAt` (switch_equipment, delivery/return reset).
  - Cycle-strict delivery video (`deliveryVideoSatisfied`) and return evidence (`belongsToCurrentReturnCycle`).
  - Unit-mismatch answer clearing (`applyChecklistContext`).
  - Server 409 `EQUIPMENT_ASSIGNMENT_CONFLICT` → Needs Attention with the work kept.

### 0.4 Reference lists used by the checklist
- Already refreshed by the normal app flow:
  - the **price list** at launch (`SplashViewController.swift:34`);
  - the **store** and **category** lists by Dispatch (`DispatchListViewController.swift:2071, 186`).
- **Employees** (`EmployesList`, used for the required employee), **equipment** (`EquipmentList`), **product settings** and **users** (`OrderDetailUserData`, used for notes) are loaded **only** by the checklist, license, rental-ready, machine-profile and Order Details screens.
- **Offline failures overwrite cached lists with `[]`.**
  - For example, `getEmployeeList` calls `completion([])` after serving the cache (`CategoryListFile.swift:277-288`).
  - `CheckListViewController.swift:210-213` then clears `arrMachineList`.
  - A phone that has the lists can still lose them on screen while offline.

### 0.5 What is already local-first (Phase 4 does not change these)
- Checklist prepare, complete and reset, and switch_equipment (`ChecklistOperations.swift`, `PreparationLifecycle.swift`).
- Media and license (`MediaOperations.swift`).
- `terms.accept` evidence.
- Driver checklist, Assembly availability acknowledgements, and fulfillment inputs / override.
- The leg-completion gate, Needs Attention (retained, `satisfiedNeedsAttention`), and checklist drafts and completion markers (`kPendingCheckList_*`, `kCheckListOrderDetailsData_*`).

---

## 1. Approach — keep the screen flow by preloading the caches the screens already read

Every screen on the path already works **cache-first**. The only reason a never-opened mission fails offline is that the first cache write happens during an online open.

**Phase 4 writes, from the mission package, the canonical server payload that each screen would have cached after an online open, into that screen's existing cache:**

| Screen | Existing cache (unchanged format) | Bridged from |
|---|---|---|
| Equipment checklist (canonical questions, unit, cycle) | `ChecklistContextStore` (`<opuid>__<leg>`) | package `checklist_context` (already shipped) |
| Order Details | MMKV `kOrderDetailData_<order uid>` (`OrdersListModel`) | package `order_details` (**B1**) |
| Checklist screens' order model | MMKV `kOrderDetailsData_<order uid>` (`OrdersModel`) | the same `order_details` (**B1**) |
| Assembly Review (Delivery) | UserDefaults `kQueueLineAssembly_<order uid>` | package `assembly` (**B2**, delivery missions) |

- There is **no parallel offline workflow and no second checklist cache.** Each bridged artifact is byte-for-byte the canonical response shape the online path writes, decoded by the same models.
- Inspection shows the flow **can** be preserved: once those caches exist, nothing on the path needs a network read except T&C (Phase 5). The rest of this plan makes the bridge safe (freshness, identity, company, sign-in) and fixes the offline defects the path exposes (§0.3 G-A–G-D, the list overwrites in §0.4, and the §0.1 crash hazards).

---

## 2. Data classification and backend gaps

### 2.1 The three buckets

**(a) Already in the Phase 3 mission package**
- `checklist_context`, the canonical context for that order product and leg: identity (execution, cycle, status), equipment (assignment, unit, tank and hours facts), template (id, revision), requirements, questions and answers (`previous_answer_id`, `prepared_answer_id`), operational, server_state (staged, in-transit, blockers, signature and media presence) and employee.
- `dispatch.row`: the Driver Checklist and Dispatch card fields, the delivery address, `product_data`, both employees, and the unit's store.
- `terms`: status and page URL.

**(b) Already in another durable store on the phone**
- Sync Engine operations: chips and gate evidence, stage, media, license, terms, checklist prepare/complete/reset, substitution, availability.
- Checklist drafts and completion markers.
- The note queue `kOrderNoteData`.
- The price list (launch), and the store and category lists (Dispatch).

**(c) Genuinely missing: needed only for Order Details and the checklist screens**
- **G1 — the `POST orders/details` `order` payload**, for the whole order (every line).
  - Order Details reads: billing address, notes, `subtotal`/`tax_amount`/`amount`, `payment_status` (a value of "failed" hides the tiles, ODVC:614-618), `status`, `license[]`, `terms_status`/`terms_page`.
  - For every line it also reads: `quantity`, `product_data`, `delivery_media[]`/`pickup_media[]`, and the store names.
  - The checklist screens read the same payload as `OrdersModel`/`ProductModel`: `equipment_details`, `equipment_category`, `product.checklist_id`, notes, `delivery_by`/`pickup_by`, signature URLs, hours, fuel, cleaning, `allocated_hours`, `customer_checklist_questions` (the legacy fallback), `is_delivered`/`is_returned`.
  - The package's `dispatch.row.order` has only id, unique_id, order_number, customer_name, customer_phone and delivery_address, so it cannot stand in.
- **G2 — the Queue Line Assembly Review envelope** (`GET queue-line/orders/{uid}/assembly`) for Delivery. The Delivery checklist can only be reached through Assembly Review.
- **G3 — the employees, equipment, product-settings and users lists**, if this phone has never loaded them. **This is not a backend gap:** the existing endpoints are warmed on existing triggers (§4.5, P4-D6).

**Explicitly not proposed**
- Payment aggregates and labels (`payment_status_label`, `amount_paid`, `balance_due`): iOS doesn't read them, and they cost queries per mission.
- Media thumbnails offline: they are URLs and stay online-only.
- Offline payment, address edit or states list: they stay online-only.
- T&C content: Phase 5.

### 2.2 Proposed smallest canonical package additions (**require approval — P4-D2**)

**B1 — `order_details`:** exactly the `order` object that `POST orders/details` returns.
- Following the Phase 3 B0 pattern (one mapping, no second contract), extract `Orders\ShowController`'s load plus relation assembly (backend `ShowController.php:31-111`: the order relations, and each line's hard/soft/none checklist question arrays set up through `setRelation`) into **one** service, for example `app/Services/Orders/OrderDetailsPayload::for(Order $order): array`.
  - `ShowController` returns `['success'=>true, 'message'=>…, 'order'=>OrderDetailsPayload::for($order)]`, byte-identical to today.
  - The package builder embeds `order_details => OrderDetailsPayload::for($row->order)`.
- **Parity test:** the package's `order_details` deep-equals `POST orders/details` `order` for the same order. It is the same code path, so this is full equality, not just the consumed paths.
- An order is built **once per packages request**, with a request-scoped memo by order id, so the lines of one order share it.
- It is duplicated across missions of the same order. This is accepted: packages are downloaded only when a revision changes.

**B2 — `assembly`** (delivery missions only): the Assembly Review envelope `{data, meta:{generated_at, employee}}` from the same `QueueLineAssemblyPresenter::forOrder` the endpoint uses (backend `QueueLineAssemblyController.php:31-56`).
- **Parity test** against `GET queue-line/orders/{uid}/assembly`.
- Return missions carry `assembly: null`, because the Return path has no Assembly Review.

**Build isolation (extends Phase 3 Minor #3):** B1 and B2 are each built in their own try/catch inside the package builder.
- A failure ships the package with that key set to `null`: the Dispatch card and the canonical checklist context still arrive.
- It is reported only server-side, never with exception text.
- A package missing B1 still passes validation; the phone just does not bridge Order Details for it.

**Revision coverage (P4-D3).** Whatever Order Details and Assembly Review render must reach offline phones when the office changes it; otherwise a gate code added to the notes at noon never reaches a phone that goes offline at 1 pm. The options:
- **(a) Snapshot only.** `order_details`/`assembly` are refreshed only when the mission revision changes for another reason. Cheapest, but office edits to notes, billing, payment status or sibling lines do not propagate.
- **(b) Batched order fingerprint in the mission revision (recommended).** Hash a cheap fingerprint built from **eager-loaded relations only**:
  - the order columns Order Details renders (`subtotal`, `tax_amount`, `grand_total`, `last_payment_status`, `terms_status`);
  - billing and shipping address columns;
  - notes (id, note, updated_at);
  - license media ids;
  - every line's rendered columns (unique_id, product_name, quantity, is_delivered, is_returned, store ids, equipment ids) and media ids;
  - for delivery missions, the order's Queue Line and assembly inputs (queue items staged/stage, availability acknowledgements, option selections).
  - It adds a constant number of statements per manifest, not per mission, keeping the manifest under the 450-statement cap. That is measured in B1, and any cap change is justified in the test.
  - Each fingerprint source gets a mutation test in `DispatchOfflineRevisionCompletenessTest`, plus no-churn tests for noisy siblings.
  - **Side effect:** more office edits now trigger the existing debounced silent wake (≤ one per ~2 minutes). This is server-driven; there is still no phone polling.
- **(c) Hash the full payloads.** Rejected: `Orders\ListResource` runs payment-summary queries per mission (`OrderPaymentSummary::for`, `total_paid`, `balance_due`, backend `Orders/ListResource.php:63-75`), which breaks the 450-statement cap. The per-minute wake watcher would also pay that cost.

**Performance:**
- B1/B2 cost is paid on the **packages** endpoint, per distinct order, and only for missions whose revision changed.
- A packages-endpoint statement guard (linear in orders, bounded per order) is added.
- Manifest cost changes only by the fingerprint's eager loads (option b).

**Fixture:** `dispatch_offline_packages.json` is regenerated with `order_details` and `assembly`. The mobile copy stays byte-identical, and contract tests on both sides pin the shape.

---

## 3. Decisions requiring approval

| # | Proposed decision | Recommendation |
|---|---|---|
| **P4-D1** | **Keep the screen flow by bridging the package into the caches the screens already read** (§1). No parallel offline workflow and no second checklist cache. | Approve |
| **P4-D2** | **Backend contract additions B1 `order_details` and B2 `assembly`** (§2.2), built by one shared extraction from `ShowController` and the existing assembly presenter, parity-tested, with per-key build isolation. | Approve |
| **P4-D3** | **Revision coverage for B1/B2:** option **(b)**, a batched order fingerprint in the mission revision, accepting more (debounced) office-edit wakes; the manifest cap is re-measured. The alternative is (a), snapshot only. | (b) |
| **P4-D4** | **Offline substitution and restart:** the action is still recorded durably, local-first as today. The **replacement unit's or new cycle's checklist then shows "This unit's checklist needs a connection"**: it never uses the replaced unit's context and never reuses a superseded execution (fixes G-A–G-D). The old unit's answers stay cleared, as today. The alternative is to block substitution and restart while offline. | Record durably + "needs a connection" |
| **P4-D5** | **A bridged context's `employee` is the user signed in now**, taken from the local profile, not the user who downloaded it. This matches what the online endpoint would return for this phone's user and keeps `performedBy` and restart attribution correct on a shared phone. If there is no local profile, the package's value is kept. | Approve |
| **P4-D6** | **Reference-list warm-up:** on the existing reconciliation triggers (launch, login, foreground, network restored — **never a timer**), when online, fetch the employees, equipment, product-settings and users lists through their **existing** endpoints, but only if that list's cache is empty or older than **12 h**. **Also fix** the offline overwrite of cached lists with `[]` (§0.4). | Approve |
| **P4-D7** | **Order Details offline states (no redesign):**<br>• A bridged or cached copy renders as today. Offline it adds one slim freshness line reusing the Dispatch/Queue Line `QueueLineFreshness` wording, "Offline · showing the order saved at …". Order Details has no freshness line today.<br>• With no copy at all (for example the package failed B1), show **"This order isn't downloaded to this phone yet"** instead of an endless skeleton.<br>• Fix the three nil-model crash hazards. | Approve (the freshness line is optional) |
| **P4-D8** | **T&C boundary in Phase 4** (§4.7): offline, the T&C tile opens a clear **"Signing Terms & Conditions needs a connection"** state, not a blank web view. The Delivery leg can then be completed only through the **existing** Warning/override path, with T&C recorded as unmet and a reason captured, or completed later online. Phase 5 makes signing work offline. | Approve |
| **P4-D9** | **Bridge ledger:** a small metadata file (no payload) recording, per order uid and per mission key, the last bridged package revision and its server-observed time. It prevents re-bridging the same package over a fresher online write. Order Details / `getOrderDetails` / Assembly Review stamp it when they save a live response. **This is not a second cache;** the data lives only in the existing caches. | Approve |
| **P4-D10** | **Phase 3 §9's "full ChecklistContext validation of packages"** means **validation when bridging only**: a `checklist_context` that fails to decode is simply not bridged (diagnostic logged). The package stays presentable, keeping the Phase 3 opacity rule and its test (`testAChecklistContextIsOpaqueInPhase3`). | Approve |
| **P4-D11** | **Lines with no canonical context** (for example a sibling line that is not an active mission): Phase 4 keeps today's behavior (the legacy questions from `order_details`, and the durable `legacy_customer_checklist.submit`). Canonical offline execution is guaranteed for **active mission lines**, which always carry a bridged context. | Keep existing |

---

## 4. Mobile design

### 4.1 Bridge components
- **`DispatchOfflineFieldBridge`** (Sync Core, Foundation only, covered by `swift test`) holds the decisions:
  - `contextDecision(package:existing:operations:) → .write(context) | .skip(reason)`
  - `orderDetailsDecision(package:ledger:) → .write | .skip`
  - `assemblyDecision(...)`
  - ledger updates
  - It writes checklist contexts directly into `ChecklistContextStore` (a Core type) and hands `order_details`/`assembly` to App-layer writers through a small protocol.
- **`DispatchOfflineOrderBridge`** (App layer, new file, hosted tests) writes the existing caches:
  - `kOrderDetailData_<uid>` through `OrdersListModel` (the save Order Details already uses, ODM:160);
  - `kOrderDetailsData_<uid>` through `OrdersModel` (the same save as `OrderDetailsFile.swift:89`);
  - `KabbaAssemblySync.cache(envelope, orderUniqueId:)`.
  - It then **re-applies queued local notes** (`kOrderNoteData`) onto the fresh copy, using the same patch Order Details uses today (ODVC:1677-1794, extracted into a shared function), so a bridge never hides a note written offline.
- **When the bridge runs** (`DispatchOfflineSync`):
  - After every reconciler commit that stores a new package revision, on the reconciler's queue, then on the main queue for MMKV.
  - Once at launch for packages already on disk, which makes a relaunch or an interrupted bridge idempotent through the ledger.
  - **Only for the current tenant and session:** the Phase 3 session-bound reconciler and tenant key. A different company's packages are never bridged.

### 4.2 Checklist-context bridge rules (`DispatchOfflineFieldBridge.contextDecision`)
1. **Decode** `package.checklist_context` with `ChecklistContext.decode(envelopeData:)` (bare object). If it fails, skip (P4-D10).
2. **Identity:** `identity.order_product_unique_id` and `.leg` must equal the package's own. Phase 3 already validates this; re-check it.
3. **Never overwrite fresher truth:** skip when the stored context has a later `server_time` (server clock, ISO-8601) **or** a higher `identity.cycle`.
4. **Never write a superseded context:** skip when its `checklist_execution_id` ∈ `EffectiveFieldState.supersededExecutionIds(engine.snapshot())`, **or** when the order product has a local discard (`lastDiscardAt`) later than the package's `serverObservedAt`. A local substitution or reset newer than the download wins; the phone waits for the server's new cycle.
5. **Employee:** replace `employee` with the signed-in user when they differ (P4-D5).
6. **Save** with `ChecklistContextStore.save`. Contexts are **never deleted** by the bridge, by mission removal or by Phase 3 GC; the Phase 3 byte-identity tests stay green.

### 4.3 Order-details and assembly bridge rules
- **Write** a package's `order_details`/`assembly` only when the ledger says **this package revision has not been bridged for that order**, **and** the package's server-observed time is later than the ledger's last write for that order. A live `orders/details` or assembly fetch stamps the ledger too, so a fresher online copy is never overwritten by an older package.
- **Multi-line orders:** the newest package (by server-observed time) among the order's missions wins.
- **Local work is never touched:** local availability acknowledgements are a Sync Engine overlay (not in the cache), drafts and markers are separate keys, and queued notes are re-applied (§4.1).

### 4.4 Context fallback correctness (fixes G-A–G-D)
Add **`ChecklistContextFallbackPolicy`** in Core; `ChecklistContextClient` (App) calls it. A cached context may be served offline **only if**:
- its execution is not superseded by local discard evidence;
- its unit matches the requested unit hint, when a hint is given;
- no local discard for that order product is newer than it.

Otherwise the client returns **`.unavailableOffline`**. `CheckListViewController` then shows that product's **"This unit's checklist needs a connection"** state (P4-D4). It does not revert `objMachine`, does not reuse the old execution, and does not fall back to legacy questions for that product. Online behavior is unchanged: network first, the 409 retry without the hint, and 4xx handling.

### 4.5 Reference-list warm-up and the offline-overwrite fix (P4-D6)
- `DispatchOfflineSync` runs a warm-up **after** a successful reconciliation on a launch, login, foreground or network-restored trigger (never a timer, never a wake). It fetches the employees, equipment, product-settings and users lists through their existing functions, only if the cache is empty or older than 12 h. A per-list timestamp is stored beside each list.
- **Fix:** the list loaders (`getEmployeeList`, `getEquipmentList`, `getStoreList`, `getCategoryList`, `getPriceList`, `getProductSettingList`, `getDriverEmployeeList`) no longer call `completion([])` after serving a cache when the request fails. They keep the cached list, and `CheckListViewController` no longer clears `arrMachineList` on an offline failure.

### 4.6 Screens (minimal changes, no redesign)
- **Order Details:**
  - Renders from the bridged `kOrderDetailData_` through its existing cache-first path; the live refresh is unchanged.
  - Loading is extracted into `OrderDetailsCache.load(orderUniqueId:)` so a hosted test can prove the bridged copy renders.
  - Adds the P4-D7 states and nil-model guards: "+View Billing", Return and Delivery Photo/Video, Add Note.
- **Assembly Review:** renders the bridged cache. No change beyond stamping the ledger when it saves a live response.
- **Equipment checklist:** renders from the bridged `kOrderDetailsData_` plus the bridged contexts, through the existing path. The changes are:
  - the per-product "needs a connection" state (§4.4);
  - the list-overwrite fix (§4.5);
  - stamping the ledger on live saves.
- **Answers, prepare/complete, media, signature and completion markers:** unchanged, already local-first.

### 4.7 T&C boundary (P4-D8)
- **Online:** unchanged.
- **Offline**, when `terms_status` is not Accepted/Exempt and there is no `terms.accept` evidence: the T&C tile opens a non-blank screen that says Terms & Conditions need a connection to sign. It must not crash; today an empty or nil `terms_page` would hit the `URL(string:)!` force-unwrap.
- **The Delivery leg:** T&C stays an unmet requirement. The existing Complete → `WarningViewController` override records the reason durably, as it does today for any unmet requirement.
- **Nothing in Phase 4 renders or signs Terms content offline.** The package's `terms.offline_content_available` stays `false` until Phase 5.

### 4.8 Required behavior per scenario

| Scenario | Behavior |
|---|---|
| Package cached, context not yet bridged | The bridge runs on the next commit and at launch. If a screen opens first, the client's store lookup finds nothing: online it fetches as today; offline it shows "needs a connection" for that product. Relaunch bridges from disk. |
| A context already exists from an earlier online open | Keep whichever is fresher (later `server_time` or higher cycle). An older package never overwrites a newer online context. |
| The Phase 3 package carries a newer revision | Re-bridge. The newer `server_time` wins, unless local discard evidence is newer (rule 4). |
| Equipment substitution changes assignment or cycle — **server side** (office, web, another phone) | New manifest revision → new package → bridged context for the **new unit and cycle** replaces the old one. `applyChecklistContext` clears the old unit's on-screen answers (existing). Queued operations against the old execution are kept; the server answers 409 and they go to Needs Attention (existing, spec §14.3). |
| Equipment substitution — **on this phone while offline** | The `queue_line.switch_equipment` operation is durable (existing). The old unit's cached context is **never** served for the replacement (§4.4). The replacement's checklist shows "needs a connection" until the server's new cycle arrives by package or online fetch (P4-D4). |
| A stale checklist context from the replaced unit | It can never satisfy the replacement unit: the fallback policy rejects it, bridge rule 4 blocks re-writing it, and cycle-strict media and return evidence rules apply (existing). |
| Offline relaunch | Contexts, order caches, assembly cache, ledger, drafts, markers and Sync Engine operations are all durable and protected. The screens re-render from them, and the bridge re-runs idempotently. |
| Partial synchronization | Pending operations keep syncing FIFO per order product. A newer bridged context with the same execution id updates prefill (`prepared_answer_id`). A different execution (a server-minted cycle) means the old operations are kept and may go to Needs Attention. Drafts are never deleted by the bridge. |
| A mission removed from active Dispatch while unsynced checklist work remains | It leaves Dispatch (Phase 3). Its package is retained while any operation references the order product (D7). Bridged contexts and order caches are **not deleted**, and the work syncs or goes to Needs Attention as today. Pruning of bridged caches is deferred, as a watch item. |
| Return leg vs Delivery leg | **Return:** no Assembly Review. The Return checklist opens from Order Details once delivery is effectively complete (existing). The return context carries `previous_answer_id`; `store_required` uses the stores list (warmed by Dispatch). Bridging the return context sets Order Details' `activeReturnExecutionId`, so return evidence captured on this phone for **that** execution keeps counting. **Delivery:** requires B2 (Assembly Review) plus the context; the stage and in-transit gates come from `server_state` and the assembly (existing). |
| An unassigned delivery (`assignment: none`) | The package has no questions. The checklist needs a unit to be chosen, and that needs the online `selected` path, so it shows "needs a connection" (P4-D4). |
| T&C reached offline | §4.7. |

---

## 5. Expected files and components

**Backend** (branch `feature/dispatch-offline-phase-4`, only if P4-D2/D3 are approved)
- New `app/Services/Orders/OrderDetailsPayload.php`, extracted from `Orders/ShowController.php`, which now calls it.
- `app/Services/Dispatch/Offline/DispatchOfflineMissionPackageBuilder.php`: `order_details`, `assembly` (delivery), per-key isolation, request memo.
- `DispatchOfflineMissionSelector.php` (`WITH` additions for the fingerprint), `DispatchOfflineMissionRevision.php` (fingerprint, if option b), and possibly a new `DispatchOfflineOrderFingerprint.php`.
- Tests:
  - new `tests/Feature/Dispatch/Mobile/DispatchOfflineOrderDetailsParityTest.php` and `DispatchOfflineAssemblyParityTest.php`;
  - additions to `DispatchOfflineRevisionCompletenessTest`, `DispatchOfflineManifestPerformanceTest`, `DispatchOfflinePackagesTest` (isolation, memo) and `DispatchContractFixturesTest`;
  - a regenerated `tests/Fixtures/mobile-contract/dispatch_offline_packages.json`;
  - a `ShowController` byte-equality test (response before vs after the extraction).

**Mobile — Sync Core** (`swift test`; members of the app target and the logic test bundle)
- New `RentnKing/Sync/Core/DispatchOfflineFieldBridge.swift`: decisions, ledger model, and the writer protocol.
- New `RentnKing/Sync/Core/ChecklistContextFallbackPolicy.swift`.
- `DispatchOfflineContract.swift`: optional opaque `order_details` and `assembly` accessors on the stored package.

**Mobile — App layer**
- New `RentnKing/Sync/App/DispatchOfflineOrderBridge.swift`: the MMKV/UserDefaults writers, note re-apply, and ledger stamps.
- `DispatchOfflineSync.swift` (bridge wiring, reference warm-up), `ChecklistContextClient.swift` (fallback policy, `.unavailableOffline`).
- Order Details:
  - `OrderDetailsViewController.swift`, `OrderDetailsModel.swift`, and a new `OrderDetailsCache` helper;
  - the offline states and nil guards, and the ledger stamp.
- The rest:
  - `OrderDetailsFile.swift` (ledger stamp);
  - `CheckListViewController.swift` (the "needs a connection" state per product, and no list clearing offline);
  - `CategoryListFile.swift` and `EqupmentFile.swift` (keep the cache on failure);
  - `AssemblyReviewViewController.swift` (ledger stamp);
  - `TermsAndConditionViewController.swift` (offline boundary state, no force-unwrap).
- `RentnKing.xcodeproj/project.pbxproj`: explicit membership for the new files, using the Phase 3 `pbx_add.py` method with block-definition matching only.

**Not touched:** Sync Engine operations, the checklist operation payloads, `LegCompletionEvaluator` rules, `DriverChecklistLocalState`, Phase 3 reconciliation and freshness rules, Manual Dispatch, and T&C content.

---

## 6. Tasks (TDD, in order; each ends with a local commit)

- **M0 — Contract.**
  - Decode the fixture's `checklist_context` into `ChecklistContext`, closing the §0.2 gap.
  - Add optional opaque `order_details`/`assembly` on stored packages; an older server that omits them still decodes.
- **B1 — Backend (after approval).**
  - Extract `OrderDetailsPayload`, with the `ShowController` byte-equality test.
  - Add `order_details`/`assembly` to the package, with parity tests, isolation and memo.
  - Add the fingerprint (P4-D3), with revision-completeness and no-churn tests and the performance re-measure.
  - Regenerate the fixture and copy it byte-identically to mobile.
- **M1 — Checklist-context bridge policy** (Core): rules 1–6 with red/green tests.
- **M2 — Fallback correctness** (Core policy plus the App client): fixes G-A–G-D, and the per-product "needs a connection" state.
- **M3 — App writers:** the order-details caches (both models), the assembly cache, the ledger and note re-apply, with hosted tests.
- **M4 — Wiring:** bridge after commits and at launch, current tenant only, idempotent, off the main thread except the MMKV writes.
- **M5 — Reference warm-up and the offline list-overwrite fix.**
- **M6 — Screens:** Order Details states and guards (P4-D7), the T&C boundary (P4-D8), and the checklist "needs a connection" UI.
- **M7 — Automated acceptance scenario, plus substitution and reset tests** (§7).
- **M8 — Verification and the fresh independent review gate** (§9).

---

## 7. Test structure and traceability

### 7.1 The key physical scenario, automated
**Core (`DispatchOfflineAcceptanceTests`, `swift test`):** a `FakeDispatchServer` serves fixture-derived packages that include `checklist_context`, `order_details` and `assembly`, with a real `SyncEngine` over a temp directory.
1. The phone reconciles while online; the bridge runs. The user never opens the mission.
2. The network disappears (the server goes offline; no requests are made after this point).
3. The cached Dispatch row is presented; the Driver Checklist stage is derived (existing overlay).
4. The Order Details payload has been handed to the writer for that order uid, with the mission line present.
5. `ChecklistContextStore` returns the bridged context with the package's execution id, cycle, unit, template revision and canonical question ids, and `ChecklistContextFallbackPolicy` allows serving it offline.
6. A `delivery_checklist.prepare` operation is enqueued offline with that execution id and `context_revision`.
7. Force-quit and relaunch (new store and engine instances over the same directories): the context, ledger and pending operation survive, and a re-bridge is a no-op.

The same scenario is repeated for the Return leg (no assembly; `previous_answer_id`).

**Hosted (`DispatchOfflineAcceptanceHostedTests`, signed Simulator):** the same data through the **real** App pieces.
- The bridged `kOrderDetailData_` decodes through `OrdersListModel` and `OrderDetailsCache.load`, which renders a non-nil model with the mission line.
- `kOrderDetailsData_` decodes through `OrdersModel`.
- `kQueueLineAssembly_` decodes through `AssemblyReviewEnvelope` with the mission member.
- `ChecklistContextClient` offline returns the bridged context; `ChecklistCaptureFactory.questionModels` yields the canonical questions, and `machine(from:)` the current unit.
- A prepare operation is enqueued through the real handlers into an offline engine.
- A relaunch reads everything back.
- There are no network calls: an offline HTTP client, and no real base URL.

### 7.2 Required tests (red first)

| # | Requirement | Where |
|---|---|---|
| 1 | Package `checklist_context` decodes as the canonical `ChecklistContext` (delivery and return) | Core contract |
| 2 | Bridge writes a never-opened mission's context; identity mismatch or decode failure → skipped, package still presentable | Core bridge |
| 3 | An existing fresher online context (later `server_time` or higher cycle) is never overwritten | Core bridge |
| 4 | A newer package revision re-bridges; the same revision is a no-op (ledger) | Core bridge |
| 5 | A superseded execution, or a local discard newer than the package, is never bridged | Core bridge |
| 6 | The bridged `employee` is the signed-in user (P4-D5) | Core bridge |
| 7 | Only the current tenant and session bridge; another company's packages never do | Core bridge |
| 8 | **An old unit's cached context cannot satisfy the replacement unit:** offline substitution → fallback refuses → `.unavailableOffline`, no revert of `objMachine`, no operation on the superseded execution | Core fallback + hosted |
| 9 | Offline restart never reuses the superseded execution | Core fallback |
| 10 | Server-side substitution → newer package → the context for the new unit and cycle replaces the old; old-unit video and return evidence do not count (existing rules re-asserted) | Core |
| 11 | Order-details bridge writes both caches; a fresher live copy (ledger) is not overwritten; queued notes are re-applied | Hosted |
| 12 | Assembly bridge writes the Assembly Review cache; local acknowledgements remain an overlay | Hosted |
| 13 | Order Details: bridged copy renders; with no copy it shows "isn't downloaded" (no endless skeleton); nil-model controls cannot crash | Hosted |
| 14 | T&C offline boundary: non-blank state, no force-unwrap, and completion only through the existing override | Hosted |
| 15 | Reference warm-up only on the listed triggers when stale or empty; offline failures keep cached lists | Core policy + hosted |
| 16 | Mission removal / GC never deletes bridged contexts or order caches (Phase 3 byte-identity tests extended) | Core |
| 17 | Automated acceptance scenario, Delivery and Return (§7.1) | Core + hosted |
| 18 | Backend: parity (B1 vs `orders/details`, B2 vs assembly), `ShowController` byte-equality, per-key isolation, revision completeness and no-churn for each fingerprint source, manifest and packages performance guards, fixture shape | Backend |

---

## 8. Carried over from Phase 3 — deferred and watch items (Phase 3 is closed; not modified)

**For physical acceptance (Phase 6) — watch items**
- **Fallback threshold (Minor, 4th review):** the live-feed fallback applies only when **no** package is presentable. A partial first download stays on the partial cache (flagged not current), so a driver whose missions are all missing may see "No results found." under that flag. While already in the fallback, the first presentable package switches back to a mostly-missing cache.
- **A permanently unbuildable package (Minor, 4th review):** every run stays partial. The header remains, foreground and Dispatch-open back off up to 300 s, the "wake already applied" skip never applies, and wakes report `.failed`.
- **All Drivers fallback (Nit, 4th review):** the fallback shows the signed-in user's feed, with no indication.
- **Freshness (Nit, 4th review):** `.notDownloaded` with a non-failing answer online maps to `.current`. If every package file is corrupt within 20 s of a complete run, this means a spinner until the next trigger.
- **Snapshot hidden after a fallback (Nit, 4th review):** offline after a fallback, the MMKV feed snapshot is hidden behind "isn't downloaded".
- **F5 (Minor, 2nd review):** the store's in-memory package cache is unbounded, and a cold run decodes every package.
- **F7 (Minor, 2nd review):** "Today" uses the phone's time zone.
- **F12 (Nit, 2nd review):** an online driver switch still sends the D4 manual rider / D3 named-driver feed.
- **3rd review #4:** switching company A → B → A inside one run can leave two reconcilers on A's directory.
- **3rd review #5:** a cross-company switch between the pre-request check and the URL read.
- **Context store (new, from Phase 4 inspection; not Phase 3 behavior):** `ChecklistContextStore` is not tenant-scoped and is never pruned. The same applies to the MMKV order and assembly caches; bridged caches are not pruned in Phase 4 either.

**For the cosmetic / screen-flow pass**
- **F6 (2nd review):** a dated offline header appears over "Dispatch isn't downloaded to this phone yet".
- **"Offline" wording:** after a failure while online, the header says "Offline · showing the list saved at …" (3rd review #6), and so does a failed D3 feed (4th review).
- **F13 (2nd review):** the named-driver All view repaints the cache before the feed.

**For test hardening**
- F10 (hosted fixture via `#filePath`), F11 (no dedicated file-protection test), 3rd review #7 (no core test for moving between driver filters).
- `unavailable` is pinned only by the contract tests (4th review), and there is no view-controller test for leaving the fallback.
- F14 (`removed` over-counts), F8 (`store.state` lazy load), F9 (adapter maps a whole number to nil for `Double`).

---

## 9. Closing gate (proposed)
Phase 4 closes only when all of these pass:
- all §7 tests (red first, then green);
- the complete mobile core and signed hosted suites;
- the simulator build;
- the no-polling/timer/GPS/socket gate;
- the affected backend regression **from the final backend HEAD**:
  - `tests/Feature/Dispatch`, `tests/Feature/Api`, `tests/Feature/Mobile`, `tests/Unit/Push`;
  - `tests/Feature/QueueLine`, for the assembly presenter;
  - `tests/Feature/Orders` and `tests/Feature/CustomerChecklists`, for the `ShowController` extraction and question arrays. Their existing baseline failures must match the Phase 2/3 baseline **by test name**.
- both worktrees clean with no upstream;
- a **fresh independent reviewer** reporting no Critical or Important issues.

Then stop before Phase 5.

## 10. Physical acceptance boundary and deferred scope
- **Optional Phase 4 device smoke** (local staging only, never production): reconcile online → airplane mode → open a never-opened Delivery and Return → Driver Checklist → Order Details → Assembly Review / checklist → save answers → force quit → relaunch → the state is intact.
- **Phase 5:** a versioned offline T&C snapshot, local rendering, local signing through the Sync Engine, durable sync, and preserving the exact signed revision. Inspection notes for Phase 5: acceptance content is generated from `order.terms_collection`, while the page renders live Terms, so the two can diverge (backend `Front/TermsAndConditions/PostController.php:70`).
- **Phase 6:** full physical multi-stop acceptance (spec §17) and the watch items in §8.
- **Not in Phase 4:** choosing any unit offline (`selected`), offline payment and address edits, offline media thumbnails, pruning bridged caches, tenant-scoping the legacy MMKV caches, and Manual Dispatch.
