#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/MacCam.app"
ZIP="$ROOT/dist/MacCam.zip"

if [[ ! -d "$APP" ]]; then
  echo "No app found. Building first..."
  "$ROOT/scripts/build.sh"
fi

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xattr -cr "$ZIP" 2>/dev/null || true

echo "Packaged: $ZIP"
echo "Copy to your Mac Applications folder, then: open -a MacCam"
