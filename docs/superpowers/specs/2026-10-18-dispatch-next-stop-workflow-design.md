# Dispatch Next Stop Workflow — Design

**Date:** 2026-10-18  
**Repository:** `Kabba24ai/mobileapp`  
**Status:** Product design approved in conversation; implementation plan pending written-spec review.  
**Primary objective:** ship the continuous driver Next Stop workflow in the next mobile release without delaying release for Driver Performance Intelligence.

---

## 0. Release priority

This work is intentionally split into two phases.

### Phase 1 — release-critical, ship first
After a driver completes any active mission, the app must keep the driver inside one continuous workflow and explicitly ask what they are doing next:

- go to the next customer / next assigned mission; or
- return to a shop.

The driver must not have to back out to Dispatch and manually reconstruct the next step.

### Phase 2 — separate follow-up
Driver Performance Intelligence will analyze completed work, route addresses, expected mileage/drive time, customer-stop allowance, and available mobile timestamps. It must not delay Phase 1.

If Phase 2 is not ready when Phase 1 is ready, Phase 1 ships alone.

---

## 1. Product intent

A driver workday is a continuous chain of destinations, not a collection of isolated jobs.

Examples:

```
Bon Aqua -> Customer A delivery -> Customer B return -> Waverly -> Customer C delivery -> Bon Aqua
```

or:

```
Waverly -> Customer A return -> Bon Aqua -> Customer B delivery
```

The app must make the next destination explicit at the end of each completed mission.

Phase 1 is workflow software, not route optimization. It does not decide where the driver should go. It lets the driver explicitly choose the next destination and continue.

---

## 2. Current integration point

The current Order Details completion flow already has a single leg-aware gate:

`btnDeliveryComplatedClicked` -> `LegCompletionEvaluator`

If the physical work is complete, the current implementation either:

- shows the success overlay and pops back to `DispatchListViewController`; or
- shows Sync Needs Attention treatment and pops back to `DispatchListViewController`.

That pop-to-Dispatch behavior is the exact Phase 1 integration point.

Manual Dispatch already has a durable local-first lifecycle:

`Assigned -> On My Way -> Arrived -> Completed`

and currently pops after a successful status change. A completed Manual Dispatch should enter the same Next Stop workflow rather than ending the driver's route.

Phase 1 should preserve all existing completion gates, local-first behavior, Sync Engine behavior, assignment rules, checklist rules, and offline cache rules. It changes only what happens *after* a mission is effectively complete.

---

## 3. Canonical Phase 1 flow

### 3.1 After an Order Delivery or Return completes

```
Mission completed
  -> existing success / Sync Attention treatment
  -> Next Stop
       -> Next Customer / Mission
       -> Return to Shop
```

The screen title/copy should be direct and operational:

**What are you doing next?**

Primary choices:

1. **Next Customer / Mission**
2. **Return to Shop**

### 3.2 Next Customer / Mission

Show the driver's remaining assigned work using the same canonical Dispatch work sources already used by the app.

The list must support the mixed driver workday:

- Delivery
- Return / pickup
- Manual Dispatch

Rules:

- show only work still assigned to the signed-in driver;
- exclude work already effectively completed locally or on the server;
- respect current reassignment truth;
- use existing Dispatch ordering / `sort_key` semantics;
- do not create a second independent mission ordering system;
- do not require network connectivity if the relevant work is already in the durable offline working set.

Selecting a mission continues into that mission's existing workflow. The Next Stop feature does not bypass current mission gates.

Examples:

- next Delivery -> existing Delivery start / Assembly Review / Driver Checklist path;
- next Return -> existing Return path;
- next Manual Dispatch -> existing Manual Dispatch detail path.

### 3.3 Return to Shop

The driver chooses a shop from the tenant's active store/location data.

For Rent N King, the expected choices are:

- Bon Aqua
- Waverly

