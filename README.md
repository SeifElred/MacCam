# MacCam

Menu bar camera privacy guard for macOS.

**Privacy Lock On (default)** installs an OS **camera ban** (`allowCamera=false` + CoreMediaIO deny). Apps stay open but cannot use the camera (as if it isn’t there). Unlock when you need FaceTime or Zoom.

> On M1/M-series Macs, enter your Mac password once to install the helper. Soft-clear uses `killall` only — SIP forbids `launchctl` on `appleh13camerad`. The green LED is **hardwired to ISP power**; MacCam cannot bit-bang it. With the ban on, MacCam **pauses CMIO polling** so it does not keep the ISP warm itself.

## Plug and play

On a Mac (macOS 14+):

```bash
chmod +x scripts/*.sh
./scripts/build.sh
open dist/MacCam.app
```

Then:

1. Click the **shield** icon in the menu bar  
2. Leave **Privacy Lock On** — complete **Install** for the MacCam profile in System Settings if prompted  
3. Turn on **Launch at Login**  
4. **Unlock** only for video calls, then Lock again  

Full guide: [docs/USAGE.md](docs/USAGE.md)  
Hardware checklist: [docs/MANUAL_QA.md](docs/MANUAL_QA.md)

## Features

- Menu bar only (no Dock icon)
- Glass / vibrancy UI
- Lock = OS camera ban (apps keep running)
- Detects camera via CoreMediaIO only when the ban is off
- Launch at login (`SMAppService`)
- Optional allow list exception

## Honest limits

- Ban blocks apps (Photo Booth / FaceTime see no camera). That is the privacy win.
- LED off uses the **same path as quitting Photo Booth**: last CMIO client leaves → ISP powers off (~4s) → LED off. Ban helps by stopping apps from becoming clients; it does not cut the LED wire.
- With SIP on you cannot permanently kill Apple’s camera daemon or bit-bang the LED. If the LED stays green after idle + one restart with the ban on and no clients, use a cover or Apple Care — not kill loops.

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
