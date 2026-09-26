# Dispatch Offline Phase 6 — Physical iPhone Acceptance & Reliability — Plan

> **Status: PLAN ONLY (2026-09-26). Awaiting Gary's review and the approvals in §9.** No Phase 6 test has been run and no product code has changed.
>
> **Rules for this phase:**
> - Local only. No push, merge, deploy, feature-flag change on any shared environment, version/build bump, archive, App Store Connect upload, production terms audit, SSH to production, or production data change.
> - Neither `main` is touched.
>
> **Starting heads:** backend `d53dca7a0`, mobile `efe6cc1` (the closed Phase 5 heads). §0 has the branches and worktrees.
>
> **What Phase 6 is:** an acceptance and reliability phase, not a feature phase. It proves that Phases 1–5 work together on a real iPhone:
>
> `Dispatch download → lose connectivity → complete the field workflow offline → keep everything on the phone → regain connectivity → converge safely`
>
> The central scenario runs, fully offline, for a mission **never opened online**:
>
> `cached Dispatch → Driver Checklist → Order Details → Assembly Review → equipment checklist → Terms & Conditions + signature → completion`
>
> **How findings are handled:**
> - Critical and Important operational defects are fixed under §7.
> - Minor and Nit findings are recorded for the later cosmetic pass unless they stop the acceptance program.
> - No theoretical hardening.

---

## 0. Heads, branches and assumptions

| | Backend | Mobile |
|---|---|---|
| Worktree | `/Users/garyjezorski/Documents/kabba2_AI-dispatch-offline` (the existing Phase 1–5 worktree, which has the real `vendor/` copy the suites need) | `/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6` (new) |
| Branch | `feature/dispatch-offline-phase-6` (new; no upstream) | `feature/dispatch-offline-phase-6` (new; no upstream) |
| Starting head | `d53dca7a0` (the Phase 5 head; no Phase 6 commits in this mission) | `efe6cc1` (the Phase 5 head); this plan is committed on top |
| Base | `origin/main` `e2131ffcb` as last fetched (it contains `e60f8be0b`) | `origin/main` `5252d87` as last fetched: the 1.0.22 release (`a7d3f48`) plus the design spec |
| `main` (untouched) | local `main` `47e081b17`. Its one unpushed commit (damage staging reconcile) is **not** in the Phase branches | `a7d3f48` in `mobileapp-canonical` |

- **App version in this build:** 1.0.22 (1008), the same numbers as the uploaded App Store build. Nothing is bumped. The Phase 6 build is a **Debug, development-signed** build and is never archived or uploaded.
- **Every physical run names the exact build commit under test.** If Phase 6 fixes land on these branches, the affected scenarios are rerun on the new build (§7).
- **"The feature flag"** means the backend's `DISPATCH_OFFLINE_WAKE_ENABLED`. It is the only Dispatch-offline switch in the system (§1.1). Production has none of Phases 1–5 (nothing is pushed), so the flag doesn't exist there. Phase 6 sets it only inside the local staging process, and only if gate G2 is approved.

---

## 1. The physical-test environment (inspection, 2026-09-26)

### 1.1 Facts

| Topic | Finding |
|---|---|
| Non-production backend | **A local staging harness exists and has been used before** (Phase 6A validation 2026-08-26; Return-completion and Settings missions 2026-09-11/13). No staging *server* exists. |
| How it runs | Laravel on this Mac (`php artisan serve`), database `rc_kabba_staging`, exposed over HTTPS by a Cloudflare quick tunnel. Procedure: backend `docs/mobile-integration/PHASE_6A_VALIDATION_REPORT.md` §13. |
| Staging database today | 16 orders, 1 customer (a `@staging.local` address) and 4 old test device tokens. **No production data.** The local dev database `kabba2_ai` has 2 orders and no customers. |
| Staging schema | **Pre-Phase-1.** `mobile_installations`, `dispatch_offline_wake_states` and `orders.terms_customer_signed_at` are missing. Staging must be migrated at the Phase 6 head (gate G1). |
| HTTPS | Required. The app has **no** App Transport Security exceptions (no `NSAppTransportSecurity` in `Info.plist`). |
| Route scoping | The API routes answer only on `API_DOMAIN`; admin web only on `ADMIN_DOMAIN` (`bootstrap/app.php:23-26`). `API_DOMAIN` must equal the tunnel host, or every API call 404s. |
| Pointing the phone at staging | The DEBUG-only `StagingTestHarness` launch arguments `-KabbaBaseURL -KabbaCompanyCode -KabbaEmail -KabbaPassword` (`RentnKing/Sync/Support/StagingTestHarness.swift`, compiled out of Release). It writes the staging URL into UserDefaults `base_url` and logs in directly, **skipping the production company-code lookup**. |
| Relaunch persistence | **A later plain relaunch (Home screen, after force-quit or reboot) stays on staging.** `base_url`, the user and the token persist, and Splash routes to Home (`SplashViewController.swift:57`). The harness resets only when its arguments are present. |
| The only way back to production | A logout or a 401/expired session clears `base_url` and shows Login. Typing a company code there queries the **hardcoded production** `https://api.rentnking.com/api/admin/v1/clients` (`LoginModel.swift:24`). |
| Phone | "Rent n King", an iPhone 17 Pro Max. devicectl id `93D4CE68-DFAF-5D00-829C-9D204CFEAD35`, UDID `00008150-000E43512EBA401C`. Paired and available. **The Rent n King app is not installed** (only the UI-test runner), so a first install starts from an empty container. |
| Signing | Identity "Apple Development: Gary Jezorski", team `A9U32VVCRV`, automatic signing. Profile "iOS Team Provisioning Profile: com.RentnKingNew.app" has `aps-environment` **development**, includes this phone, and expires 2027-08-31. |
| Firebase | One `GoogleService-Info.plist` for Debug and Release: project **`rentnking-4049b`** (the production Firebase project), sender `80983883809`. The entitlement is `aps-environment = development`, so a Debug build gets an **APNs sandbox** token through FCM. |
| Wake backend | `dispatch:offline-wake` runs every minute. There is no queue worker; it sends inline. Revisions settle after 50–110 s of debounce, and each installation is woken at most every **1200 s** (≈20 min), with backoff 60→1800 s. |
| Wake credentials | FCM needs `FIREBASE_PROJECT_ID` and `FIREBASE_SERVICE_ACCOUNT_PATH` (a JSON key under `storage/`). **Both are absent locally**, and no key file exists. |
| Wake targeting | **No allowlist:** every active `mobile_installations` row is woken. Preflight: `php artisan dispatch:offline-wake:preflight` (read-only; its OAuth check calls Google). |
| Flags | `DISPATCH_OFFLINE_WAKE_ENABLED` (default false) gates **only** sending. The manifest, packages, terms and installation endpoints have no flag (auth only). **The phone has no on/off switch:** offline Dispatch runs whenever someone is signed in. |
| Outbound contact | SMS (Twilio) and the communications/terms/receipt emails use credentials in the **database `settings` table**, so `MAIL_MAILER=log` does **not** stop them. Two field actions can text a customer immediately: the "No Answer" call result on the driver checklist, and the loyalty reward on Return completion. Reminders, intents, broadcasts and loyalty outbox run only from the scheduler. **The staging `settings` values could not be read during inspection;** gate G1 verifies them first. |
| Phone repair triggers | Launch, login, foreground, Dispatch open, pull-to-refresh, network restored (Alamofire reachability) and silent push. No Dispatch BGTask, timer, location or socket anywhere. The Sync Engine alone has a one-shot retry and a BGAppRefresh request, both only while work is outstanding (§3 P8). |
| On-phone evidence | Settings › **Sync Status** (pending / needs-attention counts, operation ids, Sync Now, Retry Now, Discard), plus toasts ("Saved on this phone · Pending Sync", "Synced with Kabba", "Saved · Needs Attention — see Settings › Sync"). Logs are `print()` only (Xcode console, Debug). Durable state is under `Application Support/KabbaSync/`. |

### 1.2 Does any scenario need production?

**No.** Every scenario in §4 runs against local non-production staging with no deployment:
- Office-side changes are made in the staging admin web or by Claude in the staging database.
- The one capability staging lacks is a real **FCM silent push** (scenario G and the wake part of §6). It needs a Firebase credential for `rentnking-4049b`; that is gate G2.
- Without G2, everything else still runs. Scenario F (missed push) runs naturally, because no push is ever sent.

