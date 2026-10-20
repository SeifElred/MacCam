# MacCam — How to use

MacCam is a menu bar privacy guard for macOS 14+. It **locks your camera by default** so apps cannot keep it on (and the green LED stays off). Unlock when you need FaceTime, Zoom, etc.

> The LED is hardware-tied. MacCam cannot hide it while the camera streams. It keeps the LED off by **blocking lasting camera use**.

## Requirements

- Mac with **macOS 14 Sonoma** or later
- **Xcode Command Line Tools** (for building): `xcode-select --install`
- Optional: full **Xcode** (for running automated tests)

## Quick start (plug and play)

```bash
cd maccam
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

Look in the **top-right menu bar** for the shield/lock icon. Click it to open MacCam.

### First launch / Gatekeeper

If macOS says the app can’t be opened:

1. Right-click `MacCam.app` → **Open** → **Open**
2. Or run: `xattr -cr dist/MacCam.app && open dist/MacCam.app`

## Everyday use

| Goal | What to do |
| --- | --- |
| Keep camera/LED off | Leave **Privacy Lock On** (default) |
| Join a video call | Open MacCam → click **Unlock** → use FaceTime/Zoom → click **Lock** when done |
| Start at login | Toggle **Launch at Login** in the menu |
| Silence notifications | Turn off **Notify on attempt** |

### When an app tries the camera while locked

MacCam **does not freeze apps** (freezing leaves the green LED stuck on). It quits the process that opened the camera so the hardware releases and the LED turns off.

- Unknown / block-listed apps → stopped automatically
- Allow-listed apps → left alone
- To use FaceTime/Zoom: **Unlock** first (or add the app to the Allow list)

### Allow / Block lists

Use **Allow list** / **Block list** in the menu to review or remove apps. Counts update live.

## Install to Applications (optional)

```bash
./scripts/build.sh
./scripts/package.sh
cp -R dist/MacCam.app /Applications/
open -a MacCam
```

## Launch at Login notes

1. Enable **Launch at Login** in MacCam.
2. If macOS asks, approve MacCam under **System Settings → General → Login Items & Extensions**.
3. Unsigned/debug builds sometimes need that manual approval once.

## Quit

Menu → **Quit MacCam**, or focus the menu and press **⌘Q**.

## Privacy

- Fully local — no network, no accounts, no telemetry
- Activity log: `~/Library/Application Support/MacCam/activity.json`
- Preferences: standard `UserDefaults` for this app
- Camera TCC permission is **not** required (MacCam reads device-on status only; it does not capture video)

## Limits (honest)

- Detection reacts in ~100–500ms — not a kernel zero-gap blocker
- “Which app has the camera?” is heuristic (frontmost + known video apps)
- Can only signal processes owned by your user (not root system daemons)
- Does not hide Apple’s green menu-bar privacy indicator

## Build with Xcode instead

```bash
open MacCam.xcodeproj
# Product → Run  (or ⌘R)
```

## Run automated tests

```bash
./scripts/test.sh
```

See [MANUAL_QA.md](MANUAL_QA.md) for hardware checklist on a real Mac.
