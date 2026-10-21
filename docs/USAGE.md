# Using MacCam

MacCam lives in the menu bar. Click the camera icon to open the panel.

Stuck? See the [FAQ](FAQ.md).

## First run

```bash
git clone https://github.com/SeifElred/MacCam.git
cd MacCam
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

1. Click the menu-bar icon.
2. Turn **Camera Lock** on.
3. Tap **Enable Camera Lock (once)** and enter your Mac password.
4. Install **MacCam Disable Camera** if System Settings opens:
   - **System Settings → General → Device Management**
   - Select **MacCam Disable Camera → Install**
5. Turn on **Launch at Login** if you want the lock after every restart.

Confirm the ban is installed:

```bash
sudo profiles list -all | grep -i maccam
```

You should see `com.maccam.camera.disable`.

`profiles list` without `sudo` often prints nothing even when the profile is installed. That is normal.

## Allow, Allow 15 min, Deny

With the lock on, opening a camera app shows:

**“App wants the camera”**

| Button | Result |
| --- | --- |
| **Allow** | Camera unlocks. The app can preview. Quitting the app locks again. |
| **Allow 15 min** | Same, then the lock returns after 15 minutes. |
| **Deny** | Camera stays locked. The app sees no camera. |

If the dialog is behind other windows, click the MacCam menu-bar icon or switch to MacCam with Command-Tab.

## Lists

- **Allow List** — those apps can use the camera without a prompt.
- **Block List** — those apps stay blocked even if you would otherwise allow them.

## Restore the camera

Use this if FaceTime or Photo Booth still see no camera after you chose Allow or turned the lock off.

1. In the menu, tap **Restore Camera**.
2. Or remove the profile yourself:

**System Settings → General → Device Management → MacCam Disable Camera → Remove**

```bash
./scripts/remove-camera-ban.sh
```

Then quit and reopen Photo Booth or FaceTime.

`sudo profiles remove` can return error **-205**. That means the profile is not in the domain that command searched. Remove it in System Settings instead. Your user account is not affected.

## If the green LED stays on

The LED follows camera power. MacCam cannot switch the LED by itself.

1. Quit every app that might be using the camera (including browser tabs in a call).
2. Wait about 10 seconds. The light should drop the same way it does after you quit Photo Booth.
3. If it is still on, restart once and leave Camera Lock on.
4. If it is still on with no app using the camera, the image processor stayed powered. A physical cover or Apple Support is the fix. Do not disable System Integrity Protection, and do not loop `killall appleh13camerad` — that turns the processor back on.

## Do not run these

```bash
# SIP blocks this. It does not turn the LED off.
sudo launchctl bootout system/com.apple.appleh13camerad
sudo launchctl kickstart -k system/com.apple.appleh13camerad
```

## Uninstall

Turn Camera Lock off or remove **MacCam Disable Camera** in Device Management, then quit MacCam.

```bash
sudo launchctl bootout system/com.maccam.cameradisable 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.maccam.cameradisable.plist
sudo rm -rf "/Library/Application Support/MacCam"
rm -rf "$HOME/Library/Application Support/MacCam"
```

That removes only MacCam’s helper and profile files.
