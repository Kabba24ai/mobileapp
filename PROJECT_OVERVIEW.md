# RentnKing / KABBA.AI — iOS Project Overview

> Operational iOS app for an equipment-rental business. Field staff and drivers use it to
> stage equipment, run delivery/return checklists, dispatch drivers, manage schedules, and
> track equipment — backed by a multi-tenant REST API.

- **Bundle ID:** `com.RentnKingNew.app` (Share extension: `com.RentnKingNew.app.RentnKinExtension`)
- **Marketing version:** `1.0.13` · **Build:** `1000`
- **Min iOS:** 15.6 · **Language:** Swift (UIKit, mostly programmatic + storyboards) · **~179 Swift files**
- **Dependency manager:** Swift Package Manager (SPM)

---

## 1. Tech Stack

| Area | Choice |
|------|--------|
| UI | UIKit — mix of storyboards (`Schedule.storyboard`, `Main`) and programmatic views |
| Architecture | MVC with `Mappable` models (ObjectMapper) and file/helper service layers |
| Networking | Custom `WebServiceHelper` over Alamofire (multipart uploads) |
| Persistence | `UserDefaults`/MMKV wrapper (`SDKUserDefault`), CoreData (upload tracking), Keychain (auth token) |
| Push | Firebase Cloud Messaging (APNs) |
| Analytics/Diagnostics | Firebase Analytics + Crashlytics |
| Images | Nuke |
| Misc UI | IQKeyboardManager, KRProgressHUD, KRActivityIndicatorView, ActionSheetPicker, FontAwesome, RHPlaceholder (shimmer) |

---

## 2. Requirements & Build

- **Xcode** with the iOS 15.6+ SDK, signing team `A9U32VVCRV` (automatic signing).
- Open **`RentnKing.xcodeproj`** (SPM resolves on first build — no CocoaPods).
- `GoogleService-Info.plist` lives at `RentnKing/Core/Google File/`.

```bash
# Simulator build from CLI
xcodebuild -project RentnKing.xcodeproj -scheme RentnKing \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

> If a build fails with stale precompiled-module errors (`.pcm not found`) or `lipo: No space
> left on device`, clear `~/Library/Developer/Xcode/DerivedData/<project>/Build/Intermediates.noindex`
> and `ModuleCache.noindex` (keep `SourcePackages`), or free disk space, then rebuild.

---

## 3. Configuration & Environments (multi-tenant)

The API base URL is **not hardcoded** — it is resolved at runtime and stored in
`UserDefaults.standard.baseURL`:

1. A fixed bootstrap call `POST https://api.rentnking.com/api/admin/v1/clients` (with a client
   **`code`**) returns the tenant's `api_url`.
2. `api_url` is saved as the base URL; `login` then runs against it and returns the auth
   `token`, which is stored in the **Keychain**.
3. On launch, `SplashViewController` routes to Home only if `user`, `accessToken`, and a
   non-empty `baseURL` all exist — otherwise to the login flow.

- URLs are built by the `Url` enum via `newAPI(path)` → `makeURL(baseURL:path:)`
  (`GlobalMain.swift`), which is crash-safe (falls back to `about:blank` on a malformed URL).
- Constants live in `Core/Other Views/Helper/Metadata.swift` (`Application`), e.g.
  `BaseURL`, `imgURL` / `imgURLDEV`, `TermsURL`.

---

## 4. Module Map

```
RentnKing/
├─ AppDelegate.swift            App lifecycle, push, offline-queue drains (checklist/media)
├─ NotificaiotnFile.swift       Firebase configure + FCM/APNs registration
├─ EventCalender.swift          EventKit (add schedule events to calendar)
├─ Modules/
│  ├─ SPLASH MODEL/
│  │  ├─ Splash/                Launch routing
│  │  └─ Login Screen/          Client-code bootstrap, login, signup
│  └─ TABBAR/
│     ├─ Home Model/
│     │  ├─ Order Model/        Order details + Check List (delivery/return) ← core flow
│     │  ├─ Queue Line Model/   Staging (Pending / Staged / Completed), Change Equipment
│     │  ├─ Dispatch Model/     Dispatch list + Driver Checklist
│     │  ├─ Schedule Model/     Delivery/return schedules
│     │  ├─ Place Order Model/  Product list, categories, payment/terms
│     │  ├─ CRM / Time Clock /  Ancillary modules
│     │  └─ Setting Model/      Settings, release notes (AppReleaseModel)
│     └─ Equipment Model/       Machine profile + rental-ready checklist
└─ Core/
   ├─ Other Views/Helper/WebserviceHepler/   WebServiceHelper (networking core)
   ├─ FileData Helper/          Offline queues + sync (checklist, driver, delivery/pickup, equipment)
   ├─ CoreData/                 Upload tracking (UploadData) + MediaCleanupManager
   ├─ Keychain/                 Vendored KeychainAccess
   ├─ Frameworks/               RHPlaceholder (shimmer), SpreadsheetView, loaders
   └─ Other Views/Extension/    UIKit + Foundation extensions, UserDefaults wrapper
```

---

## 5. Key Subsystems

### Networking — `WebServiceHelper`
- Configurable per call: `methodType`, `strURL`, `dictType` (params), `dictHeader`,
  `serviceWithAlert`, `indicatorShowOrHide`.
- Two completion styles: delegate (`appDataDidSuccess` / `appDataDidFail`) and closure
  (`callAPIwithCompletation`).
- Multipart uploads via `startUploadingMultipleImages()` (Alamofire `AF.upload`), used for
  checklist submissions with signature images.
- Success is `getStringForID(key:"success") == "1"`.