### 1.3 Proposed environment (E1: local, non-production)

| Part | Value |
|---|---|
| Backend code | Backend worktree at the Phase 6 head (`d53dca7a0` today) |
| Database | `rc_kabba_staging`: backed up, migrated to the head, outbound settings blanked, seeded with the Phase 6 dataset (Appendix C). **Never production.** |
| Serving | `php artisan serve --host 127.0.0.1 --port 8123`, stdout teed to a timestamped request log, with this environment passed inline (never written to a file): `DB_DATABASE=rc_kabba_staging APP_ENV=staging MAIL_MAILER=log QUEUE_CONNECTION=sync CACHE_STORE=file SESSION_DRIVER=file API_DOMAIN=<tunnel host> API_DOMAIN_URL=https://<tunnel host> ADMIN_DOMAIN=localhost DISPATCH_OFFLINE_WAKE_ENABLED=false`. The last is `true`, with the two `FIREBASE_*` keys, only under G2. |
| HTTPS | `cloudflared tunnel --url http://127.0.0.1:8123` (a quick tunnel) or a named tunnel (decision D4) |
| Office UI | The staging admin web at `http://localhost:8123/` in the Mac's browser, as a seeded staging admin |
| Wake runner (G2 only) | `php artisan dispatch:offline-wake` run alone every 60 s by a shell loop on the Mac. It is a server-side stand-in for cron, not phone polling. **`schedule:work` / `schedule:run` must never run**, because they also start reminders, intents, broadcasts and loyalty jobs. |
| Phone build | A Debug, development-signed build of the mobile Phase 6 head, installed on "Rent n King" from Xcode/devicectl. It is pointed at staging **once** with the harness arguments and stays on staging afterwards. |
| Mac | Online and awake during runs (`caffeinate -dimsu`). A sleeping Mac is "server unreachable" to the phone. |

### 1.4 Paths to production, and how the protocol closes each

| Path | Closure |
|---|---|
| The Login screen's company-code lookup goes to production `clients` | **Never use the Login screen during Phase 6.** If the app ever shows Login (logout, 401, expiry), stop; Claude relaunches it through the harness from the Mac. |
| The Debug Login screen pre-fills credential literals committed in source (`LoginViewController.swift:98-109`, pre-existing) | Same closure. Recorded as a separate security note for Gary (§9 N1), not Phase 6 scope. |
| Sync Engine operations carry no server or company; they go wherever the current session points | The test install is used only against staging. At the end, every operation is synced or discarded and **the app is deleted from the phone** before any production install (G3). |
| A production backend waking the phone | The app isn't installed today and production's wake flag is off. This build registers only with staging. |
| The Firebase project `rentnking-4049b` is production's | Only G2 touches it (a credential), and it can target only tokens registered in the staging database. |

---

## 2. Approval gates (before any physical test)

Each gate names the environment, commits, production status, rollback, flag state, data isolation and risk. **Nothing in a gate runs until Gary approves it.**

### G1 — Stand up local staging at the Phase 6 heads
- **Environment:** E1 (§1.3). **Non-production**, this Mac only. **Commits:** backend `d53dca7a0` (or the Phase 6 head at execution time, named in the run record). **Flag:** `DISPATCH_OFFLINE_WAKE_ENABLED=false`.
- **Steps (Claude):**
  1. Back up `rc_kabba_staging` to a timestamped dump outside the repo.
  2. Read-only check of the outbound settings: the `settings` rows (`setting_name` / `setting_value`) `twilio_sid`, `twilio_auth_token`, `twilio_from_number`, `twilio_messaging_service_sid`, and the Mail Send Settings `mail_host` / `mail_from_address` (present or empty only; values never printed). If a name isn't found, Claude lists the Communication and Mail setting names (names only) before continuing.
  3. Blank those that are set, in `rc_kabba_staging` only.
  4. Delete the 4 stale `user_devices` rows.
  5. `php artisan migrate --force` against `rc_kabba_staging`.
  6. Seed Appendix C (fake customers only: `555-01xx` numbers, `@staging.local` emails).
  7. Start serve + tunnel.
  8. Run the staging readiness checks (§3 P9).
- **Data isolation:** no production data exists in staging; fake contacts only; outbound blanked; no scheduler.
- **Rollback:** stop the processes; drop `rc_kabba_staging` and restore the dump. Nothing outside this Mac changes.
- **Risk:** low. The one real risk, a text or email to a real person, is closed by steps 2–4 and the fake contacts.

### G2 — Real silent push (scenario G, and the wake half of §6)
- **Environment:** E1 plus FCM through the **production Firebase project `rentnking-4049b`**. **Commits:** as G1. **Flag:** `DISPATCH_OFFLINE_WAKE_ENABLED=true`, **only** in the staging serve / wake-runner environment.
- **Needs from Gary:**
  - **(a)** A new, dedicated service-account key for `rentnking-4049b`, limited to Firebase Cloud Messaging sending if possible. It is kept only on this Mac under the backend worktree's `storage/` (Claude confirms it is git-ignored with `git check-ignore -v` before use) and **revoked when Phase 6 ends**.
  - **(b)** Confirmation, in the Firebase console › Project settings › Cloud Messaging, that an **APNs Authentication Key** is configured for the iOS app. A key serves the sandbox tokens a Debug build has; a production-only certificate would not.
- **Explicitly not proposed:** copying production's key from the server (that would touch production).
- **Data isolation:** before the flag is set, `mobile_installations` must contain only the test phone's row (retire any others). The watcher wakes every active row.
- **Rollback:** unset the flag and keys and stop the wake runner; revoke the key.
- **Risk:** low to moderate. For the test window, a credential for the production Firebase project exists on this Mac. It can only reach tokens registered in staging.
- **If G2 is declined:** scenario G is recorded as "not tested: environment". The exit criterion "actual silent wake observed" stays open, and §8 says so.

### G3 — Install the Debug development build on "Rent n King"
- **Environment:** the phone in §1.1, **non-production** (staging only). **Commits:** mobile Phase 6 head (`efe6cc1` or later, named per run). **No** TestFlight, archive or upload.
- **Conditions:**
  - The phone is not used for production Rent n King during the window. Today the App Store app is not installed on it.
  - No App Store Rent n King is installed on it while the Debug build is present (same bundle id).
  - The Login screen is never used (§1.4).
- **End of Phase 6:** Sync Status shows 0 pending and 0 needing attention (discard leftover test ops deliberately), then **delete the app from the phone**.
- **Rollback:** delete the app. **Risk:** low.

### G4 — Staging-only controlled edits for rejection and fault scenarios
Scenarios I, M, N2, O and P need deliberate office or data changes: reassign, complete from the office, edit a frozen agreement's inputs by raw SQL, break one section, cancel or reschedule.
- **Environment:** `rc_kabba_staging` only. Each edit is logged in the run record with its undo.
- **Risk:** none outside staging.

### G5 — Tunnel choice (see D4)
- **Quick tunnel:** free and immediate. Its hostname dies within hours. A new hostname means a new `API_DOMAIN`, a harness relaunch, and a new, empty phone cache (the cache is keyed by base URL).
- **Named tunnel:** a stable hostname; needs a Cloudflare account and a DNS name (an outward-facing setup by Gary).

---

## 3. Automated preflight gates (before touching the phone)

Run in this order at the exact heads under test. **Every gate must pass or match its stated baseline.** Commands run one at a time: the backend suites share one test database, and two runs at once look like a hang.

**P0 — Clean branches and heads.** Local Mac terminal — read-only
```
cd /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline && git status --short && git rev-parse --abbrev-ref HEAD && git log -1 --format=%h && git rev-parse --abbrev-ref @{u}
cd /Users/garyjezorski/Documents/kabba2_AI && git rev-parse --short main
cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 && git status --short && git rev-parse --abbrev-ref HEAD && git log -1 --format=%h && git rev-parse --abbrev-ref @{u}
cd /Users/garyjezorski/Documents/mobileapp-canonical && git rev-parse --short main
```
Pass:
- both trees clean;
- both on `feature/dispatch-offline-phase-6` at the named heads;
- `@{u}` answers "no upstream configured";
- backend `main` = `47e081b17`, mobile `main` = `a7d3f48`.

