/// The scheduling core of a host's entries, without a widget: civil days on
/// the local wall clock ([CalendarDates], [CalendarWeekdaySet],
/// [CalendarDayHours], [CalendarMonthGrid]); [CalendarEntry], with the
/// host's payload, and the [CalendarDataSource] contract; the limits on
/// edits ([CalendarEditPolicy], [CalendarEditRules], [NoOverlapsPolicy]'s
/// overlap rule and [HistoryLockPolicy]); and a [CalendarStore], a
/// [MemoryCalendarStore] of the host's entries or a [CachingCalendarStore]
/// reading and writing through a [CalendarDataSource]. The calendar,
/// `CalendarView`, builds on it.
///
/// Experimental: the scheduling module's API may change in any release, a
/// patch release included, until it is declared stable.
library;

export 'dates/calendar_dates.dart'
    show
        CalendarDates,
        CalendarDayHours,
        CalendarHourLabelFormat,
        CalendarMonthGrid,
        CalendarWeekdaySet;
export 'entries/calendar_data_source.dart'
    show
        CalendarAllChanged,
        CalendarDataSource,
        CalendarDaysChanged,
        CalendarEntryPut,
        CalendarEntryRemoved,
        CalendarSourceChange;
export 'entries/calendar_entry.dart' show CalendarCreateRange, CalendarEntry;
export 'policy/edit_policy.dart'
    show
        CalendarEditPolicy,
        CalendarNow,
        CalendarOverlapCandidate,
        CalendarResizeEdges,
        DayLimitPolicy,
        NoOverlapsPolicy,
        UnrestrictedEditPolicy;
export 'policy/edit_rules.dart' show CalendarEarliestStart, CalendarEditRules;
export 'policy/history_lock_policy.dart' show HistoryLockPolicy;
export 'store/caching_calendar_store.dart' show CachingCalendarStore;
export 'store/calendar_store.dart'
    show
        CalendarHoursException,
        CalendarLoadStatus,
        CalendarShownEntry,
        CalendarStore,
        CalendarStoreException,
        CalendarWritePendingException,
        compareCalendarEntries;
export 'store/memory_calendar_store.dart'
    show CalendarEntryChanged, MemoryCalendarStore;
