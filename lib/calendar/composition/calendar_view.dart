/// The calendar: its four views composed under a header and the folding
/// calendar card, the controller a host sets and listens to, and what a
/// tap on an entry reports.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_builders.dart';
import '../presentation/calendar_day_badges.dart';
import '../presentation/calendar_theme.dart';
import '../views/create_details.dart';
import '../views/day_list.dart';
import '../views/month_board.dart';
import '../views/month_picker.dart';
import '../views/month_strip.dart' show monthFoldDay;
import '../views/move_request.dart';
import '../views/pinch_zoom.dart' as pinch;
import '../views/timed_grid.dart';
import 'calendar_card.dart';
import 'calendar_header.dart';
import 'calendar_theme_extension.dart';

part 'calendar_controller.dart';

/// A range of days, both inclusive.
typedef _Range = ({DateTime first, DateTime last});

/// The error a [CalendarView] given [views] throws from its build: for an
/// empty list, and for a list that names a view twice, the first view it
/// names twice; null for a list that names each of its views once.
ArgumentError? calendarViewsError(List<CalendarViewKind> views) {
  if (views.isEmpty) {
    return ArgumentError.value(views, "views", "lists no view");
  }
  final seen = <CalendarViewKind>{};
  for (final view in views) {
    if (!seen.add(view)) {
      return ArgumentError.value(views, "views", "lists ${view.name} twice");
    }
  }
  return null;
}

/// The view a calendar listing [views] shows for [requested]: [requested]
/// where [views] lists it, and otherwise the first view [views] lists.
CalendarViewKind calendarOpeningView(
  List<CalendarViewKind> views,
  CalendarViewKind? requested,
) {
  if (requested != null && views.contains(requested)) {
    return requested;
  }
  return views.first;
}

/// A tap on an entry: the [entry] as the store holds it, and whether it is
/// [editable], in edit mode with [CalendarView.editPolicy] letting it be
/// edited ([CalendarEditPolicy.mayEdit]).
@immutable
final class CalendarEntryTapDetails<T> {
  /// A tap on [entry], [editable] or not.
  const CalendarEntryTapDetails({required this.entry, required this.editable});

  /// The stored entry, without a pending move's requested time.
  final CalendarEntry<T> entry;

  /// Whether a host's form may change the entry: the calendar is
  /// [CalendarView.editable] and its [CalendarView.editPolicy] lets the
  /// entry be edited ([CalendarEditPolicy.mayEdit]).
  final bool editable;
}

/// A calendar of [store]'s entries in the views [views] lists, under a
/// header that names the month and switches between them.
///
/// The views:
///
/// - Agenda: the calendar card's month over a list of the days, one after
///   another, each day's entries beside their times and lengths. The month
///   is a `MonthStrip` under the weekdays' abbreviations, one month at
///   a time, each day a cell with its number on a circle and badges when
///   it has entries, one for each kind [dayBadges] gives them. A tap
///   selects a day, and the arrow keys move the selection once a tap has
///   given the month focus. A horizontal drag
///   slides the next or the previous month in, the card's height
///   following, a fling carrying it past several months; the chevrons
///   slide it a month at a time. None of them selects: the header names
///   the month the card shows, and [CalendarController.goTo] of the
///   selected day brings it back. The list runs both ways from the
///   selected day: a selected day scrolls to its top, and a drag or a
///   fling of the list selects each day it brings to the top, its header
///   sticking while its entries scroll under it. An entry wholly outside
///   the store's hours shows only in a count on a notice banner. A line
///   marks the current time over the rows of the clock's day. In edit mode
///   the list marks each gap in the hours with a dashed row whose button
///   reports a create through [onCreateRange], marking the row until the
///   create's future completes or a later create moves the mark, and each
///   card's builder receives the [CalendarCardDetails.onEdit] and
///   [CalendarCardDetails.onDelete]
///   [editPolicy] allows ([CalendarEditPolicy.mayEdit],
///   [CalendarEditPolicy.mayDelete]), which report through [onEditRequest] and
///   [onDeleteRequest]; the default card offers neither. A
///   drag of the list folds the month into the week of the selected day,
///   and the pull tab under the card folds or unfolds it as far as a drag
///   on it moves, a tap on it switching; a downward drag on the folded
///   strip unfolds it too. Once folded the week strip takes its place,
///   opening on that week.
/// - Day: the calendar card over a timed grid of the selected day, with no
///   day header, whose blocks show their times and summaries. The card
///   folds and unfolds as in Agenda, a drag up the grid folding it; folded,
///   its week strip is a week's worth of days whose days a tap selects and
///   which a drag slides day by day without selecting, the header naming
///   the month of the day at its middle.
/// - Week: a timed grid of the selected day's week under the header's
///   card, its days in columns under a day header whose tap selects a day.
/// - Month: the month's weeks under the header's card, each entry a chip
///   on the days it covers, from its start's day to the last day it has a
///   part in, the weeks laid out as [monthLayout] says. A
///   tap on a chip reports the entry, and a tap anywhere else on a day
///   opens that day in Day where [views] lists Day, and otherwise selects
///   it. In edit mode a long press on a day reports a create through
///   [onCreateRange] at the day's first slot from the earliest start
///   [editPolicy] gives it ([CalendarEditPolicy.earliestStartOn]) that no
///   entry shares, or, where [CalendarEditPolicy.allowsOverlaps] is false
///   and none is, at the first whose sharing entries
///   [CalendarEditPolicy.mayOverlap] all lets the create share. Where
///   neither is left it reports one at the day's first slot from that
///   start, over an entry, which may be one the policy refuses, and marks
///   the day until the create's future completes or a later create moves
///   the mark. It selects the day when it is in the month; or, where that
///   start leaves no slot of the store's hours that day whose start and
///   end the day's clock both read, as where the clock skips the start or
///   the end of each, it reports [onCreateRefused] and marks nothing.
///
/// The calendar card opens on its month, in every view. A change of view,
/// whether a menu pick, the view shown picked again, a set of
/// [CalendarController.view], new [views] or a tap on a day in Month,
/// leaves the card and the month picker as they are: Agenda and Day show
/// the card folded or not as it was, on the month a chevron or a slide
/// moved it to and with its strip on the days a drag moved it to; Week and
/// Month, which show no card, show the selected day's week or month,
/// which the header names, and leave the card waiting for Agenda or Day.
/// An open month picker stays open on its year.
///
/// An entry runs from its start to its end ([CalendarEntry]): Week and Day
/// draw a timed entry as one block per shown day it covers, at its exact
/// minutes, and an all-day entry as a bar across those days in a strip
/// above the hours, and Agenda lists it under each day it covers with that
/// day's part of it. In Week and Day a tap on a block or a bar, and in
/// Month on a chip, reports the stored entry through [onEntryTap]. In edit
/// mode, which [editable] turns on, Week's and Day's blocks move, keeping
/// the entry's length and its kind, and resize, a bar dropped on a slot
/// makes its entry a timed one, an hour long there, and a block dropped on
/// a day of the strip makes its entry all-day on that day; in Week bars
/// move and resize by days. Each
/// move and resize lands as a [CalendarMoveRequest], which [onMoveRequest]
/// receives, or with none [store] writes ([CalendarStore.requestMove]). A
/// drag over empty slots reports one continuous range through
/// [onCreateRange], across days too, and one over the strip's empty days an
/// all-day range of them, which stays marked until its future completes.
/// Out of edit mode the calendar is read-only. In
/// edit mode [editPolicy] limits what the gestures change and where a new
/// entry may start ([CalendarEditPolicy]). A pinch of two
/// fingers on Week's, Day's or Month's grid sets the controller's zoom
/// sizes. A selected day is always on a weekday [weekdays] shows. Every
/// view rings today's number.
///
/// The header's chevrons step a day in Day, a week in Week and in folded
/// Agenda, and a month in unfolded Agenda and in Month. A tap on the
/// title opens the month picker until the title is tapped again: in
/// Agenda's and Day's card it fades in over the days, the card's height
/// moving from theirs to its; in Week and Month it fades in
/// under the header as the header's card grows to hold it. While it shows,
/// the title names its year, and the chevrons or a swipe across it step a
/// year; a month picked selects its day of the selected day's day of the
/// month, as a month step does. The header's Today button shows while a
/// tap on it would change the day the calendar shows: while the selected
/// day is not the shown day nearest today, which it selects, or the card
/// or the strip has moved off the selected day, which it brings back; the
/// month picker alone does not show it, and a tap closes the picker. Its
/// edit mode toggle, where [onEditableChanged] is given, reports the
/// opposite of [editable], and its view button, the icon of the view shown,
/// opens the view menu. [headerBuilder] builds the header in place of the built-in
/// one, and [showsHeader] false builds none, nor in Week and Month the
/// header's card. The built-in header puts a transparent [Material] above
/// itself where none is above, and its view menu needs
/// [MaterialLocalizations] above the calendar.
///
/// [controller] holds the view and the selected day, which the host sets
/// and listens to, the range of days the calendar asks [store] to show,
/// and the zoom sizes; with none the calendar makes its own. A store shows
/// one range at a time, so it serves one calendar: two calendars on one
/// store each move it off the other's range when they ask, and the one
/// whose range it does not show draws its views ready only where the
/// store has read their days, until its own next ask.
///
/// The calendar opens no route, dialog or form but the built-in header's
/// view menu, builds no `Scaffold` or app bar, and never writes [store]'s
/// settings. It shows and schedules in the store's hours
/// ([CalendarStore.hours]), and builds again when a set of them notifies.
/// It draws on its store's zone ([CalendarStore.zone]): every view files,
/// places and labels the entries on the zone's clock, the clock is read on
/// it, and each day the calendar holds or hands out, the selected day, the
/// visible range's days and the days the builders' details name included,
/// is the start of a date on it, a `TZDateTime` of the zone typed
/// [DateTime], as are a create range's times. A store with no zone draws on
/// the device's clock. A notify that brings another zone keeps the
/// selected date and Week's and Day's scroll position, moves today to the
/// new clock's date, ends the drags in flight, writing nothing, and moves
/// the entries as any store change does, over the views' motion. Over a
/// [CachingCalendarStore] they move so only where the store kept the shown
/// days read across the change, which a [CachingCalendarStore.readAhead]
/// of 2 does once the store's reads have answered, so a host whose users
/// switch zones over one sets it to 2; otherwise the views draw the
/// loading state over the days the new zone's re-read has not answered.
/// It disposes no store. It draws in the [CalendarTheme]
/// above it; with none, under a Material [Theme], in a
/// [CalendarThemeExtension] of the [ThemeData], or with none the theme
/// [CalendarThemeExtension.fromColorScheme] gives the [ColorScheme]; and
/// with no [Theme] either, in the built-in theme. Under a [Theme] with no
/// [Material] above, it builds a transparent one under it, which sets the
/// theme's `bodyMedium` as the text style the views draw over. The card's
/// fold and the month picker move over the theme's motion.
///
/// [views] lists the views the header's menu offers, in its order; a list
/// that is empty or names a view twice throws an [ArgumentError] from the
/// build, in a release build as in a debug one.
///
/// [slotMinutes] is the slot of Week's and Day's grids, one row each, the
/// step their gestures snap to, the length of the slot Agenda's add button
/// and Month's long press create, and the grid those round the earliest
/// start [editPolicy] gives a day up to
/// ([CalendarEditPolicy.earliestStartOn]). The views show and schedule in
/// the store's hours as they are, which a host puts on that grid
/// ([CalendarDayHours.roundedOutTo]). The build throws an [ArgumentError],
/// in every build, after the one for [views]: for a [slotMinutes] that
/// [CalendarDates.slotMinuteChoices] does not hold; then for store hours
/// off its grid ([CalendarDayHours.isOnSlotsOf]), named `store.hours`, in
/// the build after a set of them too; and then for an [editPolicy] whose
/// [CalendarEditPolicy.dayLimit] is under 1, named `policy`; and then for
/// a [bottomPadding] that is negative or not finite. The next build that
/// throws none of them builds the views anew.
class CalendarView<T> extends StatefulWidget {
  /// A calendar of [store]'s entries in the views [views] lists.
  const CalendarView({
    super.key,
    required this.store,
    this.controller,
    this.views = CalendarViewKind.values,
    this.editable = false,
    this.onEditableChanged,
    this.editPolicy,
    this.weekdays = CalendarWeekdaySet.all,
    this.slotMinutes = CalendarDates.defaultSlotMinutes,
    this.hourLabelFormat = CalendarHourLabelFormat.twentyFourHour,
    this.monthLayout = CalendarMonthLayout.fitScreen,
    this.clock,
    this.today,
    this.blockBuilder,
    this.chipBuilder,
    this.cardBuilder,
    this.cardExtentOf,
    this.addButtonBuilder,
    this.loadingBuilder,
    this.failureBuilder,
    this.entryKindOf,
    this.dayBadges,
    this.onEntryTap,
    this.onCreateRange,
    this.onMoveRequest,
    this.onEditRequest,
    this.onDeleteRequest,
    this.onCreateRefused,
    this.showsHeader = true,
    this.headerBuilder,
    this.bottomPadding = 0.0,
  });

