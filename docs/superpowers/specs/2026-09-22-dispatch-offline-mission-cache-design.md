# Dispatch Offline Mission Cache — Design

**Date:** 2026-09-22  
**Repositories:** `Kabba24ai/mobileapp` (iOS) + canonical Kabba Laravel backend  
**Status:** Design ready for review

## 1. Problem

Kabba drivers routinely work in rural areas where cellular service is unreliable or absent. The mobile app already has durable local-first capture for several field actions, and checklist contexts can be cached after they have been opened while connected. That is not sufficient for Dispatch.

Today, a driver can leave connectivity before a later delivery or pickup has ever opened its canonical equipment checklist or Terms & Conditions. In that situation, the phone may have the Dispatch card but not all data required to complete the work.

The operational requirement is stronger:

> Every Kabba phone must automatically maintain enough local data to complete all active Dispatch work for the company within the working horizon, without depending on the logged-in employee, the selected driver filter, or any user tap.

The system must also remain responsive to Dispatch changes made throughout the day.

## 2. Goals

1. Every registered Kabba iPhone receives and maintains the same company-wide offline Dispatch working set.
2. The working horizon is:
   - every still-open overdue Dispatch mission,
   - today,
   - the next two calendar days.
3. Driver selection remains only a local UI filter over the already-cached company-wide working set.
4. New or changed Dispatch work is actively pushed toward phones in the background.
5. Drivers do not need to acknowledge notifications or manually request downloads.
6. The app must avoid timer-based server polling and remain battery friendly.
7. Equipment checklists required in the field must be available offline even if the checklist was never opened before the driver left coverage.
8. Unsigned Terms & Conditions required at the customer location must be readable and signable offline.
9. Captured field work remains local-first and is never deleted because Dispatch changes.
10. Missed or delayed background pushes must self-heal on the next normal reconciliation opportunity.

## 3. Non-goals

- Do not preload Apple Maps, map tiles, routes, or navigation data.
- Do not make preloading dependent on the logged-in employee.
- Do not make preloading dependent on the selected driver in Dispatch.
- Do not require the driver to tap a push notification.
- Do not implement recurring timer polling.
- Do not introduce a second source of business truth on the phone. Laravel remains canonical; the phone stores durable snapshots and unsynced field work.

## 4. Mission identity

The offline unit follows the existing Kabba movement model:

`order_product_unique_id + leg`

where leg is Delivery or Return.

A mission package is therefore specific to one order-product leg. Grouped loads, driver filters, and route presentation can reference these mission packages without changing their identity.

This is important for:

- multi-line orders,
- Delivery versus Return isolation,
- checklist execution/cycle correctness,
- equipment substitution,
- local-first completion,
- reassignment and cancellation handling.

## 5. Company-wide working set

Every phone stores the full active tenant/company working set for:

- all still-open overdue Dispatch missions,
- all missions dated today,
- all missions dated tomorrow,
- all missions dated the following day.

The working set includes all drivers. The currently selected driver only filters the locally available data.

A mission that is cancelled, completed, moved outside the horizon, or otherwise removed from active Dispatch disappears from the active local Dispatch list when reconciliation applies the newer server state.

Removing a mission from the active list must **not** delete locally captured unsynced work. Sync Engine operations, captured media, signatures, checklist answers, and other durable field evidence remain until they are successfully reconciled or explicitly resolved through the existing sync-attention workflow.

## 6. Synchronization architecture

### 6.1 Push-driven, not polling-driven

Dispatch synchronization is event-driven.

There must be:

- no repeating 30-second / 5-minute / similar timer,
- no permanent background loop,
- no GPS dependency,
- no persistent socket solely to discover Dispatch changes.

When a meaningful Dispatch change occurs, Laravel marks the company Dispatch dataset with a newer revision and schedules a silent background push to every registered Kabba installation for that tenant.

The push is a wake-up hint only. It does not carry the mission package itself and is not visible to the employee.

### 6.2 Change coalescing

Dispatch edits commonly happen in short bursts.

The backend should debounce push delivery for approximately 60–90 seconds and enforce a hard maximum coalescing delay of approximately two minutes.

Multiple changes during the window collapse into one wake-up because the phone always reconciles against the newest manifest revision.

### 6.3 Repair triggers

