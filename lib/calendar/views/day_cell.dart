/// One day of the calendar's month grid, and the letters or the
/// abbreviations of the weekdays over the grid.
library;

import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../scheduling/scheduling.dart';
import '../presentation/calendar_day_badges.dart';
import '../presentation/calendar_localizations.dart';
import '../presentation/calendar_theme.dart';

/// The key of the cell showing [day].
ValueKey<String> dayCellKey(DateTime day) {
  return ValueKey<String>("day-${day.year}-${day.month}-${day.day}");
}

/// The badges of [day]'s circle: none where [store] shows no marker for
/// it ([CalendarStore.dayHasShownEntries]); otherwise, where [badges] is
/// null, the primary dot alone, a null; and otherwise each kind of
/// [badges] that [CalendarDayBadges.kindOf] answers for one of the day's
/// shown entries, in [CalendarDayBadges.kinds]' order, then a null for the
/// entries it answers null for.
List<CalendarBadgeKind?> dayBadgesOf<T>(
  CalendarStore<T> store,
  DateTime day,
  CalendarDayBadges<T>? badges,
) {
  if (!store.dayHasShownEntries(day)) {
    return const <CalendarBadgeKind?>[];
  }
  if (badges == null) {
    return const <CalendarBadgeKind?>[null];
  }
  final kinds = badges.kinds;
  final has = List<bool>.filled(kinds.length, false);
  var other = false;
  for (final shown in store.entriesOn(day)) {
    final kind = badges.kindOf(shown.entry);
    final index = kind == null ? -1 : kinds.indexOf(kind);
    assert(
      kind == null || index >= 0,
      "The kind of ${shown.id}, $kind, is not one of the badges' kinds.",
    );
    if (index < 0) {
      other = true;
    } else {
      has[index] = true;
    }
  }
  return <CalendarBadgeKind?>[
    for (var index = 0; index < kinds.length; index++)
      if (has[index]) kinds[index],
    if (other) null,
  ];
}

/// Builds [builder] with the badges [store] gives [day] under [badges]
/// ([dayBadgesOf]), and builds it again only when they change.
///
/// A store change reaches no cell of the month board, whose cell builder
/// re-runs only when an axis or a cell's selection changes; this listener
/// is how a cell follows the store, rebuilding only itself.
class DayMarkerListener<T> extends StatefulWidget {
  const DayMarkerListener({
    super.key,
    required this.store,
    required this.day,
    required this.builder,
    this.badges,
  });

  final CalendarStore<T> store;
  final DateTime day;

  /// The kinds the badges mark; null for the primary dot alone.
  final CalendarDayBadges<T>? badges;

  final Widget Function(BuildContext context, List<CalendarBadgeKind?> badges)
  builder;

  @override
  State<DayMarkerListener<T>> createState() {
    return _DayMarkerListenerState<T>();
  }
}

class _DayMarkerListenerState<T> extends State<DayMarkerListener<T>> {
  late List<CalendarBadgeKind?> _badges = _read();

  List<CalendarBadgeKind?> _read() {
    return dayBadgesOf(widget.store, widget.day, widget.badges);
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleStore);
  }

  @override
  void didUpdateWidget(DayMarkerListener<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.store != oldWidget.store) {
      oldWidget.store.removeListener(_handleStore);
      widget.store.addListener(_handleStore);
    }
    if (widget.store != oldWidget.store ||
        widget.day != oldWidget.day ||
        !identical(widget.badges, oldWidget.badges)) {
      _badges = _read();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStore);
    super.dispose();
  }

  void _handleStore() {
    final badges = _read();
    if (listEquals(badges, _badges)) {
      return;
    }
    setState(() {
      _badges = badges;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _badges);
  }
}

/// The diameter of a [DayCell]'s circle.
const double dayCircleSize = 32.0;

/// The room a [DayCell]'s number keeps from either side of its circle
/// beyond the width of today's ring ([CalendarThemeData.todayRingWidth]).
const double _numberGap = 2.0;

/// The numbers of the days of a month, which the boxes of the days'
/// numbers are measured from ([labelSizeIn]).
final List<String> dayNumbers = List<String>.unmodifiable(<String>[
  for (var day = 1; day <= 31; day++) "$day",
]);

