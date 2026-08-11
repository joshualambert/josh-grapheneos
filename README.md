# josh-grapheneos

Maintenance notes, incident logs and tooling for my GrapheneOS device.

This repo is the running record of *what went wrong, what I changed, and why* on
the phone. It is deliberately low-tech: markdown notes plus a couple of shell
scripts that wrap `adb`. There is nothing to build or install.

## Device

Pixel 10 Pro (`blazer`), GrapheneOS on Android 17. Full detail and how to
refresh it: [`docs/device-profile.md`](docs/device-profile.md).

## Layout

| Path | What lives there |
| --- | --- |
| `docs/device-profile.md` | Hardware, build, installed GrapheneOS/GMS components |
| `docs/adb-runbook.md` | How to connect and pull diagnostics — start here |
| `docs/known-issues.md` | Standing issues and their current status |
| `incidents/` | One directory per investigation, with raw evidence |
| `scripts/` | `adb` wrappers used by the runbook |

## Incidents

| Date | Incident | Status |
| --- | --- | --- |
| 2026-08-11 | [Play services crashes on every incoming call](incidents/2026-08-11-gms-contact-scopes-crash/) | Root-caused, fix pending verification |

## Conventions

Incident directories are named `YYYY-MM-DD-short-slug` and always contain a
`README.md` (the writeup) plus an `evidence/` directory holding the raw logs the
conclusions were drawn from. Evidence is committed verbatim so a claim can be
re-checked later — logcat buffers are circular and roll off after a few days, so
if it is not captured here it is gone.

**Before committing evidence, check it for personal data.** Logcat can contain
phone numbers, email addresses, account names and contact records. Stack traces
generally do not, but full buffer dumps do. Scan with:

```bash
grep -nEo '[0-9]{3}[-.]?[0-9]{3}[-.]?[0-9]{4}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
  incidents/*/evidence/*
```

Redact anything real before it lands in a commit — rewriting git history after
the fact is much more annoying than not committing it.