### Offline queues (resilience)
The app is offline-tolerant. Completed work is persisted locally and drained when online:
- **Checklist queue** — `Core/FileData Helper/CheckListFile.swift` (`kSaveCheckList`).
  `appendChecklistData` → `saveArrayWithImages` (signatures stored base64) →
  `AppDelegate.updateCheckListData()` drains `arr[0]` one-by-one; keeps items on failure and
  dead-letters after `kMaxSyncAttempts`.
- **Driver checklist**, **delivery/pickup inputs**, **equipment** — parallel sync helpers in
  `Core/FileData Helper/` with remove-on-success + attempt caps.
- Retries are triggered on app launch, network-restore, and after each successful drain.

### Media upload & cleanup
- Photos/videos/license images upload via a background `URLSession` (`BackgroundUploader`),
  tracked in CoreData (`UploadData`), keyed by `order_unique_id`.
- Directories: `ImageVideo/<orderID>/`, `LicenseUpload/<orderID>_front.png` / `_back.png`.
- `MediaCleanupManager.purgeMedia(forOrder:)` reclaims an order's local media **only** after
  both delivery and return are complete and everything has uploaded (guards against deleting
  anything still pending). Triggered on the Return-checklist save success.

### Auth & security
- Bearer token stored in ONE shared **Keychain** item (`KabbaSessionKeychain` → `SharedKeychainCredentialStore`,
  service `com.rentnking.auth.shared`, access group = the app group `group.com.RentnKingNew.shared`,
  `afterFirstUnlockThisDeviceOnly`) that the share extension reads too. The store clears every
  existing copy with an access-group-less delete BEFORE the shared write — an unqualified
  `SecItemDelete` spans every access group the process can reach, so run after the write it erased
  the token (Phase 6A device blocker). Falls back to the app-private group where the app group is not
  usable as a keychain group. `KabbaSessionKeychain.shared.selfTest()` runs at launch in DEBUG builds
  and prints a sanitized OSStatus trace (`[keychain] …`). Never logs the token.
- Token read from the `token` key on login; sent as `Authorization: Bearer <token>`.

### Release notes
- `Modules/TABBAR/Home Model/Setting Model/AppReleaseModel.swift` holds the in-app changelog
  shown in Settings. Version/build come from the bundle; entries are added newest-first.

---

## 6. Dependencies (SPM)

| Package | Version | Purpose |
|---------|---------|---------|
| Alamofire | 5.12.0 | HTTP / multipart uploads |
| firebase-ios-sdk | 10.29.0 | Messaging (FCM), **Analytics**, **Crashlytics** |
| ObjectMapper | 4.4.3 | JSON ↔ model mapping (`Mappable`) |
| Nuke | 12.9.0 | Image loading/caching |
| MMKV | 2.3.0 | Fast key-value storage |
| IQKeyboardManager(Swift) | 7.2.0 | Keyboard avoidance |
| KRProgressHUD / KRActivityIndicatorView | 3.4.8 / 3.0.8 | HUD / spinners |
| ActionSheetPicker-3.0 | — | Pickers |
| FontAwesome.swift | 1.9.1 | Icon font |

(Plus Firebase's transitive deps: GoogleAppMeasurement, GoogleUtilities, gRPC, nanopb,
swift-protobuf, promises, leveldb, abseil, etc.)

---

## 7. Permissions & Capabilities

**Usage descriptions** (set via `INFOPLIST_KEY_*` build settings, merged because
`GENERATE_INFOPLIST_FILE = YES`):
- Camera — license capture + equipment delivery/return photos & video.
- Photo Library — pick license photo.
- Microphone — audio while recording equipment video.
- Calendar — add schedule events (EventKit).

**Entitlements / capabilities:**
- Push notifications (`aps-environment`), App Group `group.com.RentnKingNew.shared` (shared
  with the Share extension), Keychain.
- Background modes: `remote-notification`, `fetch`.

**Not used:** Location permission (only `CLGeocoder`/`MKMapItem` for directions — no
`CLLocationManager`), Contacts, Bluetooth, HealthKit, IDFA/ATT, In-App Purchase.

---

## 8. App Store / Release Notes

A full release-readiness audit lives in **`APP_AUDIT_REPORT.md`**. Highlights to address
before submission:
- Add an app-level **`PrivacyInfo.xcprivacy`** (Required Reason APIs: UserDefaults, file
  timestamp) and complete App Privacy labels for Firebase Analytics/Crashlytics.
- Add **`NSCalendarsFullAccessUsageDescription`** (iOS 17+ calls `requestFullAccessToEvents`).
- Reconsider the blanket **ATS** exception (`NSAllowsArbitraryLoads`) — all endpoints are HTTPS.
- Set `aps-environment` to `production` for release.
- Provide Apple a **demo account + client code** (two-step tenant login).
- Bump `CFBundleShortVersionString` / `CFBundleVersion` to match the intended submission.

---

## 9. Known Follow-ups

- Rotate API tokens server-side (hardcoded tokens were removed from the client).
- The `RentnKinExtension` Share extension is an unmodified Xcode template (placeholder
  `yourdomain.com`, macOS keys) — finish or remove it.
- ~239 `print()` statements — consider gating behind `#if DEBUG`.
- Verify the checklist submit UX doesn't mask a silent enqueue/upload failure (the submit
  screen pops on a fixed timer regardless of send result).

---

*This document summarizes the project structure and conventions for onboarding and maintenance.
For the change history shown in-app, see `AppReleaseModel.swift`; for the App Store audit, see
`APP_AUDIT_REPORT.md`.*
