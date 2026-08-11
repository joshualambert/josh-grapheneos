# Device profile

Captured 2026-08-11. Refresh with `scripts/collect-snapshot.sh` and update this
file when the build changes.

## Hardware and build

| | |
| --- | --- |
| Model | Pixel 10 Pro |
| Codename | `blazer` |
| ADB serial | `57231FDCH00869` |
| USB vendor:product | `18d1:4ee7` (Google, ADB-enabled mode) |
| Android release | 17 (SDK 37) |
| GrapheneOS build | `2026080501` |
| Security patch | 2026-08-05 |
| Build type | `user` |

## Google Play (sandboxed)

GrapheneOS's sandboxed Play — Play services runs as an ordinary unprivileged app
with no special platform access, with `app.grapheneos.gmscompat` providing the
compatibility shims it needs.

| Package | Version |
| --- | --- |
| `com.google.android.gms` | 26.24.34 (`262434035`, build 260400-938041327) |
| `com.android.vending` | 52.0.22-31 |
| `app.grapheneos.gmscompat` | 1 |
| `com.google.android.gsf` | not installed |

Play services' contacts permissions are all denied at the runtime-permission
layer (`READ_CONTACTS`, `WRITE_CONTACTS`, `GET_ACCOUNTS`), but it reaches contacts
data through **Contact Scopes** — see the
[2026-08-11 incident](../incidents/2026-08-11-gms-contact-scopes-crash/), where
that path is the cause of the crash.

## GrapheneOS components installed

```
android.overlay.grapheneos              app.grapheneos.info
app.grapheneos.AppCompatConfig          app.grapheneos.logviewer
app.grapheneos.apps                     app.grapheneos.networklocation
app.grapheneos.backup.contacts          app.grapheneos.pdfviewer
app.grapheneos.camera                   app.grapheneos.setupwizard
app.grapheneos.carrierconfig2           app.grapheneos.speechservices
app.grapheneos.gmscompat                com.android.phone.overlay.grapheneos
app.grapheneos.gmscompat.config         com.android.providers.telephony.overlay.grapheneos
app.grapheneos.gmscompat.lib
```

## Notes for future debugging

- The contacts and call-log providers run in **`android.process.acore`**. When an
  app crashes on a contacts query, that process holds the real stack — the
  crashing app only ever sees a rethrown copy.
- GrapheneOS routes contacts access for scoped apps through
  `RedirectedContentProvider` → `ScopedContactsProvider` → `ContactsProvider2`.
  Seeing `ScopedContactsProvider` in a stack means Contact Scopes is active for
  whichever app made the call.
- Per-app GrapheneOS state (Contact Scopes, Storage Scopes, per-app exploit
  protection toggles) lives in `/data/system/` and is **not** readable over ADB
  and not exposed through `dumpsys`. Read it in the Settings UI.
- The modem logs under the `SHANNON_IMS` tag; useful for signal and IMS
  questions, noisy otherwise.