Do **not** hard-code Rent N King store names into shared application logic. The code base is shared across tenants; use existing active store/reference data so each tenant receives its own stores.

After the driver selects a shop:

1. persist the selected shop locally before navigation;
2. launch the existing map/navigation helper using the shop address;
3. when the driver returns to the app, keep the shop stop as the current Next Stop state;
4. offer an explicit **Arrived at [Shop]** action;
5. after arrival, offer **Choose Next Mission**.

Phase 1 does **not** add a load/unload wizard. Loading, unloading, trailer swaps, and shop-task classification are future refinements.

This minimal shop state is enough to keep the workday continuous and produces a useful explicit arrival transition for future analytics.

---

## 4. Local-first and offline requirements

The Next Stop workflow must follow the existing Kabba mobile rule:

**User action -> durable local persistence -> immediate effective local state -> UI advances -> background/server reconciliation later where applicable.**

Phase 1 must remain usable with poor or absent service.

Required behaviors:

- completing a mission never waits on a fresh Dispatch network request before showing Next Stop;
- the user's selected shop survives app backgrounding and relaunch;
- if cached mission data is available, Next Customer works offline from the durable working set;
- if no next mission data is available offline, show the existing factual not-downloaded/offline treatment rather than inventing an empty day;
- never delete, overwrite, or discard existing Sync Engine operations;
- existing Needs Attention work remains preserved;
- a mission with Sync Needs Attention still allows the driver to proceed to Next Stop because the physical work has already happened.

The Phase 1 Next Stop state should be isolated from checklist, assignment, and mission-completion state. It must not mutate those existing records.

---

## 5. State boundary

Create one small, dedicated Next Stop state model rather than adding ad-hoc flags to existing screens.

Conceptually:

```
NextStopState
  idle
  choosing
  shopSelected(store)
  arrivedAtShop(store)
```

A selected customer/manual mission does not need a second persistent mission object. The canonical Dispatch item already exists; selecting it should route into that existing object.

The persisted Next Stop state only needs to represent the non-order/non-manual stop that Dispatch does not already model: a shop transition.

Tenant identity must be part of the persistence key so one tenant's shop stop can never appear in another tenant.

The state may be stored in a small dedicated durable file/store following existing Sync/Core persistence patterns. Avoid adding unrelated fields to existing checklist or Dispatch cache files.

---

## 6. Minimal existing-code integration

This feature is **additive in behavior**, but wiring a new workflow into existing completion points necessarily requires small edits to existing files.

Do not claim a zero-edit implementation if the code proves otherwise.

Preferred structure:

### New focused components
- pure Next Stop state/policy in Sync/Core;
- small durable Next Stop store;
- Next Stop chooser UI;
- mission selection adapter that consumes existing Dispatch working-set/manual-task sources.

### Minimal call-site edits
Only hook the new flow where existing code currently returns to Dispatch:

- successful Order Delivery/Return completion;
- Order completion with Sync Needs Attention;
- completed Manual Dispatch.

Avoid broad refactors of `OrderDetailsViewController`, `DispatchListViewController`, or Manual Dispatch. Do not redesign Dispatch.

If a current helper already provides the required mission list or navigation behavior, reuse it.

---

## 7. Reassignment and completion rules

The driver should see work they actually still own.

For the Next Customer list:

- a mission reassigned away from the driver must not remain selectable;
- a mission newly assigned to the driver may appear after normal Dispatch reconciliation;
- a mission effectively completed on this phone must not reappear;
- server-confirmed completion must not reappear;
- Manual Dispatch uses its existing effective status and canonical reassignment behavior.

No new assignment writer is introduced by this feature.

Next Stop chooses a destination; it does not assign work.

---

## 8. Timestamps and future analytics

Phase 1 must not be delayed by Driver Performance reporting.

Existing operational timestamps remain valuable:

- process/checklist start where already recorded;
- On My Way / departure;
- Arrived;
- completion;
- Manual Dispatch status transitions.

