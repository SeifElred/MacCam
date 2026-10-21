# Contributing

MacCam is a small menu-bar app. Changes that keep Camera Lock, Allow, and the LED behavior predictable are welcome.

## Before you open a pull request

1. Read [How it works](../docs/HOW-IT-WORKS.md).
2. Build and run the tests:

```bash
./scripts/build.sh
./scripts/test.sh
```

3. If you touched the lock, the Allow prompt, or the profile, walk through [Manual QA](../docs/MANUAL_QA.md) on a Mac.

## Please leave these alone unless you are fixing a proven bug

- Do not `launchctl` `com.apple.appleh13camerad`. SIP blocks it.
- Do not loop-kill `appleh13camerad`. That powers the camera and lights the LED.
- Do not poll CoreMediaIO while the lock is on. A status query wakes the sensor.
- Do not force-quit the user’s apps.
- Do not disable System Integrity Protection.

## Reports

Use the bug template and include the Mac model, macOS version, and whether `sudo profiles list -all` shows `com.maccam.camera.disable`. Do not paste passwords.
