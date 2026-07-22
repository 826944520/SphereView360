#!/usr/bin/env bash
# Build the SphereView360 iOS app for the Simulator.
# Unsigned device/IPA builds run in CI: .github/workflows/build-unsigned-ipa.yml
set -euo pipefail

MODE="${1:-build}"
CONFIGURATION="${CONFIGURATION:-Debug}"
IOS_SCHEME="SphereView360iOS"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_PROJECT="$ROOT_DIR/SphereView360.xcodeproj"
TEMP_PARENT="${TMPDIR:-/tmp}"
TEMP_PARENT="${TEMP_PARENT%/}"
SYMROOT="$TEMP_PARENT/SphereView360-iOSSimulator"

build_simulator() {
  if [[ ! -d "$XCODE_PROJECT" ]]; then
    echo "missing Xcode project: $XCODE_PROJECT" >&2
    exit 1
  fi

  rm -rf "$SYMROOT"

  /usr/bin/xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$IOS_SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphonesimulator \
    SYMROOT="$SYMROOT" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    -quiet \
    build

  echo "Built iOS simulator app: $SYMROOT/$CONFIGURATION-iphonesimulator/$IOS_SCHEME.app"
}

case "$MODE" in
  build|simulator|--build-ios-simulator|build-ios-simulator)
    build_simulator
    ;;
  *)
    echo "usage: $0 [build]" >&2
    echo "  build  Build the SphereView360iOS app for the iOS Simulator (default)" >&2
    exit 2
    ;;
esac