  /// The entries the calendar shows and its views write, and the hours it
  /// shows and schedules in ([CalendarStore.hours]). The calendar asks it
  /// to show the range of days its view shows, and never disposes it. The
  /// calendar draws on its zone ([CalendarStore.zone]), the device's clock
  /// where it has none.
  final CalendarStore<T> store;

  /// Holds the view, the selected day, the visible range and the zoom
  /// sizes; null for a controller of the calendar's own. A controller
  /// serves one calendar at a time. One whose view [views] does not list
  /// fails an assertion in a debug build, and shows the first view [views]
  /// lists.
  final CalendarController? controller;

  /// The views the header's menu offers, in its order, each once; the
  /// calendar opens on the first unless [controller] names another. With
  /// one, the built-in header has no view button.
  final List<CalendarViewKind> views;

  /// Whether the calendar is in edit mode: Week's and Day's blocks move
  /// and resize, a create gesture reports through [onCreateRange], and
  /// Agenda's card builder receives the edit and delete requests, as
  /// [editPolicy] allows. Out of it the calendar reads [editPolicy]'s
  /// [CalendarEditPolicy.dayLimit] and [CalendarEditPolicy.allowsOverlaps]
  /// when it takes a policy, and asks it nothing else.
  final bool editable;

  /// A tap on the built-in header's edit mode toggle, with the mode it
  /// asks for, the opposite of [editable], which the host shows by setting
  /// [editable]; null builds no toggle. A custom header receives it as
  /// [CalendarHeaderDetails.onEditableChanged].
  final ValueChanged<bool>? onEditableChanged;

  /// What may change in edit mode, and where a new entry may start
  /// ([CalendarEditPolicy]): Week's and Day's moves, resizes and creates,
  /// Agenda's edit and delete requests and add buttons, Month's long
  /// press, and a tap's [CalendarEntryTapDetails.editable]; null for an
  /// [UnrestrictedEditPolicy]. The calendar asks it at the minute [clock]
  /// reads and the day it marks as today ([CalendarNow]).
  ///
  /// Its [CalendarEditPolicy.dayLimit] is the most days, counting each day
  /// it has any part of, that a create drag across days in Week, over the
  /// slots or across the all-day strip, a strip bar's day-edge resize, and
  /// Week's end handle dragged into a later day may give a range: one
  /// dragged past them is held at the latest range they admit, which a
  /// release requests or reports. A move keeps the days an entry covers,
  /// except where it crosses a midnight, and no limit applies to it. A
  /// policy whose limit is under 1 throws an [ArgumentError] from the
  /// build, in every build, in every view and out of edit mode too.
  ///
  /// Its [CalendarEditPolicy.allowsOverlaps] decides whether Week's and
  /// Day's moves, resizes and creates may give an entry times another
  /// entry shares: where it is true they go over other entries' times as
  /// over free ones, the blocks sharing a day's time side by side; where
  /// it is false none gives times that another timed entry shares unless
  /// [CalendarEditPolicy.mayOverlap] lets the change share them. A move
  /// dropped where the policy refuses lands at the nearest time whose
  /// sharing entries the policy all allows, or where
  /// [CalendarEditPolicy.refusesEveryOverlap] is true at the nearest time
  /// no other entry's block covers, or goes back; and a resize it refuses
  /// stops at the first entry in its way that the policy refuses. A move or
  /// a resize asks about the times it would give, with the stored entry, a
  /// slot press about the slot's times, with no entry, and a create drag about
  /// the range a release would report, with no entry, at each change of the
  /// slot under the pointer, at a store notify and at a new minute; a refusal
  /// holds the range short of the refused entry nearest the slot it started on,
  /// or to that slot alone where the entry shares its time. Agenda's add
  /// buttons create at the first slot free of every entry where it is true, and
  /// where it is false at the first slot no entry shares, or where none does,
  /// the first sharing time only with entries [CalendarEditPolicy.mayOverlap]
  /// lets the create share; Month's long press does too where such a slot is
  /// left. The calendar checks no write of the host's, and [store] refuses none
  /// for sharing time: a host whose data forbids it refuses the write in its
  /// data source.
  ///
  /// A policy not `==` to the last one given cancels a move or a resize in
  /// flight, which then requests nothing, and ends a create range in flight,
  /// which then creates nothing: a host passes a policy whose class defines
  /// value equality, or the same instance in each build.
  final CalendarEditPolicy<T>? editPolicy;

