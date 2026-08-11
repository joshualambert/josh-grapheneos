# Play services crashes on every incoming call

| | |
| --- | --- |
| **Date opened** | 2026-08-11 |
| **Reported symptom** | "Google Play services keeps stopping" dialog on every incoming call |
| **Status** | Root-caused. Fix identified, **not yet applied or verified** |
| **Component** | GrapheneOS Contact Scopes (`ScopedContactsProvider`) × sandboxed Google Play |
| **Impact** | Cosmetic dialog + Google contact photo sync silently broken. No effect on the call itself |
| **Owner** | Josh |

## Summary

The crash has nothing to do with telephony. An incoming call triggers a caller-ID
contact lookup, which wakes Play services' People contacts-sync path, which runs
`SyncHighResPhotoIntentOperation` to fetch the caller's high-resolution contact
photo. That operation queries the contacts provider with `photo_uri` in its
projection.

Because **Contact Scopes is enabled for Play services**, the query does not go
straight to `ContactsProvider2`. GrapheneOS redirects it through
`ScopedContactsProvider`, which rewrites the query so it only returns contacts in
the allowed scope, then forwards it. The rewritten query reaches
`ContactsProvider2` in a form where `photo_uri` is not a valid column for the
target projection map, and the provider rejects it:

```
java.lang.IllegalArgumentException: Invalid column photo_uri
```

Play services issues this query from a background executor and does not catch the
exception, so it propagates to the thread's uncaught handler and takes the whole
`com.google.android.gms` process down — which is the dialog.

This is a bug in the interaction between the two, and the scoped path is the part
that is wrong: the same query against the unscoped provider is valid. Play
services is guilty only of not catching a `ContentResolver` exception.

## Symptom

System dialog reading *"Google Play services keeps stopping"* every time a call
comes in. The call rings and connects normally.

## Evidence

Raw captures are in [`evidence/`](evidence/). Everything below is drawn from
them.

### It is not an occasional crash — it is the only crash

Of 98 fatal exceptions in the device's crash buffer (covering 2026-08-08 through
2026-08-11), **97 are this exact exception**, all in `com.google.android.gms`:

```
     97 java.lang.IllegalArgumentException: Invalid column photo_uri
      1 android.app.ForegroundServiceStartNotAllowedException  (unrelated, com.discord)
```

See [`00-device-snapshot.txt`](evidence/00-device-snapshot.txt).

### The client-side stack names the culprit

From [`01-fatal-crash-gms.log`](evidence/01-fatal-crash-gms.log):

```
FATAL EXCEPTION: [com.google.android.gms.chimera.container.intentoperation.GmsIntentOperationChimeraService-Executor] idle
Process: com.google.android.gms, PID: 1178
java.lang.IllegalArgumentException: Invalid column photo_uri
	at android.database.DatabaseUtils.readExceptionFromParcel(DatabaseUtils.java:207)
	at android.content.ContentProviderProxy.query(ContentProviderNative.java:497)
	at android.content.ContentProviderClient.query(ContentProviderClient.java:350)
	at fefz.b(:com.google.android.gms@262434035@26.24.34)
	at com.google.android.gms.people.sync.focus.SyncHighResPhotoIntentOperation.onHandleIntent(...)
	at com.google.android.chimera.IntentOperation.onHandleIntent(...)
	at java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1100)
	at java.lang.Thread.run(Thread.java:1572)
```

Two things to note. `readExceptionFromParcel` means the exception was *thrown on
the other side of a binder call* and rethrown here — the client stack tells us
who asked, not what failed. And the frame below `onHandleIntent` is
`ThreadPoolExecutor`, not a `Handler` — there is no `try`/`catch` between the
query and the top of the thread, which is why the process dies.

### The provider-side stack names the mechanism

From [`03-provider-side-stacks.log`](evidence/03-provider-side-stacks.log),
logged by pid 20252 (`android.process.acore`, the contacts provider):

```
E DatabaseUtils: Writing exception to parcel
E DatabaseUtils: java.lang.IllegalArgumentException: Invalid column photo_uri
	at com.android.providers.contacts.ContactsProvider2.doQuery(ContactsProvider2.java:8238)
	at com.android.providers.contacts.ContactsProvider2.queryLocal(ContactsProvider2.java:8181)
	at com.android.providers.contacts.ContactsProvider2.query(ContactsProvider2.java:6247)
	at com.android.providers.contacts.ScopedContactsProvider.queryFiltered(ScopedContactsProvider.java:205)   <-- Contact Scopes
	at com.android.providers.contacts.ScopedContactsProvider.queryInner(ScopedContactsProvider.java:113)
	at com.android.internal.app.RedirectedContentProvider.query(RedirectedContentProvider.java:41)
	at android.content.ContentProvider$Transport.query(ContentProvider.java:305)
	at android.os.Binder.execTransact(Binder.java:1364)
```

`RedirectedContentProvider` → `ScopedContactsProvider` → `ContactsProvider2` is
the Contact Scopes interception path. The query is being rewritten in
`queryFiltered` before it reaches the real provider, and it is the rewritten form
that `ContactsProvider2` rejects.

### The same subsystem also emits invalid SQL

A second, **non-fatal** failure comes out of the same `queryFiltered` frame. The
composed statement contains an empty parenthesised group:

