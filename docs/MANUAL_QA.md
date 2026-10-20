# MacCam — Manual hardware QA

Run these on a real Mac after `./scripts/build.sh && open dist/MacCam.app`.

## Prep

- [ ] Quit FaceTime, Photo Booth, Zoom, browsers with open video tabs
- [ ] Confirm MacCam icon appears in the menu bar
- [ ] Confirm **Privacy Lock On** is the default

## Lock / block path

| # | Steps | Expected |
| --- | --- | --- |
| 1 | Lock On → open **Photo Booth** | Process freezes or is prompted within ~1s; green LED does not stay on; decision sheet appears |
| 2 | Choose **Allow once** | Photo Booth resumes; camera works; LED on while open |
| 3 | Quit Photo Booth, reopen with Lock On | Prompt appears again (once was not permanent) |
| 4 | Choose **Always allow** | Added to Allow list; reopen is silent-allowed |
| 5 | Remove from Allow list → reopen → **Always block** | App quit; listed under Block list; reopen auto-blocked with no prompt |
| 6 | Clear block list | Policy resets |

## Unlock path

| # | Steps | Expected |
| --- | --- | --- |
| 7 | Unlock → open FaceTime (or Photo Booth) | Camera works normally; status shows app name |
| 8 | Lock again while camera is open | Offending app frozen/prompted; LED turns off after freeze |
| 9 | Unlock, use camera, Quit MacCam | Camera remains usable; no orphan frozen apps |

## Login item

| # | Steps | Expected |
| --- | --- | --- |
| 10 | Enable **Launch at Login** | Toggle stays on after reopen menu; or shows approval hint |
| 11 | Approve in System Settings if asked | MacCam starts after logout/login |
| 12 | Disable Launch at Login | Status off; no longer in Login Items as enabled |

## Notifications & UI

| # | Steps | Expected |
| --- | --- | --- |
| 13 | Notify on → trigger a block prompt | Notification appears |
| 14 | Notify off → trigger again | No notification (sheet still appears) |
| 15 | Activity list | Recent events show with correct Allow/Block/Prompt labels |
| 16 | Icon states | Locked shield / unlocked / alert while prompting |

## External camera (optional)

| # | Steps | Expected |
| --- | --- | --- |
| 17 | Plug USB webcam, Lock On, open an app using it | Same freeze/prompt behavior |

## Regression / safety

| # | Steps | Expected |
| --- | --- | --- |
| 18 | Leave prompt open 30s with no click | Auto-block; process terminated; event logged |
| 19 | Rapid Lock/Unlock toggling | No crash; status text stays coherent |
| 20 | CPU while idle | Negligible (250ms poll only); Activity Monitor sanity check |

## Automated tests

```bash
./scripts/test.sh
```

All XCTest cases should pass before release.
