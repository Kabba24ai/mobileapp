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

## Driver Delivery Process Flow — P1 to P16 (added 2026-09-27, do these after A–P above)

**Same rules as above.** Test server only. Never the Login screen. "Fully offline" = Airplane Mode ON and Wi-Fi OFF, and **stay offline until Claude says**. Every scenario uses a mission Claude adds and names (P1, P2 …). Evidence goes under `~/Documents/kabba-dispatch-offline-p6-evidence/driver-flow/`. The design behind these steps is `docs/superpowers/specs/2026-09-27-driver-delivery-process-flow-design.md` (§16).

**New words you will see:**
- **Review Assembly** — a button on the Driver Checklist (and on Order Details after Arrived). It opens the Assembly Review. Before you leave the yard you can change things there; after Load Map & Go it is read-only and tapping a row explains why.
- **Load Map & Go** stays grey until the assembly says **GO**, the call is recorded (**Confirmed** with every box ticked, or **No Answer**), **Fuel = Full** and **Keys = With Machine**. A sentence under the button tells you what is still missing. Nothing is pre-selected any more.
- **Service Offline** — the message Load Map & Go shows when there is no signal: the status is saved and will sync; the map button stays for a retry.

---

### P1 — First delivery, online, start to finish (mission P1)
- [ ] Phone online. Dispatch → mission P1 → **Start Delivery**. The **Assembly Review** opens (not the Driver Checklist). It says **STOP**. **Screenshot.**
- [ ] Tap **Available** on the unit and on every option. It says **GO**. **Continue to Driver Checklist** becomes filled. Tap it.
- [ ] On the Driver Checklist nothing is selected: Call Customer, Fuel and Keys all blank. Load Map & Go is grey and a sentence says what is missing. **Screenshot.**
- [ ] The header shows the unit as **"Name · #TAG"** and a **Review Assembly** button.
- [ ] Tap **Confirmed** and tick every box → the sentence changes to Fuel. Tap **Full** → Keys. Tap **With Machine** → Load Map & Go turns green.
- [ ] Tap **Load Map & Go**. Apple Maps opens. Come back to the app: it shows **On My Way** with the Arrived button. You see the "Pending Sync → Synced" toast.
- [ ] Tap **Arrived**. **Order Details** opens. The bar under the title reads **"Delivery Arrived · Name · #TAG"** with a **Review Assembly** button. **Screenshot.**
- [ ] Do **License**, then **Terms**. Each returns to Order Details.
- [ ] Tap **CheckList Deliv**. The equipment checklist opens **directly** (no Assembly Review). Answer it and **Save**. The **Video** screen opens. Record a video and submit → back on Order Details.
- [ ] **Complete Delivery**. It should not ask for an override. Dispatch shows.
- [ ] **CHECKPOINT.** Claude confirms on the test server: On My Way once, Arrived once, completion once, media once, terms once, and the unit's id stored with the fuel/keys answers.

### P2 — Force-quit and come back at every stage (mission P2)
- [ ] Start Delivery → Assembly Review → confirm everything (GO). **Do not tap Continue.** Force-quit. Reopen, Start Delivery again → the review opens again at GO. Tap Continue.
- [ ] On the Driver Checklist tap **No Answer** and **Full**. Force-quit. Reopen, Start Delivery → the Driver Checklist opens with No Answer and Full still selected.
- [ ] Tap **With Machine** → **Load Map & Go** (dismiss Maps). Force-quit. Reopen, Start Delivery → the Driver Checklist opens **On My Way**.
- [ ] Tap **Arrived**. Force-quit. Reopen, Start Delivery → **Order Details opens directly**. **Screenshot.**
- [ ] **CHECKPOINT.** Claude confirms no step was sent twice.