**P1 — Mobile core suite.** Local Mac terminal — makes changes (build products in `.build/` only)
```
cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 && xcrun swift test 2>&1 | grep -E "error:|Executed .* tests" | tail -3
```
Pass: `Executed 547 tests, with 0 failures` at `efe6cc1` (more once Phase 6 fixes add tests; never fewer; always 0 failures). `Scripts/test-sync-core.sh` misdetects on this Xcode, so call `swift test` directly.

**P2 — Signed hosted tests, three consecutive runs** (the flake watch item, §5). Local Mac terminal — makes changes (DerivedData and result bundles)
```
cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 && mkdir -p ~/Documents/kabba-dispatch-offline-p6-evidence/preflight
for n in 1 2 3; do xcodebuild test -project RentnKing.xcodeproj -scheme RentnKingHostedTests \
  -destination 'id=15352B6A-C2E3-4027-BEA1-74DDCFFAB55E' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/kabba-p6-hosted \
  -resultBundlePath ~/Documents/kabba-dispatch-offline-p6-evidence/preflight/hosted-run$n.xcresult 2>&1 | grep -E "Executed .* tests" | tail -1; done
```
Pass: three times `Executed 84 tests, with 0 failures`.
- DerivedData lives outside `/tmp`, because macOS purges `/tmp` files unused for three days, which breaks package checkouts.
- The first run in a new worktree resolves Swift packages (needs GitHub access).

**P3 — Simulator build.** Local Mac terminal — makes changes (DerivedData)
```
cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 && xcodebuild -project RentnKing.xcodeproj -scheme RentnKing -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/kabba-p6-sim CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```
Pass: `BUILD SUCCEEDED`.

**P3b — Signed device build, no install.** Local Mac terminal — makes changes (DerivedData)
```
cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6 && xcodebuild -project RentnKing.xcodeproj -scheme RentnKing -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/kabba-p6-device build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|Signing|error:"
```
Pass: `BUILD SUCCEEDED`, signed "Apple Development". If Xcode reports a missing account, Gary signs in to Xcode (no upload is involved).

**P4 — Backend suites.**

One-time setup. Local Mac terminal — makes changes (creates one small ini file)
```
mkdir -p /Users/garyjezorski/.config/kabba-php-ini && printf 'memory_limit=2G\n' > /Users/garyjezorski/.config/kabba-php-ini/memory.ini
```
Then the suites. Local Mac terminal — makes changes (rebuilds the local test database `rc_kabba_testing` only)
```
cd /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline
export PHP_INI_SCAN_DIR=":/Users/garyjezorski/.config/kabba-php-ini"
for s in tests/Feature/Dispatch tests/Feature/Api tests/Feature/Mobile tests/Unit/Push tests/Feature/QueueLine tests/Feature/Terms tests/Feature/CustomerPortal; do echo "== $s"; php artisan test $s 2>&1 | grep -E "Tests:|FAILED"; done
```

| Suite | Pass at `d53dca7a0` |
|---|---|
| Dispatch | 597 passed |
| Api | 221 passed (220 at `4c6d3c3f6`, plus 1 added in `d53dca7a0`; this first Phase 6 run fixes the exact count) |
| Mobile | 15 passed |
| Unit/Push | 6 passed |
| QueueLine | 293 passed |
| Terms | 82 passed |
| CustomerPortal | 24 passed |

**P5 — Baseline-known failures, compared by test name.** Local Mac terminal — makes changes (test database; JUnit files in `/private/tmp`)
```
cd /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline && export PHP_INI_SCAN_DIR=":/Users/garyjezorski/.config/kabba-php-ini"
php artisan test tests/Feature/Orders --log-junit /private/tmp/p6-Orders.xml 2>&1 | grep -E "Tests:"
php artisan test tests/Feature/CustomerChecklists --log-junit /private/tmp/p6-CustomerChecklists.xml 2>&1 | grep -E "Tests:"
python3 - <<'EOF'
import xml.etree.ElementTree as ET
base = {l.strip() for l in open('/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6/docs/dispatch-offline-phase-6/baseline-known-failures.txt') if l.strip() and not l.startswith('#')}
for suite in ['Orders', 'CustomerChecklists']:
    failed = set()
    for tc in ET.parse(f'/private/tmp/p6-{suite}.xml').iter('testcase'):
        if tc.find('failure') is not None or tc.find('error') is not None:
            failed.add((tc.get('class') or tc.get('classname')).replace('Tests\\Feature\\', '') + '::' + tc.get('name'))
    mine = {b for b in base if b.startswith(suite + '\\')}
    print(suite, len(failed), 'failed; NEW:', sorted(failed - mine), '; baseline now passing:', sorted(mine - failed))
EOF
```
Pass: Orders 23 of 665 and CustomerChecklists 11 of 53 fail, with **NEW: []**. The 34 names are in `docs/dispatch-offline-phase-6/baseline-known-failures.txt` (Appendix A).
- A baseline test that now passes is reported, not a failure.
- `NoCostOrderCommunicationSuppressionTest` is known to be intermittent; a one-off failure there is rerun once before it counts.

**P6 — Manifest query ceiling.** Local Mac terminal — makes changes (test database)
```
cd /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline && PHP_INI_SCAN_DIR=":/Users/garyjezorski/.config/kabba-php-ini" DISPATCH_OFFLINE_REPORT_QUERIES=1 php artisan test tests/Feature/Dispatch/Mobile/DispatchOfflineManifestPerformanceTest.php 2>&1 | grep -E "manifest statements|Tests:"
```
Pass: `manifest statements at 50 missions: 438 (ceiling 450)` and 2 passed. The hard ceiling is 450.

**P7 — Shared contract fixture parity.** Local Mac terminal — read-only
```
B=/Users/garyjezorski/Documents/kabba2_AI-dispatch-offline/tests/Fixtures/mobile-contract; M=/Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6/RentnKingTests/KabbaSyncCore/Fixtures
for f in $B/*.json; do n=$(basename $f); [ -f $M/$n ] || echo "backend only: $n"; cmp -s $f $M/$n 2>/dev/null || echo "DIFFERS: $n"; done; for f in $M/*.json; do [ -f $B/$(basename $f) ] || echo "mobile only: $(basename $f)"; done
```
Pass: exactly one line, `DIFFERS: dispatch_list_mixed.json`. That drift is known and deferred: the mobile copy lacks `assigned_equipment`, which the cache path doesn't consume (Phase 3 plan §4). The other 30 fixtures are byte-identical.

**P8 — No polling, timers, GPS or persistent sockets.** Local Mac terminal — read-only
```
cd /Users/garyjezorski/Documents/mobileapp-dispatch-offline-p6
grep -rn --include='*.swift' -E "Timer\.scheduledTimer|Timer\(|DispatchSource\.makeTimerSource|CADisplayLink|BGAppRefreshTaskRequest|BGProcessingTaskRequest|CLLocationManager|startMonitoringSignificantLocationChanges|URLSessionWebSocketTask|webSocketTask|NWConnection|Starscream|SocketIO|PusherSwift" RentnKing | grep -v -E ":[0-9]+:\s*//"
grep -rn --include='*.swift' "asyncAfter" RentnKing/Sync
cd /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline && git diff e2131ffcb..HEAD -- routes/console.php | grep '^+' | grep -E "Schedule::"
```
Pass: exactly this known, pre-existing or by-design set (as of `efe6cc1` / `d53dca7a0`). **Any other hit fails the gate.**

| Hit | Why it is allowed |
|---|---|
| `Core/Frameworks/CLWaterWave/CLWaterWaveModel.swift:46,69` `CADisplayLink` | UI wave animation (pre-existing) |
| `Sync/Core/SyncEngine.swift:286,419,499,518` `scheduleRetryTimer` / `asyncAfter` | One-shot Sync Engine retry, re-armed only while retryable work is pending (backoff 30/60/120/300/900 s) |
| `Sync/App/KabbaSync.swift:197` `BGAppRefreshTaskRequest`; `:233,235` `asyncAfter` | Sync Engine background refresh, scheduled only when work is outstanding. The 1 s checks are bounded by a 25 s handler. |
| `Sync/App/SyncStatusUI.swift:126,209` | Toast dismissal (UI one-shot) |
| `Sync/App/DispatchOfflineSync.swift:107` | The wake's single 25 s deadline |
| Backend: one added `Schedule::command('dispatch:offline-wake')` | The server-side wake detector (every minute, on the server) |

