# MacCam — M1 Pro deep disable

MacCam does **not** force-quit apps. With Privacy Lock On it:

1. Installs an OS **configuration profile** (`allowCamera = false`) — apps see **no camera**
2. **Boots out** `appleh13camerad` (M1 camera daemon) so the sensor/LED can release
3. On Unlock, removes the profile and restores the camera service

The green LED is hardwired to camera power — software cannot flip the LED alone. Disabling camera activation is what turns it off.

## Plug and play

```bash
git pull
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

## One-time setup (required on M1 Pro)

1. Open MacCam (password prompt appears automatically when locked).
2. Enter your **Mac password** — do not cancel.
3. Wait until status is **Camera disabled — LED off**.
4. Check diagnostics: **OS ban = camera blocked**, **Sensor = OFF**.

## Everyday

| Goal | Action |
| --- | --- |
| No camera / LED off | Keep Privacy Lock On |
| Use FaceTime/Zoom | Unlock → call → Lock again |
| Launch at login | Enable in menu |

## If LED stays on

1. Tap **Apply camera ban + clear LED** and enter password.
2. **Copy Terminal fix command** → paste in Terminal.
3. If diagnostics show **OS ban = camera blocked** and **Sensor = OFF** but the physical LED is still green → **Restart Mac to clear stuck LED** (known macOS glitch).

## Uninstall

```bash
sudo launchctl bootout system/com.maccam.cameradisable
sudo profiles remove -identifier=com.maccam.camera.disable
sudo rm -f /Library/LaunchDaemons/com.maccam.cameradisable.plist
sudo rm -rf "/Library/Application Support/MacCam"
```