  /// The weekdays the calendar shows, and the one its weeks start on. A
  /// change moves a selected day it hides to the nearest shown one.
  final CalendarWeekdaySet weekdays;

  /// The length of one slot, in minutes: one of
  /// [CalendarDates.slotMinuteChoices], or the build throws an
  /// [ArgumentError], in every build. The store's hours start and end on
  /// its grid, or the build throws an [ArgumentError] naming
  /// `store.hours`.
  final int slotMinutes;

  /// The format the calendar writes times of day in: Week's and Day's
  /// hour labels and landing label, Agenda's times, Month's banners and
  /// chips, and the times the entry builders write
  /// ([CalendarBlockDetails.hourLabelFormat],
  /// [CalendarChipDetails.hourLabelFormat]).
  final CalendarHourLabelFormat hourLabelFormat;

  /// How Month lays out a week whose chips its share of the height does
  /// not hold.
  final CalendarMonthLayout monthLayout;

  /// Reads the current time, which the calendar reads when first built and
  /// again at the start of each minute; null reads [DateTime.now]. A
  /// reading is taken on the clock of [store]'s zone, the same instant, or
  /// with no zone as its local time, so the day it marks is that clock's.
  ///
  /// A new function is read at once, and the next minute is timed from
  /// its reading. The reading replaces the time the calendar holds where
  /// it marks another today, lies in another minute or gives another
  /// [CalendarNow.timeOnToday], so a closure written in the host's build,
  /// a new function at each build, does not give the views a new time at
  /// each build.
  final DateTime Function()? clock;

  /// The day the calendar marks as today and opens on, read by its year,
  /// month and day, so a UTC today names the same date, which the calendar
  /// takes on the clock of [store]'s zone; null marks the day [clock] reads
  /// on that clock, the local one with no zone, moving at its midnight.
  final DateTime? today;

  /// Draws Week's and Day's blocks; null for the module's default.
  final CalendarBlockBuilder<T>? blockBuilder;

  /// Draws Month's chips and cards, and the bars of Week's and Day's
  /// all-day strip; null for the module's default.
  final CalendarChipBuilder<T>? chipBuilder;

  /// Draws Agenda's cards; null for the module's default.
  final CalendarCardBuilder<T>? cardBuilder;

  /// The height of [cardBuilder]'s card of an entry; null for the default
  /// card's.
  final double Function(CalendarShownEntry<T> entry)? cardExtentOf;

  /// Draws Agenda's add buttons; null for the module's default.
  final CalendarAddButtonBuilder? addButtonBuilder;

  /// Draws the views' loading states; null for the module's default.
  final CalendarLoadingBuilder? loadingBuilder;

  /// Draws the views' failure states; null for the module's default.
  final CalendarFailureBuilder? failureBuilder;

  /// The word naming an entry's kind in what a screen reader hears for its
  /// chip in Month; null leaves it out.
  final String? Function(CalendarEntry<T> entry)? entryKindOf;

  /// The kinds of entry the badges on the days of Agenda's and Day's
  /// calendar card mark, a dot for each kind a day has; null for one dot
  /// in the theme's primary colour on a day with entries.
  final CalendarDayBadges<T>? dayBadges;

  /// A tap on a block or a bar in Week or Day, or on a chip in Month, of an
  /// entry that is not pending and that the store holds; null reports
  /// nothing.
  final ValueChanged<CalendarEntryTapDetails<T>>? onEntryTap;

  /// A create the calendar's gestures picked, in edit mode, as a
  /// [CalendarCreateDetails]: its range, the range a gesture picked in Week
  /// or Day, a gap's first free slot in Agenda, the add button's, and a
  /// day's first free slot in Month, a long press's; where its mark is on
  /// screen when it is reported, in global logical pixels
  /// ([CalendarCreateDetails.globalRect]); and whether the user chose its
  /// length ([CalendarCreateDetails.userChoseLength]), which only a drag in
  /// Week or Day does. The view marks the create, Week and Day its range,
  /// Agenda the gap's row and Month the day, until the future completes or
  /// fails, unless a later create in that view has moved the mark. Null
  /// reports nothing, and the mark clears at once. A failure of the
  /// function, whether it throws within the call or its future fails, is
  /// not caught: a host that handles one passes a function that does.
  final Future<void> Function(CalendarCreateDetails details)? onCreateRange;

  /// A move or a resize the gestures landed in Week or Day, in edit mode,
  /// whose entry shows at the requested times, pending, until the future
  /// completes; the host writes it, or another entry in its place, to
  /// [store] ([CalendarStore.requestMove]), or lets it go. Null writes it
  /// to [store] and catches the write's failure, as a failed write shows
  /// the stored entry again; a host that wants to see failures passes its
  /// own function. Only the grid that made the request holds it: another
  /// view, or a grid built anew as a switch between Week and Day builds
  /// one, shows the store's entry meanwhile. A failure of the function,
  /// whether it throws within the call or its future fails, is not caught:
  /// a host that handles one passes a function that does.
  final Future<void> Function(CalendarMoveRequest<T> request)? onMoveRequest;

  /// An edit request from an Agenda card, with the stored entry: a
  /// [cardBuilder] calling [CalendarCardDetails.onEdit] makes it; null
  /// reports nothing.
  final ValueChanged<CalendarEntry<T>>? onEditRequest;

  /// A delete request from an Agenda card, with the stored entry: a
  /// [cardBuilder] calling [CalendarCardDetails.onDelete] makes it; null
  /// reports nothing. The calendar deletes nothing itself.
  final ValueChanged<CalendarEntry<T>>? onDeleteRequest;

  /// Month's long press, in edit mode, on a day where the earliest start
  /// [editPolicy] gives it ([CalendarEditPolicy.earliestStartOn]) leaves no
  /// slot of the store's hours whose start and end the day's clock both
  /// read, as where the clock skips the start or the end of each; null
  /// reports nothing.
  final ValueChanged<DateTime>? onCreateRefused;

  /// Whether the calendar builds a header; false builds none, whatever
  /// [headerBuilder], and in Week and Month no header card.
  final bool showsHeader;

  /// Builds the header in the built-in one's place, from what it shows and
  /// the actions it calls; null for [defaultCalendarHeaderBuilder]. A throw
  /// in it costs the header alone.
  final CalendarHeaderBuilder? headerBuilder;

  /// The room the calendar keeps at its bottom, in logical pixels, past
  /// the bottom inset of its [MediaQuery] ([MediaQuery.paddingOf]), which
  /// it keeps too: room for what a host lays over the calendar's bottom
  /// edge, such as a floating action button. Week's and Day's grid
  /// scrolls its last slot up past both, or where its slots stretch to
  /// its height ends them above both, and keeps the row counting the
  /// entries after the hours above both; Month's weeks share the height
  /// above both, which stays empty. Agenda's list, which runs on past
  /// every day it shows, lets its rows pass under them. Under Week's,
  /// Day's and Month's grids the [MediaQuery] reports no bottom inset, so
  /// a builder there pads by none again.
  final double bottomPadding;

  @override
  State<CalendarView<T>> createState() {
    return _CalendarViewState<T>();
  }
}