The live audit of the same rules is §6.

**P9 — Staging readiness (after G1).** Local Mac terminal — read-only (queries staging and the local API only)
```
cd /Users/garyjezorski/Documents/kabba2_AI-dispatch-offline
DB_DATABASE=rc_kabba_staging APP_ENV=staging php artisan migrate:status | tail -5
mysql -N rc_kabba_staging -e "select setting_name, (setting_value is not null and setting_value<>'') as is_set from settings where setting_name in ('twilio_sid','twilio_auth_token','twilio_from_number','twilio_messaging_service_sid','mail_host','mail_from_address'); select count(*) as user_devices from user_devices; select installation_id, platform, app_build, retired_at from mobile_installations;"
curl -s -o /dev/null -w "%{http_code}\n" -H "Accept: application/json" https://<tunnel host>/api/admin/v1/dispatch/offline/manifest
```
Pass:
- no pending migrations;
- every outbound setting `is_set = 0`;
- `user_devices` = 0;
- `mobile_installations` holds only the test phone (after its first launch), or nothing yet;
- the unauthenticated manifest call returns `401` (the route exists on the tunnel host). A `404` means `API_DOMAIN` is wrong.
- Under G2 also: `DB_DATABASE=rc_kabba_staging APP_ENV=staging FIREBASE_PROJECT_ID=rentnking-4049b FIREBASE_SERVICE_ACCOUNT_PATH=<path> php artisan dispatch:offline-wake:preflight` passes. It sends nothing, but its token check calls Google.

**P10 — Device evidence path works (after G3).** Local Mac terminal — read-only (copies files off the phone)
```
xcrun devicectl device copy from --device 93D4CE68-DFAF-5D00-829C-9D204CFEAD35 --domain-type appDataContainer --domain-identifier com.RentnKingNew.app --source "Library/Application Support/KabbaSync" --destination ~/Documents/kabba-dispatch-offline-p6-evidence/S0/container
```
Pass: the `KabbaSync/` tree arrives (`operations/`, `dispatch-offline/v1/<tenant>/index.json`, …). If this devicectl form is refused, the fallback is Xcode › Devices › Download Container.

---

## 4. Physical iPhone acceptance matrix

### 4.0 Conventions

- **"Fully offline"** means Airplane Mode on **and** Wi-Fi off, both checked in Control Center (Airplane Mode can leave Wi-Fi on).
- **Evidence folder:** `~/Documents/kabba-dispatch-offline-p6-evidence/<scenario>/` on the Mac, outside every repo (decision D12). Phone screenshots are AirDropped there, and Claude's server checks are saved there as text.
- **Server checks** are the read-only staging queries in Appendix B. Claude runs them at each **Checkpoint**.
- **Device state:** the P10 container copy at the marked points. Operation files are compared by operation id.
- **"No duplicates"** means, for the scenario's order lines:
  - `mobile_operations` has exactly one row per operation id, and each field action appears once by type;
  - one `order_product_checklist_executions` completion per leg;
  - `order_media` row count equals the distinct `client_media_id` count;
  - one terms acceptance;
  - one leg completion.
- **Xcode debugger:** never attached during G, battery (§6) or any "backgrounded" step; a debugger keeps the app from suspending. Force-quit means swiping the app away in the app switcher.
- **Throttle timing:** the app skips a foreground or Dispatch-open refresh within 20 s of a fully current run. A test that expects a refresh from those triggers waits at least 30 s after the previous run.
- **Reset (default):** the Appendix C reset for the scenario's orders. The phone is not reinstalled between scenarios unless a scenario says so.

### S0 — Environment smoke (not a scenario; proves the setup)
1. **Setup:** G1 and G3 are done. Claude installs the build and launches it once with the harness arguments (staging URL, company `KABBA`, `driver@staging.local`).
2. **Action:** the app reaches Home. Open Dispatch.
3. **Expect:**
   - the Appendix C missions appear for every driver with no driver chosen;
   - pick each driver: the list filters with no request in the server log;
   - Settings shows "All synced".
4. **Checkpoint:**
   - `mobile_installations` has one row with build 1008;
   - the server log shows one manifest GET and one packages POST;
   - P10 works, and `index.json` lists every Appendix C mission as ready.
5. **Pass:** all of the above.

### A — Golden never-opened Delivery (M1)

