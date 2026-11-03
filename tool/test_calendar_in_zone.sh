#!/usr/bin/env bash
# Runs flutter test in the time zone its first two arguments name: with TZ
# set to the IANA name where the platform reads zone names from TZ (macOS,
# Linux), and on Windows, whose TZ variable takes no zone names, with the
# system zone switched to the Windows zone id and restored on exit.
#
# Usage: bash tool/test_calendar_in_zone.sh <IANA zone> <Windows zone id>
#          [flutter test arguments]
# With no flutter test arguments it runs test/scheduling and test/calendar.
set -u

if [ "$#" -lt 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: bash tool/test_calendar_in_zone.sh <IANA zone>" \
    "<Windows zone id> [flutter test arguments]" >&2
  exit 64
fi
iana="$1"
windows="$2"
shift 2

if [ "$#" -eq 0 ]; then
  set -- test/scheduling test/calendar
fi

if ! command -v tzutil >/dev/null 2>&1; then
  TZ="$iana" exec flutter test "$@"
fi

# Git Bash rewrites an argument such as /g into a path unless told not to.
before="$(MSYS_NO_PATHCONV=1 tzutil /g)"
if [ -z "$before" ]; then
  echo "tzutil /g printed no zone" >&2
  exit 1
fi

# One run at a time holds the system zone, whichever zone it switches to:
# a second run would record the first one's zone as the one to restore.
# mkdir fails where the directory exists, so only one run creates it.
lock="${TMPDIR:-/tmp}/test_calendar_in_zone.lock"
if ! mkdir "$lock" 2>/dev/null; then
  held="$(cat "$lock/zone" 2>/dev/null)"
  echo "Another run of this script holds the system zone, or one ended" \
    "without restoring it; the zone before it was \"${held:-unknown}\"." \
    "Wait for that run, or restore that zone with" \
    "MSYS_NO_PATHCONV=1 tzutil /s \"<zone id>\" and remove $lock." >&2
  exit 1
fi
printf "%s\n" "$before" >"$lock/zone"

restore() {
  MSYS_NO_PATHCONV=1 tzutil /s "$before"
  rm -rf "$lock"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP

# A zone left switched by a run that could not restore it, such as one
# whose shell was killed, would otherwise be restored to itself.
if [ "$before" = "$windows" ]; then
  echo "The system zone is already $windows: a run of this script ended" \
    "without restoring it, or it is your own zone. Restore your zone with" \
    "MSYS_NO_PATHCONV=1 tzutil /s \"<zone id>\", or where $windows is your" \
    "own zone, run flutter test directly." >&2
  exit 1
fi

# The C runtime reads TZ in place of the system zone when it is set.
unset TZ
MSYS_NO_PATHCONV=1 tzutil /s "$windows" || exit 1
flutter test "$@"
status=$?
exit "$status"
