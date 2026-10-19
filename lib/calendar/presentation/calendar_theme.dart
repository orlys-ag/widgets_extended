/// The calendar's theme: every colour, text style, motion and icon its
/// views draw, and the inherited widget that hands it down.
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The colours, text styles, motion and icons the calendar's views draw.
///
/// Every field is set: a parameter left out takes its built-in value, a
/// neutral light palette with the typography, motion and icons the views
/// are designed around, so `const CalendarThemeData()` is a whole theme.
///
/// The text styles are partial (`inherit: true`): a view merges each over
/// the ambient [DefaultTextStyle], as [Text] does, so the host's font and
/// the bold-text setting still apply. A text style's colour is not used:
/// the view draws the text in the colour field each style's doc names.
///
/// [entryTintOpacity], [pendingEntryOpacity] and [actionLabelStyle] are
/// read by the module's default builders: the tint they fill an entry's
/// box with, the opacity they draw a pending entry at, and the Retry of a
/// failed read.
///
/// [CalendarTheme] hands a theme down the tree, and [CalendarTheme.of]
/// reads it.
@immutable
class CalendarThemeData with Diagnosticable {
  /// Creates a theme; each parameter left out takes its built-in value.
  ///
  /// [todayRingWidth] must be zero or more, and [draggedBlockOpacity],
  /// [entryTintOpacity] and [pendingEntryOpacity] each from 0 to 1.
  /// [motionDuration] must be zero or more, and every text style
  /// must have `inherit: true`; [CalendarTheme.of] asserts those two in a
  /// debug build, since this constructor's asserts cannot read them.
  const CalendarThemeData({
    this.primary = _primary,
    this.onPrimary = _onPrimary,
    this.primaryTint = _primaryTint,
    this.background = _background,
    this.surface = _surface,
    this.outline = _outline,
    this.text = _text,
    this.textSecondary = _textSecondary,
    this.textMuted = _textMuted,
    this.error = _error,
    this.notice = _notice,
    this.noticeOutline = _noticeOutline,
    this.onNotice = _onNotice,
    this.todayRing = _todayRing,
    this.todayRingWidth = _todayRingWidth,
    this.draggedBlockOpacity = _draggedBlockOpacity,
    this.entryTintOpacity = _entryTintOpacity,
    this.pendingEntryOpacity = _pendingEntryOpacity,
    this.motionDuration = _motionDuration,
    this.motionCurve = _motionCurve,
    this.beforeHoursIcon = _beforeHoursIcon,
    this.afterHoursIcon = _afterHoursIcon,
    this.durationIcon = _durationIcon,
    this.entryMenuIcon = _entryMenuIcon,
    this.addEntryIcon = _addEntryIcon,
    this.hourLabelStyle = _hourLabelStyle,
    this.dayHeaderWeekdayStyle = _dayHeaderWeekdayStyle,
    this.dayHeaderNumberStyle = _dayHeaderNumberStyle,
    this.blockTitleStyle = _blockTitleStyle,
    this.blockSummaryStyle = _blockSummaryStyle,
    this.detailedBlockTitleStyle = _detailedBlockTitleStyle,
    this.detailedBlockDetailStyle = _detailedBlockDetailStyle,
    this.landingLabelStyle = _landingLabelStyle,
    this.badgeStyle = _badgeStyle,
    this.noticeStyle = _noticeStyle,
    this.messageStyle = _messageStyle,
    this.monthDayNumberStyle = _monthDayNumberStyle,
    this.monthDayNumberMarkedStyle = _monthDayNumberMarkedStyle,
    this.monthMoreStyle = _monthMoreStyle,
    this.chipTitleStyle = _chipTitleStyle,
    this.monthCardTitleStyle = _monthCardTitleStyle,
    this.monthCardTimeStyle = _monthCardTimeStyle,
    this.agendaHeaderTitleStyle = _agendaHeaderTitleStyle,
    this.agendaHeaderEmptyTitleStyle = _agendaHeaderEmptyTitleStyle,
    this.agendaHeaderCountStyle = _agendaHeaderCountStyle,
    this.agendaHeaderEmptyCountStyle = _agendaHeaderEmptyCountStyle,
    this.agendaTimeStyle = _agendaTimeStyle,
    this.entryCardTitleStyle = _entryCardTitleStyle,
    this.entryCardSummaryStyle = _entryCardSummaryStyle,
    this.dayNumberStyle = _dayNumberStyle,
    this.dayNumberMarkedStyle = _dayNumberMarkedStyle,
    this.stripWeekdayStyle = _stripWeekdayStyle,
    this.weekdayHeaderStyle = _weekdayHeaderStyle,
    this.weekdayLetterStyle = _weekdayLetterStyle,
    this.monthNameStyle = _monthNameStyle,
    this.monthNameMarkedStyle = _monthNameMarkedStyle,
    this.actionLabelStyle = _actionLabelStyle,
  }) : assert(todayRingWidth >= 0.0, "todayRingWidth must be zero or more."),
       assert(
         draggedBlockOpacity >= 0.0 && draggedBlockOpacity <= 1.0,
         "draggedBlockOpacity must be from 0 to 1.",
       ),
       assert(
         entryTintOpacity >= 0.0 && entryTintOpacity <= 1.0,
         "entryTintOpacity must be from 0 to 1.",
       ),
       assert(
         pendingEntryOpacity >= 0.0 && pendingEntryOpacity <= 1.0,
         "pendingEntryOpacity must be from 0 to 1.",
       );

