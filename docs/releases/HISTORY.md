# Release history: KABBA.AI (RentnKing) iOS

One row per build uploaded to App Store Connect. `Scripts/release-preflight.sh` reads this table: a new build must be higher than every build here, and a version marked Released or Approved is closed to new builds.

**Source commit** is the commit the archive was built from. A binary from MOBILE-QUALITY-01 onwards also carries it: in Settings → About, tap the version to see it.

| Version | Build | Source commit | Branch | Uploaded | App Store status |
|---|---|---|---|---|---|
| 1.0.24 | 1010 | 92fbd1e | main | 2026-10-06 | Released |
| 1.0.25 | 1011 | ec5e410 | fix/independent-checklist-combine-release-2026-10-06 | 2026-10-07 | Released |
| 1.0.26 | 1012 | 6e5e1ec | fix/fuel-def-readings-1.0.26 | 2026-10-15 | Approved |
| 1.0.26 | 1013 | 47d24e9 | fix/fuel-def-readings-1.0.26 | 2026-10-18 | Rejected by App Store Connect: version 1.0.26 already closed (90062/90186) |
| 1.0.27 | 1013 | 44927ea635b8 | fix/fuel-def-readings-1.0.26 | 2026-10-18 | Released (current App Store version, per the MOBILE-QUALITY-01 work order) |

The next build must be **1014 or higher**, under a version above 1.0.27. The route-events release is planned as 1.0.28 (1014).

## Notes
- **Copies installed from a computer.** A copy installed with Xcode shows the in-app release notes of the code it was built from. Before 1.0.28, those notes could differ from the shorter text pasted into App Store Connect. From 1.0.28, both come from one draft (see `RELEASE_PROCESS.md`).
- **Settings → About shows how the copy was installed:** App Store, TestFlight, "Installed from a computer" or Simulator.