/// The size the widest of [texts] takes as a one-line [Text] of [style]
/// lays it out in [context], as wide as the widest and as tall as the
/// tallest: [style] merged over the [DefaultTextStyle], bold where the
/// context asks for bold text, with the context's line height, letter and
/// word spacing overrides, at the context's text height behaviour and
/// locale, and at [scaler], or where it is null the context's text scale.
/// Makes [context] depend on what it reads there. Keeps the sizes it measured
/// last, so a build that asks again measures nothing, also under a style
/// that differs only in what paints the text, such as its colour
/// ([TextStyle.compareTo]), until the fonts change
/// ([PaintingBinding.systemFonts]), as a font loaded at run time changes
/// them.
Size labelSizeIn(
  BuildContext context,
  TextStyle style,
  List<String> texts, {
  TextScaler? scaler,
}) {
  final defaults = DefaultTextStyle.of(context);
  var effective = style.inherit ? defaults.style.merge(style) : style;
  if (MediaQuery.boldTextOf(context)) {
    effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  final height = MediaQuery.maybeLineHeightScaleFactorOverrideOf(context);
  final letterSpacing = MediaQuery.maybeLetterSpacingOverrideOf(context);
  final wordSpacing = MediaQuery.maybeWordSpacingOverrideOf(context);
  if (height != null || letterSpacing != null || wordSpacing != null) {
    effective = effective.merge(
      TextStyle(
        height: height,
        letterSpacing: letterSpacing,
        wordSpacing: wordSpacing,
      ),
    );
  }
  final key = _LabelKey(
    effective,
    scaler ?? MediaQuery.textScalerOf(context),
    defaults.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
    Localizations.maybeLocaleOf(context),
    texts,
  );
  if (!_labelSizesFollowFonts) {
    _labelSizesFollowFonts = true;
    PaintingBinding.instance.systemFonts.addListener(_labelSizes.clear);
  }
  final size = _labelSizes.remove(key) ?? key.measure();
  _labelSizes[key] = size;
  if (_labelSizes.length > _labelSizesKept) {
    _labelSizes.remove(_labelSizes.keys.first);
  }
  return size;
}

/// The sizes [labelSizeIn] measured, the most recently asked for last.
final LinkedHashMap<_LabelKey, Size> _labelSizes =
    LinkedHashMap<_LabelKey, Size>();

/// How many sizes [_labelSizes] keeps.
const int _labelSizesKept = 32;

/// Whether a change of the fonts empties [_labelSizes].
bool _labelSizesFollowFonts = false;

/// How many times [labelSizeIn] has laid labels out rather than reading a
/// size it kept, in a debug build; it only counts up. A test reads it to
/// pin what measures again: a size kept or measured is the same size, so
/// no widget shows the difference.
@visibleForTesting
int debugLabelSizeMeasures = 0;

/// What [labelSizeIn] measures a size from.
@immutable
final class _LabelKey {
  const _LabelKey(
    this.style,
    this.scaler,
    this.behavior,
    this.locale,
    this.texts,
  );

  final TextStyle style;
  final TextScaler scaler;
  final TextHeightBehavior? behavior;
  final Locale? locale;
  final List<String> texts;

  Size measure() {
    assert(() {
      debugLabelSizeMeasures++;
      return true;
    }());
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      textHeightBehavior: behavior,
      locale: locale,
      maxLines: 1,
    );
    var width = 0.0;
    var height = 0.0;
    for (final text in texts) {
      painter.text = TextSpan(text: text, style: style);
      painter.layout();
      width = math.max(width, painter.width);
      height = math.max(height, painter.height);
    }
    painter.dispose();
    return Size(width, height);
  }

  /// Equal where the styles lay text out alike ([TextStyle.compareTo]),
  /// whatever paints it, and the scalers scale alike: equal either way
  /// round, since a [SystemTextScaler] at a factor of 1 equals
  /// [TextScaler.noScaling] while [TextScaler.noScaling] equals no
  /// [SystemTextScaler], and both hash as their factor.
  @override
  bool operator ==(Object other) {
    return other is _LabelKey &&
        other.style.compareTo(style) != RenderComparison.layout &&
        (other.scaler == scaler || scaler == other.scaler) &&
        other.behavior == behavior &&
        other.locale == locale &&
        listEquals(other.texts, texts);
  }

  @override
  int get hashCode {
    // Of the fields [TextStyle.compareTo] reads to tell a layout apart, so
    // keys equal under [==] hash alike.
    final layout = Object.hash(
      style.fontFamily,
      style.fontSize,
      style.fontWeight,
      style.fontStyle,
      style.letterSpacing,
      style.wordSpacing,
      style.height,
    );
    return Object.hash(layout, scaler, behavior, locale, Object.hashAll(texts));
  }
}