| Step | Action | Connectivity | Expected UI | Expected durable local state |
|---|---|---|---|---|
| A1 | Claude seeds or reassigns M1 into today's Dispatch while the phone is online | online | Without G2, M1's card appears after an ordinary trigger (pull-to-refresh, reopening Dispatch or returning to the app); under G2 the wake brings it in with no tap | `index.json` has M1 ready at its revision; package on disk |
| A2 | Nothing. Let reconciliation finish (≥30 s). **Do not open M1.** | online | — | `field-ledger.json`: M1 sections `order_details`, `assembly`, `terms` ok; bridged caches written |
| A3 | Fully offline. Force-quit and relaunch (proves nothing depends on memory) | **offline** | Dispatch shows M1 from the cache, with the offline header | unchanged |
| A4 | Dispatch → M1 → **Driver Checklist**: Load Map & Go (On My Way), then Arrived | offline | Buttons advance; the card shows the stage | two `driver_checklist.update` ops, pending |
| A5 | **Order Details** | offline | The full order renders: customer, lines, notes. **Never** "This order isn't downloaded…" | — |
| A6 | **Assembly Review** | offline | The saved assembly with "Offline · showing the saved assembly"; the M1 line is present | — |
| A7 | **Delivery equipment checklist**: answer every required question and capture every required item (photo, and any driver's-license or delivery-video step the normal workflow asks for) | offline | The checklist for **M1's unit**; "Saved on this phone · Pending Sync" | `delivery_checklist.prepare` op + `delivery_media.upload` op + asset file |
| A8 | **Terms & Conditions** | offline | The frozen agreement renders fully (customer name, addendum, approval box); no network page | `terms-agreements/<tenant>/<M1 order>/current.json` present |
| A9 | Customer ticks the approval and signs; submit | offline | "Signed on this phone — It syncs automatically when the phone is online." | one `terms.sign` op + PNG asset |
| A10 | Complete the Delivery through the normal workflow (Delivery Complete) | offline | Completion proceeds **without** the Warning override for T&C; the card leaves Pending | `delivery_checklist.complete` op pending |
| A11 | Force-quit, relaunch, still offline | offline | M1 still completed on this phone; T&C "Signed on this phone"; Settings "N pending" | all ops still present and pending; nothing marked synced |
| A12 | Restore Wi-Fi | **online** | Toasts "Synced with Kabba"; Settings drains to "All synced", with **no** manual Sync Now | ops become synced |
| A13 | Wait ≥30 s, then pull to refresh Dispatch | online | M1 shows the server's completed state; T&C Accepted | — |

- **Server after reconnect (Checkpoint):**
  - `delivery_equipment_driver_status` progressed through On My Way → Arrived;
  - one completed delivery execution for M1's line;
  - one `order_media` per capture;
  - `orders.terms_status` = Accepted, with `terms_customer_signed_at` = the phone's signing time (not the sync time) and `signature_image` present;
  - `accepted_terms_content` = the frozen agreement;
  - delivery status Delivered.
  - **No duplicates** (§4.0).
- **Evidence:** screenshots at A3, A5–A9, A11 and A12 (Settings); container copies after A11 and after A12; the Appendix B checks after A13.
- **Pass:** every row as expected, the server state exact, no duplicates, and no step needed the network before A12.
- **Fail:** any "isn't downloaded" / "needs a connection" at A4–A10; any loss after A11; a duplicate; or a manual Sync Now needed.
- **Reset:** Appendix C reset for M1.

### B — Golden never-opened Return (M2)
Same principle as A on M2 (a unit on rent, due back today). The differences:
- **No Assembly Review step** (Return has none) and **no T&C** ("not required" for Return).
- **B4 Driver Checklist offline:** set the call result to anything **except** "No Answer" (§1.1: No Answer texts the customer). The No-Answer path is exercised only once, deliberately, in M with outbound blanked.
- **B6 Return checklist offline:** fuel, damage question, photo, and any license or media step the normal Return workflow asks for. **B7 Return completion offline.**
- **Server after reconnect:** one completed return execution; the unit back in the store per the Return rules; media once. Any fuel or damage answer creates only its ledger charge (no card or gateway call); the loyalty SMS cannot send (outbound blanked).

Evidence, pass/fail and reset as A.

### C — App termination at meaningful points (M6, M3)
Force-quit and relaunch **offline** at each point. For each point:
- **Expected UI:** the same state as before the quit.
- **Durable state:** the same operation files, byte-identical ids.
- **Not falsely confirmed:** nothing shows "Synced with Kabba" before reconnection.

| Point | How to reach it | After relaunch offline |
|---|---|---|
| C1 After package download, before opening | Online first download of M6; quit **before** opening it; go offline; relaunch | M6 cached and openable end-to-end (A5–A8 screens) |
| C2 After partial checklist answers | Offline: answer half of M6-line-1's checklist and **Save**; quit | Answers still there; unanswered still required |
| C3 After locally saved prepared state | Offline: complete the answers (prepare); quit | Checklist shows prepared; the `prepare` op pending once |
| C4 After signature, before sync | Offline: sign M6's T&C; quit | "Signed on this phone"; no second capture offered |
| C5 After completion queued, before server acknowledgment | Offline: complete M6; quit. Then go online **with the staging server stopped** (tunnel up, so 502 → retry); quit again; start the server | Relaunch shows completion pending, never "synced". After the server starts, it converges once. |

Server after C5: exactly one of each operation (no duplicate from the retries; replays show as `replay_count`, not new rows).

### D — Device reboot (M3)
1. Offline, on M3: On My Way, a partial checklist, a captured photo and a signature (T&C if pending).
2. **Power the iPhone off and on** (still offline) and unlock it. Relaunch the app from the Home screen.
3. **Expect:**
   - the app opens on staging (not Login);
   - M3's cached Dispatch, checklist answers, photo and signature are intact;
   - Settings shows the same pending count;
   - operation files are unchanged (container copy before and after).
4. Restore the network: converges once.

- **Pass:** no loss or corruption; no Login screen.
- **Note:** protected files are readable only after the first unlock following a reboot ("until first unlock"). The app is opened only after unlocking.

### E — Network transitions (M6 second line, plus ops queued in each state)
Precondition: the phone has an active cellular plan (decision D10). If not, E2–E5's cellular legs are recorded as not testable.

| Transition | Action | Expect |
|---|---|---|
| E1 Wi-Fi → cellular | With an op pending and the app foreground, turn Wi-Fi off, cellular on | Sync continues or retries over cellular; no duplicate |
| E2 cellular → no service | Queue an op, then remove all service (Airplane) mid-sync | The op stays pending (retry); nothing lost |
| E3 Wi-Fi → Airplane | Same with Wi-Fi as the source | Same |
| E4 offline → Wi-Fi | Queue offline, restore Wi-Fi with the app foreground | Drain and Dispatch reconcile start **automatically** (server log: a manifest GET plus op requests within seconds), with no Sync Now |
| E5 offline → cellular | Same over cellular | Same |

Also, per transition: make one office change to a cached mission while the phone is offline. On restoration, the change appears **without a tap**, through the network-restored trigger.

### F — Missed silent push (G2 off, or the wake runner stopped)
For each trigger:
1. Claude makes a meaningful office change: reassign M3 to another driver, or change M4's delivery time.
2. Confirm in the server log that the phone makes **no** request (no push is sent).
3. Wait 60 s, then fire the trigger:

| Trigger | Action | Expect |
|---|---|---|
| F1 App foreground | Background the app, then return to it | One manifest GET; the change appears |
| F2 Launch / login completion | Force-quit, then launch | Same |
| F3 Dispatch open / refresh | Leave Dispatch, reopen it; then pull to refresh | Same (the open is skipped if within 20 s of a complete run; pull-to-refresh always runs) |
| F4 Network restoration | Go offline, make the change, restore the network | Same, without opening anything |

- **Pass:** each trigger repairs the cache, and only changed packages are downloaded (server log: packages POST lists only the changed mission).
- **Principle:** a missed push only delays freshness, it is never a correctness failure.

### G — Actual silent push (needs G2)
- **Preconditions:**
  - the wake runner is running and the flag is on (staging process only);
  - `mobile_installations` holds only the test phone;
  - Background App Refresh is **on** (system and per app) and Low Power Mode is **off**;
  - the app is backgrounded (Home button), **not** force-quit, with no debugger;
  - phone unlocked or locked (both are tried).
- **G1 — first change:**
  1. Claude makes one meaningful change (reassign M4).
  2. **Expect:** within about 1–3 minutes (50–110 s debounce plus the next minute tick) the watcher sends one wake (`mobile_installations.last_woken_at` / `last_woken_revision`).
  3. The server log shows the phone's manifest GET, then a packages POST **for M4 only**, and then nothing further (the app sleeps again).
  4. Open the app without refreshing: M4 already shows the change.
- **G2 — spacing:**
  1. Make a second change 5 minutes later.
  2. **Expect no wake before 1200 s** have passed since the first. Then one wake repairs the cache.
  3. A foreground in the meantime also repairs it (F1).
- **G3 — burst:** make three changes within 60 s. **Expect one wake** (coalesced), not three.
- **Judgment:**
  - iOS may delay or drop background pushes, so one missed delivery is **not** a failure.
  - A failure is: a wake that arrives but does not repair; repeated wakes with no change; a visible notification or badge from a Dispatch wake; or the app staying active after the wake (no end within about 25 s).
- **Evidence:** the server request log with timestamps; the `mobile_installations` columns before and after; phone screenshots (with no visible notification).

### H — Multiple drivers, company-wide cache
- **Setup:** Appendix C spreads missions across D1, D2 and D3, including an overdue Return (M5) and a T+2 mission (M4). The phone is signed in as D1.
- **Action:** online, after S0, go fully offline. Open Dispatch with no driver selected, then select D2, D3 and back to All.
- **Expect:**
  - all drivers' active missions are present, independent of the signed-in employee;
  - overdue (M5) and T+2 (M4) are included; T+3 (M12) is not;
  - every filter change is local, with **zero** requests while online (server log);
  - the cache is sufficient offline for every driver's mission, down to T&C (open one D2 mission end-to-end through A5–A8 offline).
- **Watch (F12):** online, a named-driver switch may still send the Manual Dispatch rider or live-feed request. Record it; it is not a failure unless it delays or breaks the screen.

### I — Equipment substitution (M3; M1 for the phone side)
- **I1 — office substitution before field use:**
  1. Online, Claude or Gary switches M3's unit U3 → U3b in the staging admin.
  2. After a refresh trigger, the phone's M3 package and checklist are **for U3b**.
  3. Go offline and open M3's checklist: it is U3b's checklist. Nothing from U3 appears.
- **I2 — phone-side substitution offline:**
  1. Offline in M1's Assembly Review, switch the unit, if the category's equipment list is cached. If it isn't, the expected message is "Could not load that category's equipment. Check the connection and try again."; record which occurred.
  2. **Expect after a switch:**
    - a durable `queue_line.switch_equipment` op;
    - the line shows "<product>: this unit's checklist needs a connection. What you did is saved on this phone — connect to the internet to load the checklist for the current unit.";
    - Save/Submit is blocked for that line;
    - the **old unit's answers and media never satisfy it**.
  3. Reconnect: the switch syncs, the new cycle's context is fetched, and the checklist is completed for the new unit.
- **Server:** the old unit's execution is never completed for the new unit; media are attached to the correct cycle.
- **Watch (Phase 4 M-1):** the narrow race of a substitution before the line had an execution plus a package downloaded before the switch synced. Promote per §5.

### J — Checklist restart (M6 line 2)
1. Offline: answer part of the checklist, then **Delete / Start Over** (restart).
2. Force-quit and relaunch offline.
3. **Expect:**
   - the superseded cycle is **not** reused;
   - the line shows the needs-a-connection state for the new cycle;
   - old answers are not offered as current;
   - a durable `delivery_checklist.reset` op.
4. Reconnect: the reset syncs, a new execution is minted, and the old cycle stays superseded on the server.

### K — On My Way / Arrived
1. Offline on M7: On My Way, then force-quit and relaunch offline. **Expect:** the card and Screen 2 still show On My Way, and Arrived is available.
2. Arrived, then force-quit and relaunch offline. **Expect:** Arrived stands.
3. Reconnect.

- **Server:** `delivery_equipment_driver_status` = Arrived; exactly two `driver_checklist.update` operations (no duplicate); the stage is never downgraded by a later refresh.

### L — Partial sync (several ops; only some succeed)
1. Offline on M6 and M1: queue On My Way, a checklist prepare, a photo upload, a T&C signature and a completion (at least 5 ops).
2. Restore the network. After the first two ops show synced (server `mobile_operations`), **stop the staging server** (the tunnel stays up, so 502s come back as retryable).
3. **Expect:**
   - the synced ops stay synced;
   - the rest stay pending, with growing retry intervals (30/60/120 s in the server-log gaps);
   - nothing is rolled back;
   - nothing moves to Needs Attention.
4. Start the server. **Expect:** the rest converge once. `replay_count` may rise for a lost acknowledgment; there are no new duplicate rows.

### M — Needs Attention (one controlled terminal rejection)
1. Offline on M7: On My Way queued.
2. Claude reassigns M7 to D2 on the staging board (G4).
3. Reconnect. **Expect:**
   - `409 DISPATCH_ASSIGNMENT_CHANGED`;
   - the op is **Needs Attention** and the toast says "Saved · Needs Attention — see Settings › Sync";
   - Settings shows "1 needs attention", **not** pending;
   - the original op and its data are kept, with Discard available;
   - unrelated queued work (M1's checklist, from L or A) keeps syncing.
4. **Watch point:** after the reconcile, does M7's card still present the local On My Way stage? By Phase 3 §3.9 design, an unconfirmed local step "stands" while Needs Attention. Record exactly what the card shows, in D1's and D2's filters, and grade it per §7. It is Critical only if it creates a material business risk.
5. **Deliberate No-Answer check** (outbound blanked): set call result = No Answer once on M7 before reconnecting. The server attempts the SMS and fails safely (`sender_not_configured`). Nothing is sent.

### N — Terms freshness under the frozen-agreement model (adapted; decision D6)
Phase 5's approved rule is that **an order's agreement is frozen at order creation**: there are no terms revisions, stale signatures or re-signing after template changes (Phase 5 plan §0.1). "A can never count as B" is therefore tested on the two real paths.

- **N1 — templates change after download (M1-like order):**
  1. The phone has the order's agreement A.
  2. Gary or Claude edits the company terms and the product addendum templates in the staging admin.
  3. **Expect:**
     - the order's mission revision does **not** change (server log: no package re-download for it);
     - offline, the phone still shows A;
     - the customer signs A;
     - on reconnect the server accepts it, and `accepted_terms_content` is A, **not** the new template.
- **N2 — the server's frozen agreement diverges (M7, raw SQL, G4):**
  1. After M7's package is on the phone, Claude edits M7's `orders.customer_name` directly in `rc_kabba_staging`, bypassing the model's immutability guard, to simulate a restore or corruption. This makes the server identity B ≠ the phone's A.
  2. Offline: the customer signs A.
  3. Reconnect. **Expect:**
     - `409 TERMS_IDENTITY_MISMATCH`, and the op is **Needs Attention with its PNG kept** (A's evidence preserved);
     - a `mobile_sync_issues` row is recorded;
     - T&C shows unsigned, then after a refresh the verified B;
     - the customer signs B, and that new op is accepted with B's identity;
     - A's op stays Needs Attention until a person discards it.
  4. **A never satisfies B:** a Needs Attention `terms.sign` never counts for completion.
- **Known accepted risk this can show:** if the Delivery was completed offline on the strength of the pending A signature, the completion may be accepted while the terms are rejected. This is the accepted "local-first pending-signature satisfaction" risk (Phase 5 §13.6). It is recorded, not a blocker, unless it behaves materially differently from that description.

### O — Partial mission package (M8; decision D7)
1. **Fault injection:** Claude makes one staging-only data change that makes exactly **one** section of M8's package fail. The method is chosen at execution and **verified first** by an authenticated packages request (curl, read-only) showing `sections.<x> = "failed"` while `dispatch` and `checklist_context` are present.
2. If no data change isolates a section cleanly, the fallback is staging-only, **uncommitted** fault-injection scaffolding, and only with Gary's approval.
3. **Expect:**
   - M8's Dispatch card is present and usable;
   - M8 is **not** Delivery-ready offline: the failed section's screen shows its not-downloaded state, never a blank page;
   - other missions are unaffected;
   - each repair trigger re-requests M8 **at the same revision**.
4. Undo the fault, then fire any trigger. **Expect:** M8 repairs and becomes fully ready.
5. The "never becomes ready" variant is the watch item in §5.

### P — Mission removal or change while local work exists (M4, M9)
1. **P1:** offline on M9, capture work (answers, a photo). Online, Claude **cancels** M9's order.
2. **P2:** offline on M4, capture work. Claude **reschedules** M4 to T+5 (outside the horizon).
3. **P3:** reassign a mission with captured work to another driver (covered in M).
4. Reconnect.
5. **Expect:**
   - cancelled or out-of-horizon missions **leave active Dispatch**;
   - their captured work is **not deleted**: the ops are still in Sync Status and the files are in the container copy;
   - the work syncs, or is refused and parked as Needs Attention by the server's own rules. It is never silently dropped.
   - A reassigned mission moves to the other driver's filter and stays cached (inside the horizon).

---

## 5. Previously deferred watch items → physical triggers

These are **watched, not fixed**. Each lists what physical behavior promotes it to a defect, and the proper response.

| Item | Physical scenario | Promote to defect when… | Response |
|---|---|---|---|
| **Partial first download** (Phase 3 4th-review Minor): the fallback applies only when **no** package is presentable | On a fresh install (or new tunnel host), stop the server after the manifest and a few packages, so the signed-in driver's missions are missing | The driver sees "No results found." or an unusable list in the field with no way to recover without support, **or** recovery doesn't happen on the next trigger | Code (threshold per driver) if it blocks a morning start; otherwise wording in the cosmetic pass |
| **Permanently unbuildable mission** (Phase 3 4th-review Minor; Phase 4 M-5: same-revision repair has no backoff) | O with the fault left in place across ≥5 triggers and ≥2 wakes | The repeated re-download causes a visible slowdown, battery or network cost in §6, or the header misleads a driver into thinking everything is stale | Code (per-mission attempt count and cooldown) if §6 shows material cost; otherwise continued deferral |
| **F5** (and Phase 4 M-8: larger packages): the in-memory package cache is unbounded; a cold run decodes every package | Seed about 50 missions (decision D9), then cold-launch the app offline 3× and online 3× | A noticeable launch or Dispatch delay (a spinner past about 2 s on this device), memory warnings, or jetsam termination | Code (eviction / lazy decode) if seen; otherwise deferral |
| **F7:** "Today" uses the phone's time zone | Only meaningful if the phone's time zone differs from the company's (`America/Chicago`). Check the phone setting once | A mission shows under the wrong day for a driver in the company time zone | Continued deferral while phones are in the company's zone; code otherwise |
| **F12:** an online driver switch still sends the Manual Dispatch rider / named-driver feed request | H, online part (server log) | The request delays or breaks the screen, or offline switching makes any request | Cosmetic/perf pass unless it breaks offline behavior |
| **3rd review #4:** an A → B → A company switch inside one run can leave two reconcilers on A | Needs two companies on one phone. Staging has one company code, so it is **not exercised** unless a second staging company is approved | Any cross-company data seen, or a stuck reconcile | Continued deferral (single-company staging); code if observed |
| **3rd review #5:** a cross-company switch between the pre-request check and the URL read | Same as #4 | Same | Same |
| **Assembly Review freshness** (Phase 4 M-6): a non-mission assembly member's stage or lane change changes no revision | Appendix C M11: M1's order has a second line with no driver (not an active mission). Claude changes that line's Queue Line stage in staging; the phone refreshes | The bridged Assembly Review shows a stale stage that would lead a driver to a wrong staging or loading decision in normal use | Code (include members in the fingerprint) if it misleads; wording if it only lags |
| **Historical hosted flake** (Phase 4: one run, 1 failure in 38 s after a probe run) | P2 runs the suite 3× with result bundles kept | Any hosted failure: identify it from the bundle and reproduce it | Fix the test (a timing dependency) if reproducible; otherwise record it with the bundle |
| **Phase 4 M-1 / M-2** (substitution race; a line with no stored context falls back to legacy questions) | I | The old unit's context is served for a new unit, or legacy questions are submitted for an active mission offline | Code if seen in the normal workflow |

**Also observed during this inspection (recorded, not fixed):**
- With the wake flag on and Firebase unset, the watcher resolves the sender outside its `try`, so it would throw instead of logging its fatal line (`DispatchOfflineWakeWatcher.php:144`; plausible, not run). The preflight blocks enabling in that state. **Minor.**
- "Offline · showing the list saved at…" also appears online after a partial or failed run (known, 3rd review #6). **Cosmetic pass.**

---

## 6. Background and battery acceptance

**Goal:** show that the design still has no recurring timer polling, no GPS and no persistent Dispatch socket, and that the app sleeps between meaningful Dispatch changes. There is **no arbitrary battery-percentage threshold**. The method is comparative.

- **Observation windows:** same phone, similar conditions.
  - Battery 40–90 % and not charging.
  - Same network.
  - Low Power Mode off, Background App Refresh on.
  - No debugger or Instruments attached, except the short traces below.
  - Screen off except at the logged check-ins.

| Window | Length | Setup | Office activity |
|---|---|---|---|
| W0 comparator | 4 h | The app installed but **force-quit** and not opened. iOS doesn't launch a user-terminated app for background pushes or refresh, so it is inactive; signing out is avoided because returning would need the Login screen. | none |
| W1 idle | 4 h | Signed in, backgrounded, 0 pending ops, fully current cache | **none** |
| W2 working day (simulated) | 8 h, or two 4 h blocks with a quick tunnel (D4) | Signed in, backgrounded; Gary opens the app about 6 times as a driver would | about 6 office changes spread through the day, including one burst of 3 within 60 s |

- **Captured per window:**
  - **Silent wakes observed:** the watcher's sends (`mobile_installations.last_woken_at` history from the run record) versus phone manifest GETs within 60 s of a send.
  - **Foreground-triggered refreshes:** manifest GETs within 5 s of a logged foreground.
  - **Package downloads:** packages POSTs and which mission keys each requested.
  - **Network requests while idle:** every request in the staging log with no preceding wake, foreground, open or pending-op cause.
  - **Whether the app stays active unexpectedly:** requests that continue more than 30 s after a wake, or repeating at a regular interval.
  - **iOS battery data:** Settings › Battery (Last 24 Hours): Rent n King's screen-on and **background** minutes, the overall battery delta, and screen-on time (screenshot at start and end).
  - **Short Xcode Instruments traces,** only in addition: one wake-handling trace and one foreground trace (Activity Monitor + Network templates) to confirm the handler ends. Not used for the idle windows.
- **Expected:**
  - **W1:** zero Dispatch requests and zero Sync Engine requests. The Sync Engine's retry and background refresh exist only while work is pending, and W1 has none. Background minutes are near the W0 comparator.
  - **W2:** per burst, at most one wake per 1200 s, each followed by one manifest GET and packages only for the changed missions. Each foreground makes at most one manifest GET, skipped within 20 s of a current run. Nothing else.
- **Suspicious, investigated under §7:**
  - repeated idle network activity with no Dispatch change;
  - a periodic request pattern uncorrelated with changes or foregrounds, which suggests a timer;
  - package downloads at an unchanged revision (other than the documented failing-section case in §5);
  - background activity continuing after the wake deadline, or runaway background minutes;
  - persistently high Kabba energy or background minutes while idle, relative to W0 and W1;
  - any location or socket use.
- **Grading:** a material battery or network problem is **Important** (§7). One unexplained request with a plausible trigger is recorded and watched.

---

## 7. Severity and fix policy

### 7.1 Definitions

- **Critical:**
  - field work can be lost;
  - the wrong customer's or order's data can be committed during ordinary use;
  - a financial or contractual completion is duplicated;
  - the workflow claims a server-confirmed state that never occurred, in a way that creates material business risk;
  - the app cannot complete the principal field workflow.
- **Important:**
  - a common offline workflow can't be completed reliably;
  - stale equipment, cycle or terms data can satisfy the wrong requirement;
  - reconnection routinely fails to converge without intervention;
  - force-quit or reboot loses or corrupts legitimate field state;
  - background behavior creates material battery or network problems.
- **Minor:**
  - an uncommon, recoverable issue with a practical workaround;
  - misleading but non-dangerous wording;
  - a one-off refresh inconvenience;
  - cosmetic or low-probability behavior that doesn't lose field work.
- **Nit:** a cleanup, test, documentation or code-quality issue with no meaningful employee or customer effect.
- **Not Important by itself:** a finding is not Important merely because a theoretical edge case exists. It is graded on observed or realistically reachable behavior.

### 7.2 What happens on a finding

- **Critical or Important:**
  1. Stop the physical run at that scenario.
  2. Capture the evidence.
  3. Find the root cause.
  4. **Report to Gary** with the smallest proposed repair (decision D8: stop-and-report is the default, matching Gary's standing rule).
  5. Once approved: TDD (failing test first, shown red), the minimum fix, the focused and regression suites, a fresh independent review, the affected automated preflight gates, then **rerun the affected physical scenario and any scenario that depends on it** on the new build.
- **Minor or Nit:** recorded in the run record (§10) for the later cosmetic pass. Not fixed unless it prevents the acceptance program from completing.
- **Never:** speculative cleanup batched into a physical-test fix, or one fix covering two findings.
- **Accepted and deferred items** are not reopened automatically:
  - the cross-customer Sync Engine queue;
  - the Phase 5 very-large-font / noisy-signature Minor;
  - the crafted-PNG re-encoding size Minor;
  - the remaining Phase 5 Nits;
  - historical signed-record cleanup;
  - the production terms audit.

  They are reopened only if physical testing shows a materially different real-world problem.

---

## 8. Release-candidate exit criteria

Phase 6 is complete when **all** of these hold on the named final heads:

1. A — Golden Delivery passes on the physical iPhone.
2. B — Golden Return passes on the physical iPhone.
3. C — Force-quit survival passes at all five points.
4. D — Reboot survival passes.
5. E and A12 — Offline capture and restored-network convergence pass (automatic, no manual sync).
6. A8–A9 and N — The signature and T&C offline path passes. A can never count as B.
7. I and J — Substitution and restart identity isolation pass.
8. F — A missed silent push repairs through every ordinary trigger.
9. G — An actual silent wake is observed to the extent iOS permits. If G2 was declined, this is recorded as "not tested: environment", and Gary decides whether that blocks release.
10. P8 plus §6 — No recurring polling, GPS or persistent Dispatch socket.
11. §6 — The battery and background observation finds no material abnormal behavior.
12. No open Critical or Important Phase 6 defect.
13. §3 — The automated gates rerun clean at the final heads.
14. G3 cleanup is done: the app is deleted from the phone and staging rolled back or kept as Gary decides; the G2 key is revoked if one was created.

**Phase 6 completion does not authorize** a production merge or deploy, enabling the production wake flag, an App Store upload, or minimum-version enforcement. Those remain separate, explicit decisions for Gary after the physical and cosmetic passes.

---

## 9. Decisions for Gary (before execution)

| # | Decision | Recommendation |
|---|---|---|
| **D1** | Approve **G1**: stand up local non-production staging at the Phase 6 heads (§2) | Yes. It is the only environment that needs no deployment. |
| **D2** | **G2** real silent push: **(a)** a new dedicated FCM key for `rentnking-4049b` (revoked afterwards), plus confirming an APNs Auth Key in Firebase; or **(b)** defer scenario G | (a) if you are comfortable creating the key; otherwise (b), with criterion 9 recorded as environment-limited |
| **D3** | Approve **G3**: the Debug build on "Rent n King" for the Phase 6 window, the phone not used for production Rent n King, and the app deleted at the end | Yes |
| **D4** | Tunnel: quick tunnel, or a named tunnel with a stable hostname | Quick tunnel for scenarios A–P. Named tunnel only if you want W2 as one unbroken 8 h window. |
| **D5** | Approve **G4**: staging-only controlled edits (reassign, office completion, raw-SQL agreement edit, cancel or reschedule, section fault) | Yes |
| **D6** | Accept scenario **N adapted** to the frozen-agreement model: N1 template edits, N2 identity divergence | Yes. The "revision A → B" wording in the brief conflicts with Phase 5's approved frozen model. |
| **D7** | Scenario O fault injection: a data edit first; staging-only **uncommitted** scaffolding only if needed, with your approval at that time | Yes |
| **D8** | Fix protocol for Critical/Important: stop and report, then fix on approval; or fix immediately | Stop and report (your standing rule) |
| **D9** | Seed volume for the F5 / load watch: about how many active missions does one company have across overdue + today + 2 days? | 50 unless you give a real number |
| **D10** | Does "Rent n King" have an active cellular plan? E's cellular legs need one. | Tell me; otherwise E1, E2 and E5 are recorded as not testable |
| **D11** | Who performs office actions: you in the staging admin web, or Claude by scripted staging changes | Claude scripts the deterministic changes; you do 2–3 real admin edits (A1, I1, N1) for realism |
| **D12** | The evidence folder `~/Documents/kabba-dispatch-offline-p6-evidence/` outside the repos; the run record summarized in this plan | Yes |

**Separate security note (not Phase 6 scope), N1:** the Debug Login screen pre-fills credential literals that are committed in source (`LoginViewController.swift:98-109`, pre-existing). If they are live credentials, rotate them and remove the literals, as a separate decision.

---

## 10. Execution order, first scenario and record

- **Order:**
  1. Approvals.
  2. P0–P8.
  3. G1 → P9.
  4. G3 → P10 → S0.
  5. **A** (first).
  6. B, C, D, K, J, I, L, M, N, O, P, H, E, F.
  7. G (if G2).
  8. §5 watch runs.
  9. §6 windows (W0 → W1 → W2).
  10. Final automated gates.
  11. Cleanup.
- **Recommended first physical scenario: A, the Golden never-opened Delivery,** right after the S0 smoke. It exercises every phase together (1–5). If it fails, the later scenarios would mostly be measuring the same defect.
- **Run record:** appended here as §11 (execution record) and §12 (review record), as in Phases 3–5. Each run records:
  - the scenario;
  - the exact build commits;
  - the tunnel host;
  - pass or fail with the evidence folder;
  - the findings and their grades;
  - any staging edit and its undo.

---

## Appendix A — Baseline-known backend failures (compared by name)

`docs/dispatch-offline-phase-6/baseline-known-failures.txt` holds the 34 names: Orders 23 of 665, CustomerChecklists 11 of 53. They were identical by name at every Phase 2–5 verification.
- They are pre-existing: extension-payment, refund-idempotency and schedule-validation tests in Orders, and checklist transaction and logging tests in CustomerChecklists.
- They are unrelated to Dispatch offline.

## Appendix B — Staging evidence queries (Claude runs these at checkpoints)

Local Mac terminal — read-only (staging database only)
```
mysql rc_kabba_staging -e "
  SELECT operation_type, status, COUNT(*) n, SUM(replay_count) replays, MIN(created_at), MAX(completed_at)
    FROM mobile_operations WHERE created_at >= '<run start>' GROUP BY operation_type, status;
  SELECT operation_id, COUNT(*) FROM mobile_operations WHERE created_at >= '<run start>' GROUP BY operation_id HAVING COUNT(*) > 1;
  SELECT op.unique_id, op.delivery_status, op.pickup_status, op.delivery_equipment_driver_status, op.pickup_equipment_driver_status,
         op.delivery_checklist_status, op.pickup_checklist_status, op.delivery_tnc_status
    FROM order_products op WHERE op.unique_id IN (<scenario lines>);
  SELECT order_product_id, leg, status, COUNT(*) FROM order_product_checklist_executions
    WHERE order_product_id IN (<scenario line ids>) GROUP BY order_product_id, leg, status;
  SELECT order_product_id, COUNT(*) files, COUNT(DISTINCT client_media_id) distinct_ids FROM order_media
    WHERE order_product_id IN (<scenario line ids>) GROUP BY order_product_id;
  SELECT unique_id, terms_status, terms_accepted_at, terms_customer_signed_at, signature_image IS NOT NULL signed, LENGTH(accepted_terms_content) record_len
    FROM orders WHERE unique_id IN (<scenario orders>);
  SELECT * FROM mobile_sync_issues WHERE created_at >= '<run start>';
  SELECT installation_id, app_build, last_seen_at, last_woken_revision, last_woken_at, next_attempt_at, failed_attempts, retired_at FROM mobile_installations;
  SELECT settled_revision, pending_revision, last_tick_at, last_result FROM dispatch_offline_wake_states;"
```
Column names were checked against `rc_kabba_staging` on 2026-09-26. The Phase 2 and Phase 5 tables and columns exist only after the G1 migration.

## Appendix C — Phase 6 staging dataset (seeded under G1; the script is written at execution)

- **Customers:** fake only. "P6 Test Customer n", phone `555-01nn`, `p6-n@staging.local`, fake addresses. The order `unique_id`s are freshly generated, never cloned.
- **Users:**
  - D1 = the signed-in staging driver `driver@staging.local`;
  - D2 and D3 = additional active drivers;
  - one staging admin for the admin web.
- **Missions:** T = the test day; all in the Truck transport mode.

| Mission | Leg · driver · date | Purpose |
|---|---|---|
| M1 | Delivery · D1 · T · unit U1 · required yes/no + photo + signature · terms **Pending** with a frozen agreement (global terms + one product addendum with one `[customer_approval]`) · Assembly Review | A, N1, I2, L |
| M2 | Return · D1 · T · unit U2 on rent · return checklist (fuel, damage question, photo) | B |
| M3 | Delivery · D2 · T+1 · unit U3; spare U3b in the same category | C, D, H, I1 |
| M4 | Delivery · D3 · T+2 · unit U4 | H (horizon edge), F, G, P2 (reschedule to T+5) |
| M5 | Return · D2 · T−1 (overdue, still open) · unit U5 | H (overdue) |
| M6 | Delivery · D1 · T · **two lines** (U6a, U6b) · terms Pending | C, E, J, L, multi-line identity |
| M7 | Delivery · D1 · T · unit U7 · terms Pending | K, M, N2 |
| M8 | Delivery · D2 · T · unit U8 | O and the unbuildable watch item |
| M9 | Delivery · D3 · T+1 · unit U9 | P1 (cancel with unsynced work) |
| M10 | Delivery · D1 · T · terms **Exempt** | "T&C not required" path (sanity) |
| M11 | A second line on M1's order with **no driver** (not an active mission) | The Assembly Review freshness watch (M-6) |
| M12 | Delivery · D3 · T+3 | H: outside the horizon, so it must **not** be cached |
| Volume | About 40 more synthetic missions across D1–D3 in the horizon (D9) | F5 / load watch |

- **Resets:** per mission, return the lines to Pending, delete that run's executions, media, operations and terms acceptance for those ids (recorded SQL), and restore any edited field. **Or** restore the G1 dump and reseed for a full reset.

## Appendix D — Device evidence commands

- **Container copy:** P10.
- **Install:** Claude uses Xcode or `xcrun devicectl device install app` with the P3b build.
- **Launch once with the harness:** `xcrun devicectl device process launch --device 93D4CE68-DFAF-5D00-829C-9D204CFEAD35 com.RentnKingNew.app -KabbaBaseURL https://<tunnel host>/api/admin/v1/ -KabbaCompanyCode KABBA -KabbaEmail driver@staging.local -KabbaPassword <staging password>`. Later launches are from the Home screen.
- **Lock probe:** before any automated step, `xcrun devicectl device process launch` answers "Locked" or "Launched".
- **Screenshots:** on the phone (side button + volume up), AirDropped to the evidence folder.
