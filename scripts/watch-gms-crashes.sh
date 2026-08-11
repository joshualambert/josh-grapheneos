#!/usr/bin/env bash
# Live-tail the crash buffer and print a line each time Play services dies.
# Use this to reproduce on demand: start it, then place a call to the phone.
# Ctrl-C to stop.
set -uo pipefail

echo "Watching for com.google.android.gms crashes. Place a test call now. Ctrl-C to stop."
adb logcat -b crash -v threadtime \
  | grep --line-buffered -E 'FATAL EXCEPTION|Process: |^.*(java|android)\.[a-z].*Exception' \
  | grep --line-buffered -vE '^\s*at '
