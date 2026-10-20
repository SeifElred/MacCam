# MacCam — Manual hardware QA

Run after `./scripts/build.sh && open dist/MacCam.app`.

## Prep

- [ ] Quit old MacCam builds
- [ ] Open Photo Booth so the green LED is on
- [ ] Confirm MacCam icon is in the menu bar with **Privacy Lock On**

## Disable path (no app force-quit)

| # | Steps | Expected |
| --- | --- | --- |
| 1 | Open MacCam while Photo Booth shows camera; Install ban if prompted | Photo Booth stays open; preview fails / no camera; diagnostics **OS ban = camera blocked**, **Sensor = poll paused** |
| 2 | Lock On → try FaceTime camera | FaceTime stays open; camera unavailable |
| 3 | Unlock → open Photo Booth | Camera works; LED on while previewing |
| 4 | Lock again | Ban re-applied (Install if needed); apps blocked again |
| 5 | Launch at Login | Survives logout/login with lock on and ban active |
| 6 | With ban on, leave MacCam idle 30s | `log stream` for `appleh13camerad` shows no repeating `ISP_PowerOnCamera` from MacCam |

## LED honesty

| # | Steps | Expected |
| --- | --- | --- |
| 7 | Ban on, Photo Booth blocked, physical LED still green | UI does **not** promise “LED off”; hint suggests restart / cover / Apple Care |
| 8 | Restart once with ban installed | LED often clears; if not, hardware/cover only |

## UI

| # | Steps | Expected |
| --- | --- | --- |
| 9 | Open menu | Glass panel; status “Apps blocked from camera” (or LED honesty) when ban on |
| 10 | Toggle lock | Copy switches between blocked / available |

## Automated

```bash
./scripts/test.sh
```