/// The box a day's number lies in where a ring or a pill can draw around
/// it, each day's alike: [least] at no text scaling, and at a larger text
/// the widest of [dayNumbers] in the widest of [styles] ([labelSizeIn]),
/// with the room [least] leaves around it at no scaling on each axis.
Size numberBoxIn(BuildContext context, List<TextStyle> styles, Size least) {
  var width = least.width;
  var height = least.height;
  for (final style in styles) {
    final scaled = labelSizeIn(context, style, dayNumbers);
    final unscaled = labelSizeIn(
      context,
      style,
      dayNumbers,
      scaler: TextScaler.noScaling,
    );
    width = math.max(
      width,
      scaled.width + math.max(0.0, least.width - unscaled.width),
    );
    height = math.max(
      height,
      scaled.height + math.max(0.0, least.height - unscaled.height),
    );
  }
  return Size(width, height);
}

/// [label], a one-line [Text], centred in a box at least [box] large, the
/// size the widest label of its kind takes ([labelSizeIn]), and scaled
/// down with that box where its parent cannot hold it, so every label of
/// the kind scales alike and lies alike in its box.
Widget fittedLabel(Size box, Widget label) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: ConstrainedBox(
      constraints: BoxConstraints(minWidth: box.width, minHeight: box.height),
      child: Center(child: label),
    ),
  );
}

/// The abbreviations of the seven weekdays in [strings], Monday first.
List<String> weekdayAbbreviationsOf(CalendarLocalizations strings) {
  return <String>[
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
      strings.weekdayAbbreviation(weekday),
  ];
}

/// The space between a strip cell's label line and its circle.
const double stripLabelGap = 2.0;

/// The height of a cell of the week strip, a [DayCell] at a full collapse:
/// the line of the tallest weekday abbreviation in
/// [CalendarThemeData.stripWeekdayStyle] of the theme above [context], as
/// a [Text] lays it out in [context] ([labelSizeIn]), then
/// [stripLabelGap] and [dayCircleSize]. Makes [context] depend on the
/// theme, the localizations and what [labelSizeIn] reads.
double stripCellHeight(BuildContext context) {
  final line = labelSizeIn(
    context,
    _DayCellStyles.of(context).stripWeekday,
    weekdayAbbreviationsOf(CalendarLocalizations.of(context)),
  ).height;
  return line + stripLabelGap + dayCircleSize;
}

/// The diameter of a badge on a [DayCell]'s circle that carries one or
/// two.
const double _badgeSize = 9.0;

/// The diameter of a badge on a [DayCell]'s circle that carries three or
/// more, whose first lies near the circle's top, under the weekday name
/// in the week strip, which a [_badgeSize] one there reaches.
const double _smallBadgeSize = 7.0;

/// The width of the ring around a [_badgeSize] badge, and around a
/// [_smallBadgeSize] one.
const double _badgeRim = 1.5;
const double _smallBadgeRim = 1.0;

/// The most a badge on a [DayCell]'s circle reaches past the circle's box
/// on any side: [_badgeCentre] turns each badge's centre about the
/// circle's centre at the distance of a lone badge's, and the badge's box,
/// its rim inside it, is at most [_badgeSize] across.
const double dayBadgeReach =
    math.sqrt2 * (dayCircleSize / 2.0 - _badgeSize / 2.0) +
    _badgeSize / 2.0 -
    dayCircleSize / 2.0;

/// The most badges a [DayCell]'s circle draws.
const int _maxDrawnBadges = 4;

/// The angle about a [DayCell]'s circle's centre from one badge's centre
/// to the next: 30 degrees.
const double _badgeStep = math.pi / 6.0;