class _CalendarViewState<T> extends State<CalendarView<T>>
    with TickerProviderStateMixin {
  /// The host's controller, or one of this state's own, which [dispose]
  /// disposes. The view and the selected day live on it alone.
  late CalendarController _controller;
  late bool _ownsController;

  /// The views the state works from: [CalendarView.views], unmodifiable,
  /// or every view while [_viewsError] stands.
  List<CalendarViewKind> _views = CalendarViewKind.values;

  /// What [calendarViewsError] answers for [CalendarView.views], which the
  /// build throws.
  ArgumentError? _viewsError;

  /// The error the build throws for a [CalendarView.slotMinutes] that
  /// [CalendarDates.slotMinuteChoices] does not hold, or null.
  ArgumentError? get _slotMinutesError {
    final slotMinutes = widget.slotMinutes;
    if (CalendarDates.slotMinuteChoices.contains(slotMinutes)) {
      return null;
    }
    return ArgumentError.value(
      slotMinutes,
      "slotMinutes",
      "is not one of ${CalendarDates.slotMinuteChoices}",
    );
  }

  /// The error the build throws for a [CalendarView.bottomPadding] that is
  /// negative or not finite, or null.
  ArgumentError? get _bottomPaddingError {
    final padding = widget.bottomPadding;
    if (padding >= 0.0 && padding < double.infinity) {
      return null;
    }
    return ArgumentError.value(
      padding,
      "bottomPadding",
      "is not non-negative and finite",
    );
  }

  /// The error the build throws for store hours ([CalendarStore.hours])
  /// off the grid of [CalendarView.slotMinutes], or null.
  ArgumentError? get _storeHoursError {
    final hours = widget.store.hours;
    if (hours.isOnSlotsOf(widget.slotMinutes)) {
      return null;
    }
    return ArgumentError.value(
      hours,
      "store.hours",
      "do not start and end on the grid of ${widget.slotMinutes}-minute "
          "slots",
    );
  }

  /// The hours the views show and schedule in: the store's
  /// ([CalendarStore.hours]), which a build past [_storeHoursError] has on
  /// the grid of [CalendarView.slotMinutes].
  CalendarDayHours get _hours {
    return widget.store.hours;
  }

  /// The store's hours as this state last took them, which
  /// [_handleStoreChange] compares a notify's hours with.
  late CalendarDayHours _storeHours;

  /// The store's zone as this state last took it ([_takeZone]), on whose
  /// clock every day the state holds or reports starts ([_dayIn]) and the
  /// clock is read ([_nowAt]); null for the device's.
  Location? _storeZone;

  /// The calendar's one clock: the time read at the start of each minute
  /// and the day marked as today, which the views follow and the policy
  /// is asked at ([_nowAt]).
  late final _CalendarNowNotifier _now;

  /// Fires at the start of the next minute, to read the clock again.
  Timer? _minuteTimer;

  /// The policy the calendar takes where [CalendarView.editPolicy] is null.
  late final UnrestrictedEditPolicy<T> _unrestricted =
      UnrestrictedEditPolicy<T>();

  CalendarEditPolicy<T> get _policy {
    return widget.editPolicy ?? _unrestricted;
  }

  /// The rules [_takeRules] last gave, made at its first call and at its
  /// first after a reassemble; a call that throws leaves them.
  CalendarEditRules<T>? _madeRules;

  /// Takes the rules the build checks and a create asks: [_policy] in
  /// [_hours] and slots of [CalendarView.slotMinutes], made again only for
  /// a policy not `==` to the last ([CalendarEditRules.updated]). Throws
  /// their [ArgumentError] for a policy whose day limit is under 1, or for
  /// hours off the grid between a set of them and the next build.
  CalendarEditRules<T> _takeRules() {
    final made = _madeRules;
    return _madeRules = made == null
        ? CalendarEditRules<T>(
            policy: _policy,
            hours: _hours,
            slotMinutes: widget.slotMinutes,
          )
        : made.updated(
            policy: _policy,
            hours: _hours,
            slotMinutes: widget.slotMinutes,
          );
  }

  /// A day of the month the calendar card shows and the header names
  /// since a slide of the month strip, a chevron or a drag of the week
  /// strip moved the card off the selected day's month or week: the first
  /// day of the month the month strip rests on, or the day at the middle
  /// of the week strip. Null while the card shows the selected day.
  DateTime? _browsedDay;

  /// Whether a drag of the week strip set [_browsedDay], which is then the
  /// day at the strip's middle, rather than a slide or a chevron. The
  /// strip a switch to Week or Month takes away comes back with that day
  /// at its middle. False once a fold short of the week ([_handleFold]) or
  /// new weekdays end that strip, as the next one opens on the week of
  /// [monthFoldDay].
  bool _browsedByStrip = false;

  /// The month grid of the selected day.
  late CalendarMonthGrid _grid;

  /// Whether the calendar card settles on its week strip rather than its
  /// month. Only Agenda and Day show the card; Week and Month keep it as
  /// it is for them.
  bool _collapsed = false;

  /// Whether the month picker shows, and the year it shows.
  bool _picksMonth = false;
  int _pickerYear = 0;

  /// Counts the calls that bring the week strip back to the selected day,
  /// which `WeekStrip.recalls` passes on.
  int _stripRecalls = 0;

  /// How far the calendar card has folded, 0 for the month and 1 for its
  /// week: linear, so a drag on the pull tab moves it with the finger.
  late final AnimationController _collapseController = AnimationController(
    vsync: this,
  );

  /// How far the month picker has come in, 0 for out and 1 for in.
  late final AnimationController _pickerShown = AnimationController(
    vsync: this,
  );

  /// Resolves the theme the state draws and animates its own parts with,
  /// and the one it puts above the views ([_resolveTheme]).
  final CalendarThemeResolver _themes = CalendarThemeResolver();

  /// The theme [_themes] last resolved.
  CalendarThemeData get _theme {
    return _themes.theme;
  }

  /// The key of the header, the cards and the views, under the optional
  /// [Material] and [CalendarTheme], so a resolve that adds or drops one
  /// keeps the views' state.
  final GlobalKey _contentKey = GlobalKey();

  /// The range this state last asked a store to show, and that store.
  _Range? _askedRange;
  CalendarStore<T>? _askedStore;

  /// Whether a lifecycle change left the store's range to ask after the
  /// frame.
  bool _askPending = false;

  CalendarViewKind get _view {
    return _controller._view!;
  }

  DateTime get _day {
    return _controller._selectedDay!;
  }

  DateTime Function() get _clock {
    return widget.clock ?? DateTime.now;
  }

  @override
  void initState() {
    super.initState();
    _takeViews();
    _storeZone = widget.store.zone;
    _now = _CalendarNowNotifier(_nowAt(_clock()));
    final host = widget.controller;
    _ownsController = host == null;
    _bind(host ?? CalendarController(), shown: null);
    _collapseController.addListener(_handleFold);
    _scheduleMinute(_now.value.time);
    _storeHours = widget.store.hours;
    // Before any view's, which the views build after this, so at a notify
    // a view that takes a new zone reads the clock this state retook.
    widget.store.addListener(_handleStoreChange);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTheme();
  }

  @override
  void reassemble() {
    _themes.reset();
    // A reload can change what a getter of the policy answers while the
    // policy stays `==` to itself, which [CalendarEditRules.updated] would
    // not read again.
    _madeRules = null;
    super.reassemble();
    _resolveTheme();
  }

  @override
  void didUpdateWidget(CalendarView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clock != oldWidget.clock) {
      _minuteTimer?.cancel();
      final next = _nowAt(_clock());
      if (!_readsAlike(next, _now.value)) {
        _now.value = next;
      }
      _scheduleMinute(next.time);
    } else if (widget.today != oldWidget.today) {
      _now.value = _nowAt(_now.value.time);
    }
    final viewsChanged = !listEquals(widget.views, oldWidget.views);
    if (viewsChanged) {
      _takeViews();
    }
    if (widget.controller != oldWidget.controller) {
      _swapController();
    }
    if (viewsChanged && !_views.contains(_view)) {
      _noteLifecycle();
      _writeView(
        _ownsController
            ? calendarOpeningView(_views, _view)
            : _listedView(_view),
      );
    }
    final weekdaysChanged = widget.weekdays != oldWidget.weekdays;
    if (weekdaysChanged) {
      _noteLifecycle();
      final day = CalendarDates.shownDayNear(_day, widget.weekdays);
      _controller._selectedDay = day;
      _grid = CalendarMonthGrid.of(day, weekdays: widget.weekdays);
      // The card keys its week strip by its weekdays, so a new strip opens.
      _browsedByStrip = false;
    }
    if (widget.store != oldWidget.store) {
      // Before the views' own updates, which run in the build after this.
      oldWidget.store.removeListener(_handleStoreChange);
      widget.store.addListener(_handleStoreChange);
      _storeHours = widget.store.hours;
      final zone = widget.store.zone;
      if (zone != _storeZone) {
        _takeZone(zone);
      }
    }
    if (viewsChanged || weekdaysChanged || widget.store != oldWidget.store) {
      _scheduleAsk();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChange);
    _minuteTimer?.cancel();
    _noteLifecycle();
    _controller._detach(this);
    if (_ownsController) {
      _controller.dispose();
    }
    _collapseController.dispose();
    _pickerShown.dispose();
    // The views listening to it have unmounted by now: an element's
    // children unmount before it does.
    _now.dispose();
    super.dispose();
  }

  /// Takes [CalendarView.views]: its error, and the list the state works
  /// from, the default list while the error stands, so the controller, the
  /// clock and the store's range stay those of the default list.
  void _takeViews() {
    final error = calendarViewsError(widget.views);
    _viewsError = error;
    if (error != null) {
      _views = CalendarViewKind.values;
    } else if (!listEquals(_views, widget.views)) {
      _views = List<CalendarViewKind>.unmodifiable(widget.views);
    }
  }

  /// Binds [controller] and applies its view and day, or where it names
  /// none, the view and day [shown] holds, and with nothing shown yet,
  /// the first listed view and today's nearest shown day. Writes the range
  /// this state last asked, which a controller swapped in reads at once,
  /// and asks the store for the range after the frame.
  void _bind(
    CalendarController controller, {
    required ({CalendarViewKind view, DateTime day})? shown,
  }) {
    if (!_ownsController) {
      controller._noteLifecycle();
    }
    controller._attach(this);
    _controller = controller;
    final named = controller._view;
    final CalendarViewKind view;
    if (named == null) {
      view = calendarOpeningView(_views, shown?.view);
    } else if (_ownsController) {
      view = calendarOpeningView(_views, named);
    } else {
      view = _listedView(named);
    }
    final day = CalendarDates.shownDayNear(
      _dayIn(controller._selectedDay ?? shown?.day ?? _now.value.today),
      widget.weekdays,
    );
    controller._visibleRange = _askedRange;
    if (shown == null) {
      controller._view = view;
      controller._selectedDay = day;
      _grid = CalendarMonthGrid.of(day, weekdays: widget.weekdays);
    } else {
      controller._view = shown.view;
      controller._selectedDay = shown.day;
      _writeDay(day);
      if (view != shown.view) {
        _writeView(view);
      }
    }
    _scheduleAsk();
  }

  /// Takes [CalendarView.controller] in place of the one bound: a new
  /// host's, or, where the host's went, one of this state's own holding
  /// what the host's held. Disposes a controller of this state's own that
  /// it replaces.
  void _swapController() {
    final old = _controller;
    final shown = (view: _view, day: _day);
    _noteLifecycle();
    old._detach(this);
    final host = widget.controller;
    final next = host ?? CalendarController._copyOf(old);
    if (_ownsController) {
      old.dispose();
    }
    _ownsController = host == null;
    _bind(next, shown: shown);
  }

  /// Switches to an own copy of [shared], which another state's bind took,
  /// holding what it holds; after the frame, where this state is still
  /// mounted, reports the shared controller in a debug build and builds
  /// again on the copy.
  void _takeCopyOf(CalendarController shared) {
    final copy = CalendarController._copyOf(shared);
    copy._binding = this;
    _controller = copy;
    _ownsController = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      assert(() {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError.fromParts(<DiagnosticsNode>[
              ErrorSummary(
                "A CalendarController was given to two "
                "CalendarViews.",
              ),
              ErrorDescription(
                "A controller serves one CalendarView at a time. It now "
                "serves the CalendarView built last, and the other one goes "
                "on with a copy of it that its host cannot reach.",
              ),
              ErrorHint("Give each CalendarView its own controller."),
            ]),
            library: "widgets_extended calendar",
          ),
        );
        return true;
      }());
      setState(() {});
    });
  }

  /// Notes, before a lifecycle change writes the host's controller, what
  /// its getters read, so it notifies once after the frame where they then
  /// read otherwise. A controller of this state's own has no listener
  /// outside it.
  void _noteLifecycle() {
    if (!_ownsController) {
      _controller._noteLifecycle();
    }
  }

  /// [view], where [_views] lists it; otherwise the first view [_views]
  /// lists, after a debug build reports a [FlutterError] naming both.
  /// Nothing is thrown, so a debug build goes on as a release build does.
  CalendarViewKind _listedView(CalendarViewKind view) {
    assert(() {
      if (!_views.contains(view)) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: FlutterError.fromParts(<DiagnosticsNode>[
              ErrorSummary(
                "A CalendarView's controller holds a view that "
                "its views do not list.",
              ),
              ErrorDescription(
                "The controller holds ${view.name}, and views lists "
                "${_views.map((kind) => kind.name).join(", ")}.",
              ),
              ErrorHint(
                "The CalendarView shows ${_views.first.name}, the first view "
                "views lists. Set the controller to a listed view before "
                "building the CalendarView with views that drop its view.",
              ),
            ]),
            library: "widgets_extended calendar",
          ),
        );
      }
      return true;
    }());
    return calendarOpeningView(_views, view);
  }

  /// Builds again where a notify of the store brings other hours, which
  /// the views take from this state's build, or another zone, which it
  /// takes first ([_takeZone]). The views follow the store's entries, load
  /// state and zone themselves, so any other notify builds nothing here.
  void _handleStoreChange() {
    final hours = widget.store.hours;
    final zone = widget.store.zone;
    if (hours == _storeHours && zone == _storeZone) {
      return;
    }
    if (zone != _storeZone) {
      _takeZone(zone);
    }
    setState(() {
      _storeHours = hours;
    });
  }

  /// Takes [zone], the store's new zone: keeps the selected date and the
  /// card's browsed one, each now the start of that date on the new clock
  /// ([_dayIn]); reads the held time on the new clock, which moves today
  /// to the new clock's date; and asks the store for the range after the
  /// frame. Its controller notifies once after the frame, as its selected
  /// day and range read otherwise ([_noteLifecycle]). The clock notifies
  /// whether or not the new reading is `==` to the old
  /// ([_CalendarNowNotifier.retake]), as [CalendarNow] compares instants,
  /// and two zones can read the same instants on different dates.
  void _takeZone(Location? zone) {
    _noteLifecycle();
    _storeZone = zone;
    _controller._selectedDay = _dayIn(_day);
    final browsed = _browsedDay;
    if (browsed != null) {
      _browsedDay = _dayIn(browsed);
    }
    _now.retake(_nowAt(CalendarDates.inZone(_now.value.time, zone: zone)));
    _scheduleAsk();
  }

  /// The start of [day]'s date, read by its year, month and day, on the
  /// clock of the store's zone: a `TZDateTime` of the zone, or a local
  /// midnight with none. Every day entering the state passes through it,
  /// so the days it holds compare with one another by `==`.
  DateTime _dayIn(DateTime day) {
    return CalendarDates.dateOfDayNumber(
      CalendarDates.dayNumber(day),
      zone: _storeZone,
    );
  }

  /// The clock reading [time] on the day the calendar marks as today:
  /// [CalendarView.today], or with none [time]'s day, both on the clock of
  /// the store's zone where it has one, and otherwise [time]'s local day.
  CalendarNow _nowAt(DateTime time) {
    final zone = _storeZone;
    if (zone == null) {
      return CalendarNow(time: time, today: widget.today ?? time.toLocal());
    }
    final zoned = CalendarDates.inZone(time, zone: zone);
    return CalendarNow(time: zoned, today: widget.today ?? zoned);
  }

  /// Whether [next], a reading of a new [CalendarView.clock], leaves
  /// [held], the time the calendar holds, current: it marks the same
  /// today, lies in the same minute and gives the same
  /// [CalendarNow.timeOnToday], which is all the views and the built-in
  /// policies read of a [CalendarNow]. A closure written in the host's
  /// build is a new function at each build; keeping [held] for its reading
  /// gives the views no new [CalendarNow] to ask the policy at.
  static bool _readsAlike(CalendarNow next, CalendarNow held) {
    return next.today == held.today &&
        next.timeOnToday == held.timeOnToday &&
        _minuteStartOf(next.time) == _minuteStartOf(held.time);
  }

  /// The instant [time]'s minute starts at: [time] less its seconds and
  /// their fractions.
  static DateTime _minuteStartOf(DateTime time) {
    return time.subtract(
      Duration(
        seconds: time.second,
        milliseconds: time.millisecond,
        microseconds: time.microsecond,
      ),
    );
  }

  /// Reads the clock again at the start of the minute after [now], and
  /// from then on at the start of each. The views follow [_now]
  /// themselves; a minute that marks another day as today builds this
  /// state again too, for the calendar card, its strips and the month
  /// picker, which take today as a value.
  void _scheduleMinute(DateTime now) {
    final intoMinute = Duration(
      seconds: now.second,
      milliseconds: now.millisecond,
      microseconds: now.microsecond,
    );
    _minuteTimer = Timer(const Duration(minutes: 1) - intoMinute, () {
      final last = _now.value;
      final next = _nowAt(_clock());
      _now.value = next;
      if (next.today != last.today) {
        setState(() {});
      }
      _scheduleMinute(next.time);
    });
  }

  /// Resolves the theme the views draw with, and whether a [Material] goes
  /// above them ([CalendarThemeResolver.resolve]). Sets the fold's and the
  /// picker's durations to the theme's.
  void _resolveTheme() {
    _themes.resolve(context);
    _collapseController.duration = _theme.motionDuration;
    _pickerShown.duration = _theme.motionDuration;
  }

  /// The range of days the calendar asks the store to show: the month
  /// grid's in Agenda and Month, the selected day's week in Week, and the
  /// shown days of that week in Day, so a step within it reads nothing.
  _Range _rangeOf() {
    final weekdays = widget.weekdays;
    switch (_view) {
      case CalendarViewKind.agenda:
      case CalendarViewKind.month:
        return (first: _dayIn(_grid.firstDay), last: _dayIn(_grid.lastDay));
      case CalendarViewKind.week:
        final first = weekdays.weekStartOf(_day);
        return (
          first: first,
          last: CalendarDates.addDays(first, DateTime.daysPerWeek - 1),
        );
      case CalendarViewKind.day:
        final days = CalendarDates.shownDaysOfWeek(_day, weekdays);
        return (first: days.first, last: days.last);
    }
  }

  /// Asks the store to show [_rangeOf], where the range moved or the
  /// store is new, writing the range to the controller first, so a store
  /// listener that moves the selection from inside the store's `show`
  /// writes the later range last.
  void _showRange() {
    final range = _rangeOf();
    final store = widget.store;
    if (range == _askedRange && identical(store, _askedStore)) {
      return;
    }
    _askedRange = range;
    _askedStore = store;
    _controller._visibleRange = range;
    store.show(range.first, range.last);
  }

  /// Asks the store for the range after the frame, when no build runs: a
  /// store notifies inside `show`, where a listener outside the element
  /// being built may not mark itself to build.
  void _scheduleAsk() {
    if (_askPending) {
      return;
    }
    _askPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _askPendingRange();
    });
  }

  /// The ask a lifecycle change left pending, which the controller's
  /// after-the-frame notify runs first, so its listeners read the range.
  /// A state unmounted meanwhile asks nothing.
  void _askPendingRange() {
    if (!_askPending || !mounted) {
      return;
    }
    _askPending = false;
    _showRange();
  }

  /// Runs an event's [change], asks the store for the range at once, and
  /// notifies the controller once where its view, selected day, range or
  /// [CalendarController.showsSelectedDay] changed.
  void _event(VoidCallback change) {
    final controller = _controller;
    final before = controller._observed;
    setState(change);
    _showRange();
    if (_controller._observed != before) {
      _controller._notifyEvent();
    }
  }

  /// Selects [day], a shown day, leaving the card's browse and moving the
  /// month grid to its month.
  void _writeDay(DateTime day) {
    if (day == _day) {
      return;
    }
    _controller._selectedDay = day;
    _browsedDay = null;
    if (!_grid.contains(day)) {
      _grid = CalendarMonthGrid.of(day, weekdays: widget.weekdays);
    }
  }

  /// Shows [view], leaving the calendar card's fold and browse and the
  /// month picker as they are.
  void _writeView(CalendarViewKind view) {
    _controller._view = view;
  }

  void _select(DateTime day) {
    final selected = _dayIn(day);
    if (selected == _day) {
      return;
    }
    _event(() {
      _writeDay(selected);
    });
  }

  /// A host's set of the selected day.
  void _selectDay(DateTime day) {
    _select(CalendarDates.shownDayNear(_dayIn(day), widget.weekdays));
  }

  /// A menu pick, a header's [CalendarHeaderDetails.onSelectView] or a
  /// host's set of the view: [view] must be listed. A pick of the view
  /// shown changes nothing, and so notifies nothing.
  void _selectView(CalendarViewKind view) {
    assert(
      _views.contains(view),
      "CalendarView lists ${_views.map((kind) => kind.name).join(", ")}, "
      "not ${view.name}.",
    );
    _event(() {
      _writeView(calendarOpeningView(_views, view));
    });
  }

  /// A host's goTo, one event: closes the month picker; then where [day]'s
  /// nearest shown day is selected, brings the card or the strip a drag or
  /// a chevron moved back to it, and otherwise selects it.
  void _goTo(DateTime day) {
    final target = CalendarDates.shownDayNear(_dayIn(day), widget.weekdays);
    final closesPicker = _picksMonth;
    final browsed = _browsedDay != null;
    if (!closesPicker && !browsed && target == _day) {
      return;
    }
    _event(() {
      _picksMonth = false;
      if (target != _day) {
        _writeDay(target);
      } else if (browsed) {
        _browsedDay = null;
        _stripRecalls++;
      }
    });
    if (closesPicker) {
      _pickerShown.animateTo(0.0, curve: _theme.motionCurve);
    }
  }

  /// Month's tap on [day]: opens it in Day where [_views] lists Day, with
  /// one notify, and otherwise selects it.
  void _openDay(DateTime day) {
    if (!_views.contains(CalendarViewKind.day)) {
      _select(day);
      return;
    }
    final opened = _dayIn(day);
    _event(() {
      _writeDay(opened);
      _writeView(CalendarViewKind.day);
    });
  }

  /// The first day of the month the calendar card shows.
  DateTime get _cardMonth {
    final day = _browsedDay ?? _day;
    return DateTime(day.year, day.month);
  }

  /// Moves the calendar card to the month of [day], selecting nothing.
  void _browse(DateTime day) {
    _event(() {
      _browsedDay = _dayIn(DateTime(day.year, day.month));
      _browsedByStrip = false;
    });
  }

  /// Notes [day], which a drag brought to the week strip's middle.
  void _browseStrip(DateTime day) {
    _event(() {
      _browsedDay = _dayIn(day);
      _browsedByStrip = true;
    });
  }

  /// Ends a strip browse once the fold leaves the week: [CalendarCard]
  /// builds its `WeekStrip` only at a full fold, so the strip a drag moved
  /// is gone, and the one the card folds into next opens on the week of
  /// [monthFoldDay].
  void _handleFold() {
    if (_browsedByStrip && _collapseController.value < 1.0) {
      _event(() {
        _browsedByStrip = false;
      });
    }
  }

  /// [_browsedDay] where the view shows the calendar card, and null in
  /// Week and Month, which show the selected day's week or month while the
  /// card waits.
  DateTime? get _shownBrowse {
    return _showsCalendarCard ? _browsedDay : null;
  }

  /// [CalendarController.showsSelectedDay] of this calendar: false while
  /// the month picker shows.
  bool get _showsSelectedDay {
    return !_picksMonth && _browseHoldsSelectedDay;
  }

  /// Whether the calendar card or the week strip, as a slide, a chevron or
  /// a drag left it, holds the selected day, whether the month picker shows
  /// over it or not; true in Week and Month, which show no card.
  bool get _browseHoldsSelectedDay {
    final browsed = _shownBrowse;
    if (browsed == null) {
      return true;
    }
    final day = _day;
    if (!_collapsed) {
      return browsed.year == day.year && browsed.month == day.month;
    }
    final target = CalendarDates.dayNumber(day);
    return _stripDays(browsed).any((shown) {
      return CalendarDates.dayNumber(shown) == target;
    });
  }

  /// The shown days the folded card's week strip holds while [browsed] is
  /// [_browsedDay]: a week's count of them around [browsed], the day a
  /// drag brought to the strip's middle, the first half of the count
  /// before it, as `WeekStrip` finds its middle; or, where a slide or a
  /// chevron browsed the card, the shown days of the week the strip opens
  /// on ([monthFoldDay]).
  List<DateTime> _stripDays(DateTime browsed) {
    final weekdays = widget.weekdays;
    if (!_browsedByStrip) {
      return CalendarDates.shownDaysOfWeek(
        monthFoldDay(
          _cardMonth,
          selectedDay: _day,
          today: _now.value.today,
          weekdays: weekdays,
        ),
        weekdays,
      );
    }
    final count = weekdays.columns.length;
    var shown = browsed;
    for (var step = 0; step < count ~/ 2; step++) {
      shown = CalendarDates.nextShownDay(shown, -1, weekdays);
    }
    final days = <DateTime>[];
    for (var step = 0; step < count; step++) {
      days.add(shown);
      shown = CalendarDates.nextShownDay(shown, 1, weekdays);
    }
    return days;
  }

  CalendarStepUnit get _stepUnit {
    if (_picksMonth) {
      return CalendarStepUnit.year;
    }
    switch (_view) {
      case CalendarViewKind.agenda:
        return _collapsed ? CalendarStepUnit.week : CalendarStepUnit.month;
      case CalendarViewKind.month:
        return CalendarStepUnit.month;
      case CalendarViewKind.week:
        return CalendarStepUnit.week;
      case CalendarViewKind.day:
        return CalendarStepUnit.day;
    }
  }

  /// Steps by [_stepUnit] over the shown weekdays: a day step skips the
  /// hidden ones, and a month step keeps the day of the month where it can
  /// and takes the nearest shown day of that month where it lands on a
  /// hidden one. A year step moves the month picker alone, and a month step
  /// in Agenda the calendar card alone.
  void _step(int direction) {
    final weekdays = widget.weekdays;
    switch (_stepUnit) {
      case CalendarStepUnit.year:
        setState(() {
          _pickerYear += direction;
        });
      case CalendarStepUnit.day:
        _select(CalendarDates.nextShownDay(_day, direction, weekdays));
      case CalendarStepUnit.week:
        _select(CalendarDates.addDays(_day, DateTime.daysPerWeek * direction));
      case CalendarStepUnit.month:
        if (_view == CalendarViewKind.agenda) {
          _browse(CalendarDates.addMonths(_cardMonth, direction));
        } else {
          _select(
            CalendarDates.shownDayNear(
              CalendarDates.addMonths(_day, direction),
              weekdays,
            ),
          );
        }
    }
  }

  void _stepBack() {
    _step(-1);
  }

  void _stepOn() {
    _step(1);
  }

  void _openMonthPicker() {
    _event(() {
      _picksMonth = true;
      _pickerYear = _day.year;
    });
    _pickerShown.animateTo(1.0, curve: _theme.motionCurve);
  }

  void _closeMonthPicker() {
    _event(() {
      _picksMonth = false;
    });
    _pickerShown.animateTo(0.0, curve: _theme.motionCurve);
  }

  /// Selects the day of [month] a month step from the selected day would.
  /// The month picker stays open, filling [month].
  void _pickMonth(DateTime month) {
    final months = (month.year - _day.year) * 12 + month.month - _day.month;
    _select(
      CalendarDates.shownDayNear(
        CalendarDates.addMonths(_day, months),
        widget.weekdays,
      ),
    );
  }

  bool get _showsCalendarCard {
    return _view == CalendarViewKind.agenda || _view == CalendarViewKind.day;
  }

  void _setCollapsed(bool collapsed) {
    if (collapsed == _collapsed || !_showsCalendarCard) {
      return;
    }
    _settleCollapse(collapsed);
  }

  /// Folds or unfolds the calendar card from however far it has folded, a
  /// drag on the pull tab having moved it. Unfolding closes the month
  /// picker, and leaves a browse the month the card shows, which a later
  /// fold opens the strip on a week of.
  void _settleCollapse(bool collapsed) {
    if (collapsed != _collapsed || (!collapsed && _picksMonth)) {
      _event(() {
        _collapsed = collapsed;
        if (!collapsed) {
          _picksMonth = false;
          _browsedByStrip = false;
        }
      });
    }
    _collapseController.animateTo(
      _collapsed ? 1.0 : 0.0,
      curve: _theme.motionCurve,
    );
  }

  void _unfold() {
    _setCollapsed(false);
  }

  /// In Day, a drag that scrolls the grid's content up folds the month
  /// into its week, as a scroll of Agenda's list does.
  bool _handleGridScroll(ScrollNotification notification) {
    if (_view == CalendarViewKind.day &&
        notification.metrics.axis == Axis.vertical &&
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        (notification.scrollDelta ?? 0.0) > 0.0) {
      _setCollapsed(true);
    }
    return false;
  }

  /// A drag that moves the list's content up folds the month into its
  /// week; the list runs on both ways, so a downward drag on the folded
  /// strip unfolds it. Only drags count, so the scroll that brings a
  /// selected day to the list's top folds nothing. Overscroll counts as
  /// well.
  bool _handleListScroll(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    final double delta;
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      delta = notification.scrollDelta ?? 0.0;
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      delta = notification.overscroll;
    } else {
      return false;
    }
    if (delta > 0.0) {
      _setCollapsed(true);
    }
    return false;
  }

  /// A tap on the block or chip of [id]: reports the stored entry, and
  /// whether a form may change it, the choice between a form that edits
  /// and one that shows.
  void _openEntry(String id) {
    final onEntryTap = widget.onEntryTap;
    final entry = widget.store.storedEntry(id);
    if (onEntryTap == null || entry == null) {
      return;
    }
    onEntryTap(
      CalendarEntryTapDetails<T>(
        entry: entry,
        editable: widget.editable && _policy.mayEdit(entry, _now.value),
      ),
    );
  }

  /// [CalendarView.onCreateRange]'s future for [details], a throw within
  /// the call failing it, so a view that marks the create clears the mark.
  Future<void> _createRange(CalendarCreateDetails details) {
    final onCreateRange = widget.onCreateRange;
    if (onCreateRange == null) {
      return Future<void>.value();
    }
    return Future<void>.sync(() {
      return onCreateRange(details);
    });
  }

  void _requestEdit(String id) {
    final onEditRequest = widget.onEditRequest;
    final entry = widget.store.storedEntry(id);
    if (onEditRequest != null && entry != null) {
      onEditRequest(entry);
    }
  }

  void _requestDelete(String id) {
    final onDeleteRequest = widget.onDeleteRequest;
    final entry = widget.store.storedEntry(id);
    if (onDeleteRequest != null && entry != null) {
      onDeleteRequest(entry);
    }
  }

  /// [CalendarController.createOn]: a create on [day] as
  /// [_openCreateFlow] reports one, after the current time where [day] is
  /// today, with [_createRange]'s future, or null where it reports a
  /// refusal. It selects nothing and marks nothing.
  Future<void>? _createOnRequest(DateTime day, Rect globalRect) {
    return _openCreateFlow(_dayIn(day), globalRect, afterNow: true)?.done;
  }

  /// Month's long press on [day], whose cell lies at [globalRect],
  /// selecting it first when it is a day of the shown month; a day of
  /// another month leaves the selection and the month as they are. Returns
  /// what [_openCreateFlow] returns.
  ({DateTime start, Future<void> done})? _createOn(
    DateTime day,
    Rect globalRect,
  ) {
    if (_grid.contains(day)) {
      _select(day);
    }
    return _openCreateFlow(_dayIn(day), globalRect);
  }

  /// Reports a create on [day], from the earliest start [_policy] gives it
  /// ([CalendarEditPolicy.earliestStartOn]), at the slot
  /// [CalendarEditRules.firstSlot] gives over the entries the store shows
  /// on it: the first no entry shares, or, where [_policy]'s
  /// [CalendarEditPolicy.allowsOverlaps] is false and none is, the first
  /// sharing time only with entries its [CalendarEditPolicy.mayOverlap]
  /// allows; or where it gives none, at the first slot of the hours from
  /// that start, over an entry, refused or not, which asks [_policy]
  /// nothing. Each is a slot whose times the clock reads, in that start's
  /// occurrence where [day]'s clock repeats its time, so none starts before
  /// it. Where [afterNow] and [day] is today, the start is the later of
  /// that start and the current time ([CalendarNow.timeOnToday]). It takes
  /// [globalRect] as its rect and returns the start of the range it
  /// reports with [_createRange]'s future. Where it leaves no such slot in
  /// the hours, it reports [CalendarView.onCreateRefused] instead and
  /// returns null.
  ({DateTime start, Future<void> done})? _openCreateFlow(
    DateTime day,
    Rect globalRect, {
    bool afterNow = false,
  }) {
    final rules = _takeRules();
    final now = _now.value;
    var start = rules.earliestStartOn(day, now);
    final earliest = start.earliest;
    if (afterNow &&
        earliest != null &&
        CalendarDates.dayNumber(start.day) ==
            CalendarDates.dayNumber(now.today) &&
        earliest.isBefore(now.timeOnToday)) {
      start = CalendarEarliestStart(start.day, now.timeOnToday);
    }
    final shown = widget.store.entriesOn(day).map((shown) {
      return shown.entry;
    });
    final slot =
        rules.firstSlot(start, clearOf: shown) ?? rules.firstSlot(start);
    if (slot == null) {
      widget.onCreateRefused?.call(day);
      return null;
    }
    return (
      start: slot.start,
      done: _createRange(
        CalendarCreateDetails(
          range: CalendarCreateRange(start: slot.start, end: slot.end),
          globalRect: globalRect,
          userChoseLength: false,
        ),
      ),
    );
  }

  CalendarHeaderDetails _headerDetails() {
    return CalendarHeaderDetails(
      view: _view,
      views: _views,
      day: _shownBrowse ?? _day,
      pickerYear: _picksMonth ? _pickerYear : null,
      stepUnit: _stepUnit,
      onPrevious: _stepBack,
      onNext: _stepOn,
      onSelectView: _selectView,
      onOpenPicker: _openMonthPicker,
      onClosePicker: _closeMonthPicker,
      onToday: _goToToday,
      canGoToToday: _canGoToToday,
      editable: widget.editable,
      onEditableChanged: widget.onEditableChanged,
    );
  }

  /// The header's Today: [_goTo] of the day the calendar marks as today.
  void _goToToday() {
    _goTo(_now.value.today);
  }

  /// [CalendarHeaderDetails.canGoToToday]: whether the selected day is not
  /// the shown day nearest today, or the card or the strip has moved off
  /// it. The month picker counts for neither, as it changes no day.
  bool get _canGoToToday {
    if (!_browseHoldsSelectedDay) {
      return true;
    }
    final target = CalendarDates.shownDayNear(
      _dayIn(_now.value.today),
      widget.weekdays,
    );
    return CalendarDates.dayNumber(target) != CalendarDates.dayNumber(_day);
  }

  /// The header in its place, built in a [Builder] there, so a throw in
  /// [CalendarView.headerBuilder] builds an error widget in the header's
  /// place alone; null where [CalendarView.showsHeader] is false.
  Widget? _buildHeader() {
    if (!widget.showsHeader) {
      return null;
    }
    final details = _headerDetails();
    final builder = widget.headerBuilder ?? defaultCalendarHeaderBuilder;
    return Builder(
      builder: (context) {
        return builder(context, details);
      },
    );
  }

  /// The month picker, on [_pickerYear], filling the selected day's month
  /// and ringing today's.
  Widget _buildMonthPicker() {
    final today = _now.value.today;
    return MonthPicker(
      key: const ValueKey<String>("month-picker"),
      year: _pickerYear,
      selectedMonth: DateTime(_day.year, _day.month),
      currentMonth: DateTime(today.year, today.month),
      onSelectMonth: _pickMonth,
      onBrowse: (year) {
        setState(() {
          _pickerYear = year;
        });
      },
    );
  }

  Widget _buildCard(Widget? header) {
    return CalendarCard<T>(
      store: widget.store,
      month: _cardMonth,
      selectedDay: _day,
      today: _now.value.today,
      weekdays: widget.weekdays,
      stripRecalls: _stripRecalls,
      collapse: _collapseController,
      collapsed: _collapsed,
      pickerShown: _pickerShown,
      picksMonth: _picksMonth,
      header: header,
      buildPicker: _buildMonthPicker,
      onSelectDay: _select,
      onBrowseMonth: _browse,
      onBrowseStrip: _browseStrip,
      onSettle: _settleCollapse,
      onUnfold: _unfold,
      stripMiddleDay: _browsedByStrip ? _browsedDay : null,
      dayBadges: widget.dayBadges,
    );
  }

  Widget _buildHeaderCard(Widget? header) {
    if (header == null) {
      return const SizedBox.shrink();
    }
    return CalendarHeaderCard(
      header: header,
      pickerShown: _pickerShown,
      picksMonth: _picksMonth,
      buildPicker: _buildMonthPicker,
    );
  }

  /// The calendar card over the day list.
  Widget _buildAgenda(Widget? header) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 0.0),
          child: _buildCard(header),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleListScroll,
            child: DayList<T>(
              key: const ValueKey<String>("day-list"),
              store: widget.store,
              weekdays: widget.weekdays,
              format: widget.hourLabelFormat,
              hours: _hours,
              slotMinutes: widget.slotMinutes,
              editable: widget.editable,
              editPolicy: _policy,
              selectedDay: _day,
              now: _now,
              onTopDay: _select,
              onCreateRange: _createRange,
              onEdit: _requestEdit,
              onDelete: _requestDelete,
              cardBuilder: widget.cardBuilder,
              cardExtentOf: widget.cardExtentOf,
              addButtonBuilder: widget.addButtonBuilder,
              loadingBuilder: widget.loadingBuilder,
              failureBuilder: widget.failureBuilder,
            ),
          ),
        ),
      ],
    );
  }

  /// The room Week's, Day's and Month's grids keep at their bottom: the
  /// bottom inset of the calendar's [MediaQuery] and
  /// [CalendarView.bottomPadding].
  double get _bottomRoom {
    return MediaQuery.paddingOf(context).bottom + widget.bottomPadding;
  }

  /// [grid] under a [MediaQuery] with no bottom inset, which [_bottomRoom]
  /// has taken.
  Widget _withoutBottomInset(Widget grid) {
    return MediaQuery.removePadding(
      context: context,
      removeBottom: true,
      child: grid,
    );
  }

  /// The timed grid of the selected day's week in Week, under the header
  /// card, and of the selected day in Day, under the calendar card. The
  /// grid builds in a builder on the controller, which a pinch's zoom
  /// rebuilds alone.
  Widget _buildTimed(Widget? header) {
    final view = _view;
    final range = _rangeOf();
    final week = view == CalendarViewKind.week;
    final firstDay = week ? range.first : _day;
    final dayCount = week ? DateTime.daysPerWeek : 1;
    final controller = _controller;
    final bottomRoom = _bottomRoom;
    final key = ValueKey<(CalendarViewKind, bool)>((
      view,
      dayCount > 1 && widget.weekdays.columns.length > 1,
    ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (week)
          _buildHeaderCard(header)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
            child: _buildCard(header),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleGridScroll,
            child: _withoutBottomInset(
              ListenableBuilder(
                listenable: controller,
                builder: (context, child) {
                  return TimedGrid<T>(
                    // Each view builds its own grid, which opens scrolled to
                    // its opening time, and so does a week of one shown
                    // weekday, as a grid keeps one day column or more than
                    // one.
                    key: key,
                    store: widget.store,
                    firstDay: firstDay,
                    dayCount: dayCount,
                    selectedDay: _day,
                    now: _now,
                    onSelectDay: _select,
                    onOpenEntry: _openEntry,
                    onCreate: _createRange,
                    onMoveRequest: widget.onMoveRequest,
                    onZoom: (minSlotHeight, minDayWidth) {
                      controller.setZoom(
                        minSlotHeight: minSlotHeight,
                        minDayWidth: minDayWidth,
                      );
                    },
                    editable: widget.editable,
                    editPolicy: _policy,
                    weekdays: widget.weekdays,
                    hours: _hours,
                    slotMinutes: widget.slotMinutes,
                    hourLabelFormat: widget.hourLabelFormat,
                    minDayWidth: controller.minDayWidth,
                    minSlotHeight: controller.minSlotHeight,
                    storeRange: range,
                    // The week strip names Day's one day.
                    showsDayHeader: week,
                    blockBuilder: widget.blockBuilder,
                    chipBuilder: widget.chipBuilder,
                    loadingBuilder: widget.loadingBuilder,
                    failureBuilder: widget.failureBuilder,
                    bottomPadding: bottomRoom,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The header card, and under it, on the surface colour across the full
  /// width and down to the bottom, the weekday letters and the month
  /// board, which builds in a builder on the controller, which a pinch's
  /// zoom rebuilds alone.
  Widget _buildMonth(Widget? header) {
    final controller = _controller;
    final bottomRoom = _bottomRoom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeaderCard(header),
        Expanded(
          child: ColoredBox(
            color: _theme.surface,
            child: _withoutBottomInset(
              ListenableBuilder(
                listenable: controller,
                builder: (context, child) {
                  return MonthBoard<T>(
                    key: const ValueKey<String>("month-board"),
                    store: widget.store,
                    grid: _grid,
                    layout: widget.monthLayout,
                    minDayWidth: controller.minDayWidth,
                    weekScale: controller.monthWeekScale,
                    hours: _hours,
                    hourLabelFormat: widget.hourLabelFormat,
                    selectedDay: _day,
                    now: _now,
                    onSelectDay: _select,
                    onOpenDay: _openDay,
                    onCreateOnDay: widget.editable ? _createOn : null,
                    onOpenEntry: _openEntry,
                    onZoom: (weekScale, minDayWidth) {
                      controller.setZoom(
                        monthWeekScale: weekScale,
                        minDayWidth: minDayWidth,
                      );
                    },
                    chipBuilder: widget.chipBuilder,
                    loadingBuilder: widget.loadingBuilder,
                    failureBuilder: widget.failureBuilder,
                    entryKindOf: widget.entryKindOf,
                    bottomPadding: bottomRoom,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _viewsError;
    if (error != null) {
      throw error;
    }
    final slotError = _slotMinutesError;
    if (slotError != null) {
      throw slotError;
    }
    final hoursError = _storeHoursError;
    if (hoursError != null) {
      throw hoursError;
    }
    final paddingError = _bottomPaddingError;
    if (paddingError != null) {
      throw paddingError;
    }
    _takeRules();
    final header = _buildHeader();
    final Widget view;
    switch (_view) {
      case CalendarViewKind.agenda:
        view = _buildAgenda(header);
      case CalendarViewKind.day:
      case CalendarViewKind.week:
        view = _buildTimed(header);
      case CalendarViewKind.month:
        view = _buildMonth(header);
    }
    Widget content = KeyedSubtree(key: _contentKey, child: view);
    final inserted = _themes.inserted;
    if (inserted != null) {
      content = CalendarTheme(data: inserted, child: content);
    }
    if (_themes.hasTheme && !_themes.hasMaterial) {
      content = Material(type: MaterialType.transparency, child: content);
    }
    return content;
  }
}

/// [_CalendarViewState]'s clock: a listenable [CalendarNow] whose [value]
/// setter, as a [ValueNotifier]'s, notifies only for a value not `==` to
/// the one it holds, and whose [retake] replaces and notifies always.
final class _CalendarNowNotifier extends ChangeNotifier
    implements ValueListenable<CalendarNow> {
  _CalendarNowNotifier(this._value);

  CalendarNow _value;

  @override
  CalendarNow get value {
    return _value;
  }

  set value(CalendarNow next) {
    if (next == _value) {
      return;
    }
    _value = next;
    notifyListeners();
  }

  /// Takes [next] and notifies, `==` to the held value or not, as a new
  /// zone's reading of the same instants on other dates is.
  void retake(CalendarNow next) {
    _value = next;
    notifyListeners();
  }
}
