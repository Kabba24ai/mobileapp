# Dispatch Offline Phase 3 — iOS Durable Mission Cache + Reconciliation Coordinator — Implementation Plan

> **Status: APPROVED with locked decisions D1–D7 (Gary, 2026-09-23); see §2.** Gap G1 is resolved by B0 (§1), which runs first on the backend branch.
> Rules for execution: TDD task by task (failing test → prove the failure → minimum code → focused and regression tests → review the diff → local commit). Local only: no push, merge, deploy, SSH, production data, feature flag, version/build bump, archive, or App Store upload.
> **Phase 3 closes only after all of these pass:**
> - B0 backend parity and revision tests;
> - all 18 planned mobile cache/reconciliation scenarios (§6);
> - the complete affected backend regression;
> - the complete mobile core suite (`swift test`);
> - the simulator build;
> - a fresh independent reviewer reporting no Critical or Important issues.
>
> Then stop before Phase 4.

**Goal:** Every Kabba iPhone keeps a durable, company-wide offline Dispatch working set: all still-open overdue missions plus today and the next two calendar days, for all drivers. It reconciles that set against the Phase 1 manifest on every trigger (silent wake, launch, login, foreground, Dispatch open/refresh, network restoration), and the Dispatch screen renders from it immediately.

**Spec:** `docs/superpowers/specs/2026-09-22-dispatch-offline-mission-cache-design.md`: §5, §7, §11–§14, §15, §16, §17 (iOS), §18 step 3, §19.

**Builds on (local branches, no upstream):**
- Backend `feature/dispatch-offline-phase-2` @ `098a68c64` (worktree `/Users/garyjezorski/Documents/kabba2_AI-dispatch-offline`). It contains Phase 1 (manifest and packages) and Phase 2 (installation registry, silent FCM wake).
- Mobile `feature/dispatch-offline-phase-2` @ `f460081` (worktree `/Users/garyjezorski/Documents/mobileapp-dispatch-offline`).
- **This plan's branch:** mobile `feature/dispatch-offline-phase-3`, cut from `f460081`, worktree `/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p3`, no upstream.

**Baseline (2026-09-23, Phase 3 worktree at `f460081`):** `swift test` passes **334/334**.

---

## 0. What the inspection found (the contracts Phase 3 builds on)

| Contract | Actual shape (from the Phase 2 branches, not old `origin/main`) |
|---|---|
| Manifest | `GET dispatch/offline/manifest` (relative to `Application.BaseURL_NEW` = `…/api/admin/v1/`, from the login `api_url`). `data.revision` and each `missions[].revision` are **64-hex sha256 strings**, not the integers shown in the spec example. Each mission has `mission_key` = `order_product_unique_id:leg`, `order_product_unique_id`, `leg` (`delivery`\|`return`), and `effective_date` (Y-m-d). `horizon.through_date` = server today + 2 in the app timezone. The list is complete and unpaginated, and empty is a valid state. The endpoint is read-only. |
| Packages | `POST dispatch/offline/packages` with body `{"missions":[{"order_product_unique_id","leg"}]}`, **1–100 per request** (`PackagesRequest::MAX_MISSIONS`). Returns `data.packages[]` and `data.not_active[]` (mission keys no longer in the live set). Each package: `mission_key`, `revision` (post-build), `order_product_unique_id`, `leg`, `dispatch` (stable summary, hashed into the revision), `checklist_context` (the canonical `ChecklistContext` shape plus `employee`/`server_time`), `terms` (`status`, `page_url`, `offline_content_available: false`). |
| Package side effect | Each package runs `buildContext()`, which may mint a checklist execution. Only in the existing canonical backstop does it also supersede a prepared cycle whose unit changed and un-stage its Queue Line item. The online checklist-context endpoint behaves the same way. Background downloads can therefore trigger that backstop sooner than a person opening the checklist would. This is accepted Phase 1 behavior, not changed here. |
| Silent wake | FCM data `type=dispatch_changed`, `dispatch_revision` = the settled **manifest revision** (the same value as manifest `data.revision`). Handled in `NotificaiotnFile.swift` `didReceiveRemoteNotification:fetchCompletionHandler:`, which currently returns `.noData` before the badge increment. |
| Working-set rule (server) | Truck legs assigned to an active driver. Delivery: `delivery_status=Pending`. Return: `delivery_status=Completed` and `pickup_status=Pending`. So there is at most **one active mission per order product**, which matches the one-card-per-row Dispatch feed. |
| Tenant | `UserDefaults.baseURL` is set from the login response's `api_url` and cleared on logout and on a real 401. The backend deployment is single-tenant, but one phone can sign in to different deployments (RentnKing and Kabba). **The phone-side tenant is the base URL.** |
| Mobile durable-storage idiom | `<Application Support>/KabbaSync/…`, excluded from backup. `FileSyncOperationStore.ensureProtectedDirectory` and `writeProtected` do an atomic temp-file + rename with `completeUntilFirstUserAuthentication`, so background wakes after first unlock can read and write. `ChecklistContextStore` stores one JSON file per key under an `NSLock`. |
| Dispatch screen today | `DispatchListViewController` renders `[SchedulesModel]` (the legacy `OrderProducts\ListResource` row, ObjectMapper) from `POST orders/schedules/dispatch` (paginated, per driver, per date filter, `include_manual=1`). It is cached in MMKV per `schedule_type × day × driver`, with `manual_jobs` riding on page 1. "All Drivers" sends an empty `driver_id`, which the server **scopes to the logged-in user** under `include_manual=1`. |

### Test-infra finding (from Phase 2, fixed in M0)
`Scripts/test-sync-core.sh` detects the toolchain with `$DEVELOPER_DIR/usr/bin/xcrun`, which does not exist on the installed Xcode (`xcrun` lives in `/usr/bin`). The script therefore always takes its `swiftc` fallback. That fallback cannot compile `DispatchWakeTests.swift` (Phase 2), because it is the only test file without the `#if canImport(KabbaSyncCore)` guard. `swift test` is unaffected (334/334). M0 fixes both in their own commit.

---

## 1. Backend contract gap G1 — resolved by B0 (D1 approved)

**Phase 3 cannot present the existing Dispatch card, or open the Driver Checklist, from a Phase 1 package.** The package's `dispatch` block is a compact summary. The Dispatch card, the Driver Checklist (Screen 2) and the Assign Driver screen all read the full legacy `SchedulesModel` row, and several of those values are absent or have different meanings:

| Needed by the current UI (file) | Legacy feed row (`OrderProducts\ListResource`) | Phase 1 package `dispatch` |
|---|---|---|
| Green progress band, Start button colour, `DriverChecklistRouting`, Screen 2 restore (`hasSavedDriverProgress`, `DriverChecklistViewController`: `ready_to_go_at`, `arrived_at`, `is_arrived`, `equipment_fuel`, `equipment_key_location`, `equipment_driver_status`, `call_customer`, `driver_checks`) | `delivery_checklist{…}` / `pickup_checklist{…}` | **absent**, and not in the revision, so another phone's driver progress would never propagate |
| Card header `#order.id` | `order.id` (DB id) | absent (only `order_number`, `unique_id`) |
| Customer phone / call button | `order.customer_phone` (orders column) | `order.customer_phone` is the **shipping-address phone**, a different value |
| Start / End Point store (`objEquipment.equipment_store.name`, "Pending" when none) | `equipment.equipment_store.store_name` | absent (`schedule.store_name` is the leg's delivery/pickup store, a different meaning) |
| Displayed date/time | `delivery_date`/`pickup_date` = the **scheduled** date formatted with the env-driven `DATE_FORMAT`; time formatted with `api_time_format` | only the **effective** (dispatch-adjusted) Y-m-d and raw `H:i:s`; the phone cannot reproduce the env format |
| Assign Driver screen (both employees), leg-membership predicate | `delivery_employee` **and** `pickup_employee` | only the active leg's driver |
| Card icon | `delivery_transport_mode` (used for both legs) | the leg's own transport mode |
| Product options on Screen 2 | `product_data.product_option_items` (via `transformProductData`) | `product.options` (raw) |
| Category filter | server filters on `product.categories` | absent |
| Row identity (`SchedulesModel.id`, dedupe) | `id` | absent |

A mobile-only workaround would degrade or change the card. It would drop the green band and cross-phone driver progress, show a different phone number and store, and fill in the Assign Driver screen incorrectly. That violates "do not redesign the visual Dispatch UI" and the spec's rule that the package holds the data needed to finish the stop. The legacy feed cannot stand in for the cache either: it is paginated, per driver (an empty `driver_id` means the logged-in user), and has no revisions.

### Fix B0 — additive (APPROVED as D1)
Add **`dispatch.row`**: a stable subset of exactly the legacy `OrderProducts\ListResource` row, with the same keys and values. The phone then maps it with the **unchanged** `SchedulesModel` ObjectMapper model. Because it sits inside `dispatch`, it is hashed into the mission revision automatically. Existing Phase 1 keys are untouched. Nothing from Phase 1 or 2 is deployed, so there are no migration concerns; every revision changes once, when B0 lands.

**One business mapping, not a second contract (D1 lock).** The legacy feed and `dispatch.row` are both generated from the same code:
- **New `App\Http\Resources\Api\Admin\V1\OrderProducts\DispatchRowFields`** (final, static) holds the Dispatch row logic that used to live inline in `OrderProducts\ListResource`: `identity()` (active leg, `dispatch_item_id`, `sort_key`), `delivery()` / `pickup()` (status, transport, by, priority, formatted dates and times, dispatch dates, overdue/early/late), `deliveryChecklist()` / `pickupChecklist()` (the nine driver-checklist keys), `productData()` (the former `transformProductData`), `resolvedEquipment()` (hard assignment first, then soft). **`ListResource::toArray()` is rewritten to call these**, so the legacy feed's values come from the shared methods. Its key set and values are unchanged, which `MobileDispatchParityTest`, `DispatchContractFixturesTest` and the new parity test prove.
- The heavy `Orders\ListResource` and `Equipment\ListResource` (payment summaries, location lookups) gain a static `dispatchCardFields()` for exactly the card keys, and their own `toArray()` uses it for those keys.
- The light resources (`Users`, `Stores`, `OrderAddresses`) are pure column reads, so they are reused **as they are**, through `Arr::only(resource->resolve())`.
- The offline row therefore adds no field logic of its own. It only chooses which shared keys it carries and drops the two day-dependent flags.

`dispatch.row` keys (as implemented, `DispatchRowFields::offlineRow`):
- Top level: `dispatch_source`, `dispatch_item_id`, `fulfillment_leg`, `sort_key`, `id`, `unique_id`, `product_name`, `product_data` (via the shared `productData()`), `is_delivered`, `is_returned`, and **`category_ids`** (new, additive: `product.categories` ids as ints, **sorted** so the revision never depends on load order).
- Delivery: the shared `delivery()` group minus `is_delivery_overdue` — `delivery_status`, `delivery_transport_mode`, `delivery_store_id`, `delivery_by`, `delivery_priority`, `delivery_date`, `delivery_time`, `dispatch_delivery_date`, `is_early`, `is_late_delivery` — and `delivery_checklist{equipment_fuel, equipment_key_location, equipment_driver_status, ready_to_go_at, arrived_at, is_delivered, is_arrived, call_customer, driver_checks}`.
- Pickup: the shared `pickup()` group minus `is_pickup_overdue` — `pickup_status`, `pickup_transport_mode`, `pickup_store_id`, `pickup_date`, `pickup_time`, `pickup_by`, `pickup_priority`, `dispatch_return_date`, `is_late_pickup` — and `pickup_checklist{same nine keys}`.
- Nested: `order{id, unique_id, order_number, customer_name, customer_phone, delivery_address{the OrderAddresses resource as it is}}`, `equipment{id, unique_id, equipment_name, equipment_id, is_fuel, is_key, equipment_store{the Stores resource as it is}}` (hard assignment first, else soft; `null` when none — as the feed serializes a null resource), `delivery_employee` / `pickup_employee` (the Users resource as it is, or `null`).
- Not carried (no consumer in `SchedulesModel`): `delivery_notes`, `pickup_notes`, top-level `equipment_id`, `is_soft_assigned`, `delivery_store`, `pickup_store`.

Deliberately **excluded**, because they are volatile or not needed:
- `is_delivery_overdue` and `is_pickup_overdue`. They depend on today, so they would churn every revision at midnight. The phone derives them from `effective_date` (§3.6).
- Media and signature URLs and ids; pricing and totals; `assigned_by` and `assigned_at`; `equipment_location_detail`; `assigned_equipment`; `equipment_category`; `equipment_details`; cleaning and fuel charges.

**Revision consequence (intended):** driver-checklist steps, a reassignment of either leg, and a change of the equipment's home store all bump the mission revision. After the Phase 2 debounce, that wakes phones, so driver progress propagates between phones.

**B0 tasks.** Switch the existing backend worktree to a new branch from the completed Phase 2 HEAD, **never from `main` or `origin/main`**. This leaves the Phase 2 branch intact: `git switch -c feature/dispatch-offline-phase-3 098a68c64`.
- **B0.1 (red):** `tests/Feature/Dispatch/Mobile/DispatchOfflineRowParityTest.php`.
  - For a delivery mission, a return mission, a hard-assigned unit and a soft-assigned unit, assert that **every field the Dispatch card, Driver Checklist and Assign Driver flow consume** (the §1 table, listed explicitly in the test as `CONSUMED`) is equal in `dispatch.row` and in the legacy feed row. The legacy row comes from a real `POST orders/schedules/dispatch` response for the same order product, so the comparison runs against the live feed, not a re-implementation.
  - Also assert that every `dispatch.row` key is a legacy row key (except the additive `category_ids`), assert `category_ids`, and assert that none of the excluded keys are present.
- **B0.2 (red):** revision tests in the existing revision-completeness test.
  - Each of these bumps the revision: `delivery_ready_to_go_at`, `delivery_call_customer`, `dispatch_checklist.driver.delivery.checks`, a `pickup_by` change on a delivery mission, and a change to the equipment's `store_id`.
  - Price changes do **not** bump it.
  - Crossing midnight changes no revision, apart from horizon membership.
- **B0.3 (green):**
  - Extract `DispatchRowFields` and the two `dispatchCardFields()` methods, and rewrite `OrderProducts\ListResource` (and the Orders and Equipment resources, for the card keys) to call them. The existing `MobileDispatchParityTest`, `DispatchContractFixturesTest::test_mixed_dispatch_feed_fixture` and the Dispatch feed tests must stay green **without** fixture regeneration.
  - `DispatchOfflineMissionSerializer::dispatch()` gains `'row' => DispatchRowFields::offlineRow($row)`.
  - `DispatchOfflineMissionSelector::WITH` gains `equipment.store` and `softAssignment.equipment.store`.
- **B0.4:** the manifest query count at 50 missions stays within the Phase 1 cap of 450 statements, with no N+1 (3 missions vs 30 missions → equal per-set eager-load count). Regenerate **only** `dispatch_offline_manifest.json` and `dispatch_offline_packages.json`: `WRITE_CONTRACT_FIXTURES=1 php artisan test --filter 'test_dispatch_offline_(manifest|packages)_fixture'`. That filter leaves `dispatch_list_mixed.json` untouched. Then commit.
- **B0.5:** backend regression, one test process at a time. The suites are `tests/Feature/Dispatch`, `tests/Feature/Api/Mobile`, `tests/Feature/Mobile`, `tests/Unit/Push`, `tests/Feature/QueueLine`, `tests/Feature/WaitList`.
  - Command: `cd /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline && PHP_INI_SCAN_DIR=":$SCRATCH/php-ini" php artisan test <suite>`. `$SCRATCH/php-ini/memory.ini` contains `memory_limit=2G`.
  - Expected: 1190 existing tests plus the new ones, 0 failures.
- **Commit:** `Ship the Dispatch card row in offline mission packages`.

---

## 2. Locked decisions (Gary, 2026-09-23)

| # | Decision (LOCKED) |
|---|---|
| **D1** | **B0 approved** (§1). `dispatch.row` is generated from the same business mapping as the legacy feed; there is no hand-duplicated second contract. Parity tests prove every consumed field matches the legacy row. `dispatch.row` is part of the mission revision, so driver progress and card changes invalidate cached packages. The backend Phase 3 branch is cut from the completed Phase 2 HEAD `098a68c64`, never from `main` or `origin/main`. |
| **D2** | **Order Details belongs to Phase 4. Locked Phase 4 acceptance requirement:** *a mission never opened online must later support cached Dispatch → Driver Checklist → Order Details → equipment checklist with the phone fully offline.* The current screen flow is preserved unless technical inspection proves it cannot be. Phase 3 does not touch Order Details. |
| **D3** | **Pending + Today:** render the durable cache immediately. **Pending + All:** render the cached horizon immediately; when online, the current live All feed may expand or replace it. **Offline Pending + All:** cached horizon only, with the small factual line **`Offline — showing downloaded Dispatch through <date>`** (for example "Sep 25"). **Completed and Search stay online-only** during Phase 3. No Dispatch UI redesign. |
| **D4** | **Manual Dispatch stays outside guaranteed offline scope,** on the existing feed. No Manual Dispatch offline subsystem. Previously loaded manual items remain best-effort, as today, and are **never described as offline-ready**. When the cache supplies the order legs, the manual tasks come from the existing feed's page 1 (`per_page=1`, `manual_jobs` only). |
| **D5** | **"All Drivers" is truly company-wide.** The durable cache holds all drivers, and All Drivers renders all of them. Selecting a driver is local filtering only and makes no request. *Applied with D3 (review I-3):* the mixed feed scopes a missing driver to the signed-in user, so under **All Drivers** Pending + All stays on the company-wide cache; the live All feed may replace the cached horizon only for a **named** driver. |
| **D6** | **A silent wake with no authenticated session makes no network request, preserves the cache, and completes as `.noData`.** A 401 or expired session never clears the Dispatch cache or any Sync Engine work (like every 401, `KabbaAPIClient` still posts `.kabbaAuthenticationExpired`, which is existing app behavior). After a successful authentication, reconciliation runs automatically (`.loginCompleted`). No unauthenticated Dispatch API. |
| **D7** | **Conservative cleanup.** A mission absent from the newest manifest leaves the active index immediately. Its package file is **physically purged only when both** (a) no Sync Engine operation, in any state, references that order product, **and** (b) it has been inactive (unreferenced by the active index) for a **7-day grace period**. Superseded older revisions of still-active missions follow the same rule. Cleanup never touches Sync Engine operations, media, signatures, checklist answers, `ChecklistContextStore`, `DriverChecklistLocalState`, or any other captured field work. |

## 3. Architecture

### 3.1 Responsibilities (one sentence each)
- **`DispatchOfflineContract`** (Core): Codable manifest and package-response types; request builders; strict validation.
- **`DispatchOfflineMissionStore`** (Core): the durable, per-tenant package files and active index, with a crash-safe commit order.
- **`DispatchOfflineDiff`** (Core, pure): manifest vs index → download / remove / unchanged.
- **`DispatchOfflineReconciler`** (Core): the ONE coordinator. It serializes and coalesces triggers, fetches the manifest, downloads only changed packages in batches, commits per mission, and returns a result.
- **`DispatchOfflineWorkingSet`** (Core, pure): presentation query over the store (driver, leg, Today/All, category, local completion overlay, sort), plus the not-downloaded state.
- **`DispatchOfflineSync`** (App): bootstraps the store and reconciler per tenant; wires every trigger; handles background tasks and the push completion handler; posts `.kabbaDispatchOfflineChanged`.
- **`DispatchOfflineRowAdapter`** (App): stored `dispatch.row` plus the derived overdue flags → `SchedulesModel` (ObjectMapper), with no change to `SchedulesModel`.
- **`DispatchListViewController`** (App, modified): renders from the working set first and reconciles in the background. No visual redesign.

### 3.2 On-disk layout (protected; inherits the `KabbaSync` root's backup exclusion)
```
<App Support>/KabbaSync/dispatch-offline/v1/<tenantKey>/
    index.json                                   ← the ACTIVE index (atomic replace)
    packages/<safeOPUID>__<leg>__<revision>.json ← immutable, one file per (mission, revision)
    quarantine/                                  ← undecodable files moved aside (newest 20 kept)
```
- `tenantKey` = 16-hex FNV-1a-64 of the normalized base URL (lowercased scheme and host, no trailing slash). The normalized URL is also stored in `index.json`, and a mismatch on load is treated as "no cache". There is no CryptoKit: Core stays Foundation-only.
- `safeOPUID` uses the same filename filter as `ChecklistContextStore.key` (alphanumerics, `-`, `_`).
- A package file contains `{schema:1, tenant_key, mission_key, revision, cached_at, package:<the package object exactly as received>}`. The raw object is kept so Phase 4 and 5 can decode `checklist_context` and `terms` without downloading again.
- `index.json` contains:
  - `schema`, `tenant_key`, `base_url`
  - `manifest_revision` (last applied), `through_date`
  - `last_manifest_at` (last successful manifest fetch; drives freshness), `committed_at`
  - `ever_committed` (`true` after the first successful commit, used for the not-downloaded state)
  - `entries[]`, sorted by `mission_key`: `mission_key`, `order_product_unique_id`, `leg`, `effective_date`, `server_revision` (from the manifest), `ready_revision` (nil = not downloaded yet), `package_file`.
  - `retired[]`: package files no longer referenced by `entries` (removed missions and superseded revisions), each with `package_file`, `order_product_unique_id`, and `retired_at`, the moment it first became unreferenced (D7).

### 3.3 Safe-apply order (per-mission atomicity)
1. Fetch the manifest; decode and validate it. On any failure, stop and leave the store untouched.
2. Diff against the index. **Adopt from disk** before using the network: if a valid file for `(mission, manifest revision)` already exists (left by an interrupted run), mark it ready with no download.
3. Download the remaining keys in batches of ≤100, one batch at a time. Validate each package (§3.4) and write its file atomically. A new revision is a **new file**, so the previous valid package can never be overwritten.
4. **After each batch**, commit the index atomically. The index is always one consistent view:
   - Membership is exactly the manifest.
   - Missions downloaded so far point to their new file.
   - A mission whose download failed keeps its prior `ready_revision` and file (stale but valid), or stays `ready_revision=nil` if it never had one.
   - `not_active` keys are dropped (the server says the mission became inactive after the manifest was built).
   - Missions absent from the manifest are dropped from the index. Their files are left for step 5.
5. After the final commit, run GC (D7).
   - Every file that just became unreferenced is added to `retired[]` with `retired_at = now`. A file that becomes active again leaves `retired[]`.
   - A retired file is **purged only when** `now − retired_at ≥ 7 days` **and** no Sync Engine operation, in any state, has its `order_product_unique_id`.
   - Unreferenced files that aren't recorded anywhere (orphans from a crash) are recorded as retired now, never deleted on sight.
   - GC runs only on the store's own `packages/` directory and never opens any other directory.
- **Crash at any point:** the index is either the old one or a new, fully consistent one (atomic rename). Orphaned files are adopted by step 2 or collected in step 5.
- **Index names a missing or corrupt file:** that entry is treated as not ready. It is hidden from presentation, counted as pending, and downloaded again on the next run.

### 3.4 Package validation (a failure affects only that mission)
- `mission_key == "\(order_product_unique_id):\(leg)"` and the key was requested in this batch.
- `leg` ∈ {delivery, return}; `revision` matches `^[0-9a-f]{64}$`.
- `dispatch.order_product_unique_id` and `dispatch.leg` match.
- `dispatch.row` is an object whose `unique_id` equals the order product.
- `checklist_context.identity.order_product_unique_id` and `.leg` match; `terms` is an object.
- `checklist_context` is otherwise **opaque in Phase 3**. Full `ChecklistContext` decoding is Phase 4's gate, so a checklist-schema problem cannot hide a Dispatch card.
- If the package `revision` differs from the manifest's, the package's value is stored as `ready_revision`: the mission changed again between the two requests. The next manifest converges.

### 3.5 Coalescing and trigger policy (`DispatchOfflineReconciler`, one internal serial queue)
- `request(_ trigger: DispatchOfflineTrigger, completion:)`.
- Triggers: `.wake(revision: String?)`, `.launch`, `.loginCompleted`, `.foreground`, `.dispatchScreenOpened`, `.manualRefresh`, `.networkRestored`.
- **No session:** returns `.skipped(.noSession)` immediately, with no request.
- **Wake already applied:** `.wake(r)` where `r == index.manifest_revision` and every entry is ready → `.unchanged` with **zero** requests.
- **Freshness window (review F1):** `.foreground` and `.dispatchScreenOpened` within 20 s of the last run that left **every** active mission at its manifest revision → `.skipped(.fresh)` with no request. This absorbs didBecomeActive and viewWillAppear firing together. The marker is the index's `last_current_at`, which only a complete run advances; a partial or failed run never does, and after one the cooldown below is checked first, so such a run is never "fresh" (not even after a relaunch, because the index is not fully current).
- **Partial runs (review M-4):** a partial run counts toward the cooldown below and is followed up only for repair triggers (wake, pull-to-refresh, login, network, launch).
- **Failure cooldown:** after a failed run, `.foreground` and `.dispatchScreenOpened` are skipped for 30 s, doubling per consecutive failure up to 300 s. `.wake`, `.manualRefresh`, `.networkRestored`, `.loginCompleted` and `.launch` bypass both the freshness window and the cooldown. The cooldown is not a timer: it only suppresses event-driven triggers.
- **While a run is in flight**, new requests join its waiters and never start a parallel download. When it finishes, **one** follow-up run happens only if (a) the in-flight run failed and a trigger arrived during it, (b) a coalesced `.wake` carries a revision different from the in-flight manifest's, or (c) a sign-in of the **same company** stopped it (review F3, §3.8). Every coalesced completion receives the final result.
- **There is no timer, polling, BGAppRefresh, GPS, or socket.**

### 3.6 Presentation rules (`DispatchOfflineWorkingSet`)
- **Source:** index entries with a valid ready package.
- **Today:** `effective_date <= device today` (the feed uses `<= today()`). **All:** the whole horizon.
- **Leg:** delivery missions show under Delivery, return missions under Return, and both under All.
- **Driver:** `DispatchWorkload.orderRowBelongs(selectedDriverId:isDelivered:deliveryEmployeeId:pickupEmployeeId:)` on the row. No selection means everything (D5). A missing employee id is never hidden.
- **Category:** `row.category_ids` contains the selection.
- **Local completion:** `EffectiveFieldState.CompletionOverlay` hides a leg completed on this phone (existing rule).
- **Overdue** is derived: `effective_date < device today` sets `is_delivery_overdue` or `is_pickup_overdue` on the row before mapping.
- **Order:** `row.sort_key` ascending, then `mission_key` for stability. `sort_key` is the feed's own key.
- **Offline All line (D3):** `DispatchOfflinePresentation.offlineAllLine(throughDate:)` → `Offline — showing downloaded Dispatch through Sep 25`, from the index `through_date` formatted `MMM d` (en_US_POSIX). The App shows it as the existing slim freshness header when the view is Pending + All and the phone is offline.
- **State:**
  - `.notDownloaded`: `ever_committed == false`.
  - `.ready(rows, freshness)`: freshness = `last_manifest_at`, plus counts of stale missions (`ready != server`) and missing missions (never downloaded, or the file is unreadable), across the whole working set.
- **Never current while incomplete (review F1):** `DispatchOfflineScreenPolicy.outcome(presentation:failed:online:)` flags the list as not current whenever the last answer failed (failed, partial, cooling down, no session) **or** any active mission is missing or stale — whatever the last answer said. Only a complete working set after a non-failing answer clears the saved-list header.
- **An empty manifest is `.ready([])`**, which is a genuine "no Dispatch" state, not "not downloaded".

### 3.7 Background result mapping (`DispatchOfflineReconcileResult.backgroundResult`)
- `changed == true` (presentable set membership or any `ready_revision` changed) → `.newData`, including partial runs.
- Otherwise a failure → `.failed`. Otherwise (unchanged, or skipped with no session) → `.noData`.
- For a wake, the App layer holds the handler with a **25 s deadline**. If the deadline passes, it calls the handler once, with `.newData` if a commit already changed the set and `.failed` otherwise. The run itself may continue, because it is crash-safe. The handler is guarded to be called exactly once.

### 3.8 Auth, logout, tenant

**Session binding (review I-1, implemented).** `KabbaAPIClient` re-reads the base URL and token on every request, so a run is bound to the `DispatchOfflineSession` it started under: the tenant key plus an opaque FNV hash of the credential (the token itself is never stored). The run re-checks the current session before every request and when every answer arrives; on any change (logout, another company, another employee) it stops with no write and no cleanup. A session for another tenant counts as no session.
- **Same company, another sign-in (review F3):** the old credential's answer is still discarded unwritten, but the reconciler immediately runs **one** follow-up under the new session, serving the aborted run's waiters and every trigger that arrived meanwhile (a `.loginCompleted` joins it). It never waits for an unrelated later trigger.
- **Signed out, or another company:** no follow-up (I-1). The new company's own tenant-bound reconciler serves its `.loginCompleted`; zero writes reach the old company's store.
- **Outcome notifications:** `.kabbaDispatchOfflineReconciled` is posted only for real outcomes (never a skip, never a run stopped by a session change) and carries the `tenantKey`; the Dispatch screen applies it only when that company is the one signed in now.
- Logout and 401 never touch the store (tests 15 and 16). While logged out, the app shows Login, so nothing reads the cache. After the next login with the same `api_url`, the same tenant directory is used and `.loginCompleted` repairs freshness.
- A different employee on the same tenant uses the same cache, because it is company-wide.
- A different `api_url` uses a different directory.
- A run binds to the tenant key captured at its start, so a mid-run tenant switch can never write one tenant's data into another tenant's store.
- There is no unauthenticated Dispatch API.

### 3.9 Driver trip stage (review F2)
- **Rule:** durable local action → immediate effective state → later server confirmation. Load Map & Go (`On My Way`) and Arrived are `driver_checklist.update` operations the Sync Engine already keeps on disk (retained after sync). `DriverStageOverlay` (Sync Core, `EffectiveFieldState.swift`) derives the stage for one order product + leg from them over the row's server copy. There is **no second store** for the stage.
- **Readers:** Screen 2 (`DriverChecklistViewController.getReadyToGo_ArrivedStatus`) derives it itself from `KabbaSync.engine.snapshot()`; the Dispatch card and its button colour use `DriverStagePresentation.applying` (app, `DispatchOfflineRowAdapter.swift`). Leaving Dispatch, force-quit and relaunch offline keep the stage.
- **Server confirmation:** a local step stands while it is unconfirmed (pending, syncing, needs attention); once synced it stands only until the screen shows a copy of the row the server was **asked for after** that confirmation (package `server_observed_at` = the package request's send time; feed rows = the feed request's send time; an MMKV snapshot = unknown, so the step stands). Then server truth wins — e.g. the office recalled the trip. The server's stage is never downgraded.
- **No duplicates:** `recordsDeparture` only before the leg departed and `recordsArrival` only once; Screen 2's buttons are gated the same way (Arrived becomes Continue).

### 3.10 Live-feed and Manual Dispatch request binding (review F4)
- Every live-feed page and Manual Dispatch rider request takes a `DispatchFeedRequests.Ticket`: its full `DispatchFeedScope` (status, leg type, date, driver, category, trimmed search, transport mode) plus the request generation. One builder (`currentFeedParams`) makes every request and the current scope.
- Every new list (screen open, refresh, any filter or search change, the feed fallback) restarts the generation; later pages of the same list share it.
- An answer whose ticket no longer matches is discarded **before any write**: no order slot, no manual list, no pagination, no screen change. The manual list is always written under the request's own driver + day key.

---

## 4. File structure

### Create — Sync Core (Foundation only; members of the app target AND the `KabbaSyncCoreTests` Xcode logic bundle; compiled by `swift test`)
- `RentnKing/Sync/Core/DispatchOfflineContract.swift`: `DispatchOfflineManifest` (+ `Entry`, `Horizon`); `DispatchOfflinePackage` (typed `missionKey`, `revision`, `orderProductUniqueId`, `leg`, `row: JSONValue`, raw `object: JSONValue`); `DispatchOfflinePackagesResponse`; `DispatchOfflineAPI` (`manifestRequest()`, `packagesRequests(for:) -> [SyncHTTPRequest]` batched ≤100, a fresh `op-dispatch-offline-<uuid>` operationId per request); `DispatchOfflineValidation`.
- `RentnKing/Sync/Core/DispatchOfflineMissionStore.swift`: `DispatchOfflineTenant.key(baseURL:)`, `DispatchOfflineIndex`, `DispatchOfflineMissionStore` (`loadIndex()`, `writePackage(_:)`, `existingValidPackage(missionKey:revision:)`, `loadPackage(entry:)`, `commit(_:)`, `collectGarbage(retainingOrderProducts:)`), and a test-only `faultInjection` hook (`failNextIndexCommit`, `failNextPackageWrite`).
- `RentnKing/Sync/Core/DispatchOfflineReconciler.swift`: `DispatchOfflineTrigger`, `DispatchOfflineDiff`, `DispatchOfflineReconcileResult` (+ `backgroundResult`), `DispatchOfflineReconciler(httpClient:store:hasSession:retainedOrderProducts:now:)`.
- `RentnKing/Sync/Core/DispatchOfflineWorkingSet.swift`: `DispatchOfflineQuery`, `DispatchOfflinePresentation`, `DispatchOfflineWorkingSet.present(store:query:operations:today:)`.

### Create — App layer
- `RentnKing/Sync/App/DispatchOfflineSync.swift`: `configure(rootDirectory:client:baseURL:hasSession:)`, `trigger(_:completion:)`, `handleWake(revision:completionHandler:)`, `presentation(for:)`, `Notification.Name.kabbaDispatchOfflineChanged`. Foreground-started runs are wrapped in `UIApplication.beginBackgroundTask`.
- `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchOfflineRowAdapter.swift`: `schedulesModel(from row: JSONValue, overdue: Bool) -> SchedulesModel?`.

### Create — tests
- `RentnKingTests/KabbaSyncCore/DispatchOfflineTestSupport.swift`: a fixture factory that clones the **shared** `dispatch_offline_packages.json` package and manifest entry, substituting `order_product_unique_id`, `leg`, `revision`, driver ids, `effective_date` and `category_ids`. It adds no parallel JSON shape. It also provides a scripted-response builder on top of the existing `FakeSyncHTTPClient`.
- `RentnKingTests/KabbaSyncCore/DispatchOfflineContractTests.swift`
- `RentnKingTests/KabbaSyncCore/DispatchOfflineMissionStoreTests.swift`
- `RentnKingTests/KabbaSyncCore/DispatchOfflineReconcilerTests.swift`
- `RentnKingTests/KabbaSyncCore/DispatchOfflineWorkingSetTests.swift`
- `RentnKingTests/Hosted/DispatchOfflineRowAdapterTests.swift` (app-hosted; `@testable import RentnKing`, calls the adapter, reads the `SchedulesModel` properties, no ObjectMapper import needed)

### Modify
- `RentnKing/Sync/Core/DispatchWake.swift`: `Handling.reportsNewData` → replaced by `reportsReconciliationResult: true` (still `adjustsBadge=false`, `presentsUI=false`).
- `RentnKingTests/KabbaSyncCore/DispatchWakeTests.swift`: add the `#if canImport(KabbaSyncCore)` guard (M0); update the handling assertion (M6).
- `Scripts/test-sync-core.sh`: detect the SDK with `xcrun` from `PATH` (M0).
- `RentnKing/Sync/App/KabbaSync.swift`: configure `DispatchOfflineSync` in `bootstrap` (same `root`, `client`, `hasSession`); trigger `.launch` at the end of bootstrap; trigger `.foreground` in the existing `didBecomeActive` observer.
- `RentnKing/NotificaiotnFile.swift`: a Dispatch wake calls `DispatchOfflineSync.handleWake(revision:completionHandler:)`, still returning before the badge increment. Other pushes are unchanged.
- `RentnKing/AppDelegate.swift`: `monitor.onNetworkRestored` → `.networkRestored` (inside the existing `user != nil` branch).
- `RentnKing/Modules/SPLASH MODEL/Login Screen/LoginModel.swift`: after the Phase 2 registration line, trigger `.loginCompleted`.
- `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchListViewController.swift`: source selection (D3), cache-first render, `.kabbaDispatchOfflineChanged` observer, not-downloaded state, in-memory local-edit overlay, freshness line from `last_manifest_at`.
- `RentnKing/Modules/TABBAR/Home Model/Dispatch Model/DispatchModel.swift`: a manual-only rider (`per_page=1`, reads `manual_jobs`, never writes the MMKV order slot) used when the cache supplies the order legs.
- `RentnKing/Core/Other Views/EmptyDataView/EmptyDataView.swift`: `func dispatchNotDownloaded()`, which reuses `configure`. Title: "Dispatch isn't downloaded to this phone yet". Subtitle: "Connect to the internet once to download today's work."
- `RentnKing.xcodeproj/project.pbxproj`: explicit membership, new IDs `5A5E000000000000000000A0…` (Core files → app + `KabbaSyncCoreTests`; Core tests → `KabbaSyncCoreTests`; App files → app; hosted test → `RentnKingHostedTests`).
- `RentnKingTests/KabbaSyncCore/Fixtures/`: copy **only** `dispatch_offline_manifest.json` and `dispatch_offline_packages.json` by name, from the B0 branch. **Do not** run `Scripts/sync-contract-fixtures.sh`, because it copies every fixture and would silently change `dispatch_list_mixed.json`.

### Not touched
Sync Engine store and handlers, `ChecklistContextStore` (Phase 4), T&C flow (Phase 5), Order Details (D2 → Phase 4), Driver Checklist screen logic, Manual Dispatch screens, `SchedulesModel`, legacy feed behavior for Completed and search, Info.plist, entitlements, version and build.

**`dispatch_list_mixed.json` (missing `assigned_equipment` from backend `56029fdbd`):** Phase 3 does **not** consume it. The cache path maps `dispatch.row`, and `DispatchWorkloadTests` reads only `manual_jobs` and the sort keys. It stays unchanged. If Gary wants it synced, that is a separate, standalone fixture-sync commit (copy that one file and rerun `DispatchWorkloadTests`), outside Phase 3.

---

## 5. Tasks

Commands (Local Mac terminal, all from `/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p3`):
- Core, focused: `swift test --filter <TestClass>`. Core, full: `swift test`.
- Hosted: `xcodebuild test -project RentnKing.xcodeproj -scheme RentnKingHostedTests -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RentnKingHostedTests/DispatchOfflineRowAdapterTests`
- App build: `xcodebuild build -project RentnKing.xcodeproj -scheme RentnKing -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`

**M0 — Test-infra repair (no product code).**
Add the `#if canImport(KabbaSyncCore)` guard to `DispatchWakeTests.swift`, and switch the script's detection to `xcrun --sdk macosx --show-sdk-path` from `PATH`.
Verify: `Scripts/test-sync-core.sh` and `swift test` each report 334/334.
Commit: `Test runner: detect Xcode via PATH xcrun; guard DispatchWakeTests import`.

**M1 — Contract (red → green).** Copy the two B0 fixtures, then `DispatchOfflineContractTests`:
- The manifest fixture decodes: 64-hex revisions, `mission_key == opuid:leg`, `through_date`.
- An empty `missions` list decodes, and it is valid.
- Duplicate keys, a bad leg, a non-hex revision, or a mismatched key are rejected as a whole-manifest failure.
- The packages fixture decodes: `not_active`, a valid `row`, and the raw object round-trips byte-equal after re-serialization with sorted keys.
- Each §3.4 rule rejects only that package.
- 250 missions → 3 requests of ≤100; each is `POST dispatch/offline/packages` with the exact body; each has a distinct operationId; the manifest request is `GET dispatch/offline/manifest`.

Commit: `Dispatch offline: manifest and package contract types`.

**M2 — Durable store.** `DispatchOfflineMissionStoreTests`:
- Write, then a new store instance on the same directory reads the same index and packages (**test 12**).
- A new revision is a new file, and the old one stays until GC (**test 9**).
- Injected `failNextIndexCommit` after the package writes → reload gives the previous index, and every referenced file exists (**test 10**).
- Deleting a referenced file → the entry is reported not ready, and there is no crash.
- A corrupt file is quarantined, not presented; the quarantine is capped at 20.
- A base-URL mismatch in the index → treated as no cache; two tenant keys never share a directory.
- GC (D7):
  - A removed mission's file is still on disk at day 0 and at day 6.
  - It is purged at day 7 when no operation references its order product, and kept at day 30 while an operation (pending, synced or needs-attention) references it.
  - A superseded revision follows the same rule.
  - An orphan file is recorded as retired, not deleted.
  - Sync Engine operation files and assets are byte-identical after GC.
- On iOS, files are written with `.completeFileProtectionUntilFirstUserAuthentication` (asserted through the shared `writeProtected` path).

Commit: `Dispatch offline: durable per-tenant mission store`.

**M3 — Diff and reconciler core.** `DispatchOfflineReconcilerTests` (scripted `FakeSyncHTTPClient`, fixture factory, temp directories):
- **test 1:** empty store + manifest with 3 missions → 1 manifest + 1 package request, all 3 ready.
- **test 2:** identical second run → 1 manifest request, **0** package requests, `changed=false`.
- **test 3:** one revision changes → exactly one mission requested.
- **test 4:** new mission → added.
- **test 5:** absent mission → removed from the index.
- **test 6:** absent mission with pending, needs-attention and synced Sync Engine operations plus assets → `FileSyncOperationStore` records and asset files are byte-identical, `ChecklistContextStore` files are unchanged, and the package is retained by GC.
- **test 8:** 3 changed missions, the batch returns 2 valid and 1 failing validation → 2 become ready, 1 keeps its prior revision.
- **test 9:** a transport failure on the package batch → the prior packages are still presented and `ready_revision` is not advanced.
- Package decode failure → that mission keeps its prior package, and the run is partial.
- Manifest transport failure, 5xx, or undecodable manifest → the store is byte-identical.
- Network lost after the manifest → removals applied, pending missions stay pending or stale, and the next run completes them.
- A key in `not_active` → removed.
- Package revision newer than the manifest → stored; the next identical manifest → 0 downloads.
- Interrupted run (killed after the package write, before the index commit) → the next run adopts from disk with 0 downloads.
- Empty manifest → an empty active set, `ever_committed=true`.
- Previous-day cache (`through_date` yesterday) plus a new manifest → reconciled normally.
- **test 15:** 401 on the manifest → store untouched, result `.failed(.unauthenticated)`.
- 426 → `.failed(.updateRequired)`, store untouched.
- Reinstall (empty directory) → `.notDownloaded` until the first commit.

Commit: `Dispatch offline: selective reconciliation with per-mission atomic apply`.

**M4 — Coalescing, trigger policy, background result.** Still `DispatchOfflineReconcilerTests`, using a latency-delayed fake:
- **test 11:** `.foreground` and `.wake` requested concurrently → exactly 1 manifest request, and both completions get the same result.
- A wake with a new revision arriving mid-run → exactly one follow-up run; the same revision → none.
- A trigger during a failed run → one follow-up.
- No session → 0 requests, `.skipped`.
- A wake equal to the applied revision → 0 requests.
- 20 s freshness window, and a cooldown sequence of 30/60/…/300 s, both bypassed by `.manualRefresh` / `.networkRestored` / `.loginCompleted` / `.wake`.
- **test 16:** after `.failed(.offline)`, `.networkRestored` runs immediately; after `.failed(.unauthenticated)`, `.loginCompleted` runs and repairs.
- **test 17:** `backgroundResult` table — changed → newData; unchanged → noData; skipped → noData; failed with no change → failed; partial with a change → newData.

Commit: `Dispatch offline: one coalescing coordinator for every trigger`.

**M5 — Working set.** `DispatchOfflineWorkingSetTests` (6 missions across 3 drivers, both legs, overdue / today / +1 / +2):
- **test 7 and test 18:** switching the selected driver among All, Gary, Blake and Jerome issues **0** HTTP requests (the fake records none). The All set contains all three drivers, and Gary shows only Gary's active-leg cards.
- Leg filter, Today vs All, category.
- The local completion overlay hides the leg.
- Overdue is derived; order follows `sort_key`.
- Stale and pending counts.
- Empty manifest → `.ready([])`; never-committed → `.notDownloaded` (**tests 13 and 14** at the Core level, both on a new store instance with an offline client).

Commit: `Dispatch offline: local company-wide working set query`.

**M6 — App wiring.** `DispatchOfflineSync`, and triggers in `KabbaSync.bootstrap` (launch), didBecomeActive (foreground), `onNetworkRestored`, `LoginModel` (login), and `NotificaiotnFile` (wake + completion handler, invisible). Update the `DispatchWake` handling and its test.
Verify: `swift test` passes, and the app builds. A grep gate must show no `Timer`, `scheduledTimer`, `BGAppRefreshTaskRequest`, `CLLocationManager` or `URLSessionWebSocketTask` added by the diff; no package bytes in `UserDefaults` or MMKV; and the badge line is still unreachable for Dispatch wakes.
Commit: `Dispatch offline: reconcile on wake, launch, login, foreground and network restore`.

**M7 — Dispatch screen.**
- Hosted `DispatchOfflineRowAdapterTests` maps the fixture row (delivery + a return clone) and asserts every §1 card field on `SchedulesModel`: `order.id`, `customer_phone`, `delivery_address.full_address`, `equipment.equipment_store.name`, `is_fuel`/`is_key`, both employees' `name`, `delivery_checklist.ready_to_go_at` etc., `product_data` options, `sort_key`, `is_delivered`, derived overdue.
- Then the controller:
  - Pending + Today renders from `DispatchOfflineSync.presentation` synchronously in `refreshList()` and triggers `.dispatchScreenOpened` (or `.manualRefresh` from pull-to-refresh).
  - `.kabbaDispatchOfflineChanged` re-renders without a spinner.
  - `.notDownloaded` shows the existing loading placeholder while online, and `dispatchNotDownloaded()` while offline. If the first download fails online, the screen falls back to the live feed (review I-2) — never a permanent spinner.
  - Every reconciliation outcome (any trigger) is broadcast (`.kabbaDispatchOfflineReconciled`): failed/partial → "showing the list saved at …"; success → no header (review I-2). The decisions live in `DispatchOfflineScreenPolicy` (unit-tested).
  - Offline Pending + All shows `Offline — showing downloaded Dispatch through <date>` (D3).
  - Pending + All paints the cache, then the existing feed replaces it while online (D3).
  - Completed and search keep the existing path.
  - The manual-only rider runs when online (D4).
  - Local edits (`data_updateInCurrentDic`, `updateDriver`, row removal after `scheduleUpdate`) are kept in an in-memory overlay keyed by mission, re-applied on every re-render, and dropped when that mission's `ready_revision` changes.
  - `persistOrderListAndRebuild()` does not write the MMKV order slot while the cache is the source.

Commit: `Dispatch screen: render the durable working set first, reconcile behind it`.

**M8 — Project membership and build.** Add the `pbxproj` entries (§4).
Verify: the app builds for the simulator; the hosted adapter tests pass; `swift test` passes.
Commit: `Xcode project: Dispatch offline Phase 3 files`. M1–M7 add their files to the project in the same commit that creates them; M8 is the verification checkpoint, and a separate commit only if a membership fix is needed.

**M9 — Verification gate.**
- Full `swift test` (expected: 334 plus the new tests, 0 failures) and `Scripts/test-sync-core.sh`.
- Hosted suite: `RentnKingHostedTests`, all tests.
- App simulator build.
- The M6 grep gate.
- Backend B0 regression totals (§1).
- `git status` clean in both worktrees; no upstream on either Phase 3 branch; `main` untouched.

---

## 6. Required-test traceability
| # | Requirement | Test (class · method prefix) |
|---|---|---|
| 1 | Empty store + manifest → all stored | Reconciler · `testEmptyStorePopulatedManifestStoresEveryPackage` |
| 2 | Identical manifest → 0 downloads | Reconciler · `testIdenticalManifestDownloadsNothing` |
| 3 | One revision changes → one package | Reconciler · `testOneChangedRevisionDownloadsExactlyThatMission` |
| 4 | New mission → added | Reconciler · `testNewMissionIsAdded` |
| 5 | Mission disappears → removed from active index | Reconciler · `testAbsentMissionLeavesTheActiveIndex` |
| 6 | Disappears with pending work → work untouched | Reconciler · `testRemovalNeverTouchesSyncEngineWorkOrChecklistContexts` |
| 7 | Offline driver switching → local only | WorkingSet · `testDriverSwitchingMakesNoRequest` |
| 8 | One fetch fails → others ready | Reconciler · `testOneBadPackageDoesNotBlockTheOthers` |
| 9 | Failed replacement keeps previous package | Store · `testNewRevisionNeverOverwritesPrevious`; Reconciler · `testFailedReplacementKeepsPriorPackage` |
| 10 | Interrupted apply never points at missing files | Store · `testFailedIndexCommitKeepsPreviousConsistentIndex`, `testMissingReferencedFileIsNotReady` |
| 11 | Concurrent foreground + push coalesce | Reconciler · `testConcurrentTriggersCoalesceIntoOneRun` |
| 12 | Force quit / relaunch reads same set | Store · `testNewInstanceReadsTheSameActiveSet` |
| 13 | Offline startup renders cache | WorkingSet · `testRelaunchOfflineRendersCachedSet` (+ physical P1) |
| 14 | Empty cache + offline → not downloaded | WorkingSet · `testNeverCommittedIsNotDownloadedNotEmpty` (+ physical P2) |
| 15 | 401 leaves cache intact | Reconciler · `testUnauthorizedLeavesStoreByteIdentical` |
| 16 | Network/session restoration repairs | Reconciler · `testNetworkRestoredRunsImmediatelyAfterOffline`, `testLoginCompletedRepairsAfterUnauthorized` |
| 17 | Background result newData/noData/failed | Reconciler · `testBackgroundResultMapping` |
| 18 | Multi-driver company cache, offline filter no request | WorkingSet · `testCompanyCacheHoldsEveryDriver` |

Second-review corrections (each written red first, then green):

| Finding | Requirement | Test (class · method) |
|---|---|---|
| F1 | A partial launch + Dispatch open within 20 s stays not current; a later complete run clears it | Reconciler · `testAPartialLaunchIsNeverFreshForTheNextDispatchOpen`, `testADispatchOpenCoalescedIntoAPartialLaunchIsNotCurrent`, `testAPartialRunNeverAdvancesTheDurableFreshMarker`, `testAFailedRunAfterASuccessIsNotFreshEither`; ScreenPolicy · `testTheCacheIsNeverCurrentWhileAnyMissionIsStaleOrMissing`, `testWhichAnswersMeanTheListMayNotBeCurrent`; WorkingSet · `testAnUnreadablePackageCountsAsMissing` |
| F2 | Offline Load Map & Go / Arrived survive reopen and relaunch; no duplicate step | DriverTripStage · `testLoadMapAndGoSavedOnThisPhoneIsOnMyWayImmediately`, `testArrivedSavedOnThisPhoneIsArrived`, `testEveryRetainedStateCountsUntilTheServerIsSeenAfterConfirmation`, `testServerTruthIsKeptAndNeverDowngraded`; DriverTripStageDurability · `testTheStageSurvivesReopenAndRelaunchOfflineWithoutDuplicates`; WorkingSet · `testEveryRowNamesWhenTheServerWasAskedForIt`; Hosted · `testLoadMapAndGoSavedOfflineShowsOnTheCachedCard`, `testAnotherLegsOrProductsStageNeverShows` |
| F3 | Same company: old answer discarded, one prompt follow-up; cross company: zero writes, no follow-up | Reconciler · `testASameCompanySignInMidRunDiscardsTheOldAnswerAndRepairsUnderTheNewSession`, `testASameCompanyLoginDuringTheRunCoalescesIntoExactlyOneFollowUp`, `testASignOutMidRunStillStopsWithoutAFollowUp`, `testACrossCompanySwitchLeavesTheOldStoreAloneWhileTheNewCompanyReconcilesItsOwn`; ScreenPolicy · `testOnlyARealOutcomeForTheSignedInCompanySettlesTheScreen` |
| F4 | A driver switch or any non-driver filter change while a request is in flight discards its answer | FeedRequests · `testADriverSwitchWhileARequestIsInFlightDiscardsItsAnswer`, `testEveryNonDriverFilterChangeObsoletesAnInFlightRequest`, `testARefreshOfTheSameScopeObsoletesTheOlderRequest`, `testTheNextPageOfTheSameListIsAccepted`; Hosted · `testEveryRequestParameterIsPartOfTheRequestsScope` |

---

## 7. Independent-review gate
After M9, a **fresh** reviewer (no prior context) reviews `f460081..HEAD` (mobile) and `098a68c64..HEAD` (backend B0) against this plan and the spec. It checks:
- The safe-apply order and the crash windows.
- No path that deletes or edits Sync Engine, `ChecklistContextStore` or `DriverChecklistLocalState` data.
- Tenant isolation.
- Coalescing races (the serial queue, completions called exactly once).
- The push handler is invisible, and its completion is called exactly once within the deadline.
- No polling, timers, GPS or sockets.
- Revision churn from B0.
- Card parity with the legacy row.
- Test strength (each required test reds on the defect it names).

**Phase 3 closes only with no remaining Critical or Important findings.** Critical and Important findings are fixed and re-verified; Minor ones may be documented for later.

### Review record
- **First review (2026-09-23):** I-1 (tenant leak), I-2 (online failures ignored), I-3 (All Drivers replaced by the signed-in user's feed) — fixed in `24b222e` and `6ac3724` (§3.5, §3.8, D3/D5 note).
- **Second review (2026-09-24):** no drift in the shared backend `DispatchRowFields` extraction; I-1 and I-3 confirmed fixed. Two Important and two Minor findings, all fixed in the correction pass:
  - **F1 (Important):** a partial run's saved-list header was cleared by a `.fresh` skip → §3.5 freshness marker + §3.6 never-current-while-incomplete.
  - **F2 (Important):** offline Load Map & Go / Arrived on cached rows lived only in the screen's memory → §3.9.
  - **F3 (Minor):** a same-company sign-in mid-run waited for an unrelated trigger; an aborted run's outcome could settle another company's screen → §3.8.
  - **F4 (Minor):** live-feed / Manual Dispatch answers were bound to driver, day, leg and status only, and the manual list was keyed at answer time → §3.10.
- **Deferred Phase 3 Minor/Nit findings (second review; not fixed in this phase):**
  - F5 (Minor) — the store's in-memory package cache is never evicted, and the first run after a cold launch decodes every package file.
  - F6 (Minor) — offline + never downloaded + Pending + All shows the "Offline — showing downloaded Dispatch" header above "Dispatch isn't downloaded to this phone yet". To be handled with the later cosmetic / screen-flow pass.
  - F7 (Minor) — "Today" uses the phone's time zone, not the app's (accepted in §3.6).
  - F8 (Nit) — `equipment.store.state` is lazy-loaded (bounded by the number of stores, not missions).
  - F9 (Nit) — the row adapter would map a whole-number JSON value to nil for a `Double?` model field (no consumed field is `Double` today).
  - F10 (Nit) — the hosted adapter tests load the fixture via `#filePath` (Simulator only).
  - F11 (Nit) — file protection has no dedicated store test (it relies on the shared `writeProtected`).
  - F12 (Nit) — an online driver switch still sends the D4 Manual Dispatch rider request, and the D3 live All feed for a named driver.
  - F13 (Nit) — Pending + All with a named driver repaints the cache before the feed replaces it.
  - F14 (Nit) — `removed` also counts `not_active` keys that were not in the index.

## 8. Physical iPhone acceptance boundary
- **Phase 3 device smoke** (optional, local staging only: the staging harness with the B0 backend branch; never production):
  - P1: download while online → force quit → airplane mode → relaunch → the Dispatch cards render, and driver switching works with no request.
  - P2: fresh install + airplane mode → the "isn't downloaded" state.
  - P3: an office reassignment → foreground → the card moves drivers.
- **Deferred to Phase 6 (full acceptance, spec §17):** silent-wake delivery on real phones, which needs Firebase and production-like APNs; six missions across several drivers; multi-stop airplane-mode completion; idle background with no Dispatch requests; battery and network verification.

## 9. Deferred scope (explicitly NOT in Phase 3)
- **Phase 4:**
  - Bridge `checklist_context` into the canonical `ChecklistContextStore`, preserving cycle and equipment identity.
  - Full `ChecklistContext` validation of packages.
  - **Offline Order Details (Screen 3) for never-opened orders (D2).** **Locked Phase 4 acceptance:** a mission never opened online must later support cached Dispatch → Driver Checklist → Order Details → equipment checklist with the phone fully offline, preserving the current screen flow unless inspection proves it cannot be preserved.
  - Prove that unopened later Delivery and Return checklists work offline.
- **Phase 5:** versioned offline T&C snapshot (backend), local rendering, local signature acceptance through the Sync Engine, and durable sync. Phase 3 stores `terms` opaquely and never renders it.
- **Phase 6:** the full physical acceptance in §8.
- **Deferred Phase 3 review findings F5–F14** (§7 review record); F6 goes with the cosmetic / screen-flow pass.
- **Other:** later cosmetic and screen-flow changes; the final regression, version/build, archive and upload. Manual Dispatch offline readiness (D4: outside guaranteed scope; no offline subsystem). The `dispatch_list_mixed.json` sync. Anything production: deploy, flag enablement, preflight on the server.

## 10. Self-review against the approved spec
| Spec | Covered by |
|---|---|
| §5 company-wide, all drivers, removal ≠ field-work deletion | §3.3, §3.6, D5, D7, tests 5, 6, 18 |
| §6.3 repair triggers (launch/login, foreground, Dispatch open/refresh, network restore) | §3.5, M6, test 16 |
| §7 missing → download / newer → refresh / same → nothing / absent → remove | §3.3, tests 1–5 |
| §11 one coordinator; serialize and coalesce; batch; validate; persist; atomic index; end promptly; idempotent | §3.3–3.5, §3.7, tests 2, 11, 17 |
| §12 protected durable storage, tenant namespace, key, revision, payload, cached-at, schema, separate index; cleanup only without dependent work | §3.2, D7, M2 |
| §13 cache ≠ Sync Engine | §4 "Not touched", test 6 |
| §14 stale-data rules 1–6 | §3.3 (replace when there's no work; work never deleted), §3.6 (removed missions hidden, reassignment moves the card, no filter I/O) |
| §15 no polling or GPS or keepalive; one manifest per run; only changed packages; backoff; prompt end | §3.5 (+ cooldown), §3.7, M6 grep gate |
| §16 failure behaviors | M3 failure tests |
| §17 iOS list (checklist and T&C items → Phase 4/5; wrong tenant → §3.8) | §6, §9 |
| §19 release safety: nothing ships from this phase | status header, §9 |

No placeholders or open decisions (D1–D7 locked 2026-09-23).