Silent iOS background pushes are best-effort and cannot be treated as the only correctness mechanism.

The same reconciliation routine must also run when appropriate on:

- app launch/login completion,
- app foreground,
- Dispatch screen refresh/open,
- an active app session regaining network connectivity.

These are repair paths, not timer polling.

A missed push therefore delays freshness but cannot permanently strand the device on an old dataset.

## 7. Server-side manifest

Laravel exposes a lightweight, tenant-scoped Dispatch offline manifest.

Conceptual response:

```json
{
  "revision": 18427,
  "generated_at": "2026-09-22T18:22:00Z",
  "horizon": {
    "includes_open_overdue": true,
    "through_date": "2026-09-24"
  },
  "missions": [
    {
      "mission_key": "OP-UNIQUE-ID:delivery",
      "revision": 41
    },
    {
      "mission_key": "OP-UNIQUE-ID:return",
      "revision": 12
    }
  ]
}
```

The manifest contains the complete active working set, not a paginated partial view.

The phone compares the manifest with its local index:

- missing locally -> download,
- server revision newer -> refresh,
- revision unchanged -> do nothing,
- local mission absent from the new manifest -> remove from active presentation,
- local unsynced work for a removed mission -> retain outside active presentation until reconciled.

The manifest is intentionally small. A silent wake that discovers no changed mission should end after this single request.

## 8. Mission package

For each new or changed mission, the phone downloads the field data required to finish that stop without connectivity.

The package should contain, directly or through stable embedded snapshots:

### Dispatch / order
- mission key and revision,
- order identity and number,
- customer identity and contact fields needed in the field,
- delivery/pickup address,
- scheduled date/time,
- active leg,
- current lifecycle state,
- assigned Delivery and Return employees needed by Dispatch,
- transport mode and other fields required by the existing Dispatch card/workflow.

### Product / equipment
- order-product identity,
- ordered product information required by field UI,
- currently assigned equipment identity,
- equipment display/reference data required by the checklist,
- product options / assembly facts required by the field workflow.

### Checklist
- canonical checklist context for the mission leg,
- current checklist execution/cycle identity,
- canonical question IDs and question content,
- prepared/completed state,
- stage/in-transit restrictions,
- current equipment assignment used by the execution,
- any other server-state fields already required by the existing ChecklistContext contract.

The server remains authoritative. The cached context is a durable snapshot that permits offline execution.

### Terms & Conditions
If terms are already accepted or exempt, the package records that state.

If terms may still need to be signed, the mission package must include an offline-renderable snapshot of the exact Terms & Conditions version that must be signed, including a stable terms revision/hash or equivalent server identity.

The field flow must be capable of:

1. displaying that cached terms snapshot without network access,
2. capturing the customer's signature/acceptance locally,
3. durably recording the acceptance in the Sync Engine before advancing,
4. synchronizing the signed acceptance to Laravel when connectivity returns,
5. preserving which exact terms revision/content was signed.

Caching only the existing web URL is not sufficient.

## 9. Mission revision rules

A mission revision must change whenever server state changes in a way that can affect field execution or presentation.

Examples include:

- assignment/reassignment to a driver,
- delivery/pickup date or time change,
- cancellation or reopen,
- movement into or out of the offline horizon,
- customer/delivery address change,
- equipment assignment/substitution,
- checklist reset/new execution cycle,
- relevant checklist content/rules change,
- T&C accepted/exempt state change,
- T&C content/version change,
- completion/lifecycle status,
- other Dispatch fields rendered or enforced by the mobile workflow.

Revision invalidation should be centralized in Laravel's canonical Dispatch/checklist/domain services rather than scattered across individual controllers.

## 10. Device registration and background push

Each app installation must register a stable installation identity and current APNs token with Laravel for its company/tenant.

Registration is installation-scoped, not driver-scoped.

Laravel must be able to send the Dispatch-change silent push to every active mobile installation belonging to the tenant regardless of which employee is signed in or which driver filter is selected.

The push payload should contain only enough information to wake and identify the reason/revision, for example:

```json
{
  "aps": {
    "content-available": 1
  },
  "type": "dispatch_changed",
  "dispatch_revision": 18427
}
```

The client still fetches the manifest and does not trust push payload content as canonical business state.

APNs token rotation and reinstall behavior must be handled. Invalid tokens should be retired server-side.

