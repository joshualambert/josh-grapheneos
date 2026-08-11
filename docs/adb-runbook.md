# adb runbook

How to get a shell on the phone and pull the diagnostics the incident writeups
are built from.

## One-time setup

### On the phone

1. **Settings → About phone →** tap *Build number* seven times to unlock
   developer options.
2. **Settings → System → Developer options → USB debugging →** on.
3. Plug in over USB. Accept the *Allow USB debugging?* prompt and tick
   *Always allow from this computer* so it survives reconnects.

GrapheneOS also gates ADB behind **Settings → Security → Exploit protection →
USB → *Allow USB access when unlocked***, and it disables ADB entirely after a
reboot until the device is unlocked once. If `adb devices` shows nothing after a
reboot, unlock the phone first.

### On the workstation (Arch)

```bash
sudo pacman -S android-tools
```

Or, without root — this is how the tooling was installed here:

```bash
curl -sSL -o /tmp/pt.zip \
  https://dl.google.com/android/repository/platform-tools-latest-linux.zip
unzip -q /tmp/pt.zip -d ~/.local/share/
mv ~/.local/share/platform-tools/* ~/.local/share/android-platform-tools/
ln -sf ~/.local/share/android-platform-tools/adb ~/.local/bin/adb
ln -sf ~/.local/share/android-platform-tools/fastboot ~/.local/bin/fastboot
```

`~/.local/bin` is already on `PATH`.

## Verifying the connection

```bash
adb devices -l
# 57231FDCH00869   device usb:3-2 product:blazer model:Pixel_10_Pro device:blazer
```

`unauthorized` means the on-device prompt has not been accepted. `no permissions`
means a missing udev rule — the Google vendor ID is `18d1`:

```bash
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0664", GROUP="uucp"' \
  | sudo tee /etc/udev/rules.d/51-android.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
```

If the device is absent from `adb devices` entirely, confirm the kernel sees it
at all — no `lsusb` needed:

```bash
for d in /sys/bus/usb/devices/*/; do
  [ -f "$d/idVendor" ] && echo "$(cat $d/idVendor):$(cat $d/idProduct) $(cat $d/product 2>/dev/null)"
done | grep -i 18d1
```

The product ID tells you the USB mode. `4ee7` and `4ee2` include ADB; `4ee1`
(MTP only) means USB debugging is off or the mode is set to *No data transfer*.

## Pulling diagnostics

### Crashes

The `crash` buffer holds only fatal Java exceptions, which makes it the fastest
way to see what is actually dying:

```bash
adb logcat -b crash -d -v threadtime          # dump and exit
adb logcat -b crash -d | grep 'Process:' \
  | sed 's/.*Process: //;s/, PID.*//' | sort | uniq -c | sort -rn
```

Note that one logical failure appears many times — a crashing background service
gets restarted and re-crashes, typically 2–6 times a second apart. Count
*clusters*, not lines.

### Everything else

`-b crash` only ever shows the *client* side of a failed IPC. When an app dies on
a `ContentProvider` call, the useful stack — the one with the real SQL and the
real cause — is logged by the **provider's** process into the main buffer. Always
pull both:

```bash
adb logcat -b all -d -v threadtime > /tmp/full.log
```

Then work backwards from the crash timestamp. Given a crash at `13:29:26`:

```bash
grep -E '^08-11 13:29:2[0-9]' /tmp/full.log
```

To find the server side of a binder call, get the provider's pid and grep it:

```bash
adb shell ps -A | grep -E 'android.process.acore|providers.contacts'
grep ' 20252 ' /tmp/full.log
```

`android.process.acore` is the contacts/call-log provider process.

### Reproducing live

```bash
scripts/watch-gms-crashes.sh   # then trigger the behaviour on the phone
```

### Snapshotting device state

```bash
scripts/collect-snapshot.sh                            # -> docs/device-snapshot-<date>.txt
scripts/collect-snapshot.sh incidents/<slug>/evidence/00-device-snapshot.txt
```

## Useful one-liners

```bash
# Package version, install times, permission grants
adb shell dumpsys package com.google.android.gms | less

# Just the runtime permission state
adb shell dumpsys package com.google.android.gms | grep 'granted='

# Which package serves a content authority
adb shell dumpsys package providers | grep -i contacts

# Build identity
adb shell getprop ro.build.display.id
adb shell getprop ro.build.version.security_patch

# Open an app's settings page directly
adb shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS \
  -d package:com.google.android.gms
```

## Caveats

- **The buffers roll.** On this device the crash buffer covers roughly three
  days. Capture evidence into an incident directory the same day you find it.
- `adb shell` runs as the `shell` user. It cannot read `/data/system/` or app
  private data, so GrapheneOS per-app state such as Contact Scopes assignments is
  **not** visible over ADB. Those have to be read and changed in the Settings UI.
- Prefer `-v threadtime`; the default format omits the pid/tid columns that let
  you correlate the two sides of a binder call.
