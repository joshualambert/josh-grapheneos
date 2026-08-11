# Known issues

Standing problems on this device. Anything with a full investigation behind it
links to its incident directory.

## Open

### Play services crashes on every incoming call

**Since:** at least 2026-08-08 (earliest entry surviving in the crash buffer)
**Severity:** cosmetic dialog; Google contact photo sync broken
**Incident:** [2026-08-11-gms-contact-scopes-crash](../incidents/2026-08-11-gms-contact-scopes-crash/)

GrapheneOS Contact Scopes rewrites Play services' contact-photo query into a form
`ContactsProvider2` rejects (`Invalid column photo_uri`); Play services does not
catch it and the process dies. Fix is to turn Contact Scopes off for Play
services — identified but **not yet applied or verified**.

Quick check for whether it is still happening:

```bash
adb logcat -b crash -d | grep -c 'Invalid column photo_uri'
```

## Watching

### Discord foreground-service crash

One instance on 2026-08-11:

```
android.app.ForegroundServiceStartNotAllowedException: Service.startForeground() not allowed:
  service com.discord/com.google.android.play.core.assetpacks.ExtractionForegroundService
```

A Play Asset Delivery download tried to start a foreground service from the
background. Single occurrence, no reported user impact, not investigated. Worth
opening an incident only if it recurs.

## Resolved

*(none yet)*
