# Next Stop route events (2026-10-20)

**Owner decision (Gary, 2026-10-20).** The driver's answers on the Next Stop screen are the evidence for Kabba's Driver Efficiency route reconstruction. Phase 1 kept them on the phone; this branch synchronizes them. No mobile release is authorised; see the backend's `docs/driver-efficiency-2026-10-19/ROLLOUT.md`.

## What the phone already did (Phase 1, 1.0.27)

- When a Delivery, Return or Manual Dispatch is completed, the driver is asked **"What are you doing next?"**:
  - **Next Customer / Mission** opens the picker. Choosing a mission opens it through Dispatch.
  - **Return to Shop** opens the shop list, then Maps. The screen offers **Arrived at <shop>**, and then **Choose Next Mission**.
- **Only the shop stop was persisted, locally** (`NextStopStore`). No Sync Engine handler; nothing reached Kabba.
- **On My Way and Arrived** for order legs are `driver_checklist.update` with device `captured_at`. "Load Map & Go" is the On My Way, and it opens Maps.
- **Manual Dispatch statuses** went without device time.
- **When Next Stop does not open:**
  - Order Details opened from the Orders list (no Complete button);
  - no Dispatch beneath;
  - incomplete work (Driver Override screen);
  - Back without tapping Complete;
  - a cancelled manual task.

## What this branch adds

| Answer on the screen | Operation `next_stop.event` → `POST dispatch/next-stop/events` |
|---|---|
| A mission chosen in the picker (and actually opened) | `event=next_mission`, `from` = the stop just finished (or the shop reached on this screen), `to` = the mission + its leg, `heading_to_shop` when chosen on the way to a shop |
| A shop chosen (after the shop stop reached disk, before Maps) | `event=return_to_shop`, `from` = the stop just finished, `to` = the store (`unique_id`) |
| Arrived at <shop> | `event=arrived_at_shop`, `to` = the store |

- **Durable and idempotent.** A canonical Sync Engine operation: durable before anything else, operation id = idempotency key, `captured_at` = the tap. It is offline-safe, and a retry or a relaunch delivers it exactly once.
- **Its own ordering key**, with no business identity. It never waits behind a mission's operations, and never holds them up.
- **A 404 means "not yet".** It is read as a server without the endpoint (an app ahead of its backend): the answer waits and retries, never Needs Attention. Validation refusals still need attention.
- **Best-effort for the driver.** Recording never blocks or changes the screen's behaviour.
- **Where the driver is standing.** `beginNextStopFlow(completed:)` receives the completed mission:
  - Order Details passes its leg (`effectiveCompletionLeg`);
  - Manual Dispatch passes its task (both the board row and the Next Stop picker path).
- **A stale shop stop is ignored.** A shop stop loaded from disk was set before the job just completed, so answers start from that job. Only a shop chosen or reached **on this screen** is "from the shop".
- **Manual Dispatch** status operations now send `captured_at` (the tap). The server keeps it on the operation record only.

## Tests

- **Core (`swift test`):** `NextStopRouteEventsTests` covers payload shapes, refused shapes, the request (operation id, `captured_at`), offline → relaunch → delivered once with its original time, its own ordering key, 404 waits while 422 needs attention, and an invalid stored payload.
- **Hosted:** `NextStopWorkflowHostedTests`, route-events extension:
  - the shop is durable, then the answer is recorded, then Maps opens;
  - a failed write records nothing;
  - arrival;
  - A → B;
  - store → customer;
  - on the way to a shop;
  - a stale shop stop;
  - a refused pick records nothing;
  - Delivery, Return and Manual completions hand their identity to Next Stop;
  - a Return on offer carries its leg;
  - the Manual Dispatch request carries `captured_at`;
  - the handler needs a session.
