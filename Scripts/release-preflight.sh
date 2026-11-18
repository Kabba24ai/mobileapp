#!/bin/bash
#
# Release preflight — run BEFORE archiving a build for App Store Connect. Refuses to
# continue when the build could ship an outdated binary or inconsistent version
# metadata, and prints what the release record and App Store Connect need.
#
#   Scripts/release-preflight.sh <marketing version> <build number>
#   e.g. Scripts/release-preflight.sh 1.0.28 1014
#
# Checks (any failure exits 1, nothing is changed):
#   • the working tree has no uncommitted changes to tracked files (the stamp in the
#     binary would say "+ uncommitted changes" and the commit could not be traced);
#   • the app AND the share extension carry exactly this version and build;
#   • the build number is higher than every build in docs/releases/HISTORY.md, and the
#     version is not one App Store Connect already closed (released/approved);
#   • AppReleaseCatalog has notes for this version (Scripts/whats-new.sh renders them).
#
# Archive with the commit stamped explicitly (the build phase also reads git itself):
#   KABBA_SOURCE_REVISION=$(git rev-parse --short=12 HEAD) KABBA_SOURCE_STATE=clean xcodebuild archive …
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: Scripts/release-preflight.sh <version> <build>}"
BUILD="${2:?usage: Scripts/release-preflight.sh <version> <build>}"
PBX="$ROOT/RentnKing.xcodeproj/project.pbxproj"
HISTORY="$ROOT/docs/releases/HISTORY.md"
problems=0
fail() { echo "✖ $*"; problems=$((problems + 1)); }
ok() { echo "✓ $*"; }

cd "$ROOT"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  fail "uncommitted changes to tracked files — commit them, or the build cannot be traced to a commit"
  git status --short --untracked-files=no | sed 's/^/    /'
else
  ok "working tree clean at $(git rev-parse --short=12 HEAD) ($(git rev-parse --abbrev-ref HEAD))"
fi

# App + extension (the test targets keep 1.0 / 1).
VERSIONS=$( { grep -E 'MARKETING_VERSION = ' "$PBX" || true; } | sed -E 's/.*= ([^;]+);/\1/' | { grep -vx '1.0' || true; } | sort -u)
BUILDS=$( { grep -E 'CURRENT_PROJECT_VERSION = ' "$PBX" || true; } | sed -E 's/.*= ([^;]+);/\1/' | { grep -vx '1' || true; } | sort -u)
[ "$VERSIONS" = "$VERSION" ] && ok "app and extension are version $VERSION" || fail "MARKETING_VERSION is '$(echo $VERSIONS)', expected $VERSION in every app/extension configuration"
[ "$BUILDS" = "$BUILD" ] && ok "app and extension are build $BUILD" || fail "CURRENT_PROJECT_VERSION is '$(echo $BUILDS)', expected $BUILD in every app/extension configuration"

if [ -f "$HISTORY" ]; then
  MAXBUILD=$( { grep -E '^\| [0-9]+\.[0-9]+\.[0-9]+ \| [0-9]+ \|' "$HISTORY" || true; } | awk -F'|' '{gsub(/ /,"",$3); print $3}' | sort -n | tail -1)
  if [ -n "$MAXBUILD" ] && [ "$BUILD" -le "$MAXBUILD" ]; then
    fail "build $BUILD is not higher than $MAXBUILD, the last build recorded in docs/releases/HISTORY.md (build numbers only ever increase)"
  else
    ok "build $BUILD is higher than every recorded build (${MAXBUILD:-none})"
  fi
  if grep -E "^\| $VERSION \| [0-9]+ \|.*\| (Released|Approved|Live)" "$HISTORY" >/dev/null; then
    fail "version $VERSION is already released/approved — App Store Connect will refuse new builds for it (bump the version)"
  else
    ok "version $VERSION is still open"
  fi
else
  fail "docs/releases/HISTORY.md is missing"
fi

if NOTES=$("$ROOT/Scripts/whats-new.sh" "$VERSION" 2>&1); then
  ok "release notes found for $VERSION"
else
  fail "${NOTES#✖ }"
  NOTES=""
fi

echo
if [ "$problems" -gt 0 ]; then
  echo "✖ Preflight failed ($problems problem(s)). Nothing was changed."
  exit 1
fi
echo "Preflight passed. Record in docs/releases/HISTORY.md after the upload:"
echo "| $VERSION | $BUILD | $(git rev-parse --short=12 HEAD) | $(git rev-parse --abbrev-ref HEAD) | <upload date> | Uploaded |"
echo
echo "App Store Connect → What's New in This Version (paste; it is NOT synced automatically):"
echo "$NOTES"
