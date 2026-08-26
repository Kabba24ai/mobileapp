#!/bin/bash
#
# Phase 6A — on-device authentication UI tests (RentnKingUITests) against a
# controlled STAGING backend. Runs the SIGNED app on a real iPhone and drives
# the real sign-in / sign-out / session-recovery flows through the DEBUG-only
# StagingTestHarness (launch arguments; compiled out of Release).
#
# Prerequisites (see docs/mobile-integration/PHASE_6A_VALIDATION_REPORT.md §13):
#   • a staging Laravel reachable over HTTPS (a Cloudflare quick tunnel to a
#     local `php artisan serve`, or any staging host) with a seeded company
#     code + user;
#   • the iPhone paired, developer-mode on, and UNLOCKED for the whole run
#     (xcodebuild parks on "Unlock … to Continue" while the screen is locked);
#   • a signing identity / Apple ID in Xcode (automatic signing, team A9U32VVCRV).
#
# Env:
#   KABBA_UDID        device udid (default: the first attached device)
#   KABBA_BASE_URL    https://<host>/api/admin/v1/   (note the trailing slash)
#   KABBA_EMAIL       staging employee email
#   KABBA_PASSWORD    staging employee password
#   KABBA_TEST        one of: logout | revoked | all   (default: logout)
#
# The revoked-token test needs the server to delete the session mid-run; do that
# out of band once the app has signed in (the report §13 shows the exact SQL).
#
set -euo pipefail
UDID="${KABBA_UDID:-$(xcrun xctrace list devices 2>/dev/null | awk '/\(1[0-9]\.[0-9].*\)/{print $NF; exit}' | tr -d '()')}"
: "${KABBA_BASE_URL:?set KABBA_BASE_URL}"
: "${KABBA_EMAIL:?set KABBA_EMAIL}"
: "${KABBA_PASSWORD:?set KABBA_PASSWORD}"
TEST="${KABBA_TEST:-logout}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

only=()
case "$TEST" in
  logout)  only=(-only-testing:RentnKingUITests/AuthFlowUITests/test_login_then_explicit_logout_then_login_again) ;;
  revoked) only=(-only-testing:RentnKingUITests/AuthFlowUITests/test_revoked_token_returns_to_login_on_next_request) ;;
  all)     only=(-only-testing:RentnKingUITests) ;;
  *) echo "unknown KABBA_TEST=$TEST"; exit 2 ;;
esac

# xcodebuild forwards host env vars prefixed TEST_RUNNER_ to the test runner (prefix stripped).
TEST_RUNNER_KABBA_BASE_URL="$KABBA_BASE_URL" \
TEST_RUNNER_KABBA_EMAIL="$KABBA_EMAIL" \
TEST_RUNNER_KABBA_PASSWORD="$KABBA_PASSWORD" \
exec xcodebuild test \
  -project "$ROOT/RentnKing.xcodeproj" \
  -scheme RentnKingUITests \
  -destination "id=$UDID" \
  -allowProvisioningUpdates \
  "${only[@]}"
