#!/bin/bash
#
# Copies the shared mobile-contract fixtures from the Laravel repository into this
# repo so the Swift tests decode the SAME JSON the Laravel tests assert the API
# produces. Run after `WRITE_CONTRACT_FIXTURES=1 php vendor/bin/phpunit --filter
# MobileContractFixturesTest` in the Laravel repo, then commit both.
#
#   Scripts/sync-contract-fixtures.sh [path-to-Kaaba2]
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LARAVEL="${1:-$ROOT/../Kaaba2}"
SRC="$LARAVEL/tests/Fixtures/mobile-contract"
DST="$ROOT/RentnKingTests/KabbaSyncCore/Fixtures"

[ -d "$SRC" ] || { echo "✖ fixtures not found at $SRC"; exit 1; }
mkdir -p "$DST"
cp "$SRC"/*.json "$DST"/
echo "▶ synced $(ls "$DST"/*.json | wc -l | tr -d ' ') fixture(s) from $SRC"
ls "$DST"
