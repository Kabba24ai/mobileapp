Claude Code mission: Kabba checklist Combine fix and Apple release preparation

Run this task in Claude Code in VS Code on Gary's Mac. Carry out the work, rather than only explaining commands. Follow this repository's AGENTS.md and CLAUDE.md instructions. Preserve existing local work. Report real blockers with the exact failing command and evidence.

SOURCE AND AUTHORIZATION

Repository: https://github.com/Kabba24ai/mobileapp
Patch carrier branch: review/checklist-batch-isolation-2026-10-06
Patch path: release-review/checklist-batch-isolation.patch
Patch upload commit: a89030ee7bd0c4f288f485dac2be6873d7aa7998
Patch base: 92fbd1e64158842535fd257938553fe97d6e9680

The remote review branch contains a patch, not an implemented app change. Fetch and apply the patch in a separate implementation worktree before testing or building. Do not merge the patch carrier branch as though it implements the fix.

The user authorized downloading and applying this fix, reviewing it in Xcode, and preparing an Apple release. Prepare and validate the archive and release handoff. Actual upload to Apple, submission for App Review, replacing a pending submission, and changing live release settings are outside this preparation task. Complete all preparation before requesting any further release action.

1. LOCATE THE CHECKOUT AND APPLY THE PATCH

An expected checkout location is /Users/garyjezorski/Documents/mobileapp-canonical, containing RentnKing.xcodeproj. Verify it exists; locate the actual checkout if needed. Check git status, current branch, remotes, and repository instructions. Verify the origin repository is Kabba24ai/mobileapp before fetching or pushing. Do not discard, reset, or overwrite unrelated local work.

Fetch origin/main and review/checklist-batch-isolation-2026-10-06. Create a new worktree and implementation branch from current origin/main, using an available name such as fix/independent-checklist-combine-release-2026-10-06. Record the base SHA and worktree path.

Retrieve the patch from its immutable upload commit; for example, once that commit is fetched:

  git show a89030ee7bd0c4f288f485dac2be6873d7aa7998:release-review/checklist-batch-isolation.patch > /tmp/kabba-checklist-batch-isolation.patch

In the implementation worktree, run:

  git apply --check /tmp/kabba-checklist-batch-isolation.patch
  git apply /tmp/kabba-checklist-batch-isolation.patch
  git diff --check

If main has advanced and the patch conflicts, review intervening changes and resolve only the relevant conflicts. Do not force an old main over newer work. Confirm that all nine patch files are applied, including project test registration, hosted tests, the portable test script, and docs/checklist-batch-isolation.md. Read that document and review the complete code diff.

2. REVIEW THE BEHAVIOR AND FIX ANY VERIFIED PROBLEMS

The contract is independent processing per order-product, delivery/return leg, and rental cycle. Combine shares only employee, signature, and return-store convenience fields onto rows that actually participate. It must not couple checklist completion, photos, charges, execution IDs, or another rental cycle. The backend contract stays unchanged, and behavior is the same for all tenants aside from existing branding/domain differences.

Review Preview, Submit, Save, background progress, offline scope, Cancel/Back, and restored drafts. Pay particular attention to:

- Untouched rows are ignored in both Combine modes, including operational defaults and common convenience values alone. Zero participating rows must produce no operation.
- Partially entered rows remain visible and must validate, including a partial row without an assigned unit. Validation must identify the correct original row after blanks are removed.
- Shared convenience fields are copied onto participating rows without mutating the source draft. Preview cancellation must preserve original row data.
- Individual mode signs the selected equipment only. Every submitted row needs a real signature image or valid saved signature URL. An empty UIImage must not count as signed.
- Save and background progress use the same participation policy and common-field copies as Preview/Submit.
- Partial submission removes only submitted drafts. Sibling drafts, shared values, and mode survive restoration, even when one row remains and the Combine toggle is hidden.
- Completed cache merges only actually submitted rows with prior completed rows. It must never seed completion from untouched or partially entered source rows.
- Completion checks respect the canonical current leg/cycle context, rather than movement-status defaults. Restart or reassignment clears explicit-input flags correctly.

If review or compilation finds a genuine defect, fix it within this scope and add a meaningful regression check where needed. Do not refactor unrelated systems or change dependencies just to clear unrelated failures.

3. RUN REAL XCODE VALIDATION