/// Where the centre of the badge at [index] of [count] lies in the box of
/// a [DayCell]'s circle. A lone badge lies in the box's top right corner,
/// its centre near the rim at 45 degrees; the others turn about the
/// circle's centre from there by [_badgeStep] each, clockwise for the
/// later ones, as many before it as after, whatever their size.
Offset _badgeCentre(int index, int count) {
  const half = dayCircleSize / 2.0;
  // From the circle's centre to a lone badge's.
  const dx = half - _badgeSize / 2.0;
  const dy = _badgeSize / 2.0 - half;
  final turn = (index - (count - 1) / 2.0) * _badgeStep;
  final cos = math.cos(turn);
  final sin = math.sin(turn);
  return Offset(half + dx * cos - dy * sin, half + dx * sin + dy * cos);
}

/// The key of the badge at [index] of those on the circle of a [DayCell]
/// for [day], counted along the rim from the first.
ValueKey<String> dayBadgeKey(DateTime day, [int index = 0]) {
  return ValueKey<String>(
    "day-badge-${day.year}-${day.month}-${day.day}-$index",
  );
}

/// What a [DayCell] and a [WeekdayHeader] draw with, made from one
/// [CalendarThemeData] by [forTheme] and never changed.
@immutable
class _DayCellStyles {
  _DayCellStyles._(this.theme)
    : selectedNumber = theme.dayNumberMarkedStyle.copyWith(
        color: theme.onPrimary,
      ),
      todayNumber = theme.dayNumberMarkedStyle.copyWith(color: theme.primary),
      todayNumberDisabled = theme.dayNumberMarkedStyle.copyWith(
        color: _disabled(theme, theme.primary),
      ),
      numberFrom = theme.dayNumberStyle.copyWith(color: theme.text),
      numberFromMuted = theme.dayNumberStyle.copyWith(color: theme.textMuted),
      numberTo = theme.dayNumberMarkedStyle.copyWith(color: theme.text),
      numberFromDisabled = theme.dayNumberStyle.copyWith(
        color: _disabled(theme, theme.text),
      ),
      numberFromMutedDisabled = theme.dayNumberStyle.copyWith(
        color: _disabled(theme, theme.textMuted),
      ),
      numberToDisabled = theme.dayNumberMarkedStyle.copyWith(
        color: _disabled(theme, theme.text),
      ),
      stripWeekday = theme.stripWeekdayStyle.copyWith(color: theme.textMuted),
      weekdayName = theme.weekdayHeaderStyle.copyWith(color: theme.textMuted),
      weekdayLetter = theme.weekdayLetterStyle.copyWith(color: theme.text),
      selectedCircle = BoxDecoration(
        color: theme.primary,
        shape: BoxShape.circle,
      ),
      circle = BoxDecoration(color: theme.background, shape: BoxShape.circle),
      ring = BoxDecoration(
        border: Border.all(color: theme.todayRing, width: theme.todayRingWidth),
        borderRadius: BorderRadius.circular(dayCircleSize / 2.0),
      ),
      weightOnly =
          theme.dayNumberStyle.copyWith(
            color: theme.text,
            fontWeight: theme.dayNumberMarkedStyle.fontWeight,
          ) ==
          theme.dayNumberMarkedStyle.copyWith(color: theme.text);

  /// [colour] at [theme]'s [CalendarThemeData.disabledOpacity].
  static Color _disabled(CalendarThemeData theme, Color colour) {
    return colour.withValues(alpha: colour.a * theme.disabledOpacity);
  }

  /// The styles of [theme]: those made for it before, or for a theme `==`
  /// to it last, so an equal theme makes none.
  static _DayCellStyles forTheme(CalendarThemeData theme) {
    final kept = _memo[theme];
    if (kept != null) {
      return kept;
    }
    final last = _last;
    final styles = last != null && last.theme == theme
        ? last
        : _DayCellStyles._(theme);
    _memo[theme] = styles;
    _last = styles;
    return styles;
  }

  /// The styles of the theme above [context], which [context] then depends
  /// on.
  static _DayCellStyles of(BuildContext context) {
    return forTheme(CalendarTheme.of(context));
  }

  static Expando<_DayCellStyles> _memo = Expando<_DayCellStyles>();
  static _DayCellStyles? _last;

  /// Drops the styles made so far, which keep the code that made them
  /// across a hot reload, so the next read makes them again.
  static void _reset() {
    _memo = Expando<_DayCellStyles>();
    _last = null;
  }

  final CalendarThemeData theme;
  final TextStyle selectedNumber;
  final TextStyle todayNumber;