## 11. iOS background reconciliation coordinator

The iOS app should have one Dispatch offline-sync coordinator used by every trigger: silent push, foreground, Dispatch refresh, login completion, and active-session network restoration.

Responsibilities:

1. serialize/coalesce simultaneous reconciliation requests,
2. fetch the manifest,
3. compare server and local revisions,
4. batch-fetch only changed/new mission packages,
5. validate/decode packages,
6. persist each package durably,
7. atomically replace the active mission index only after the corresponding data is safe,
8. hide missions removed from the current manifest,
9. preserve all Sync Engine field work,
10. update the existing Dispatch presentation from local data,
11. end background execution promptly.

Repeated triggers with the same manifest revision must be idempotent and cheap.

If iOS terminates a background run midway, the next trigger resumes by comparing the durable local index with the current manifest. No special fragile continuation protocol is required.

## 12. Offline cache storage

Mission packages must use protected durable on-device storage, following the same durability principles as the current Sync Engine and ChecklistContextStore.

The cache should have:

- a tenant/company namespace,
- mission key,
- mission revision,
- package payload,
- cached-at timestamp,
- optional checksum/schema version,
- a separate active manifest/index.

Do not store canonical business state only in volatile memory.

Package cleanup may remove inactive cached snapshots after there is no pending local work that depends on them. Cleanup must never remove Sync Engine operations or captured field evidence merely because a mission leaves the active horizon.

## 13. Interaction with existing local-first workflows

This feature does not replace the Sync Engine.

The responsibilities remain:

**Offline Mission Cache**
- brings server truth to the phone before it is needed,
- supplies readable forms/context while offline.

**Sync Engine**
- durably records work performed by the employee,
- queues writes,
- retries,
- retains Needs Attention,
- prevents lost field work.

The desired field sequence is:

```
background preload
    -> driver selects any driver/filter
    -> Start Delivery / Start Return
    -> Driver Checklist
    -> travel
    -> Arrived
    -> Terms / equipment checklist / media
    -> local durable completion
    -> sync now or later
```

No step after preload requires connectivity merely to reveal the data needed to do the physical work.

## 14. Conflict and stale-data behavior

The server can change a mission while a phone has old cached data.

Rules:

1. If no field work has been captured against the old package, replace it with the new package.
2. If local field work exists, never silently delete it.
3. If a server change makes that captured work incompatible (for example, equipment/cycle changed), keep the captured work and route reconciliation through the existing Pending Sync / Needs Attention patterns.
4. A stale cached mission removed from active Dispatch must not remain visible just because unsynced work exists.
5. Reassignment to another driver changes presentation immediately after reconciliation, but because every phone stores all drivers, the mission remains locally available when it is still inside the company working horizon.
6. Driver-filter selection itself causes no network dependency.

## 15. Battery and network requirements

Battery friendliness is a first-class acceptance criterion.

The feature must satisfy:

- zero recurring timer polling for Dispatch freshness,
- no location/GPS wake mechanism,
- no persistent keepalive connection,
- silent push used only as a wake hint,
- one lightweight manifest request per reconciliation,
- only changed packages downloaded,
- coalesced server pushes,
- exponential/backoff behavior for failures,
- background task ended promptly after useful work,
- identical revision -> no package downloads.

With normal operations, a phone should sleep between meaningful Dispatch changes.

## 16. Failure behavior

### Silent push missed
No user-visible failure. Next foreground/Dispatch/login/network repair trigger reconciles.

### Manifest unavailable
Keep the last durable working set. Do not erase it.

### Individual package download fails
Keep the prior safe package if one exists. Do not advance that mission's local revision until the new package is durably stored.

### Package decoding/schema problem
Retain prior package and surface diagnostics/sync-attention information for staff/development; do not replace known-good cached data with unusable data.

### Phone offline during office changes
The phone continues using its existing package. On the next connectivity opportunity, reconciliation obtains the latest manifest and repairs the cache automatically.

### Mission removed while unsynced field work exists
Remove it from active Dispatch presentation; retain the field work until synchronization/reconciliation completes.

## 17. Testing and acceptance

### Laravel
Test at minimum:

- all drivers included,
- still-open overdue included,
- today + next two dates included,
- farther future work excluded,
- completed/cancelled/non-active work excluded,
- mission revision bumps on every field-relevant change,
- unrelated changes do not churn revisions,
- manifest is complete and non-paginated,
- company/tenant isolation,
- device installation registration/token rotation,
- silent push fan-out to all tenant installations,
- 60–90 second debounce and ~2-minute maximum coalescing bound,
- package contents correspond to canonical Dispatch/checklist/T&C truth.

### iOS unit/integration
Test at minimum:

- empty cache -> complete preload,
- same manifest revision -> no mission downloads,
- one changed mission -> only that package downloaded,
- multiple changed missions -> batch refresh,
- removed mission disappears from active list,
- removed mission with pending field work retains that work,
- reassignment updates filters without requiring another download solely for driver selection,
- checklist context is available when offline without ever opening the checklist while connected,
- second/third/fourth mission remains usable offline,
- T&C content renders offline,
- offline terms signature is durable and later syncs,
- interrupted reconciliation self-heals,
- simultaneous triggers coalesce,
- wrong tenant data cannot enter the cache.

### Physical iPhone acceptance
Use a real production-like sequence:

1. Seed/assign at least six mixed Delivery/Return missions across multiple drivers.
2. Confirm every phone receives the company-wide working set without choosing a driver.
3. Change assignments/times/equipment during the day; verify phones update without taps.
4. Put the phone into airplane mode before opening later missions.
5. Complete a later Delivery checklist that was never manually opened while online.
6. Complete a later Return checklist offline.
7. Open and sign previously unsigned T&C offline.
8. Capture required media offline.
9. Restore connectivity and verify durable operations reconcile.
10. Confirm cancelled/rescheduled-out-of-horizon work leaves the active list while unsynced work remains protected.
11. Verify no recurring Dispatch network requests occur during an idle background period with no Dispatch changes.

## 18. Rollout sequence

The implementation should be staged so each layer is independently testable:

1. **Backend revision/manifest foundation**
   - canonical mission identity,
   - working-horizon query,
   - mission revisions,
   - manifest/package APIs.

2. **Installation registration + silent APNs wake**
   - tenant-wide device registry,
   - change event/debounce,
   - silent push,
   - no user interaction.

3. **iOS mission cache + reconciliation coordinator**
   - protected storage,
   - manifest compare,
   - selective package refresh,
   - all-driver local Dispatch source,
   - removal semantics.

4. **Checklist preloading integration**
   - prepopulate canonical ChecklistContextStore from mission packages,
   - preserve cycle/equipment identity,
   - prove unopened checklists work offline.

5. **Offline T&C**
   - versioned terms snapshot,
   - local rendering,
   - local signature/acceptance,
   - durable sync.

6. **Physical multi-stop acceptance and battery/network verification**
   - real iPhone,
   - multiple drivers,
   - multiple rural-style stops,
   - dynamic office edits,
   - connectivity loss/restoration.

## 19. Release safety

This work changes mobile/background behavior and Laravel APIs. It must not be folded into a release solely because source changes pass unit tests.

Before App Store release:

- run the complete Sync Core regression suite,
- run Dispatch/checklist/T&C hosted tests,
- physically validate background silent-push behavior on real iPhones,
- physically validate offline second/third/later missions,
- verify APNs production entitlement/configuration,
- verify no timer polling,
- verify production-like tenant isolation,
- verify no field work can be deleted by cache cleanup/reconciliation.

Version/build bump, archive, and App Store upload remain a separate explicit release mission.

## 20. Final design decisions

The following decisions are intentionally locked:

- Cache is **company-wide on every phone**, not driver-login-specific.
- Driver selection is a **local filter only**.
- Horizon is **open overdue + today + next two days**.
- Updates are **push-driven**, not timer-polled.
- Dispatch changes are coalesced for roughly **60–90 seconds**, with about a **2-minute maximum delay** during edit bursts.
- Silent push requires **no employee interaction**.
- Missed push is repaired by normal lifecycle reconciliation.
- **Maps are completely out of scope.**
- Active Dispatch removal and local field-work retention are separate concerns.
- Checklist data is proactively cached before the checklist is opened.
- Unsigned T&C must be truly usable offline, not merely represented by a cached URL.
- Laravel remains canonical; the phone cache is a durable operational snapshot.