The patch was checked with Swift syntax parsing and 23 portable policy assertions on Linux. This is not an iOS build or hosted XCTest run. Full swift test could not compile on Linux because CryptoKit was unavailable. Do not reuse those checks as evidence of an Xcode pass.

Inspect xcodebuild -version, the active developer directory, schemes, and destinations. Use the project's pinned SwiftPM resolution; do not update package versions without a demonstrated need. There is a project SwiftPM Package.resolved. Discover actual simulator destinations rather than assuming a particular model or OS.

Shared schemes include RentnKing, RentnKingHostedTests, KabbaSyncCoreTests, RentnKingUITests, and RentnKinExtension. Confirm these in the checkout with xcodebuild -list -project RentnKing.xcodeproj.

Run the portable script with the Mac Swift executable:

  python3 Scripts/test-checklist-batch-policy.py "$(xcrun --find swift)"

Run Scripts/test-sync-core.sh using its repository instructions. Run the full RentnKingHostedTests scheme on an available iOS simulator, including ChecklistBatchIsolationHostedTests and DispatchOfflineFieldBridgeHostedTests. Use xcodebuild test with -project RentnKing.xcodeproj, the actual destination ID, and a unique -resultBundlePath. Preserve .xcresult output and the command exit status; do not mask failures with logging pipes. Run the affected UI flows in RentnKingUITests, including applicable preparation and driver-delivery coverage. Build the RentnKing app and extension. Investigate every relevant compile/test failure; distinguish unrelated baseline failures with evidence from the base revision.

Smoke-test using safe test orders with three equipment rows, for both Delivery and Return and Combine ON and OFF:

- Complete one, two, and all three rows; also complete only the third row.
- Leave all rows untouched, including prefilled defaults and shared fields alone.
- Leave a partial sibling, including one with no unit; confirm it blocks submission and focuses the correct row.
- Verify shared employee/store/signature apply only to participating rows. Individual signatures must remain independent.
- Preview and cancel, save, background the app, relaunch, and restore drafts.
- Submit A first, restore B/C, then submit B; confirm completion cache and unsubmitted drafts remain correct. Verify shared mode restoration with the last remaining row.
- Verify delivery cannot complete return, and a prior cycle cannot complete the next cycle. Exercise existing restart/substitution behavior.
- Confirm photos/media and charges remain attached to the correct equipment and no untouched sibling sends a progress/completion operation.

Record simulator/device coverage honestly. If hardware or credentials prevent a required check, identify the exact check still outstanding. Do not modify real customer orders to perform these tests.

4. PREPARE THE APPLE RELEASE

Expected App Store Connect identity: Kabba, app ID 6751110122, team A9U32VVCRV, bundle ID com.RentnKingNew.app; extension target RentnKinExtension. Verify these against the project and signed-in Apple account before distribution.

The previously reported release was version 1.0.24, build 1010, submitted for review. Check current App Store Connect state and processed/uploaded build numbers now; do not assume that state or that build 1011 is available. Choose the appropriate marketing version and a new valid build number based on current Apple state. Keep app and extension version/build settings consistent across relevant configurations. Do not cancel or replace a pending review submission automatically.

After tests pass, commit the implementation and necessary version changes on the implementation branch. Push that branch to the verified repository and create a draft implementation PR with the behavior change and actual validation results. Keep this distinct from the patch carrier branch. Do not merge main as part of this preparation task.

Use the tested implementation commit to archive RentnKing in Release for a generic iOS device. Use the existing team and signing configuration, an isolated archive output path, and an explicit result/log path. Resolve signing or entitlement errors rather than silently changing bundle identity. Validate the archive for App Store Connect distribution through Xcode Organizer or supported tooling. Use an App Store distribution route suitable for eventual App Review, not a TestFlight Internal Only route.

Prepare the signed .xcarchive, any needed export configuration/IPA, validation evidence, and concise release notes describing the independent equipment checklist fix. Preserve symbols and identify any warnings, distinguishing existing dependency warnings from new problems. Do not call the archive release-ready if tests, signing, or archive validation are incomplete.

Official Apple references:
https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
https://help.apple.com/xcode/mac/current/en.lproj/dev37441e273.html
https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/

5. FINAL HANDOFF

Report the implementation branch, commit SHA, draft PR URL, worktree path, app version/build, current Apple review state, Xcode version, test results with counts and any outstanding coverage, archive/export paths, and validation outcome. Provide release notes and the concrete next action for Apple upload/submission. State clearly whether anything has actually been uploaded or submitted to Apple; preparation alone is not submission.
