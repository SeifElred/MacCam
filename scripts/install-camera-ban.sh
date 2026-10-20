#!/bin/bash
# Install MacCam's System-scoped camera ban (allowCamera=false + CMIO deny).
# This is the strongest LED-off path that does NOT disable SIP or delete user data.
# When you need the camera: run scripts/remove-camera-ban.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="$HOME/Library/Application Support/MacCam/disable-camera.mobileconfig"
mkdir -p "$(dirname "$PROFILE")"

# Prefer checked-in profile; else generate from repo copy.
SRC="$ROOT/config/disable-camera.mobileconfig"
if [[ -f "$SRC" ]]; then
  cp -f "$SRC" "$PROFILE"
else
  echo "Missing $SRC" >&2
  exit 1
fi

echo "Installing System camera ban (password required)…"
echo "This only adds a removable configuration profile — it does not touch your files."
sudo profiles install -type configuration -path "$PROFILE"

echo
echo "Verify:"
profiles list -all | grep -i maccam || true
/usr/bin/osascript -l JavaScript -e \
  "$.NSUserDefaults.alloc.initWithSuiteName('com.apple.applicationaccess').objectForKey('allowCamera').js" \
  || true
echo "Expected allowCamera check: false"
echo
echo "Now: quit all camera apps, wait 5s, confirm green LED is off."
echo "If LED was stuck on before install: Restart once, then leave the ban installed."
