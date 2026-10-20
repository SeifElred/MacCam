#!/bin/bash
# Install MacCam's System-scoped camera ban (allowCamera=false + CMIO deny).
# macOS no longer allows `profiles install` from Terminal — must Install via System Settings.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="$HOME/Library/Application Support/MacCam/disable-camera.mobileconfig"
SRC="$ROOT/config/disable-camera.mobileconfig"

if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC — run: git pull" >&2
  exit 1
fi

mkdir -p "$(dirname "$PROFILE")"
cp -f "$SRC" "$PROFILE"

echo "Opening the MacCam camera-ban profile…"
echo
echo "Do this next (required — Terminal cannot install profiles anymore):"
echo "  1) System Settings opens (or a Profiles dialog)."
echo "  2) Go to: System Settings → General → Device Management"
echo "     (on some macOS: Privacy & Security → Profiles)"
echo "  3) Select “MacCam Disable Camera” → Install → enter your Mac password."
echo "  4) Confirm with:  profiles list -all | grep -i maccam"
echo
open "$PROFILE"
sleep 1
open "x-apple.systempreferences:com.apple.Profiles-Settings.extension" 2>/dev/null \
  || open "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings" 2>/dev/null \
  || true

echo "Waiting for you to click Install…"
echo "After Install, run:"
echo "  profiles list -all | grep -i maccam"
echo
echo "Success = Photo Booth / FaceTime see no camera."
echo "LED is ISP-tied (not bit-bangable with SIP on)."
echo "Do NOT loop-kill appleh13camerad — that re-powers the ISP."
echo "If LED stays green after a restart with the ban on: cover / Apple Care."
