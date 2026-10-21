#!/bin/bash
#
# Prints the App Store "What's New" text for a version, rendered from the ONE authoritative
# release-note draft: that version's entry in AppReleaseCatalog.history — the same notes
# Settings → About shows on the phone. Paste the output into App Store Connect by hand;
# nothing publishes it automatically.
#
#   Scripts/whats-new.sh 1.0.28 > whats-new-1.0.28.txt
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: Scripts/whats-new.sh <marketing version>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/main.swift" <<'SWIFT'
import Foundation
let version = CommandLine.arguments[1]
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("✖ " + message + "\n").data(using: .utf8)!)
    exit(1)
}
guard let text = AppReleaseCatalog.appStoreWhatsNew(for: version) else {
    fail("No release notes for \(version) in AppReleaseCatalog.history. Add the entry first — it is the one draft for both Settings and the App Store.")
}
guard text.count <= AppReleaseCatalog.appStoreWhatsNewLimit else {
    fail("\(text.count) characters; App Store Connect allows \(AppReleaseCatalog.appStoreWhatsNewLimit).")
}
print(text)
SWIFT

xcrun swiftc -o "$TMP/whats-new" "$ROOT/RentnKing/Sync/Core/AppReleaseCatalog.swift" "$TMP/main.swift" 2>"$TMP/build.log" \
  || { cat "$TMP/build.log" >&2; exit 1; }
"$TMP/whats-new" "$VERSION"
