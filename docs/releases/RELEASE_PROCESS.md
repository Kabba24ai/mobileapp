# iOS release process

This process keeps one set of release notes per version. It also makes every build traceable to the commit it was built from.

## One release-note draft per version

The draft is the version's entry in `AppReleaseCatalog.history`, in `RentnKing/Sync/Core/AppReleaseCatalog.swift`.
- **On the phone:** Settings → About shows that entry for the installed version.
- **On the App Store:** the "What's New in This Version" text is rendered from the same entry:

```
Scripts/whats-new.sh 1.0.29 > whats-new-1.0.29.txt
```

Write each line for a customer-facing reader. The same words appear on every phone, so don't keep a separate, shorter App Store version.

**App Store Connect is not connected to the repository.** Its text is pasted by hand. Nothing here publishes or synchronizes it. If the App Store text is edited in App Store Connect, edit the catalog entry to match.

## Steps for a release
1. **Write the notes.** Add or update the catalog entry for the new version. A test fails when the project's version has no entry (`AppReleaseCatalogTests`).
2. **Set the version.** Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in all four app and extension configurations.
   - The build must be higher than every build in `HISTORY.md`.
   - The version must not be one App Store Connect has already closed.
3. **Commit.** Builds are made only from a clean, committed tree.
4. **Run the preflight.** `Scripts/release-preflight.sh <version> <build>` checks:
   - the tree is clean;
   - the app and extension versions agree;
   - the build is higher than every earlier build;
   - the version is still open;
   - the notes exist.

   It then prints the HISTORY row and the What's New text.
5. **Archive.** Name the commit explicitly; the build phase stamps it into `KabbaBuildInfo.plist`:
   ```
   KABBA_SOURCE_REVISION=$(git rev-parse --short=12 HEAD) KABBA_SOURCE_STATE=clean \
     xcodebuild archive -project RentnKing.xcodeproj -scheme RentnKing -configuration Release …
   ```
6. **Export, upload and check.** In App Store Connect, paste the printed What's New text and pick the build.
   - Submission is done only with Gary's approval.
7. **Record it.** Add the row to `HISTORY.md` with the source commit. Update its status when Apple approves or releases it.

## Checking a phone
In Settings → About, tap **Version**. The build details show:
- version and build;
- source commit, plus "+ uncommitted changes" when built from a modified tree;
- configuration;
- how the copy was installed: App Store, TestFlight, "Installed from a computer" or Simulator;
- the UTC build time.

Tap the details to copy them for support.
