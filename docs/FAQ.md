# FAQ

## Where is the app after I open it?

In the **menu bar**, as a camera icon. MacCam is a background app, so it never appears in the Dock. If you do not see the icon, quit any stuck copy and open it again:

```bash
killall MacCam 2>/dev/null || true
open dist/MacCam.app
```

## It asked for my password. What did I just allow?

One helper, installed once. It can turn the camera ban on and off. It does not read your documents, mail, photos, or keychain.

## What is “MacCam Disable Camera”?

A configuration profile. It tells macOS that camera access is not allowed. Remove it any time in **System Settings → General → Device Management**. Removing it does not delete your user or your files.

## `profiles remove` says error -205

The profile is not in the place that command looked. Open **System Settings → General → Device Management** and remove **MacCam Disable Camera** there.

`profiles list` without `sudo` often shows nothing even when the profile is installed. Check with:

```bash
sudo profiles list -all | grep -i maccam
```

## `profiles install` says the tool no longer supports installs

That is current macOS. Double-click the profile, or run `./scripts/install-camera-ban.sh`, then click **Install** in System Settings.

## Photo Booth says there is no camera

The lock is doing its job. Open Photo Booth again and tap **Allow**, or turn **Camera Lock** off and tap **Restore Camera**.

## I tapped Allow and the preview is black

Quit the camera app and open it once more. The ban has to finish lifting before the app opens a stream. If it is still black, tap **Restore Camera** in the menu.

## The green LED stayed on

The LED follows camera power. It is not a separate light MacCam can switch.

- If a call or Photo Booth is open, the LED should be on.
- After you quit that app, wait about 10 seconds.
- If it is still on with Camera Lock enabled and no app using the camera, restart once.
- If it is still on after that, the image processor stayed powered. A physical cover or Apple Support is the fix.

Do not run `sudo launchctl kickstart` or `bootout` on `com.apple.appleh13camerad`. System Integrity Protection blocks it, and killing that daemon in a loop turns the camera back on.

## Will this disable System Integrity Protection?

No. Leave SIP on. MacCam is built to work with it enabled.

## Does it work on Intel Macs?

Yes, on macOS 14 or later. The same profile blocks camera access. The LED behavior described in the README was verified on Apple silicon, where the light is tied to the image processor.

## Can I start it when I log in?

Yes. In the menu, turn on **Launch at Login**.

## How do I uninstall?

[Uninstall](../README.md#uninstall) in the README. Turn the lock off or remove the profile first, then quit MacCam, then delete the helper files if you want them gone.