  /// [todayNumber] of a disabled day.
  final TextStyle todayNumberDisabled;

  /// An unmarked number where the month is unfolded: in the shown month,
  /// and in another.
  final TextStyle numberFrom;
  final TextStyle numberFromMuted;

  /// Every number where the month is folded into its week.
  final TextStyle numberTo;

  /// [numberFrom], [numberFromMuted] and [numberTo] of a disabled day,
  /// each colour at the theme's [CalendarThemeData.disabledOpacity].
  final TextStyle numberFromDisabled;
  final TextStyle numberFromMutedDisabled;
  final TextStyle numberToDisabled;

  /// Whether [numberFrom] and [numberTo] differ in their weight alone.
  final bool weightOnly;

  final TextStyle stripWeekday;
  final TextStyle weekdayName;
  final TextStyle weekdayLetter;
  final BoxDecoration selectedCircle;
  final BoxDecoration circle;
  final BoxDecoration ring;

  /// The dot of [kind], or the primary dot for null, ringed [rim] wide in
  /// the surface colour.
  BoxDecoration badgeOf(CalendarBadgeKind? kind, double rim) {
    return BoxDecoration(
      color: kind?.color ?? theme.primary,
      shape: BoxShape.circle,
      border: Border.all(color: theme.surface, width: rim),
    );
  }

  /// The style of an unmarked number [t] of the way through the fold, for a
  /// day of the shown month when [inMonth], and a disabled day's where not
  /// [enabled]: the prepared style itself at either end; between them
  /// [TextStyle.lerp] of the two ends, or where they differ in weight
  /// alone, the unfolded style at the lerped weight, which keeps the colour
  /// and shadows the two ends share, and for a day outside the shown month
  /// lerps the colour between the two ends' colours.
  TextStyle numberAt(double t, {required bool inMonth, required bool enabled}) {
    final TextStyle from;
    final TextStyle to;
    if (enabled) {
      from = inMonth ? numberFrom : numberFromMuted;
      to = numberTo;
    } else {
      from = inMonth ? numberFromDisabled : numberFromMutedDisabled;
      to = numberToDisabled;
    }
    if (t <= 0.0) {
      return from;
    }
    if (t >= 1.0) {
      return to;
    }
    if (!weightOnly) {
      return TextStyle.lerp(from, to, t)!;
    }
    final weight = FontWeight.lerp(from.fontWeight, to.fontWeight, t);
    if (inMonth) {
      return from.copyWith(fontWeight: weight);
    }
    return from.copyWith(
      fontWeight: weight,
      color: Color.lerp(from.color, to.color, t),
    );
  }
}

/// The element of a [DayCell] and a [WeekdayHeader], which drops the
/// styles made so far on a hot reload, before its widget builds again.
class _DayCellElement extends StatelessElement {
  _DayCellElement(super.widget);

  @override
  void reassemble() {
    _DayCellStyles._reset();
    super.reassemble();
  }
}

/// A day number on a circle: the background grey, the primary colour when
/// selected, ringed when today, and with its [badges] when the day has
/// items, in the [CalendarTheme] above it: up to four dots along the
/// circle's rim, 30 degrees apart, about a lone dot's place at its top
/// right corner, smaller where there are three or more. A screen reader
/// hears the day with every badge's kind
/// ([CalendarLocalizations.dayWithBadges]), and then, on today's cell,
/// [CalendarLocalizations.today]. Where [enabled] is false the number
/// draws at the theme's [CalendarThemeData.disabledOpacity] unless the day
/// is selected, and a screen reader hears the day disabled.
///
/// [collapse] runs from 0, the month grid, to 1, the week strip. At 0 a
/// day outside the shown month is muted on no circle and the weekday name
/// is left to the header above the grid; at 1 every day reads at full
/// strength on its circle and carries its weekday's abbreviation
/// above it. The
/// cell listens to [collapse] itself, so the transition rebuilds the cells
/// and not the board.
///
/// The abbreviation and the number each keep to one line at any text
/// size, each in a box as large as the widest of its kind
/// ([labelSizeIn]), which scales down where the cell's width or the
/// circle cannot hold it, so every day's scales alike; the number keeps
/// the width of today's ring and [_numberGap] from the circle's sides.
class DayCell extends StatelessWidget {
  const DayCell({
    super.key,
    required this.day,
    required this.inMonth,
    required this.isSelected,
    required this.isToday,
    required this.badges,
    required this.collapse,
    this.enabled,
  });

