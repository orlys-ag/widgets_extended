#!/usr/bin/env bash
# Runs flutter test in America/Havana, whose clock skips its midnight hour
# on 2026-03-08 and repeats it on 2026-11-01, the days the calendar's
# midnight tests need, through tool/test_calendar_in_zone.sh: on Windows by
# switching the system zone to Cuba Standard Time until it exits.
#
# Usage: bash tool/test_calendar_in_havana.sh [flutter test arguments]
# With no arguments it runs test/calendar.
exec bash "$(dirname "$0")/test_calendar_in_zone.sh" America/Havana \
  "Cuba Standard Time" "$@"
