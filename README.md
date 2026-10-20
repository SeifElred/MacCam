# MacCam

Menu bar camera privacy guard for macOS.

**Privacy Lock On (default)** disables the Mac camera hardware — apps stay open, but they can’t use the camera (as if it isn’t there), and the green LED turns off. Unlock when you need FaceTime or Zoom.

> On M1/M-series Macs, click **Enable LED protection (one-time)** and enter your Mac password once. That installs a tiny root helper so the LED can actually turn off. MacCam does not force-quit your apps.

## Plug and play

On a Mac (macOS 14+):

```bash
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

Then:

1. Click the **shield** icon in the menu bar  
2. Leave **Privacy Lock On** — camera/LED stay off  
3. Turn on **Launch at Login**  
4. **Unlock** only for video calls, then Lock again  

Full guide: [docs/USAGE.md](docs/USAGE.md)  
Hardware checklist: [docs/MANUAL_QA.md](docs/MANUAL_QA.md)

## Features

- Menu bar only (no Dock icon)
- Glass / vibrancy UI
- Lock = camera disabled (apps keep running)
- Detects camera via CoreMediaIO
- Launch at login (`SMAppService`)
- Optional allow list exception

## Develop

```bash
open MacCam.xcodeproj
./scripts/test.sh
./scripts/package.sh
```

## Requirements

- macOS 14 Sonoma or later  
- Xcode Command Line Tools to build  

## License

Use and modify freely for personal privacy tooling.
