# Manual QA

Run on a Mac after:

```bash
./scripts/build.sh
open dist/MacCam.app
```

Quit any older MacCam process first: `killall MacCam`.

## Setup

- [ ] Menu-bar camera icon appears. No Dock icon.
- [ ] **Enable Camera Lock (once)** asks for the Mac password a single time.
- [ ] **MacCam Disable Camera** can be installed from System Settings → General → Device Management.
- [ ] `sudo profiles list -all` includes `com.maccam.camera.disable`.

## Lock and Allow

| # | Steps | Expected |
| --- | --- | --- |
| 1 | Lock on. Open Photo Booth. Tap **Deny** | Photo Booth stays open and has no camera |
| 2 | Open Photo Booth again. Tap **Allow** | Preview works. LED on while previewing |
| 3 | Quit Photo Booth | Lock returns. After a few seconds the LED can go dark |
| 4 | Open Photo Booth. Tap **Allow 15 min** | Preview works. Lock returns when the timer ends or the app quits |
| 5 | Add an app to the Allow List and open it | No prompt. Camera works for that app |
| 6 | Launch at Login, log out and back in | Menu-bar icon returns with the lock on |

## LED

| # | Steps | Expected |
| --- | --- | --- |
| 7 | Lock on, no camera app, wait 10 seconds | LED follows ISP power-off. UI does not claim it flipped the LED wire |
| 8 | LED still green with no client after a restart | UI stays honest. Cover or Apple Support, not a kill loop |

## Restore

| # | Steps | Expected |
| --- | --- | --- |
| 9 | Turn the lock off, or tap **Restore Camera** | Photo Booth sees the camera again after a reopen |
| 10 | Remove the profile in Device Management | Same result. User files unchanged |

## Automated

```bash
./scripts/test.sh
```
