#!/usr/bin/env bash
# Runs flutter test in a time zone whose clock skips its midnight hour on
# 2026-03-08 and repeats it on 2026-11-01, the days the calendar's midnight
# tests need: with TZ=America/Havana where the platform reads zone names from
# TZ (macOS, Linux), and on Windows, whose TZ variable takes no zone names,
# with the system zone switched to Cuba Standard Time and restored on exit.
#
# Usage: bash tool/test_calendar_in_havana.sh [flutter test arguments]
# With no arguments it runs test/calendar.
set -u

if [ "$#" -eq 0 ]; then
  set -- test/calendar
fi

if ! command -v tzutil >/dev/null 2>&1; then
  TZ=America/Havana exec flutter test "$@"
fi

# Git Bash rewrites an argument such as /g into a path unless told not to.
before="$(MSYS_NO_PATHCONV=1 tzutil /g)"
if [ -z "$before" ]; then
  echo "tzutil /g printed no zone" >&2
  exit 1
fi
# A second run started while the first holds the zone would restore Cuba
# Standard Time on exit, after the first restored the real zone.
if [ "$before" = "Cuba Standard Time" ]; then
  echo "The system zone is already Cuba Standard Time: another run of this" \
    "script holds it, or one ended without restoring it. Wait for that run," \
    "or restore your zone with MSYS_NO_PATHCONV=1 tzutil /s \"<zone id>\"." >&2
  exit 1
fi

restore() {
  MSYS_NO_PATHCONV=1 tzutil /s "$before"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP

# The C runtime reads TZ in place of the system zone when it is set.
unset TZ
MSYS_NO_PATHCONV=1 tzutil /s "Cuba Standard Time" || exit 1
flutter test "$@"
status=$?
exit "$status"
