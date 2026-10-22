# Release history: KABBA.AI (RentnKing) iOS

One row per build uploaded to App Store Connect. `Scripts/release-preflight.sh` reads this table: a new build must be higher than every build here, and a version marked Released or Approved is closed to new builds.

**Source commit** is the commit the archive was built from. A binary from MOBILE-QUALITY-01 onwards also carries it: in Settings → About, tap the version to see it.

| Version | Build | Source commit | Branch | Uploaded | App Store status |
|---|---|---|---|---|---|
| 1.0.24 | 1010 | 92fbd1e | main | 2026-10-06 | Released |
| 1.0.25 | 1011 | ec5e410 | fix/independent-checklist-combine-release-2026-10-06 | 2026-10-07 | Released |
| 1.0.26 | 1012 | 6e5e1ec | fix/fuel-def-readings-1.0.26 | 2026-10-15 | Approved |
| 1.0.26 | 1013 | 47d24e9 | fix/fuel-def-readings-1.0.26 | 2026-10-18 | Rejected by App Store Connect: version 1.0.26 already closed (90062/90186) |
| 1.0.27 | 1013 | 44927ea635b8 | fix/fuel-def-readings-1.0.26 | 2026-10-18 | Released (approved; on every company phone, per Gary 2026-10-21) |
| 1.0.28 | 1014 | 375115102806 | release/1.0.28-1014 | 2026-10-21 | Uploaded; superseded by 1015, not to be submitted |
| 1.0.28 | 1015 | f2516522db0a | release/1.0.28-combined | 2026-10-21 | Uploaded 20:36 CDT (combined release); submit for review in App Store Connect |

**1.0.28 is ONE combined release** (owner decision 2026-10-21): build 1015 from `release/1.0.28-combined` carries the route events of 1014 plus every MOBILE-QUALITY-01 improvement (prepared as 1.0.29, which was never uploaded). When Apple approves 1.0.28, change its status to Approved (the preflight then treats 1.0.28 as closed); the next build is then **1016 or higher** under a higher version.

## Notes
- **Copies installed from a computer.** A copy installed with Xcode shows the in-app release notes of the code it was built from. Before 1.0.28, those notes could differ from the shorter text pasted into App Store Connect. From 1.0.28, both come from one draft (see `RELEASE_PROCESS.md`).
- **Settings → About shows how the copy was installed:** App Store, TestFlight, "Installed from a computer" or Simulator.
