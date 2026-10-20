# MacCam — M1 Pro deep disable

MacCam does **not** force-quit apps. With Privacy Lock On it:

1. Installs a **System** configuration profile: `allowCamera=false` + CoreMediaIO `Device Access Allowed=false`
2. Soft-clears camera daemons with `killall` (SIP forbids `launchctl` on `appleh13camerad`)
3. On Unlock, removes that profile so FaceTime/Photo Booth work again

The green LED is hardwired to camera power. The only software way to keep it off when idle is to keep the camera **banned at OS level** so nothing can power the sensor.

**Do not** run `sudo launchctl kickstart/bootout/enable` on `com.apple.appleh13camerad` — SIP returns “Operation not permitted”.

## Fastest path: install the camera ban

Newer macOS removed `profiles install` from Terminal. You must click **Install** in System Settings:

```bash
cd /path/to/MacCam
git pull
chmod +x scripts/*.sh
./scripts/install-camera-ban.sh
```

Then:

1. **System Settings → General → Device Management** (or **Profiles**)
2. Select **MacCam Disable Camera** → **Install** → enter your Mac password
3. Confirm: `profiles list -all | grep -i maccam`
4. If LED was already stuck green: **Restart once**, leave the ban installed

When you need the camera:

```bash
./scripts/remove-camera-ban.sh
# or remove “MacCam Disable Camera” in Device Management
```

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
3. If a **Profiles** install dialog appears, click Install and enter your password again.
4. Wait until status is **Camera disabled — LED off**.
5. Check diagnostics: **OS ban = camera blocked**, **Sensor = OFF**.

## Everyday

| Goal | Action |
| --- | --- |
| No camera / LED off | Keep Privacy Lock On |
| Use FaceTime/Zoom | Unlock → wait for **OS ban = off** → reopen Photo Booth/FaceTime |
| Camera missing after unlock | Tap **Restore camera now**, or run the restore commands below (**without** sudo kickstart) |
| Launch at login | Enable in menu |

## Restore camera (if Unlock left apps without a camera)

Error `-205` with `sudo profiles remove` means the ban is **not** a root/system profile — remove it as your user:

```bash
# No sudo — user-domain profile
profiles remove -identifier=com.maccam.camera.disable

# List what’s installed
profiles list

# Soft-bounce the camera daemon (SIP-safe)
killall -9 appleh13camerad

# Quit and reopen Photo Booth / FaceTime
```

If `profiles list` still shows MacCam, open **System Settings → General → Device Management** (or **Profiles**) and remove **MacCam Disable Camera**.

## If LED stays on

1. Tap **Apply camera ban + clear LED** and enter password; complete any Install Profile dialog.
2. **Copy Terminal fix command** → paste in Terminal.
3. If diagnostics show **OS ban = camera blocked** and **Sensor = OFF** but the physical LED is still green → **Restart Mac to clear stuck LED** (known macOS glitch).

## Uninstall

```bash
sudo launchctl bootout system/com.maccam.cameradisable
profiles remove -identifier=com.maccam.camera.disable
sudo rm -f /Library/LaunchDaemons/com.maccam.cameradisable.plist
sudo rm -rf "/Library/Application Support/MacCam"
rm -rf "$HOME/Library/Application Support/MacCam"
```
