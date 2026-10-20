# MacCam — M1 Pro deep disable

MacCam does **not** force-quit apps. With Privacy Lock On it:

1. Installs a **System** configuration profile: `allowCamera=false` + CoreMediaIO `Device Access Allowed=false`
2. Soft-clears camera daemons with `killall` (SIP forbids `launchctl` on `appleh13camerad`)
3. **Pauses its own CoreMediaIO polling** while the ban is active (CMIO enumerate → `ISP_PowerOnCamera` → green LED)
4. On Unlock, removes that profile so FaceTime/Photo Booth work again

The green LED is hardwired to camera/ISP power. MacCam cannot bit-bang the LED wire independently of the ISP.

### Why the LED goes off when you quit Photo Booth

Normal use: Photo Booth opens a CMIO stream → `ISP_PowerOnCamera` → LED on. Quit Photo Booth → last client disconnects → ~4s `DeferredPowerOff` → `ISP_PowerOffCamera` → LED off.

That is the **only** software path that turns the LED off. Ban does not cut the LED wire; it stops apps from becoming clients. If nothing (including MacCam) talks to `appleh13camerad` for ~4s, the LED should go dark the same way as after Photo Booth.

What SIP blocks: disabling Apple’s camera launchd, or driving the LED pin without powering the ISP.

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
3. Confirm: `profiles list -all | grep -i maccam` (may need sudo)
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

1. Open MacCam (password prompt appears when you tap to install the helper).
2. Enter your **Mac password** — do not cancel.
3. If a **Profiles** install dialog appears, click Install and enter your password again.
4. Wait until status is **Apps blocked from camera** (or ban-on LED honesty hint).
5. Check diagnostics: **OS ban = camera blocked**, **Sensor = poll paused**.

## Everyday

| Goal | Action |
| --- | --- |
| No camera for apps | Keep Privacy Lock On (ban installed) |
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

Proven on M-series with SIP on:

1. Any CMIO client calls `ISP_PowerOnCamera` and resets a ~4s power-off timer (same timer that turns the LED off after Photo Booth).
2. `killall -9 appleh13camerad` in a loop does **not** force LED off — the daemon respawns and clients reconnect.
3. Ban can block Photo Booth while something else still wakes the ISP → LED stays green.

What to do:

1. Confirm ban: Photo Booth shows no camera; diagnostics **OS ban = camera blocked**, **Sensor = poll paused**.
2. Quit camera-ish apps (Chrome/Zoom tabs, Continuity Camera). Wait **10 seconds** — LED should drop like after Photo Booth.
3. If still green: **Restart once** with the ban still installed.
4. If still green with no software client → **webcam cover** or **Apple Care**. You cannot cut the LED wire with SIP on.

## Uninstall

```bash
sudo launchctl bootout system/com.maccam.cameradisable
profiles remove -identifier=com.maccam.camera.disable
sudo rm -f /Library/LaunchDaemons/com.maccam.cameradisable.plist
sudo rm -rf "/Library/Application Support/MacCam"
rm -rf "$HOME/Library/Application Support/MacCam"
```