  final DateTime day;
  final bool inMonth;
  final bool isSelected;
  final bool isToday;

  /// Whether the day may be picked: false draws it disabled; null, as
  /// true, draws it enabled and gives its [Semantics] no enabled state.
  final bool? enabled;

  /// The badges the circle carries ([dayBadgesOf]), a null for the
  /// primary dot.
  final List<CalendarBadgeKind?> badges;

  final Animation<double> collapse;

  /// Whether the day has items, so its circle carries a badge.
  bool get hasEntries {
    return badges.isNotEmpty;
  }

  @override
  StatelessElement createElement() {
    return _DayCellElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final strings = CalendarLocalizations.of(context);
    final styles = _DayCellStyles.of(context);
    final boxes = (
      name: labelSizeIn(
        context,
        styles.stripWeekday,
        weekdayAbbreviationsOf(strings),
      ),
      number: numberBoxIn(context, <TextStyle>[
        styles.numberFrom,
        styles.numberTo,
      ], Size.zero),
    );
    return Semantics(
      button: true,
      selected: isSelected,
      enabled: enabled,
      label: <String>[
        strings.dayWithBadges(day, <String?>[
          for (final kind in badges) kind?.label,
        ]),
        if (isToday) strings.today,
      ].join(", "),
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: collapse,
        builder: (context, child) {
          return _buildAt(collapse.value, styles, strings, boxes);
        },
      ),
    );
  }

  Widget _buildBadge(int index, int count, _DayCellStyles styles) {
    final centre = _badgeCentre(index, count);
    final small = count >= 3;
    final size = small ? _smallBadgeSize : _badgeSize;
    return Positioned(
      left: centre.dx - size / 2.0,
      top: centre.dy - size / 2.0,
      child: DecoratedBox(
        key: dayBadgeKey(day, index),
        decoration: styles.badgeOf(
          badges[index],
          small ? _smallBadgeRim : _badgeRim,
        ),
        child: SizedBox(width: size, height: size),
      ),
    );
  }

  /// The cell at [collapse]'s value [t]: its weekday's abbreviation, in a
  /// box of [boxes]' name, over its number, in a box of [boxes]' number,
  /// each box the widest of its kind ([labelSizeIn]).
  Widget _buildAt(
    double t,
    _DayCellStyles styles,
    CalendarLocalizations strings,
    ({Size name, Size number}) boxes,
  ) {
    final disabled = enabled == false;
    final TextStyle numberStyle;
    if (isSelected) {
      numberStyle = styles.selectedNumber;
    } else if (isToday) {
      numberStyle = disabled ? styles.todayNumberDisabled : styles.todayNumber;
    } else {
      numberStyle = styles.numberAt(t, inMonth: inMonth, enabled: !disabled);
    }
    final BoxDecoration fill;
    if (isSelected) {
      fill = styles.selectedCircle;
    } else if (inMonth) {
      fill = styles.circle;
    } else {
      fill = BoxDecoration(
        color: styles.theme.background.withValues(alpha: t),
        shape: BoxShape.circle,
      );
    }
    Widget circle = Container(
      width: dayCircleSize,
      height: dayCircleSize,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: styles.theme.todayRingWidth + _numberGap,
      ),
      decoration: fill,
      foregroundDecoration: isToday ? styles.ring : null,
      child: fittedLabel(
        boxes.number,
        Text("${day.day}", maxLines: 1, style: numberStyle),
      ),
    );
    if (badges.isNotEmpty) {
      final count = math.min(badges.length, _maxDrawnBadges);
      circle = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          circle,
          for (var index = 0; index < count; index++)
            _buildBadge(index, count, styles),
        ],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ClipRect(
            child: Align(
              alignment: Alignment.bottomCenter,
              heightFactor: t,
              child: Opacity(
                opacity: t,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: stripLabelGap),
                  child: fittedLabel(
                    boxes.name,
                    Text(
                      strings.weekdayAbbreviation(day.weekday),
                      maxLines: 1,
                      style: styles.stripWeekday,
                    ),
                  ),
                ),
              ),
            ),
          ),
          circle,
        ],
      ),
    );
  }
}

