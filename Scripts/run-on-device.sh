#!/usr/bin/env bash
# Build Rotoskop for a connected physical iPhone and launch it.
#
# Usage:
#   Scripts/run-on-device.sh              # auto-pick first connected iPhone
#   Scripts/run-on-device.sh Martin        # by device name
#   Scripts/run-on-device.sh 00008140-…    # by UDID
#   DEVICE=Martin Scripts/run-on-device.sh
#
# Requires: Xcode signing already set up (Automatic + Development Team),
# phone unlocked / Trusted This Computer, and connected via USB or network.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/Apps/Rotoskop/Rotoskop.xcodeproj"
SCHEME="Rotoskop"
BUNDLE_ID="com.rotoskop.app"
DERIVED="${ROTOSKOP_DERIVED_DATA:-$ROOT/build/DerivedData-device}"
CONFIGURATION="${CONFIGURATION:-Debug}"

die() { echo "error: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

need xcodebuild
need xcrun

list_physical_iphones() {
  # Prefer xcodebuild destinations (same IDs xcodebuild accepts).
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null \
    | sed -n 's/.*{ platform:iOS, arch:arm64, id:\([^,]*\), name:\([^ }]*\).*/\1	\2/p'
}

resolve_device() {
  local want="${1:-}"
  local lines
  lines="$(list_physical_iphones)"
  [[ -n "$lines" ]] || die "no physical iPhone destinations found (is the phone connected and trusted?)"

  if [[ -z "$want" ]]; then
    # First connected phone.
    echo "$lines" | head -1
    return
  fi

  # Match by UDID or name (case-insensitive).
  local match
  match="$(echo "$lines" | awk -F'	' -v w="$want" '
    BEGIN { IGNORECASE=1 }
    $1 == w || $2 == w { print; found=1; exit }
    END { exit !found }
  ')" || true

  if [[ -z "$match" ]]; then
    echo "Connected phones:" >&2
    echo "$lines" | awk -F'	' '{ printf "  %s  (%s)\n", $2, $1 }' >&2
    die "device not found: $want"
  fi
  echo "$match"
}

DEVICE_ARG="${1:-${DEVICE:-}}"
DEVICE_LINE="$(resolve_device "$DEVICE_ARG")"
DEVICE_ID="$(echo "$DEVICE_LINE" | awk -F'	' '{print $1}')"
DEVICE_NAME="$(echo "$DEVICE_LINE" | awk -F'	' '{print $2}')"

echo "==> Device: $DEVICE_NAME ($DEVICE_ID)"
echo "==> Building ($CONFIGURATION) → $DERIVED"

mkdir -p "$DERIVED"

# -quiet keeps the log usable; full log on failure via tee of a temp file.
BUILD_LOG="$(mktemp -t rotoskop-device-build)"
cleanup() { rm -f "$BUILD_LOG"; }
trap cleanup EXIT

if ! xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -quiet \
  build >"$BUILD_LOG" 2>&1
then
  echo "error: xcodebuild failed; last 80 lines:" >&2
  tail -80 "$BUILD_LOG" >&2
  exit 1
fi

APP="$DERIVED/Build/Products/${CONFIGURATION}-iphoneos/Rotoskop.app"
[[ -d "$APP" ]] || die "built app not found at $APP"

echo "==> Installing $APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "==> Launching $BUNDLE_ID"
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  "$BUNDLE_ID"

echo "==> Done"
