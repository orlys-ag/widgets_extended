#!/usr/bin/env bash
# Runs flutter test in America/Santiago, whose clock repeats its last hour,
# going back from 24:00 to 23:00, on 2026-04-04 and skips its midnight hour
# on 2026-09-06, the days the calendar's late-repeat tests need, through
# tool/test_calendar_in_zone.sh: on Windows by switching the system zone to
# Pacific SA Standard Time until it exits.
#
# Usage: bash tool/test_calendar_in_santiago.sh [flutter test arguments]
# With no arguments it runs test/calendar.
exec bash "$(dirname "$0")/test_calendar_in_zone.sh" America/Santiago \
  "Pacific SA Standard Time" "$@"