/// The height of a [WeekdayHeader].
const double weekdayHeaderHeight = 32.0;

/// The letters of the shown weekdays over a month grid, in [weekdays]'
/// order, or with [abbreviated] their abbreviations as a [DayCell] in
/// the week strip shows them, one per column: equal shares of the header's
/// width, or with [columnWidth], columns that wide, scrolled across by
/// [horizontal]'s offset as the grid under them is, and clipped to the
/// header. Each keeps to one line at any text size, in a box as large as
/// the widest ([labelSizeIn]), which scales down where its column or the
/// header's [weekdayHeaderHeight] cannot hold it, so every column's scales
/// alike.
class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({
    super.key = const ValueKey<String>("weekday-header"),
    required this.weekdays,
    this.abbreviated = false,
    this.columnWidth,
    this.horizontal,
    this.columnDirection,
  });

  final CalendarWeekdaySet weekdays;

  /// Whether each column shows its weekday's abbreviation
  /// ([CalendarLocalizations.weekdayAbbreviation]) rather than its letter
  /// ([CalendarLocalizations.weekdayLetter]).
  final bool abbreviated;

  /// The width of each column; null for equal shares of the width.
  final double? columnWidth;

  /// The grid's horizontal scroll, which a header of [columnWidth] wide
  /// columns follows: a growing offset moves the letters against the way
  /// the columns run, as it moves the grid's days.
  final ScrollController? horizontal;

  /// The way the columns run: null for the ambient [Directionality], as a
  /// grid that follows it lays its days out. A header over a grid whose
  /// columns run one way whatever that direction gives it here; the
  /// letters keep the ambient direction as text.
  final TextDirection? columnDirection;

  @override
  StatelessElement createElement() {
    return _DayCellElement(this);
  }

  @override
  Widget build(BuildContext context) {
    final width = columnWidth;
    final styles = _DayCellStyles.of(context);
    final strings = CalendarLocalizations.of(context);
    final box = labelSizeIn(
      context,
      abbreviated ? styles.weekdayName : styles.weekdayLetter,
      abbreviated
          ? weekdayAbbreviationsOf(strings)
          : <String>[
              for (
                var weekday = DateTime.monday;
                weekday <= DateTime.sunday;
                weekday++
              )
                strings.weekdayLetter(weekday),
            ],
    );
    final letters = <Widget>[
      for (final column in weekdays.columns)
        if (width == null)
          Expanded(child: _buildLetter(column, styles, strings, box))
        else
          SizedBox(
            width: width,
            child: _buildLetter(column, styles, strings, box),
          ),
    ];
    final direction = columnDirection ?? Directionality.of(context);
    if (width == null) {
      return SizedBox(
        height: weekdayHeaderHeight,
        child: Row(textDirection: direction, children: letters),
      );
    }
    final scroll = horizontal;
    final row = Row(
      textDirection: direction,
      mainAxisSize: MainAxisSize.min,
      children: letters,
    );
    final leftToRight = direction == TextDirection.ltr;
    return SizedBox(
      height: weekdayHeaderHeight,
      child: ClipRect(
        child: OverflowBox(
          alignment: leftToRight ? Alignment.centerLeft : Alignment.centerRight,
          maxWidth: double.infinity,
          child: scroll == null
              ? row
              : AnimatedBuilder(
                  animation: scroll,
                  child: row,
                  builder: (context, child) {
                    final offset = scroll.hasClients ? scroll.offset : 0.0;
                    return Transform.translate(
                      offset: Offset(leftToRight ? -offset : offset, 0.0),
                      child: child,
                    );
                  },
                ),
        ),
      ),
    );
  }

  /// The name of the weekday of [column], a [CalendarDates.weekdayColumn],
  /// Monday 0, in a box of [box], the widest name's size.
  Widget _buildLetter(
    int column,
    _DayCellStyles styles,
    CalendarLocalizations strings,
    Size box,
  ) {
    final weekday = column + 1;
    final Text label;
    if (abbreviated) {
      label = Text(
        strings.weekdayAbbreviation(weekday),
        maxLines: 1,
        style: styles.weekdayName,
      );
    } else {
      label = Text(
        strings.weekdayLetter(weekday),
        maxLines: 1,
        style: styles.weekdayLetter,
      );
    }
    return Center(child: fittedLabel(box, label));
  }
}
