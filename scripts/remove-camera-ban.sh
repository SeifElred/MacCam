#!/bin/bash
# Remove MacCam camera ban so FaceTime / Photo Booth work again.
# Prefer System Settings — `profiles remove` often fails (-205) depending on install domain.
set -euo pipefail

ID="com.maccam.camera.disable"

echo "Remove the camera ban in System Settings (most reliable):"
echo "  System Settings → General → Device Management → MacCam Disable Camera → Remove"
open "x-apple.systempreferences:com.apple.Profiles-Settings.extension" 2>/dev/null || true
echo

echo "Also trying CLI remove (may no-op or return -205)…"
profiles remove -identifier="$ID" 2>/dev/null || true
profiles -R -p "$ID" 2>/dev/null || true

echo "One soft bounce of appleh13camerad (SIP-safe; do not loop-kill)…"
killall -9 appleh13camerad 2>/dev/null || true
echo "Done. Quit/reopen Photo Booth / FaceTime if needed."
