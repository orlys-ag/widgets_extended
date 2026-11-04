/// A calendar of a host's entries in Agenda, Day, Week and Month views:
/// [CalendarView] over a [CalendarStore], such as a [MemoryCalendarStore]
/// of the host's entries or a [CachingCalendarStore] reading and writing
/// through the host's [CalendarDataSource].
///
/// The calendar builds on the scheduling module,
/// `package:widgets_extended/scheduling/scheduling.dart`, and shows every
/// name that barrel shows.
///
/// Experimental: the calendar's API may change in any release, a patch
/// release included, until it is declared stable.
library;

export '../scheduling/scheduling.dart'
    show
        CachingCalendarStore,
        CalendarAllChanged,
        CalendarCreateRange,
        CalendarDataSource,
        CalendarDates,
        CalendarDayHours,
        CalendarDaysChanged,
        CalendarEarliestStart,
        CalendarEditPolicy,
        CalendarEditRules,
        CalendarEntry,
        CalendarEntryChanged,
        CalendarEntryPut,
        CalendarEntryRemoved,
        CalendarHourLabelFormat,
        CalendarHoursException,
        CalendarLoadStatus,
        CalendarMonthGrid,
        CalendarNow,
        CalendarOverlapCandidate,
        CalendarResizeEdges,
        CalendarShownEntry,
        CalendarSourceChange,
        CalendarStore,
        CalendarStoreException,
        CalendarWeekdaySet,
        CalendarWritePendingException,
        DayLimitPolicy,
        HistoryLockPolicy,
        MemoryCalendarStore,
        NoOverlapsPolicy,
        UnrestrictedEditPolicy,
        compareCalendarEntries;
export 'composition/calendar_header.dart'
    show
        CalendarHeaderBuilder,
        CalendarHeaderDetails,
        CalendarStepUnit,
        CalendarViewKind,
        defaultCalendarHeaderBuilder;
export 'composition/calendar_theme_extension.dart' show CalendarThemeExtension;
export 'composition/calendar_view.dart'
    show CalendarController, CalendarEntryTapDetails, CalendarView;
export 'presentation/calendar_activity_indicator.dart'
    show CalendarActivityIndicator;
export 'presentation/calendar_builders.dart'
    show
        CalendarAddButtonBuilder,
        CalendarAddButtonDetails,
        CalendarBlockBuilder,
        CalendarBlockDetails,
        CalendarCardBuilder,
        CalendarCardDetails,
        CalendarChipBuilder,
        CalendarChipDetails,
        CalendarFailureBuilder,
        CalendarFailureState,
        CalendarLoadingBuilder,
        CalendarLoadingState,
        CalendarStateSite,
        calendarCardStripExtent;
export 'presentation/calendar_day_badges.dart'
    show CalendarBadgeKind, CalendarDayBadges;
export 'presentation/calendar_defaults.dart'
    show
        defaultCalendarAddButtonBuilder,
        defaultCalendarBlockBuilder,
        defaultCalendarCardBuilder,
        defaultCalendarChipBuilder,
        defaultCalendarFailureBuilder,
        defaultCalendarLoadingBuilder;
export 'presentation/calendar_localizations.dart'
    show CalendarLocalizations, DefaultCalendarLocalizations;
export 'presentation/calendar_theme.dart' show CalendarTheme, CalendarThemeData;
export 'views/month_board.dart' show CalendarMonthLayout;
export 'views/move_request.dart' show CalendarMoveKind, CalendarMoveRequest;