  static const Color _primary = Color(0xFF3D4B5C);
  static const Color _onPrimary = Color(0xFFFEFEFE);
  static const Color _primaryTint = Color(0xFFE8EBEF);
  static const Color _background = Color(0xFFF3F4F6);
  static const Color _surface = Color(0xFFFCFCFC);
  static const Color _outline = Color(0xFFD3D7DD);
  static const Color _text = Color(0xFF1D2125);
  static const Color _textSecondary = Color(0xFF454B53);
  static const Color _textMuted = Color(0xFF5A6069);
  static const Color _error = Color(0xFFB42318);
  static const Color _notice = Color(0xFFFFF5D1);
  static const Color _noticeOutline = Color(0xFFE9D68C);
  static const Color _onNotice = Color(0xFF574400);
  static const Color _todayRing = Color(0xFF7A8899);
  static const double _todayRingWidth = 2.0;
  static const double _draggedBlockOpacity = 0.66;
  static const double _entryTintOpacity = 0.14;
  static const double _pendingEntryOpacity = 0.5;
  static const Duration _motionDuration = Duration(milliseconds: 300);
  static const Curve _motionCurve = Curves.fastOutSlowIn;

  // Code points of the MaterialIcons font, as the Material library's
  // `Icons` declares them, so the presentation layer needs no Material
  // import: keyboard_arrow_up, keyboard_arrow_down, hourglass_empty,
  // more_horiz and add.
  static const IconData _beforeHoursIcon = IconData(
    0xe356,
    fontFamily: "MaterialIcons",
  );
  static const IconData _afterHoursIcon = IconData(
    0xe353,
    fontFamily: "MaterialIcons",
  );
  static const IconData _durationIcon = IconData(
    0xe325,
    fontFamily: "MaterialIcons",
  );
  static const IconData _entryMenuIcon = IconData(
    0xe402,
    fontFamily: "MaterialIcons",
  );
  static const IconData _addEntryIcon = IconData(
    0xe047,
    fontFamily: "MaterialIcons",
  );

