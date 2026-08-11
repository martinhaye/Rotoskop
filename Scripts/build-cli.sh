#!/usr/bin/env bash
# Keep the host-side release CLI current with the shared assembler/build sources.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Xcode app builds export an iOS SDKROOT. Clear platform-specific variables so
# SwiftPM builds the CLI for the Mac host instead of the app destination.
exec /usr/bin/env \
  -u SDKROOT \
  -u SDK_NAME \
  -u PLATFORM_NAME \
  -u EFFECTIVE_PLATFORM_NAME \
  /usr/bin/xcrun --sdk macosx swift build \
    --package-path "$ROOT" \
    --configuration release \
    --product rotoskop
