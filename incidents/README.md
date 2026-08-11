# Incidents

One directory per investigation, named `YYYY-MM-DD-short-slug`.

## Index

| Date | Incident | Status |
| --- | --- | --- |
| 2026-08-11 | [Play services crashes on every incoming call](2026-08-11-gms-contact-scopes-crash/) | Root-caused, fix pending verification |

## Structure

```
YYYY-MM-DD-slug/
├── README.md      the writeup
└── evidence/      raw logs the writeup cites
```

Number evidence files in the order the argument uses them
(`00-device-snapshot.txt`, `01-fatal-crash-*.log`, …) so a reader can follow
along top to bottom.

## Writing one

Keep the writeup arranged so the conclusion is reachable without reading the
logs, and the logs are there when someone doubts the conclusion:

- **Header table** — date, symptom, status, component, impact
- **Summary** — what is actually happening, in a paragraph
- **Symptom** — what was observed, in the reporter's terms
- **Evidence** — the chain, each step quoting the capture it comes from
- **Root cause** — the defect, stated precisely
- **Fix** — what to change, *and why that one* over the alternatives considered
- **Verification** — the steps to prove it worked, runnable by someone else
- **Follow-up** — checkboxes for what is left

State plainly what is inferred rather than directly observed. The 2026-08-11
incident could not read Contact Scopes state over ADB and says so, rather than
presenting the inference as a measurement.

## Capturing evidence

`adb logcat` buffers are circular and hold roughly three days here. Capture the
same day. See [`../docs/adb-runbook.md`](../docs/adb-runbook.md).

**Check captures for personal data before committing** — see the note in the
[root README](../README.md).