  static const TextStyle _hourLabelStyle = TextStyle(
    fontSize: 11.0,
    height: 1.0,
  );
  static const TextStyle _dayHeaderWeekdayStyle = TextStyle(fontSize: 11.0);
  static const TextStyle _dayHeaderNumberStyle = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _blockTitleStyle = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _blockSummaryStyle = TextStyle(fontSize: 10.0);
  static const TextStyle _detailedBlockTitleStyle = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _detailedBlockDetailStyle = TextStyle(fontSize: 12.0);
  static const TextStyle _landingLabelStyle = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _badgeStyle = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _noticeStyle = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _messageStyle = TextStyle();
  static const TextStyle _monthDayNumberStyle = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle _monthDayNumberMarkedStyle = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _monthMoreStyle = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _chipTitleStyle = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _monthCardTitleStyle = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _monthCardTimeStyle = TextStyle(fontSize: 11.0);
  static const TextStyle _agendaHeaderTitleStyle = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _agendaHeaderEmptyTitleStyle = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _agendaHeaderCountStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _agendaHeaderEmptyCountStyle = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _agendaTimeStyle = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _entryCardTitleStyle = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _entryCardSummaryStyle = TextStyle(fontSize: 14.0);
  static const TextStyle _dayNumberStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle _dayNumberMarkedStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _stripWeekdayStyle = TextStyle(
    fontSize: 12.0,
    height: 1.2,
  );
  static const TextStyle _weekdayHeaderStyle = TextStyle(fontSize: 12.0);
  static const TextStyle _weekdayLetterStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _monthNameStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle _monthNameMarkedStyle = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle _actionLabelStyle = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
  );

  /// The accent: a selected day's fill and badge, Month's selected pill, the
  /// month picker's selected pill, today's number and current month, the
  /// landing pill, the edge of the move and create marks, the selection
  /// outline and grips, the text and icon of the hidden-days pill and the
  /// duration chip, the add icon and the default add button's icon, the
  /// activity indicator, and the Retry label.
  final Color primary;

  /// Text drawn on [primary] and on [error].
  final Color onPrimary;

  /// A light form of [primary]: a selected day header, today's column and
  /// the marked slots, the hidden-days pill, the duration chip and the add
  /// button.
  final Color primaryTint;

  /// Weekend columns, Month's days of other months, a day's circle, the
  /// month picker's pills, Agenda's header band, and the loading scrim,
  /// drawn at an alpha of 0.85.
  final Color background;

  /// The timed grid's body, header and gutter cells, the ring of a grip and
  /// of a badge, and the entry card's menu; the default entries' tints
  /// blend into it.
  final Color surface;

  /// The grid lines of Week, Day and Month, and Agenda's dashed gaps.
  final Color outline;

  /// Titles, the numbers of the shown month, and weekday letters.
  final Color text;

  /// Hour labels, the weekday of a day header, summaries and details,
  /// Agenda's start times and counts, and the arrows of a cut block.
  final Color textSecondary;

  /// Weekday names over the strip and over Agenda's month, the numbers of
  /// other months, an empty day's header, gap times, and the entry card's
  /// menu icon.
  final Color textMuted;

  /// The current-time line and pill, and a failed read's message.
  final Color error;

  /// The fill of the rows, banners and strips that count entries outside
  /// the hours, and of Month's "+N more".
  final Color notice;

  /// The edges of those rows and banners.
  final Color noticeOutline;

  /// The text and arrows on [notice].
  final Color onNotice;

  /// The ring around today's number and around the current month.
  final Color todayRing;

  /// The width of the ring around today's number and the current month, in
  /// logical pixels of the ringed box's own space; zero or more.
  final double todayRingWidth;

  /// The opacity of the block a move leaves behind on the timed grid, from
  /// 0 to 1: the board's `BoardDragConfig.draggedItemOpacity`.
  final double draggedBlockOpacity;

  /// The opacity of an entry's colour in the tint the default builders
  /// fill its box with, blended over [surface]; from 0 to 1.
  final double entryTintOpacity;

  /// The opacity the default builders draw a pending entry at; from 0 to
  /// 1.
  final double pendingEntryOpacity;

  /// How long each animation the views run takes; zero or more. Zero turns
  /// the views' motion off: every change shows at once, and the activity
  /// indicator stands still.
  final Duration motionDuration;

  /// The curve each animation the views run eases on.
  final Curve motionCurve;

  /// The arrow marking the top of a block cut by the start of the hours, a
  /// row or banner of entries before the hours.
  final IconData beforeHoursIcon;

  /// The arrow marking the bottom of a block cut by the end of the hours, a
  /// row or banner of entries after the hours.
  final IconData afterHoursIcon;

  /// The icon before an entry's length on Agenda's duration chip.
  final IconData durationIcon;

  /// The icon of an entry card's menu.
  final IconData entryMenuIcon;

  /// The icon of the button that adds an entry in a gap.
  final IconData addEntryIcon;

  /// The hour labels in Week's and Day's gutter. Its colour is not used:
  /// they draw in [textSecondary].
  final TextStyle hourLabelStyle;

  /// A day header's weekday. Its colour is not used: it draws in
  /// [textSecondary].
  final TextStyle dayHeaderWeekdayStyle;

  /// A day header's number. Its colour is not used: it draws in [primary]
  /// on today, and in [text] otherwise.
  final TextStyle dayHeaderNumberStyle;

  /// A block's title on a timed grid of several days. Its colour is not
  /// used: it draws in [text].
  final TextStyle blockTitleStyle;

  /// The first summary of a block on a timed grid of several days. Its
  /// colour is not used: it draws in [textSecondary].
  final TextStyle blockSummaryStyle;

  /// A block's title on a timed grid of one day. Its colour is not used: it
  /// draws in [text].
  final TextStyle detailedBlockTitleStyle;

  /// The times and summaries of a block on a timed grid of one day. Its
  /// colour is not used: they draw in [textSecondary].
  final TextStyle detailedBlockDetailStyle;

  /// The label naming where a drag lands. Its colour is not used: it draws
  /// in [onPrimary].
  final TextStyle landingLabelStyle;

  /// The text of a small pill: the hidden-days pill and Agenda's duration
  /// chip, drawn in [primary], and the current-time pill, drawn in
  /// [onPrimary]. Its colour is not used.
  final TextStyle badgeStyle;

  /// The text counting entries outside the hours: Week's and Day's "+N
  /// more" rows, Agenda's banners and an entry card's strips. Its colour is
  /// not used: it draws in [onNotice].
  final TextStyle noticeStyle;

  /// A failed read's message. Its colour is not used: it draws in [error].
  final TextStyle messageStyle;

  /// Month's day number. Its colour is not used: it draws in [text], and in
  /// [textMuted] for a day of another month.
  final TextStyle monthDayNumberStyle;

  /// Month's selected or today's day number. Its colour is not used: it
  /// draws in [onPrimary] when selected, and in [primary] on today.
  final TextStyle monthDayNumberMarkedStyle;

  /// Month's "+N more". Its colour is not used: it draws in [onNotice].
  final TextStyle monthMoreStyle;

  /// A Month chip's title. Its colour is not used: it draws in [text].
  final TextStyle chipTitleStyle;

  /// A Month card's title. Its colour is not used: it draws in [text].
  final TextStyle monthCardTitleStyle;

  /// A Month card's times. Its colour is not used: they draw in
  /// [textSecondary].
  final TextStyle monthCardTimeStyle;

  /// Agenda's day title, and the height an empty day's title keeps. Its
  /// colour is not used: it draws in [text].
  final TextStyle agendaHeaderTitleStyle;

  /// An empty day's title in Agenda. Its colour is not used: it draws in
  /// [textMuted].
  final TextStyle agendaHeaderEmptyTitleStyle;

  /// The count of a day's entries in Agenda. Its colour is not used: it
  /// draws in [textSecondary].
  final TextStyle agendaHeaderCountStyle;

  /// An empty day's count in Agenda. Its colour is not used: it draws in
  /// [textMuted].
  final TextStyle agendaHeaderEmptyCountStyle;

  /// Agenda's times: an entry's start, drawn in [textSecondary], and a
  /// gap's time, drawn in [textMuted]. Its colour is not used.
  final TextStyle agendaTimeStyle;

  /// An entry card's title. Its colour is not used: it draws in [text].
  final TextStyle entryCardTitleStyle;

  /// An entry card's summaries. Its colour is not used: they draw in
  /// [textSecondary].
  final TextStyle entryCardSummaryStyle;

  /// A day's number in Agenda's month while unmarked. Its colour is not
  /// used: it draws in [text], and for a day of another month in
  /// [textMuted] moving to [text] as the month folds into its week.
  final TextStyle dayNumberStyle;

  /// A selected or today's day number in Agenda's month, and every number
  /// in the week strip, which the other numbers move to as the month folds.
  /// Its colour is not used: it draws in [onPrimary] when selected, in
  /// [primary] on today, and otherwise as [dayNumberStyle] does.
  final TextStyle dayNumberMarkedStyle;

  /// A strip day's weekday name, whose line sets the strip's height. Its
  /// colour is not used: it draws in [textMuted].
  final TextStyle stripWeekdayStyle;

  /// The weekday names over Agenda's month. Its colour is not used: they
  /// draw in [textMuted].
  final TextStyle weekdayHeaderStyle;

  /// The weekday letters over Month. Its colour is not used: they draw in
  /// [text].
  final TextStyle weekdayLetterStyle;

  /// A month's name in the month picker. Its colour is not used: it draws in
  /// [text].
  final TextStyle monthNameStyle;

  /// The selected and the current month's name in the month picker, and
  /// the style the picker measures names in. Its colour is not used: it
  /// draws in [onPrimary] when selected, and in [primary] for the current
  /// month.
  final TextStyle monthNameMarkedStyle;

  /// The Retry of the default failure builder. Its colour is not used: it
  /// draws in [primary].
  final TextStyle actionLabelStyle;

  /// The 32 text styles, in the order the fields are declared.
  List<TextStyle> get _textStyles {
    return <TextStyle>[
      hourLabelStyle,
      dayHeaderWeekdayStyle,
      dayHeaderNumberStyle,
      blockTitleStyle,
      blockSummaryStyle,
      detailedBlockTitleStyle,
      detailedBlockDetailStyle,
      landingLabelStyle,
      badgeStyle,
      noticeStyle,
      messageStyle,
      monthDayNumberStyle,
      monthDayNumberMarkedStyle,
      monthMoreStyle,
      chipTitleStyle,
      monthCardTitleStyle,
      monthCardTimeStyle,
      agendaHeaderTitleStyle,
      agendaHeaderEmptyTitleStyle,
      agendaHeaderCountStyle,
      agendaHeaderEmptyCountStyle,
      agendaTimeStyle,
      entryCardTitleStyle,
      entryCardSummaryStyle,
      dayNumberStyle,
      dayNumberMarkedStyle,
      stripWeekdayStyle,
      weekdayHeaderStyle,
      weekdayLetterStyle,
      monthNameStyle,
      monthNameMarkedStyle,
      actionLabelStyle,
    ];
  }

  /// A copy with each given field replaced and the others kept.
  CalendarThemeData copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primaryTint,
    Color? background,
    Color? surface,
    Color? outline,
    Color? text,
    Color? textSecondary,
    Color? textMuted,
    Color? error,
    Color? notice,
    Color? noticeOutline,
    Color? onNotice,
    Color? todayRing,
    double? todayRingWidth,
    double? draggedBlockOpacity,
    double? entryTintOpacity,
    double? pendingEntryOpacity,
    Duration? motionDuration,
    Curve? motionCurve,
    IconData? beforeHoursIcon,
    IconData? afterHoursIcon,
    IconData? durationIcon,
    IconData? entryMenuIcon,
    IconData? addEntryIcon,
    TextStyle? hourLabelStyle,
    TextStyle? dayHeaderWeekdayStyle,
    TextStyle? dayHeaderNumberStyle,
    TextStyle? blockTitleStyle,
    TextStyle? blockSummaryStyle,
    TextStyle? detailedBlockTitleStyle,
    TextStyle? detailedBlockDetailStyle,
    TextStyle? landingLabelStyle,
    TextStyle? badgeStyle,
    TextStyle? noticeStyle,
    TextStyle? messageStyle,
    TextStyle? monthDayNumberStyle,
    TextStyle? monthDayNumberMarkedStyle,
    TextStyle? monthMoreStyle,
    TextStyle? chipTitleStyle,
    TextStyle? monthCardTitleStyle,
    TextStyle? monthCardTimeStyle,
    TextStyle? agendaHeaderTitleStyle,
    TextStyle? agendaHeaderEmptyTitleStyle,
    TextStyle? agendaHeaderCountStyle,
    TextStyle? agendaHeaderEmptyCountStyle,
    TextStyle? agendaTimeStyle,
    TextStyle? entryCardTitleStyle,
    TextStyle? entryCardSummaryStyle,
    TextStyle? dayNumberStyle,
    TextStyle? dayNumberMarkedStyle,
    TextStyle? stripWeekdayStyle,
    TextStyle? weekdayHeaderStyle,
    TextStyle? weekdayLetterStyle,
    TextStyle? monthNameStyle,
    TextStyle? monthNameMarkedStyle,
    TextStyle? actionLabelStyle,
  }) {
    return CalendarThemeData(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryTint: primaryTint ?? this.primaryTint,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      outline: outline ?? this.outline,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      error: error ?? this.error,
      notice: notice ?? this.notice,
      noticeOutline: noticeOutline ?? this.noticeOutline,
      onNotice: onNotice ?? this.onNotice,
      todayRing: todayRing ?? this.todayRing,
      todayRingWidth: todayRingWidth ?? this.todayRingWidth,
      draggedBlockOpacity: draggedBlockOpacity ?? this.draggedBlockOpacity,
      entryTintOpacity: entryTintOpacity ?? this.entryTintOpacity,
      pendingEntryOpacity: pendingEntryOpacity ?? this.pendingEntryOpacity,
      motionDuration: motionDuration ?? this.motionDuration,
      motionCurve: motionCurve ?? this.motionCurve,
      beforeHoursIcon: beforeHoursIcon ?? this.beforeHoursIcon,
      afterHoursIcon: afterHoursIcon ?? this.afterHoursIcon,
      durationIcon: durationIcon ?? this.durationIcon,
      entryMenuIcon: entryMenuIcon ?? this.entryMenuIcon,
      addEntryIcon: addEntryIcon ?? this.addEntryIcon,
      hourLabelStyle: hourLabelStyle ?? this.hourLabelStyle,
      dayHeaderWeekdayStyle:
          dayHeaderWeekdayStyle ?? this.dayHeaderWeekdayStyle,
      dayHeaderNumberStyle: dayHeaderNumberStyle ?? this.dayHeaderNumberStyle,
      blockTitleStyle: blockTitleStyle ?? this.blockTitleStyle,
      blockSummaryStyle: blockSummaryStyle ?? this.blockSummaryStyle,
      detailedBlockTitleStyle:
          detailedBlockTitleStyle ?? this.detailedBlockTitleStyle,
      detailedBlockDetailStyle:
          detailedBlockDetailStyle ?? this.detailedBlockDetailStyle,
      landingLabelStyle: landingLabelStyle ?? this.landingLabelStyle,
      badgeStyle: badgeStyle ?? this.badgeStyle,
      noticeStyle: noticeStyle ?? this.noticeStyle,
      messageStyle: messageStyle ?? this.messageStyle,
      monthDayNumberStyle: monthDayNumberStyle ?? this.monthDayNumberStyle,
      monthDayNumberMarkedStyle:
          monthDayNumberMarkedStyle ?? this.monthDayNumberMarkedStyle,
      monthMoreStyle: monthMoreStyle ?? this.monthMoreStyle,
      chipTitleStyle: chipTitleStyle ?? this.chipTitleStyle,
      monthCardTitleStyle: monthCardTitleStyle ?? this.monthCardTitleStyle,
      monthCardTimeStyle: monthCardTimeStyle ?? this.monthCardTimeStyle,
      agendaHeaderTitleStyle:
          agendaHeaderTitleStyle ?? this.agendaHeaderTitleStyle,
      agendaHeaderEmptyTitleStyle:
          agendaHeaderEmptyTitleStyle ?? this.agendaHeaderEmptyTitleStyle,
      agendaHeaderCountStyle:
          agendaHeaderCountStyle ?? this.agendaHeaderCountStyle,
      agendaHeaderEmptyCountStyle:
          agendaHeaderEmptyCountStyle ?? this.agendaHeaderEmptyCountStyle,
      agendaTimeStyle: agendaTimeStyle ?? this.agendaTimeStyle,
      entryCardTitleStyle: entryCardTitleStyle ?? this.entryCardTitleStyle,
      entryCardSummaryStyle:
          entryCardSummaryStyle ?? this.entryCardSummaryStyle,
      dayNumberStyle: dayNumberStyle ?? this.dayNumberStyle,
      dayNumberMarkedStyle: dayNumberMarkedStyle ?? this.dayNumberMarkedStyle,
      stripWeekdayStyle: stripWeekdayStyle ?? this.stripWeekdayStyle,
      weekdayHeaderStyle: weekdayHeaderStyle ?? this.weekdayHeaderStyle,
      weekdayLetterStyle: weekdayLetterStyle ?? this.weekdayLetterStyle,
      monthNameStyle: monthNameStyle ?? this.monthNameStyle,
      monthNameMarkedStyle: monthNameMarkedStyle ?? this.monthNameMarkedStyle,
      actionLabelStyle: actionLabelStyle ?? this.actionLabelStyle,
    );
  }

  /// The theme [t] of the way from [a] to [b]: [a] itself where [a] and
  /// [b] are the same instance.
  ///
  /// Colours interpolate with [Color.lerp], text styles with
  /// [TextStyle.lerp], the duration with [lerpDuration] and the four
  /// doubles with [lerpDouble]; the icons and the curve are [a]'s below 0.5
  /// and [b]'s from it. A [t] outside 0 to 1, as an overshooting curve
  /// gives, may take the duration, [todayRingWidth], [draggedBlockOpacity],
  /// [entryTintOpacity] or [pendingEntryOpacity] out of its domain, so each
  /// is clamped into it.
  static CalendarThemeData lerp(
    CalendarThemeData a,
    CalendarThemeData b,
    double t,
  ) {
    if (identical(a, b)) {
      return a;
    }
    final duration = lerpDuration(a.motionDuration, b.motionDuration, t);
    final switched = t < 0.5 ? a : b;
    return CalendarThemeData(
      primary: Color.lerp(a.primary, b.primary, t)!,
      onPrimary: Color.lerp(a.onPrimary, b.onPrimary, t)!,
      primaryTint: Color.lerp(a.primaryTint, b.primaryTint, t)!,
      background: Color.lerp(a.background, b.background, t)!,
      surface: Color.lerp(a.surface, b.surface, t)!,
      outline: Color.lerp(a.outline, b.outline, t)!,
      text: Color.lerp(a.text, b.text, t)!,
      textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
      textMuted: Color.lerp(a.textMuted, b.textMuted, t)!,
      error: Color.lerp(a.error, b.error, t)!,
      notice: Color.lerp(a.notice, b.notice, t)!,
      noticeOutline: Color.lerp(a.noticeOutline, b.noticeOutline, t)!,
      onNotice: Color.lerp(a.onNotice, b.onNotice, t)!,
      todayRing: Color.lerp(a.todayRing, b.todayRing, t)!,
      todayRingWidth: clampDouble(
        lerpDouble(a.todayRingWidth, b.todayRingWidth, t)!,
        0.0,
        double.infinity,
      ),
      draggedBlockOpacity: clampDouble(
        lerpDouble(a.draggedBlockOpacity, b.draggedBlockOpacity, t)!,
        0.0,
        1.0,
      ),
      entryTintOpacity: clampDouble(
        lerpDouble(a.entryTintOpacity, b.entryTintOpacity, t)!,
        0.0,
        1.0,
      ),
      pendingEntryOpacity: clampDouble(
        lerpDouble(a.pendingEntryOpacity, b.pendingEntryOpacity, t)!,
        0.0,
        1.0,
      ),
      motionDuration: duration.isNegative ? Duration.zero : duration,
      motionCurve: switched.motionCurve,
      beforeHoursIcon: switched.beforeHoursIcon,
      afterHoursIcon: switched.afterHoursIcon,
      durationIcon: switched.durationIcon,
      entryMenuIcon: switched.entryMenuIcon,
      addEntryIcon: switched.addEntryIcon,
      hourLabelStyle: TextStyle.lerp(a.hourLabelStyle, b.hourLabelStyle, t)!,
      dayHeaderWeekdayStyle: TextStyle.lerp(
        a.dayHeaderWeekdayStyle,
        b.dayHeaderWeekdayStyle,
        t,
      )!,
      dayHeaderNumberStyle: TextStyle.lerp(
        a.dayHeaderNumberStyle,
        b.dayHeaderNumberStyle,
        t,
      )!,
      blockTitleStyle: TextStyle.lerp(a.blockTitleStyle, b.blockTitleStyle, t)!,
      blockSummaryStyle: TextStyle.lerp(
        a.blockSummaryStyle,
        b.blockSummaryStyle,
        t,
      )!,
      detailedBlockTitleStyle: TextStyle.lerp(
        a.detailedBlockTitleStyle,
        b.detailedBlockTitleStyle,
        t,
      )!,
      detailedBlockDetailStyle: TextStyle.lerp(
        a.detailedBlockDetailStyle,
        b.detailedBlockDetailStyle,
        t,
      )!,
      landingLabelStyle: TextStyle.lerp(
        a.landingLabelStyle,
        b.landingLabelStyle,
        t,
      )!,
      badgeStyle: TextStyle.lerp(a.badgeStyle, b.badgeStyle, t)!,
      noticeStyle: TextStyle.lerp(a.noticeStyle, b.noticeStyle, t)!,
      messageStyle: TextStyle.lerp(a.messageStyle, b.messageStyle, t)!,
      monthDayNumberStyle: TextStyle.lerp(
        a.monthDayNumberStyle,
        b.monthDayNumberStyle,
        t,
      )!,
      monthDayNumberMarkedStyle: TextStyle.lerp(
        a.monthDayNumberMarkedStyle,
        b.monthDayNumberMarkedStyle,
        t,
      )!,
      monthMoreStyle: TextStyle.lerp(a.monthMoreStyle, b.monthMoreStyle, t)!,
      chipTitleStyle: TextStyle.lerp(a.chipTitleStyle, b.chipTitleStyle, t)!,
      monthCardTitleStyle: TextStyle.lerp(
        a.monthCardTitleStyle,
        b.monthCardTitleStyle,
        t,
      )!,
      monthCardTimeStyle: TextStyle.lerp(
        a.monthCardTimeStyle,
        b.monthCardTimeStyle,
        t,
      )!,
      agendaHeaderTitleStyle: TextStyle.lerp(
        a.agendaHeaderTitleStyle,
        b.agendaHeaderTitleStyle,
        t,
      )!,
      agendaHeaderEmptyTitleStyle: TextStyle.lerp(
        a.agendaHeaderEmptyTitleStyle,
        b.agendaHeaderEmptyTitleStyle,
        t,
      )!,
      agendaHeaderCountStyle: TextStyle.lerp(
        a.agendaHeaderCountStyle,
        b.agendaHeaderCountStyle,
        t,
      )!,
      agendaHeaderEmptyCountStyle: TextStyle.lerp(
        a.agendaHeaderEmptyCountStyle,
        b.agendaHeaderEmptyCountStyle,
        t,
      )!,
      agendaTimeStyle: TextStyle.lerp(a.agendaTimeStyle, b.agendaTimeStyle, t)!,
      entryCardTitleStyle: TextStyle.lerp(
        a.entryCardTitleStyle,
        b.entryCardTitleStyle,
        t,
      )!,
      entryCardSummaryStyle: TextStyle.lerp(
        a.entryCardSummaryStyle,
        b.entryCardSummaryStyle,
        t,
      )!,
      dayNumberStyle: TextStyle.lerp(a.dayNumberStyle, b.dayNumberStyle, t)!,
      dayNumberMarkedStyle: TextStyle.lerp(
        a.dayNumberMarkedStyle,
        b.dayNumberMarkedStyle,
        t,
      )!,
      stripWeekdayStyle: TextStyle.lerp(
        a.stripWeekdayStyle,
        b.stripWeekdayStyle,
        t,
      )!,
      weekdayHeaderStyle: TextStyle.lerp(
        a.weekdayHeaderStyle,
        b.weekdayHeaderStyle,
        t,
      )!,
      weekdayLetterStyle: TextStyle.lerp(
        a.weekdayLetterStyle,
        b.weekdayLetterStyle,
        t,
      )!,
      monthNameStyle: TextStyle.lerp(a.monthNameStyle, b.monthNameStyle, t)!,
      monthNameMarkedStyle: TextStyle.lerp(
        a.monthNameMarkedStyle,
        b.monthNameMarkedStyle,
        t,
      )!,
      actionLabelStyle: TextStyle.lerp(
        a.actionLabelStyle,
        b.actionLabelStyle,
        t,
      )!,
    );
  }

  /// Whether [motionDuration] and every text style lie in their domains:
  /// asserts each, and returns true so it can sit inside an `assert`.
  bool _debugCheckDomains() {
    assert(
      !motionDuration.isNegative,
      "CalendarThemeData.motionDuration must be zero or more: "
      "$motionDuration.",
    );
    assert(
      _textStyles.every((style) {
        return style.inherit;
      }),
      "Every CalendarThemeData text style must have inherit: true, so it "
      "merges over the ambient DefaultTextStyle and interpolates.",
    );
    return true;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is CalendarThemeData &&
        other.primary == primary &&
        other.onPrimary == onPrimary &&
        other.primaryTint == primaryTint &&
        other.background == background &&
        other.surface == surface &&
        other.outline == outline &&
        other.text == text &&
        other.textSecondary == textSecondary &&
        other.textMuted == textMuted &&
        other.error == error &&
        other.notice == notice &&
        other.noticeOutline == noticeOutline &&
        other.onNotice == onNotice &&
        other.todayRing == todayRing &&
        other.todayRingWidth == todayRingWidth &&
        other.draggedBlockOpacity == draggedBlockOpacity &&
        other.entryTintOpacity == entryTintOpacity &&
        other.pendingEntryOpacity == pendingEntryOpacity &&
        other.motionDuration == motionDuration &&
        other.motionCurve == motionCurve &&
        other.beforeHoursIcon == beforeHoursIcon &&
        other.afterHoursIcon == afterHoursIcon &&
        other.durationIcon == durationIcon &&
        other.entryMenuIcon == entryMenuIcon &&
        other.addEntryIcon == addEntryIcon &&
        other.hourLabelStyle == hourLabelStyle &&
        other.dayHeaderWeekdayStyle == dayHeaderWeekdayStyle &&
        other.dayHeaderNumberStyle == dayHeaderNumberStyle &&
        other.blockTitleStyle == blockTitleStyle &&
        other.blockSummaryStyle == blockSummaryStyle &&
        other.detailedBlockTitleStyle == detailedBlockTitleStyle &&
        other.detailedBlockDetailStyle == detailedBlockDetailStyle &&
        other.landingLabelStyle == landingLabelStyle &&
        other.badgeStyle == badgeStyle &&
        other.noticeStyle == noticeStyle &&
        other.messageStyle == messageStyle &&
        other.monthDayNumberStyle == monthDayNumberStyle &&
        other.monthDayNumberMarkedStyle == monthDayNumberMarkedStyle &&
        other.monthMoreStyle == monthMoreStyle &&
        other.chipTitleStyle == chipTitleStyle &&
        other.monthCardTitleStyle == monthCardTitleStyle &&
        other.monthCardTimeStyle == monthCardTimeStyle &&
        other.agendaHeaderTitleStyle == agendaHeaderTitleStyle &&
        other.agendaHeaderEmptyTitleStyle == agendaHeaderEmptyTitleStyle &&
        other.agendaHeaderCountStyle == agendaHeaderCountStyle &&
        other.agendaHeaderEmptyCountStyle == agendaHeaderEmptyCountStyle &&
        other.agendaTimeStyle == agendaTimeStyle &&
        other.entryCardTitleStyle == entryCardTitleStyle &&
        other.entryCardSummaryStyle == entryCardSummaryStyle &&
        other.dayNumberStyle == dayNumberStyle &&
        other.dayNumberMarkedStyle == dayNumberMarkedStyle &&
        other.stripWeekdayStyle == stripWeekdayStyle &&
        other.weekdayHeaderStyle == weekdayHeaderStyle &&
        other.weekdayLetterStyle == weekdayLetterStyle &&
        other.monthNameStyle == monthNameStyle &&
        other.monthNameMarkedStyle == monthNameMarkedStyle &&
        other.actionLabelStyle == actionLabelStyle;
  }

  @override
  int get hashCode {
    return Object.hashAll(<Object>[
      primary,
      onPrimary,
      primaryTint,
      background,
      surface,
      outline,
      text,
      textSecondary,
      textMuted,
      error,
      notice,
      noticeOutline,
      onNotice,
      todayRing,
      todayRingWidth,
      draggedBlockOpacity,
      entryTintOpacity,
      pendingEntryOpacity,
      motionDuration,
      motionCurve,
      beforeHoursIcon,
      afterHoursIcon,
      durationIcon,
      entryMenuIcon,
      addEntryIcon,
      ..._textStyles,
    ]);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty("primary", primary, defaultValue: _primary))
      ..add(ColorProperty("onPrimary", onPrimary, defaultValue: _onPrimary))
      ..add(
        ColorProperty("primaryTint", primaryTint, defaultValue: _primaryTint),
      )
      ..add(ColorProperty("background", background, defaultValue: _background))
      ..add(ColorProperty("surface", surface, defaultValue: _surface))
      ..add(ColorProperty("outline", outline, defaultValue: _outline))
      ..add(ColorProperty("text", text, defaultValue: _text))
      ..add(
        ColorProperty(
          "textSecondary",
          textSecondary,
          defaultValue: _textSecondary,
        ),
      )
      ..add(ColorProperty("textMuted", textMuted, defaultValue: _textMuted))
      ..add(ColorProperty("error", error, defaultValue: _error))
      ..add(ColorProperty("notice", notice, defaultValue: _notice))
      ..add(
        ColorProperty(
          "noticeOutline",
          noticeOutline,
          defaultValue: _noticeOutline,
        ),
      )
      ..add(ColorProperty("onNotice", onNotice, defaultValue: _onNotice))
      ..add(ColorProperty("todayRing", todayRing, defaultValue: _todayRing))
      ..add(
        DoubleProperty(
          "todayRingWidth",
          todayRingWidth,
          defaultValue: _todayRingWidth,
        ),
      )
      ..add(
        DoubleProperty(
          "draggedBlockOpacity",
          draggedBlockOpacity,
          defaultValue: _draggedBlockOpacity,
        ),
      )
      ..add(
        DoubleProperty(
          "entryTintOpacity",
          entryTintOpacity,
          defaultValue: _entryTintOpacity,
        ),
      )
      ..add(
        DoubleProperty(
          "pendingEntryOpacity",
          pendingEntryOpacity,
          defaultValue: _pendingEntryOpacity,
        ),
      )
      ..add(
        DiagnosticsProperty<Duration>(
          "motionDuration",
          motionDuration,
          defaultValue: _motionDuration,
        ),
      )
      ..add(
        DiagnosticsProperty<Curve>(
          "motionCurve",
          motionCurve,
          defaultValue: _motionCurve,
        ),
      )
      ..add(
        DiagnosticsProperty<IconData>(
          "beforeHoursIcon",
          beforeHoursIcon,
          defaultValue: _beforeHoursIcon,
        ),
      )
      ..add(
        DiagnosticsProperty<IconData>(
          "afterHoursIcon",
          afterHoursIcon,
          defaultValue: _afterHoursIcon,
        ),
      )
      ..add(
        DiagnosticsProperty<IconData>(
          "durationIcon",
          durationIcon,
          defaultValue: _durationIcon,
        ),
      )
      ..add(
        DiagnosticsProperty<IconData>(
          "entryMenuIcon",
          entryMenuIcon,
          defaultValue: _entryMenuIcon,
        ),
      )
      ..add(
        DiagnosticsProperty<IconData>(
          "addEntryIcon",
          addEntryIcon,
          defaultValue: _addEntryIcon,
        ),
      );
    void addStyle(String name, TextStyle value, TextStyle builtIn) {
      properties.add(
        DiagnosticsProperty<TextStyle>(name, value, defaultValue: builtIn),
      );
    }

    addStyle("hourLabelStyle", hourLabelStyle, _hourLabelStyle);
    addStyle(
      "dayHeaderWeekdayStyle",
      dayHeaderWeekdayStyle,
      _dayHeaderWeekdayStyle,
    );
    addStyle(
      "dayHeaderNumberStyle",
      dayHeaderNumberStyle,
      _dayHeaderNumberStyle,
    );
    addStyle("blockTitleStyle", blockTitleStyle, _blockTitleStyle);
    addStyle("blockSummaryStyle", blockSummaryStyle, _blockSummaryStyle);
    addStyle(
      "detailedBlockTitleStyle",
      detailedBlockTitleStyle,
      _detailedBlockTitleStyle,
    );
    addStyle(
      "detailedBlockDetailStyle",
      detailedBlockDetailStyle,
      _detailedBlockDetailStyle,
    );
    addStyle("landingLabelStyle", landingLabelStyle, _landingLabelStyle);
    addStyle("badgeStyle", badgeStyle, _badgeStyle);
    addStyle("noticeStyle", noticeStyle, _noticeStyle);
    addStyle("messageStyle", messageStyle, _messageStyle);
    addStyle("monthDayNumberStyle", monthDayNumberStyle, _monthDayNumberStyle);
    addStyle(
      "monthDayNumberMarkedStyle",
      monthDayNumberMarkedStyle,
      _monthDayNumberMarkedStyle,
    );
    addStyle("monthMoreStyle", monthMoreStyle, _monthMoreStyle);
    addStyle("chipTitleStyle", chipTitleStyle, _chipTitleStyle);
    addStyle("monthCardTitleStyle", monthCardTitleStyle, _monthCardTitleStyle);
    addStyle("monthCardTimeStyle", monthCardTimeStyle, _monthCardTimeStyle);
    addStyle(
      "agendaHeaderTitleStyle",
      agendaHeaderTitleStyle,
      _agendaHeaderTitleStyle,
    );
    addStyle(
      "agendaHeaderEmptyTitleStyle",
      agendaHeaderEmptyTitleStyle,
      _agendaHeaderEmptyTitleStyle,
    );
    addStyle(
      "agendaHeaderCountStyle",
      agendaHeaderCountStyle,
      _agendaHeaderCountStyle,
    );
    addStyle(
      "agendaHeaderEmptyCountStyle",
      agendaHeaderEmptyCountStyle,
      _agendaHeaderEmptyCountStyle,
    );
    addStyle("agendaTimeStyle", agendaTimeStyle, _agendaTimeStyle);
    addStyle("entryCardTitleStyle", entryCardTitleStyle, _entryCardTitleStyle);
    addStyle(
      "entryCardSummaryStyle",
      entryCardSummaryStyle,
      _entryCardSummaryStyle,
    );
    addStyle("dayNumberStyle", dayNumberStyle, _dayNumberStyle);
    addStyle(
      "dayNumberMarkedStyle",
      dayNumberMarkedStyle,
      _dayNumberMarkedStyle,
    );
    addStyle("stripWeekdayStyle", stripWeekdayStyle, _stripWeekdayStyle);
    addStyle("weekdayHeaderStyle", weekdayHeaderStyle, _weekdayHeaderStyle);
    addStyle("weekdayLetterStyle", weekdayLetterStyle, _weekdayLetterStyle);
    addStyle("monthNameStyle", monthNameStyle, _monthNameStyle);
    addStyle(
      "monthNameMarkedStyle",
      monthNameMarkedStyle,
      _monthNameMarkedStyle,
    );
    addStyle("actionLabelStyle", actionLabelStyle, _actionLabelStyle);
  }
}

