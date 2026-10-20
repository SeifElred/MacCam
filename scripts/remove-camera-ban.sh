#!/bin/bash
# Remove MacCam camera ban so FaceTime / Photo Booth work again.
set -euo pipefail

echo "Removing MacCam camera ban…"
# System-scoped — needs sudo
sudo profiles remove -identifier=com.maccam.camera.disable 2>/dev/null || true
profiles remove -identifier=com.maccam.camera.disable 2>/dev/null || true

echo "Verify (should NOT list MacCam):"
profiles list -all | grep -i maccam || echo "(none — OK)"

echo "Soft-bounce camera daemon…"
sudo killall -9 appleh13camerad 2>/dev/null || true
echo "Done. Quit/reopen Photo Booth if needed."
