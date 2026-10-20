#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v xcodebuild >/dev/null 2>&1 || {
  echo "error: xcodebuild required to run XCTest."
  echo "       Install Xcode from the App Store, then:"
  echo "       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
}

echo "==> Running MacCamTests"
xcodebuild \
  -project MacCam.xcodeproj \
  -scheme MacCam \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/.derivedData" \
  test \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES

echo "All automated tests finished."