/// Hands [data] down to the calendar views under it.
///
/// An [InheritedTheme], so a route a view opens through
/// [InheritedTheme.capture], as a popup menu does, sees the same theme.
class CalendarTheme extends InheritedTheme {
  /// Creates a theme that the calendar views under [child] draw with.
  const CalendarTheme({super.key, required this.data, required super.child});

  /// The theme the views under this widget draw with.
  final CalendarThemeData data;

  /// The [data] of the nearest [CalendarTheme] above [context], or the
  /// built-in values, `const CalendarThemeData()`, where there is none.
  /// Never null. Makes [context] depend on that theme, so it rebuilds when
  /// a theme that is not `==` replaces it.
  ///
  /// In a debug build, asserts that the theme's
  /// [CalendarThemeData.motionDuration] is zero or more and that each of its
  /// text styles has `inherit: true`.
  static CalendarThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<CalendarTheme>();
    final data = theme?.data ?? const CalendarThemeData();
    assert(data._debugCheckDomains());
    return data;
  }

  @override
  Widget wrap(BuildContext context, Widget child) {
    return CalendarTheme(data: data, child: child);
  }

  @override
  bool updateShouldNotify(CalendarTheme oldWidget) {
    return data != oldWidget.data;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    data.debugFillProperties(properties);
  }
}
