# Dispatch Offline — Physical iPhone Checklist (Phase 6)

**For Gary. Do one step at a time. Don't start until Claude says the setup is ready.**
The engineering plan behind this checklist is `docs/superpowers/plans/2026-09-26-dispatch-offline-phase-6-physical-acceptance.md`. Scenario letters match it.

---

## Before you start (every session)

**Safety rules. These keep production completely out of the test.**
1. **Never type a company code or log in on the phone.** If the app ever shows the Login screen, **stop and tell Claude.** Claude reopens it on the test server from the Mac.
2. **Don't install the App Store Rent n King on this phone** while the test build is on it.
3. **Keep the Mac awake and online.** The test server runs on it.
4. **"Fully offline" means Airplane Mode ON *and* Wi-Fi OFF.** Check both icons in Control Center; Airplane Mode can leave Wi-Fi on.
5. **Force-quit** means: swipe up from the bottom, then swipe Rent n King away.
6. **Screenshot:** side button + volume up. Claude will say when to AirDrop them to the Mac.
7. When a step says **CHECKPOINT**, stop and tell Claude. Claude checks the test server and says when to continue.

**Where things are in the app:**
- Settings › **Sync Status** shows what is waiting to sync ("N pending", "N need attention", or "All synced").
- Messages you may see:
  - "Saved on this phone · Pending Sync";
  - "Synced with Kabba";
  - "Saved · Needs Attention — see Settings › Sync".

---

## S0 — Setup check (Claude installs and opens the app first)

- [ ] The app opens on the Home screen (not Login).
- [ ] Open **Dispatch**. You see the test missions for **all drivers**, without choosing a driver.
- [ ] Choose each driver in the filter, then choose All again. The list changes instantly.
- [ ] Settings › Sync Status says **All synced**. **Screenshot.**
- [ ] **CHECKPOINT.**

---

## A — Delivery never opened online (mission M1) ★ first scenario

**Online part**
- [ ] Phone online, app open on Dispatch. Tell Claude "ready for A".
- [ ] Claude adds M1. Pull down to refresh if it doesn't appear within a minute.
- [ ] You see M1's card. **Do not open it.** Wait 30 seconds.

**Offline part**
- [ ] Go **fully offline**.
- [ ] Force-quit the app, then open it again. Dispatch shows M1. **Screenshot.**
- [ ] Open M1 → **Driver Checklist** → tap **Load Map & Go**, then **Arrived**.
- [ ] Open **Order Details**. The whole order shows: customer, items, notes. **Screenshot.**
  - ✗ If you see "This order isn't downloaded to this phone yet", **stop and tell Claude.**
- [ ] Open **Assembly Review**. It shows "Offline · showing the saved assembly". **Screenshot.**
- [ ] Open the **Delivery checklist**. Answer every required question and capture everything it asks for (photo, and any license or video step). **Save.**
  - You see "Saved on this phone · Pending Sync".
- [ ] Open **Terms & Conditions**. The full agreement shows, with the customer's name and the approval box. **Screenshot.**
- [ ] Tick the approval. The "customer" signs and submits.
  - You see "Signed on this phone — It syncs automatically…". **Screenshot.**
- [ ] Complete the Delivery the normal way. It should **not** ask for a T&C override.
- [ ] Force-quit and reopen, **still offline**.
  - M1 is still done, T&C still says "Signed on this phone", and Settings shows some **pending**. **Screenshot of Settings.**
