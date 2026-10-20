# MacCam — How to use (M1 / Apple Silicon)

MacCam disables the **built-in FaceTime camera hardware** while locked so apps behave as if there is no camera, and the **green LED turns off**. Apps are **not** force-quit.

On **M1 Pro**, the camera daemon (`appleh13camerad`) is owned by the system. A normal app cannot stop it without a **one-time admin password**.

> Continuity Camera = using an iPhone as a webcam. You can ignore that if you don’t use your iPhone as a Mac camera.

## Plug and play

```bash
git pull
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

## Required once (this is what makes LED-off reliable)

1. Open MacCam — with lock on it **asks for your password automatically**.
2. Enter your **Mac password** (do not cancel).
3. Wait until status says **Camera disabled — LED off**.

That installs a small root helper. After that, MacCam keeps the camera/LED cleared while locked (fast retries + short hold so apps can’t instantly re-grab).

If password was cancelled: open the menu → **Enable LED protection** again.  
If still stuck: **Copy Terminal fix command** → paste in Terminal → Return → password.

## Everyday

| Goal | Action |
| --- | --- |
| LED / camera off | Keep Privacy Lock On |
| Video call | Unlock → use camera → Lock again |
| Start at login | Enable Launch at Login |

## If LED is still on

1. Click **Turn LED off now** / **Enable LED protection** again and enter the password.
2. Or run once in Terminal:

```bash
sudo killall -9 appleh13camerad AppleCameraAssistant VDCAssistant UVCAssistant cameracaptured
```

3. Confirm status is **Camera disabled — LED off** (MacCam only shows that when the system reports the camera is actually off).

## Uninstall helper (optional)

```bash
sudo launchctl bootout system/com.maccam.cameradisable
sudo rm -f /Library/LaunchDaemons/com.maccam.cameradisable.plist
sudo rm -rf "/Library/Application Support/MacCam"
```