### P3 — Change the unit before leaving (mission P3, Claude names two spare units)
- [ ] Start Delivery → Assembly Review. Tap the unit's name → the picker opens. Pick the **direct match** spare unit Claude named → **no reason** is asked. The row shows the new unit, unconfirmed, **STOP**.
- [ ] Tap the unit's name again → pick the **other** spare unit → a **reason** is asked. Pick one.
- [ ] Tap **Available** on the unit (and options) → **GO** → Continue to Driver Checklist.
- [ ] Fuel and Keys are **blank** (the unit changed); Call is as you left it.
- [ ] **CHECKPOINT.** Claude confirms the server shows the new unit assigned, the old confirmation retired, the old checklist cycle superseded.

### P4 — Review Assembly, before and after departure (mission P4)
- [ ] Start Delivery → review → GO → Continue. On the Driver Checklist tap **Review Assembly**. Change nothing. Tap **Back to Driver Checklist**. You are back on the same Driver Checklist with your answers.
- [ ] Record the call, Full, With Machine → **Load Map & Go** (dismiss Maps). Tap **Review Assembly** again → every row is grey, no Change/Assign button, no Continue. Tap a row → a message explains the truck has left. **Screenshot.** Back.
- [ ] Tap **Arrived** → Order Details → tap **Review Assembly** in the bar → same read-only review. Back.
- [ ] **CHECKPOINT.** Claude confirms no new operations were created by the review visits.