- [ ] **CHECKPOINT** (Claude copies the phone's saved data).

**Back online**
- [ ] Turn Wi-Fi back on. **Don't tap Sync Now.**
- [ ] Within about a minute, Settings says **All synced**. **Screenshot.**
- [ ] Wait 30 seconds, then pull to refresh Dispatch. M1 shows as delivered.
- [ ] **CHECKPOINT.** Claude confirms each action reached the server **exactly once**.

---

## B — Return never opened online (mission M2)

- [ ] Online, app on Dispatch. Claude adds M2. Wait 30 seconds; **don't open it.**
- [ ] Go fully offline. Force-quit and reopen.
- [ ] M2 → **Driver Checklist**: Load Map & Go, then Arrived.
  - For the call result, choose anything **except "No Answer"**.
- [ ] **Order Details** shows fully.
- [ ] **Return checklist**: fuel, damage question, photo, and anything else it asks for. Save.
- [ ] Complete the Return the normal way. There is no T&C step (not required for returns).
- [ ] Force-quit and reopen offline. Everything is still there; Settings shows pending.
- [ ] Wi-Fi on. Settings reaches **All synced** by itself.
- [ ] **CHECKPOINT.**

---

## C — Force-quit at five moments (missions M6, M3)

For each line below: do the action **offline**, force-quit, reopen **offline**, then check that it looks exactly as before and that Settings still shows it **pending, not synced**.

- [ ] **C1** Online: let M6 download, but don't open it. Then go offline, force-quit, reopen. M6 opens fully offline.
- [ ] **C2** Answer **half** of M6's first checklist. Save. Force-quit, reopen. The answers are still there.
- [ ] **C3** Finish the answers. Save. Force-quit, reopen. It still shows finished.
- [ ] **C4** Sign M6's T&C. Force-quit, reopen. It says "Signed on this phone" and **doesn't** ask to sign again.
- [ ] **C5** Complete M6. Force-quit. Tell Claude. Claude stops the test server, then says to turn Wi-Fi on. Force-quit and reopen: still **pending**, never "Synced". Claude restarts the server. It syncs once.
- [ ] **CHECKPOINT.**

---

## D — Reboot (mission M3)

- [ ] Fully offline. On M3: Load Map & Go, answer part of the checklist, take a photo, and sign T&C if asked.
- [ ] **Turn the iPhone off, then on.** Unlock it. Stay offline.
- [ ] Open the app from the Home screen.
  - It opens normally (**not** Login), and all of M3's work is still there. **Screenshot.**
- [ ] Wi-Fi on. Settings reaches All synced.
- [ ] **CHECKPOINT.**

---

## E — Network changes (mission M6, second item)

(Only if this phone has cellular service. Tell Claude if not.)
- [ ] **E1** With something pending and the app open: turn Wi-Fi off and let cellular take over. It keeps syncing.
- [ ] **E2** While it's syncing on cellular, turn Airplane Mode on. The item stays pending, nothing is lost.
- [ ] **E3** Same as E2, starting from Wi-Fi.
- [ ] **E4** Do some work fully offline, then turn **Wi-Fi** on with the app open. It syncs **by itself**, and any office change shows up **without tapping**.
- [ ] **E5** Same as E4, but turn **cellular** on instead of Wi-Fi.
- [ ] **CHECKPOINT** after each.

---

## F — The app catches up without a push (Claude makes office changes)

For each line, Claude changes a mission and waits a minute. You then do the one action shown, and the change appears.
- [ ] **F1** Press Home, then come back to the app.
- [ ] **F2** Force-quit, then open the app.
- [ ] **F3** Leave Dispatch and come back; then pull down to refresh.
- [ ] **F4** Claude changes a mission while you're offline. Turn the network back on. The change appears without opening anything.
- [ ] **CHECKPOINT.**

---

## G — Real background push (only if approved)

- [ ] Settings › General › **Background App Refresh** is ON (and ON for Rent n King). **Low Power Mode** is OFF.
- [ ] Open the app, then press **Home**. **Don't force-quit it.** Put the phone down.
- [ ] Claude makes a change and tells you when. Wait 3 minutes. **Don't touch the phone.**
- [ ] Open the app **without refreshing**. The change is already there. No notification or badge appeared. **Screenshot.**
- [ ] Claude repeats this with a second change 5 minutes later. It may take up to 20 minutes to arrive. That spacing is on purpose.
- [ ] **CHECKPOINT.**

(If iOS skips a background push, that alone isn't a failure. Opening the app still catches up.)

---

## H — Every driver's work is on the phone

- [ ] Fully offline. Dispatch with no driver chosen shows missions for D1, D2 and D3, including yesterday's open return and missions two days out, but **nothing three days out**.
- [ ] Switch between drivers. The list changes instantly.
- [ ] Open one of **D2's** deliveries all the way to T&C, offline. It works.
- [ ] **CHECKPOINT.**

---

## I — Swapping equipment

- [ ] **I1** Online: Claude, or you in the office screen, swaps M3's unit. Refresh. Go offline and open M3's checklist. It is for the **new** unit.
- [ ] **I2** Fully offline, in M1's Assembly Review: swap the unit.
  - If it says "Could not load that category's equipment…", screenshot it and tell Claude.
  - Otherwise, the checklist for that item says it "needs a connection" and won't let you submit that item.
  - Old answers and photos are not reused.
- [ ] Wi-Fi on. The swap syncs, and you can now do the checklist for the new unit.
- [ ] **CHECKPOINT.**

---

## J — Starting a checklist over (mission M6, second item)

- [ ] Fully offline. Answer part of the checklist, then tap **Delete / Start Over**.
- [ ] Force-quit and reopen offline. The old answers **don't** come back, and the item says it needs a connection for the new checklist.
- [ ] Wi-Fi on. It syncs, and a fresh checklist loads.
- [ ] **CHECKPOINT.**

---

## K — On My Way / Arrived (mission M7)

- [ ] Fully offline. Tap **Load Map & Go**. Force-quit and reopen. It still shows On My Way.
- [ ] Tap **Arrived**. Force-quit and reopen. It still shows Arrived.
- [ ] Wi-Fi on. It syncs once.
- [ ] **CHECKPOINT.**

---

## L — Only part of the work syncs

- [ ] Fully offline. Do five things across M6 and M1: On My Way, checklist answers, a photo, a T&C signature, and a completion.
- [ ] Wi-Fi on. When Claude says so, Claude stops the server partway through.
  - What synced stays synced; the rest waits.
- [ ] Claude restarts the server. The rest syncs by itself.
- [ ] **CHECKPOINT.**

---

## M — The server refuses one item (mission M7)

- [ ] Fully offline. On M7, tap Load Map & Go. Set the call result to **No Answer** (safe: texting is switched off on the test server).
- [ ] Claude reassigns M7 to another driver.
- [ ] Wi-Fi on. You see "Saved · Needs Attention — see Settings › Sync".
  - Settings shows **1 need attention**, not pending. Your other work still syncs.
- [ ] Look at M7's card under your driver and under the new driver. **Screenshot both.**
- [ ] **CHECKPOINT.**

---

## N — Terms can't be swapped

- [ ] **N1** Online: Claude, or you in the office screen, edits the company terms templates. Go offline. M1-type T&C still shows the **original** wording. Sign it. Wi-Fi on. It is accepted.
- [ ] **N2** Claude changes M7's terms on the server behind the phone's back. Offline, the customer signs M7.
  - Wi-Fi on. The signature goes to **Needs Attention** (it is kept, not deleted).
  - Refresh M7's T&C: it shows the new version. Sign again. This one is accepted.
- [ ] **CHECKPOINT.**

---

## O — One part of a mission didn't download (mission M8)

- [ ] Claude breaks one part of M8 on the test server. Refresh.
- [ ] Offline: M8's card shows and opens, but the broken part says it isn't downloaded, never a blank screen. Other missions are fine. **Screenshot.**
- [ ] Claude fixes it. Online, refresh. M8 is complete.
- [ ] **CHECKPOINT.**

---

## P — Mission cancelled or moved while you have unsaved work

- [ ] Fully offline. Do some work on M9 and on M4: answers and a photo.
- [ ] Claude cancels M9 and moves M4 five days out.
- [ ] Wi-Fi on. M9 and M4 **leave** Dispatch, and your work is **not lost**: it syncs, or shows under Needs Attention in Settings.
- [ ] **CHECKPOINT.**

---

## Battery and background (Claude schedules these windows)

- [ ] **W0 (4 h):** force-quit the app and don't open it. Screenshot Settings › Battery at the start and end.
- [ ] **W1 (4 h):** signed in, app in the background, nothing happening. Phone face down. Same screenshots.
- [ ] **W2 (a work day, or two 4 h blocks):** open the app about 6 times as a driver would, while Claude makes office changes. Same screenshots.
- [ ] Keep the battery between 40 % and 90 %, not charging. Low Power Mode off.

---

## When Phase 6 is finished

- [ ] Settings › Sync Status says **All synced**, and **0 need attention** (Claude helps discard test leftovers).
- [ ] **Delete the Rent n King test app from the phone.**
- [ ] Tell Claude it's deleted.
