# MacCam — How to use

MacCam is a menu bar privacy guard for macOS 14+. With **Privacy Lock On**, it **disables the camera hardware** — apps stay open, but they cannot use the camera (as if none is connected), and the green LED turns off.

> MacCam does **not** force-quit Zoom, Chrome, FaceTime, etc. It only resets the macOS camera services so the sensor releases.

## Requirements

- Mac with **macOS 14 Sonoma** or later
- **Xcode Command Line Tools** (for building): `xcode-select --install`
- Optional: full **Xcode** (for running automated tests)

## Quick start (plug and play)

```bash
cd MacCam
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

Look in the **top-right menu bar** for the shield/lock icon.

### First launch / Gatekeeper

If macOS says the app can’t be opened:

1. Right-click `MacCam.app` → **Open** → **Open**
2. Or run: `xattr -cr dist/MacCam.app && open dist/MacCam.app`

## Everyday use

| Goal | What to do |
| --- | --- |
| No camera / LED off | Leave **Privacy Lock On** (default). Opening MacCam turns the camera off. |
| Join a video call | **Unlock** → use FaceTime/Zoom → **Lock** when done |
| Start at login | Toggle **Launch at Login** |
| Silence notifications | Turn off **Notify on attempt** |

### What “locked” means

- Camera system services are bounced whenever the camera turns on
- Your apps **keep running** — their camera preview just fails / shows no device
- Green LED should go off because nothing holds the sensor
- **Allow list**: if an allow-listed app is the likely camera user, MacCam won’t disable (optional exception)

### Allow / Block lists

- **Allow list** — optional exception while locked  
- **Block list** — reserved for future policy (hardware disable already blocks everyone when locked)

## Install to Applications (optional)

```bash
./scripts/build.sh
./scripts/package.sh
cp -R dist/MacCam.app /Applications/
open -a MacCam
```

## Launch at Login notes

1. Enable **Launch at Login** in MacCam.
2. If macOS asks, approve under **System Settings → General → Login Items & Extensions**.

## Quit

Menu → **Quit MacCam**, or **⌘Q**. After quitting, the camera works normally again.

## Privacy

- Fully local — no network, no accounts, no telemetry
- Activity log: `~/Library/Application Support/MacCam/activity.json`
- Camera TCC permission is **not** required

## Limits (honest)

- macOS has no public API for “revoke camera for all apps”; MacCam disables the camera **stack** instead
- Some camera daemons may need a moment to release; MacCam retries while locked
- If Continuity Camera (iPhone) is active, disconnect the phone or unlock MacCam
- If the LED stays on after lock, run once:  
  `sudo killall -9 appleh13camerad VDCAssistant AppleCameraAssistant UVCAssistant cameracaptured`

## Build with Xcode

```bash
open MacCam.xcodeproj
```

## Run automated tests

```bash
./scripts/test.sh
```

See [MANUAL_QA.md](MANUAL_QA.md) for hardware checks.