The new shop transition naturally adds two useful local business events:

- shop selected / travel intent;
- arrived at shop.

However, Phase 1 does **not** require the Driver Performance report, nightly route calculation, scoring, UI agent integration, or a new performance API.

If adding a server-side event ledger materially threatens the mobile release, defer that ledger to Phase 2. Phase 1's workflow must not depend on it.

---

## 9. Phase 2 boundary — Driver Performance Intelligence

Phase 2 will be designed and implemented separately.

Locked Phase 2 business rules already agreed:

- base analysis on what the driver actually completed under their name, not the original morning plan;
- include completed Delivery missions;
- include completed Return missions;
- include completed Manual Dispatch missions;
- include office-manually-completed work under the driver assigned at completion;
- exclude work transferred away before completion;
- mid-day plan changes, cancellations, and driver substitutions are normal;
- address-based route analysis is the baseline and must work even with incomplete mobile button usage;
- recommended route mileage and drive time are calculated on the backend from origin/destination addresses;
- Phase 1 baseline customer service allowance = **20 minutes per customer stop**;
- missing timestamps reduce telemetry completeness but do not invalidate the address-based analysis;
- do not penalize efficiency merely because a driver missed a mobile button;
- keep **Travel Efficiency** and **Stop/Service Efficiency** separate initially;
- Manual Dispatch travel counts toward accomplished work;
- shop dwell may be observed where timestamps exist, but Phase 1 of performance analytics should not force an arbitrary shop-efficiency standard.

This section is context only. None of it is a blocker for the Phase 1 mobile release.

---

## 10. Non-goals for Phase 1

Do not add:

- GPS/background location tracking;
- continuous vehicle telemetry;
- route optimization;
- automatic next-mission selection;
- driver rankings;
- efficiency scores;
- nightly analytics jobs;
- performance-report UI;
- UI-agent/API integration;
- shop loading/unloading wizard;
- new assignment logic;
- checklist redesign;
- changes to existing Delivery/Return lifecycle semantics.

---

## 11. Acceptance criteria

Phase 1 is releasable when all of the following are true:

1. Completing a Delivery opens Next Stop instead of dumping the driver back to Dispatch.
2. Completing a Return does the same.
3. Completing a Manual Dispatch does the same.
4. A driver can choose another assigned Delivery, Return, or Manual Dispatch and continue into its existing workflow.
5. A driver can choose Return to Shop and select an active tenant store.
6. Rent N King presents Bon Aqua and Waverly from canonical store data, not hard-coded shared logic.
7. Shop selection is durable before Maps opens.
8. Returning to the app preserves the selected shop.
9. The driver can mark Arrived at Shop and then choose the next mission.
10. Existing Delivery/Return completion gates remain unchanged.
11. Existing assignment locks and reassignment rules remain unchanged.
12. Existing Sync Engine operations are never deleted or discarded.
13. Needs Attention completion still lets the driver continue to Next Stop.
14. Offline cached Dispatch can supply the Next Customer list.
15. Missing offline mission data is represented honestly and does not masquerade as "no work".
16. Existing Dispatch list behavior remains unchanged outside this new post-completion path.
17. Existing Manual Dispatch lifecycle remains unchanged except for the post-Completed routing destination.
18. No Phase 2 analytics work is required to ship Phase 1.

---

## 12. Release strategy

Optimize for today's mobile release.

Implementation order should be:

1. isolated Next Stop core state/policy;
2. Next Stop chooser + shop flow;
3. hook Order completion;
4. hook Manual Dispatch completion;
5. reuse existing Dispatch sources for remaining missions;
6. focused unit/hosted tests;
7. build/smoke validation;
8. prepare the mobile release.

Do not let Phase 2 work enter the release-critical path.

One final human gate is appropriate before merge/release. All read/write code work, tests, commits, branch push, and PR preparation may proceed without intermediate approval once the implementation plan is approved.
