#!/usr/bin/env bash
# Build Rotoskop for the iOS Simulator and launch it.
#
# Usage:
#   Scripts/run-on-simulator.sh              # default: iPhone 17
#   Scripts/run-on-simulator.sh "iPhone 17 Pro"
#   Scripts/run-on-simulator.sh D338CE3D-…   # by UDID
#   SIMULATOR="iPhone Air" Scripts/run-on-simulator.sh
#
# Requires: Xcode with an available iPhone simulator runtime.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Apps/Rotoskop/Rotoskop.xcodeproj"
SCHEME="Rotoskop"
BUNDLE_ID="com.rotoskop.app"
DERIVED="${ROTOSKOP_DERIVED_DATA:-$ROOT/build/DerivedData-simulator}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEFAULT_SIM="iPhone 17"

die() { echo "error: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

need xcodebuild
need xcrun

list_iphone_sims() {
  # Prefer xcodebuild destinations (same IDs xcodebuild accepts).
  # Columns: id<TAB>name
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | sed -n 's/.*{ platform:iOS Simulator, arch:[^,]*, id:\([^,]*\), OS:[^,]*, name:\([^}]*\)}.*/\1	\2/p' \
    | awk -F'	' '$2 ~ /^iPhone / { print }' \
    | sed 's/[[:space:]]*$//'
}

resolve_sim() {
  local want="${1:-}"
  local lines
  lines="$(list_iphone_sims)"
  [[ -n "$lines" ]] || die "no iPhone simulator destinations found (install a simulator runtime in Xcode)"

  if [[ -z "$want" ]]; then
    want="$DEFAULT_SIM"
  fi

  local match
  match="$(echo "$lines" | awk -F'	' -v w="$want" '
    BEGIN { IGNORECASE=1 }
    $1 == w || $2 == w { print; found=1; exit }
    END { exit !found }
  ')" || true

  if [[ -z "$match" ]]; then
    # If caller asked for the default and it is missing, fall back to first iPhone.
    if [[ "$want" == "$DEFAULT_SIM" ]]; then
      echo "$lines" | head -1
      return
    fi
    echo "Available iPhone simulators:" >&2
    echo "$lines" | awk -F'	' '{ printf "  %s  (%s)\n", $2, $1 }' >&2
    die "simulator not found: $want"
  fi
  echo "$match"
}

SIM_ARG="${1:-${SIMULATOR:-}}"
SIM_LINE="$(resolve_sim "$SIM_ARG")"
SIM_ID="$(echo "$SIM_LINE" | awk -F'	' '{print $1}')"
SIM_NAME="$(echo "$SIM_LINE" | awk -F'	' '{print $2}')"

echo "==> Simulator: $SIM_NAME ($SIM_ID)"
echo "==> Building ($CONFIGURATION) → $DERIVED"

mkdir -p "$DERIVED"

BUILD_LOG="$(mktemp -t rotoskop-sim-build)"
cleanup() { rm -f "$BUILD_LOG"; }
trap cleanup EXIT

if ! xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DERIVED" \
  -quiet \
  build >"$BUILD_LOG" 2>&1
then
  echo "error: xcodebuild failed; last 80 lines:" >&2
  tail -80 "$BUILD_LOG" >&2
  exit 1
fi

APP="$DERIVED/Build/Products/${CONFIGURATION}-iphonesimulator/Rotoskop.app"
[[ -d "$APP" ]] || die "built app not found at $APP"

echo "==> Booting simulator (if needed)"
STATE="$(xcrun simctl list devices | awk -v id="$SIM_ID" '
  $0 ~ id {
    if ($0 ~ /\(Booted\)/) { print "Booted"; exit }
    if ($0 ~ /\(Shutdown\)/) { print "Shutdown"; exit }
    print "Other"; exit
  }
')"
if [[ "$STATE" != "Booted" ]]; then
  xcrun simctl boot "$SIM_ID" >/dev/null 2>&1 || true
fi
# Wait until boot completes (no-op if already up).
xcrun simctl bootstatus "$SIM_ID" -b >/dev/null

echo "==> Opening Simulator.app"
open -a Simulator

echo "==> Installing $APP"
xcrun simctl install "$SIM_ID" "$APP"

echo "==> Launching $BUNDLE_ID"
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$SIM_ID" "$BUNDLE_ID"

echo "==> Done"