```sql
SELECT _id FROM view_contacts
WHERE (((_id IN default_directory)))
  AND ((_id IN (966)) AND ())          -- <-- empty group
ORDER BY starred DESC, times_contacted DESC LIMIT 2000
```

```
E SQLiteLog: (1) near ")": syntax error
```

The `(<selection>) AND (<scope filter>)` shape is the scope-filter injection, and
the scope filter came out as the empty string. Play services *does* catch this
one — [`04-gms-caught-exception.log`](evidence/04-gms-caught-exception.log) shows
`DCU_CPHelper2: Caught exception thrown by the ContactsProvider` — so it produces
no dialog. It does mean contacts sync is failing quietly as well as loudly.

### Correlation with incoming calls

Crashes arrive in clusters of 2–6, one to two seconds apart, consistent with the
intent operation being retried and re-crashing. The clusters line up with call
activity — for the 13:29 cluster:

```
13:29:26.572  com.google.android.gms  FATAL EXCEPTION  Invalid column photo_uri
13:29:27.656  com.google.android.gms  FATAL EXCEPTION  Invalid column photo_uri
13:30:28.364  am_pss: [5292,10121,com.android.incallui,...]
13:30:29.385  Telecom: MissedCallNotifierImpl: sendNotificationThroughDefaultDialer
```

Full cluster list in [`02-crash-timeline.log`](evidence/02-crash-timeline.log);
44 clusters across four days.

### Contact Scopes is on for Play services

Indirect but conclusive. Play services' contacts permissions are all **denied**:

```
android.permission.READ_CONTACTS:  granted=false
android.permission.WRITE_CONTACTS: granted=false
android.permission.GET_ACCOUNTS:   granted=false
```

Yet its queries reach `ContactsProvider2` and execute real SQL against the
contacts database. That combination — runtime permission denied, access granted
anyway through `ScopedContactsProvider` — is exactly what Contact Scopes does. A
plain denial would have produced a `SecurityException` at the permission check
and never reached `queryFiltered`.

This cannot be confirmed over ADB; GrapheneOS keeps per-app scope assignments in
`/data/system/`, which the `shell` user cannot read, and exposes no `dumpsys`
output or `cmd package` verb for it. It has to be read in the Settings UI.

## Root cause

`ScopedContactsProvider.queryFiltered` produces a query that `ContactsProvider2`
will not accept, in two distinct ways:

1. It preserves the caller's projection (`photo_uri`) while retargeting the query
   such that `photo_uri` is no longer in the applicable projection map →
   `IllegalArgumentException`. **This is the fatal one.**
2. It composes `(<caller selection>) AND (<scope filter>)` without guarding
   against an empty scope filter, emitting `AND ()` → SQLite syntax error.
   Non-fatal, caught by the caller.

Play services turns (1) into a visible crash rather than a failed sync because it
runs the query on a bare executor thread with no exception handling.

## Fix

**Disable Contact Scopes for Play services**, so its contacts queries take the
ordinary permission path instead of the broken scoped one.

On the phone:

**Settings → Apps → Google Play services → Permissions → Contacts →** select
**Don't allow**. If it currently reads *Contact Scopes* or shows a chosen-contacts
count, that is the confirmation the diagnosis above needs.

Or jump straight there:

```bash
adb shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS \
  -d package:com.google.android.gms
```

### Why this and not something else

- Contacts permissions are **already denied**, so the scopes are granting access
  the ordinary permission state says Play services should not have. Turning them
  off gives up nothing that was intentionally granted.
- Play services handles a clean permission denial correctly — it is only the
  scoped path that crashes it. `DCU_CPHelper2` catching the SQL error shows the
  error handling exists; the photo-sync path just misses it.
- Granting **full** Contacts access would also stop the crash by avoiding the
  scoped path, but hands Google the entire address book. Strictly worse.
- Clearing GMS data or reinstalling will not help; nothing about the GMS-side
  state is wrong.

### Trade-off

Google-side contact photo sync stays broken — but it is already broken, failing
on every attempt for at least four days. The change converts a loud failure into
a silent one and stops the dialogs.

## Verification

The crash is triggered by an inbound call, so it has to be reproduced
deliberately:

1. `scripts/collect-snapshot.sh` and note the crash count.
2. Apply the fix above.
3. `adb logcat -b crash -c` to clear the crash buffer.
4. `scripts/watch-gms-crashes.sh`.
5. Place a call to the phone from another line. Let it ring, answer, hang up.
6. Expect **no** output from the watcher and no dialog.

Record the result in the status table at the top of this file.

## Follow-up

- [ ] Apply the fix and run the verification above
- [ ] Check whether other apps have Contact Scopes enabled; the defect is in the
      scoped provider, not in Play services, so any scoped app querying
      `photo_uri` is exposed to the same crash
- [ ] Report upstream to GrapheneOS. Both defects are in
      `ScopedContactsProvider.queryFiltered`, are reproducible from the log
      evidence here, and the empty-`AND ()` one in particular looks like a
      trivially fixable guard

## References

- Crash signature: `IllegalArgumentException: Invalid column photo_uri`
- GMS component: `com.google.android.gms.people.sync.focus.SyncHighResPhotoIntentOperation`
- OS component: `com.android.providers.contacts.ScopedContactsProvider` (`queryFiltered`, line 205)
- Play services 26.24.34 (`262434035`), GrapheneOS build `2026080501`, Android 17
