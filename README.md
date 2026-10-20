# MacCam

Menu bar camera privacy guard for macOS.

**Privacy Lock On (default)** freezes any app that opens the camera so the green LED cannot stay on. Unlock when you need video calls. Optional allow/block lists, launch at login, and activity log — all local.

> Apple wires the LED to the camera hardware. MacCam cannot turn the LED off while video is streaming; it keeps the LED off by blocking lasting camera use.

## Plug and play

On a Mac (macOS 14+):

```bash
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

Then:

1. Click the **shield** icon in the menu bar  
2. Leave **Privacy Lock On** for everyday protection  
3. Turn on **Launch at Login**  
4. **Unlock** only when you need FaceTime/Zoom, then Lock again  

Full guide: [docs/USAGE.md](docs/USAGE.md)  
Hardware checklist: [docs/MANUAL_QA.md](docs/MANUAL_QA.md)

## Features

- Menu bar only (no Dock icon)
- Lock / Unlock with clear status
- Detects camera via CoreMediaIO (no Camera permission required)
- When locked, stops apps that open the camera (no freeze — LED can release)
- Allow / block lists
- Launch at login (`SMAppService`)
- Compact local activity line

## Develop

```bash
open MacCam.xcodeproj   # or use scripts/build.sh
./scripts/test.sh       # XCTest
./scripts/package.sh    # zip dist/MacCam.app
```

## Requirements

- macOS 14 Sonoma or later  
- Xcode Command Line Tools to build  

## License

Use and modify freely for personal privacy tooling.
