#!/bin/bash
# Remove MacCam camera ban so FaceTime / Photo Booth work again.
set -euo pipefail

ID="com.maccam.camera.disable"

echo "Trying to remove MacCam camera ban…"
# May work for user-domain; System-scoped often needs System Settings.
profiles remove -identifier="$ID" 2>/dev/null || true
sudo profiles remove -identifier="$ID" 2>/dev/null || true

if profiles list -all 2>/dev/null | grep -qi maccam; then
  echo
  echo "Still listed — remove it in System Settings:"
  echo "  System Settings → General → Device Management → MacCam Disable Camera → Remove"
  open "x-apple.systempreferences:com.apple.Profiles-Settings.extension" 2>/dev/null || true
else
  echo "Profile removed (or was not installed)."
fi

echo "Soft-bounce camera daemon…"
sudo killall -9 appleh13camerad 2>/dev/null || true
echo "Done. Quit/reopen Photo Booth if needed."
