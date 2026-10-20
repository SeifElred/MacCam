# MacCam — Manual hardware QA

Run after `./scripts/build.sh && open dist/MacCam.app`.

## Prep

- [ ] Quit old MacCam builds
- [ ] Open Photo Booth so the green LED is on
- [ ] Confirm MacCam icon is in the menu bar with **Privacy Lock On**

## Disable path (no app force-quit)

| # | Steps | Expected |
| --- | --- | --- |
| 1 | Open MacCam while Photo Booth shows camera | LED turns off within ~1–2s; Photo Booth stays open but preview fails / no camera |
| 2 | Lock On → try FaceTime camera | FaceTime stays open; camera unavailable; LED off |
| 3 | Unlock → open Photo Booth | Camera works; LED on while previewing |
| 4 | Lock again | LED off; Photo Booth still running |
| 5 | Launch at Login | Survives logout/login with lock on and LED off |

## UI

| # | Steps | Expected |
| --- | --- | --- |
| 6 | Open menu | Glass panel, solid layout, status “Camera disabled — LED off” |
| 7 | Toggle lock | Copy switches between disabled / available |

## Automated

```bash
./scripts/test.sh
```
