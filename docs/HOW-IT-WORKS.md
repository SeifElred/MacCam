# How MacCam works

MacCam is a menu-bar app (`LSUIElement`). It does not show a Dock icon.

## Lock

Lock asks a small root helper to apply two settings:

1. A configuration profile payload `com.apple.applicationaccess` with `allowCamera` set to `false`.
2. CoreMediaIO **Device Access Allowed** set to `false`.

Together, apps cannot open a capture stream. They stay running. Nothing in your home folder is deleted.

The helper is `com.maccam.cameradisable`. It is the only launchd job MacCam installs. It does not boot out Apple’s camera daemon.

## Why the LED can go dark

On Apple silicon the green LED is tied to the image signal processor (ISP).

Normal Photo Booth use looks like this:

1. The app opens a CoreMediaIO stream.
2. The ISP powers on (`ISP_PowerOnCamera`). The LED lights.
3. You quit the app. The last client disconnects.
4. After a short deferred power-off (~4 seconds) the ISP powers off. The LED goes dark.

MacCam uses that same path. While locked it **stops polling CoreMediaIO**, because a status query is itself a client and keeps the ISP awake. It also avoids killing `appleh13camerad` in a loop, because launchd restarts the daemon and the ISP powers on again.

## Allow

When a camera app launches, MacCam shows an AppKit alert:

- **Allow** removes the ban, lets the helper finish, then the camera app can open a stream.
- **Allow 15 min** does the same and re-locks on a timer.
- **Deny** leaves the ban in place.

When the allowed app quits, MacCam applies the ban again.

The prompt is AppKit on purpose. A SwiftUI panel for this alert crashed on newer macOS.

## What MacCam will not do

| Action | Why |
| --- | --- |
| `launchctl` on `com.apple.appleh13camerad` | System Integrity Protection returns “Operation not permitted” |
| Loop-kill `appleh13camerad` | The daemon respawns and the LED comes back |
| Bit-bang the LED | There is no public API. The LED follows ISP power |
| Disable SIP | Out of scope. The lock works with SIP on |
| Force-quit your apps | Apps stay open and simply see no camera |

## Files MacCam writes

| Path | What |
| --- | --- |
| `/Library/LaunchDaemons/com.maccam.cameradisable.plist` | Helper |
| `/Library/Application Support/MacCam/` | Helper script and profile copy |
| `~/Library/Application Support/MacCam/` | User copy of the profile |
| Configuration profile `com.maccam.camera.disable` | The camera ban |

Nothing else.