### P5 — Fully offline first start (mission P5 — never open it online)
- [ ] Phone online on Dispatch. Claude adds P5. Wait one minute (it downloads). **Do not open it.**
- [ ] Go **fully offline**. Force-quit, reopen. Start Delivery → the Assembly Review opens from the saved copy ("Offline · showing the saved assembly"). Confirm everything → GO → Continue.
- [ ] Record the call, Full, With Machine → **Load Map & Go**. You see **Service Offline** ("…saved on this phone and will sync…"). The screen shows On My Way. **Screenshot.**
- [ ] **Stay offline until Claude says.** **CHECKPOINT** (Claude copies the phone's saved data).
- [ ] Wi-Fi on. Within a minute Settings says **All synced**. **CHECKPOINT.** Claude confirms each operation reached the server exactly once.

### P6 — Offline switch, confirm, depart, then reconnect (mission P6)
- [ ] Online: let P6 download. **Fully offline.** Start Delivery → review. Tap the unit's name → the picker shows the saved fleet list for that category. Pick a spare unit → a message warns its **checklist needs service**; tap **Switch**; give a reason if asked.
- [ ] Tap **Available** on the new unit and options → GO → Continue → call, Full, With Machine → **Load Map & Go** → Service Offline.
- [ ] **Stay offline until Claude says.** Settings shows **3 pending** (switch, confirm, On My Way). **Screenshot.**
- [ ] Wi-Fi on. **CHECKPOINT — the exact drain check:** Claude reads the server log and confirms the three requests arrived in this order — **switch → availability → On My Way** — all accepted (200), **none** Needs Attention, and the server's assignment is the new unit. Then Claude opens the new unit's checklist context on the phone (it loads now that there is service).

### P7 — The trap that started all this (mission P7, online)
- [ ] Online. Start Delivery → review → GO → Continue → call, Full, With Machine → Load Map & Go → **Arrived**. Wait for **All synced**.
- [ ] Force-quit. Reopen. Start Delivery → Order Details. Tap **CheckList Deliv** → the equipment checklist opens **directly**; the Assembly Review never shows. **Screenshot.**
- [ ] Answer and **Save** → Video → record → submit → back on Order Details (not the review). **Complete Delivery.**
- [ ] **CHECKPOINT.**

### P8 — The call (mission P8)
- [ ] Start Delivery → GO → Continue → **Full**, **With Machine**, leave the call blank → Load Map & Go stays grey; the sentence says to record the call.
- [ ] Tap **Confirmed**, tick all but one box → still grey.
- [ ] Tap **No Answer** → green. Tap **Load Map & Go**.
- [ ] **CHECKPOINT.** Claude confirms the No-Answer text was recorded **once** on the test server (outbound texting is disabled there).

### P9 — Fuel and Keys (missions P9a, P9b — P9b's unit needs neither fuel nor keys)
- [ ] P9a: GO → Continue → No Answer → **Not Full** → grey with the fuel sentence. **Full** + **Missing** → grey with the keys sentence. **Full** + **With Machine** → green. **Screenshot of each.**
- [ ] P9b: GO → Continue → the Fuel and Keys columns are **not shown**. **No Answer** alone turns Load Map & Go green.
- [ ] **CHECKPOINT.**

### P10 — The office changes the unit while you are on the Driver Checklist (mission P10)
- [ ] Online. Start Delivery → GO → Continue → call, Full, With Machine → **do not** tap Load Map & Go. Tell Claude "ready for P10".
- [ ] Claude reassigns the unit on the test server. Pull back to Dispatch and Start Delivery again (or wait for the refresh).
- [ ] Load Map & Go is grey; the sentence says to confirm the assembly; **Review Assembly** → the new unit is unconfirmed (STOP). Tap Available → GO → Back.
- [ ] Fuel and Keys are asked again for the new unit. Answer them → green.
- [ ] **CHECKPOINT.**

### P11 — Return regression (mission P11, a Return)
- [ ] Start Return → the Driver Checklist opens directly (no Assembly Review, **no Review Assembly button**, **no Fuel/Keys**). The call is blank and Load Map & Go is grey. Tap **No Answer** → green.
- [ ] Load Map & Go → **Arrived** → Order Details → Return checklist → Video (if asked) → **Complete**.
- [ ] **CHECKPOINT.** Claude confirms the Return looks exactly as before except the explicit call.

### P12 — Nothing can change the unit after Load Map & Go (mission P12)
- [ ] Start Delivery → GO → Continue → call, Full, With Machine → **Load Map & Go**.
- [ ] Try to change the unit from each of these: **Review Assembly** on the Driver Checklist (rows grey); **Order Details → CheckList Deliv → tap the unit** (refused: "already on its way"); the **Queue Line** card for this order (grey); the **Orders** list → this order → its Assembly Review (grey).
- [ ] **CHECKPOINT.** Claude confirms the server's assignment never changed.

### P13 — Same, after Arrived (mission P13)
- [ ] Repeat P12's steps, but tap **Arrived** first and start each attempt from **Order Details** and its **Review Assembly**.
- [ ] **CHECKPOINT.**

### P14 — The office cannot change it either (mission P14 — Claude drives the web pages)
- [ ] Start Delivery → … → **Load Map & Go**. Tell Claude "P14 On My Way".
- [ ] Claude tries, on the test server's admin pages: **Dispatch** (assign), **Order Details** (assign, remove, assign-and-complete with a *different* unit), **Schedules**, **Schedule Assignment**, **Schedule Conflicts**. Each is refused. Assign-and-complete with the **same** unit still completes.
- [ ] Tap **Arrived** (use a second mission if the first was completed). Tell Claude "P14 Arrived". Claude repeats the five pages.
- [ ] **CHECKPOINT.**

### P15 — A legitimate recall (mission P15 — Claude performs the office action)
- [ ] Start Delivery → … → **Load Map & Go** → **Arrived**. Tell Claude "P15 arrived".
- [ ] Claude recalls the trip on the test server: **Order Details → the line's Delivery Status → Pending** (the approved recall door; Reschedule is refused at Arrived by design).
- [ ] Pull Dispatch to refresh. Start Delivery → the **Assembly Review** opens, editable again. Change the unit, tap Available → GO → Continue → Fuel and Keys are asked again → **Load Map & Go**.
- [ ] **CHECKPOINT.** Claude confirms the lock released (`is_arrived` cleared on the feed) and the second On My Way was recorded once.

### P16 — The yard is unchanged (any Queue Line card)
- [ ] Queue Line → a card → Assembly Review → **Continue to Checklist** → answer → **Save** → Video → submit → you are back on the **Assembly Review**.
- [ ] **CHECKPOINT.**

---

## When Phase 6 is finished

- [ ] Settings › Sync Status says **All synced**, and **0 need attention** (Claude helps discard test leftovers).
- [ ] **Delete the Rent n King test app from the phone.**
- [ ] Tell Claude it's deleted.
