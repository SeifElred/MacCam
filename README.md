# MacCam

A macOS menu-bar **Camera Lock**.

When the lock is on, apps cannot open the built-in camera. When Photo Booth, FaceTime, Zoom, or another camera app starts, MacCam asks **Allow**, **Allow 15 min**, or **Deny**. Allow opens the camera for that session and locks again when you quit the app. Deny keeps the camera closed.

No Dock icon. One password, once. Your files, accounts, and System Integrity Protection are left alone.

## Install

On a Mac with **macOS 14** or later and Xcode Command Line Tools:

```bash
git clone https://github.com/SeifElred/MacCam.git
cd MacCam
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

Look for the camera icon in the **menu bar** (MacCam does not appear in the Dock).

First launch:

1. Turn **Camera Lock** on.
2. Tap **Enable Camera Lock (once)** and enter your Mac password.
3. If System Settings asks you to install **MacCam Disable Camera**, click **Install**.

That profile is removable. It is not your user account and it does not delete anything.

## Everyday

| You want | Do this |
| --- | --- |
| Camera closed by default | Leave **Camera Lock** on |
| A video call | Open the app. Choose **Allow** or **Allow 15 min** |
| Stay locked | Choose **Deny** |
| Start at login | Turn on **Launch at Login** in the menu |
| Always allow one app | Add it to the **Allow List** |
| Quit MacCam | **Quit MacCam** in the menu |

After **Allow**, use the camera normally. When you quit the camera app, MacCam locks again.

## What it actually does

MacCam installs a removable configuration profile:

- `allowCamera = false`
- CoreMediaIO **Device Access Allowed = false**

Apps stay open. They simply cannot see a camera, the same way a missing camera looks.

While locked, MacCam does **not** poll CoreMediaIO. Asking the camera stack “are you on?” is enough to wake the image processor and light the LED. MacCam stays quiet so the processor can power down the same way it does after you quit Photo Booth (about four seconds after the last client leaves).

It also does **not** loop-kill `appleh13camerad`. That daemon is protected by System Integrity Protection, and killing it in a loop wakes the processor again.

## The green LED

The LED is wired to camera power. There is no separate “turn the light off” switch.

| What you see | What it means |
| --- | --- |
| Lock on, Photo Booth has no camera, LED goes dark after a few seconds | Working as designed |
| Lock on, an app is still using the camera | LED stays on until that app quits |
| Lock on, no app is using the camera, LED stays green after a restart | The processor stayed powered. A slide cover or Apple Support is the remaining fix. SIP stays on. |

## Scripts

| Script | Purpose |
| --- | --- |
| `./scripts/build.sh` | Build `dist/MacCam.app` |
| `./scripts/test.sh` | Run unit tests |
| `./scripts/package.sh` | Zip a build for sharing |
| `./scripts/install-camera-ban.sh` | Open the profile so you can install it in System Settings |
| `./scripts/remove-camera-ban.sh` | Open System Settings so you can remove the profile |

`profiles install` from Terminal no longer works on current macOS. Install and remove the profile in **System Settings → General → Device Management**.

## Uninstall

1. Open MacCam and turn **Camera Lock** off, or remove **MacCam Disable Camera** in Device Management.
2. Quit MacCam.
3. Optional cleanup:

```bash
sudo launchctl bootout system/com.maccam.cameradisable 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.maccam.cameradisable.plist
sudo rm -rf "/Library/Application Support/MacCam"
rm -rf "$HOME/Library/Application Support/MacCam"
```

## Develop

```bash
open MacCam.xcodeproj
./scripts/test.sh
```

Guides: [docs/USAGE.md](docs/USAGE.md) · [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) · [docs/MANUAL_QA.md](docs/MANUAL_QA.md)

## Requirements

- macOS 14 Sonoma or later (Apple silicon and Intel)
- Xcode Command Line Tools (`xcode-select --install`)

## License

[MIT](LICENSE)
