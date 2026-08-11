#!/usr/bin/env bash
# Capture a point-in-time snapshot of the device's identity, build and GMS state.
# Usage: scripts/collect-snapshot.sh [output-file]
#
# Note: no `set -e` here on purpose. Most steps are greps that legitimately
# return non-zero when a package is absent or the crash buffer is empty, and an
# incomplete snapshot is far more useful than an aborted one.
set -uo pipefail

OUT="${1:-docs/device-snapshot-$(date +%Y-%m-%d).txt}"
mkdir -p "$(dirname "$OUT")"

if ! adb get-state >/dev/null 2>&1; then
  echo "No device in 'device' state. Check 'adb devices'." >&2
  exit 1
fi

# adb shell output is CRLF-terminated; strip it everywhere.
sh_() { adb shell "$@" 2>/dev/null | tr -d '\r'; }

{
  echo "# Device snapshot — $(date -Iseconds)"
  echo

  echo "## Device"
  for p in ro.product.model ro.product.device ro.build.version.release \
           ro.build.display.id ro.build.version.security_patch \
           ro.build.version.sdk ro.build.type; do
    printf '%-38s %s\n' "$p" "$(sh_ getprop "$p")"
  done
  echo

  echo "## GrapheneOS / GmsCompat packages"
  sh_ pm list packages | grep -E 'grapheneos|gmscompat' | sort
  echo

  echo "## Sandboxed Google Play components"
  for pkg in com.google.android.gms com.android.vending com.google.android.gsf \
             app.grapheneos.gmscompat; do
    ver=$(sh_ dumpsys package "$pkg" | grep -m1 'versionName=' | sed 's/^ *//')
    printf '%-32s %s\n' "$pkg" "${ver:-<not installed>}"
  done
  echo

  echo "## GMS contacts-related permission state"
  sh_ dumpsys package com.google.android.gms \
    | grep -E 'READ_CONTACTS|WRITE_CONTACTS|GET_ACCOUNTS' \
    | grep 'granted=' | sed 's/^ *//'
  echo

  echo "## Contacts provider process"
  sh_ ps -A | grep -E 'android.process.acore|providers.contacts'
  echo

  echo "## Crash buffer summary (by process)"
  adb logcat -b crash -d 2>/dev/null | tr -d '\r' \
    | grep 'Process:' | sed 's/.*Process: //;s/, PID.*//' | sort | uniq -c | sort -rn
  echo

  echo "## Crash buffer summary (by exception)"
  adb logcat -b crash -d 2>/dev/null | tr -d '\r' \
    | grep -E 'E AndroidRuntime: (java|android)\.' \
    | sed 's/.*AndroidRuntime: //' | sort | uniq -c | sort -rn
} > "$OUT"

echo "Wrote $OUT"
