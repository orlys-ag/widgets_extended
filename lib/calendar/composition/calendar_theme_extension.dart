/// The calendar's theme as a Material [ThemeExtension], and the theme a
/// [ColorScheme] gives it.
library;

import 'package:flutter/material.dart';

import '../presentation/calendar_theme.dart';

/// A [CalendarThemeData] carried in a [ThemeData]'s extensions, which a
/// `CalendarView` with no [CalendarTheme] above it draws with.
///
/// [ThemeData.lerp] interpolates it as [CalendarThemeData.lerp] does, so
/// an animated theme change animates the calendar too.
@immutable
class CalendarThemeExtension extends ThemeExtension<CalendarThemeExtension> {
  /// The extension of [data], the built-in theme unless given.
  const CalendarThemeExtension({this.data = const CalendarThemeData()});

  /// The extension of the theme [scheme]'s roles give: the accent from
  /// `primary`, `onPrimary` and `primaryContainer`; the body from
  /// `surfaceContainer` and `surface`; the lines from `outlineVariant`;
  /// the text from `onSurface` and, secondary and muted, from
  /// `onSurfaceVariant`; the current time from `error`; the notices from
  /// `tertiaryContainer`, `outlineVariant` and `onTertiaryContainer`;
  /// today's ring from `outline`; and the built-in shadows, each in
  /// `shadow` at the built-in shadow's alpha. Every other field, the text
  /// styles included, takes its built-in value.
  factory CalendarThemeExtension.fromColorScheme(ColorScheme scheme) {
    const builtIn = CalendarThemeData();
    List<BoxShadow> inShadow(List<BoxShadow> shadows) {
      return <BoxShadow>[
        for (final shadow in shadows)
          shadow.copyWith(
            color: scheme.shadow.withValues(alpha: shadow.color.a),
          ),
      ];
    }

    return CalendarThemeExtension(
      data: builtIn.copyWith(
        primary: scheme.primary,
        onPrimary: scheme.onPrimary,
        primaryTint: scheme.primaryContainer,
        background: scheme.surfaceContainer,
        surface: scheme.surface,
        outline: scheme.outlineVariant,
        text: scheme.onSurface,
        textSecondary: scheme.onSurfaceVariant,
        textMuted: scheme.onSurfaceVariant,
        error: scheme.error,
        notice: scheme.tertiaryContainer,
        noticeOutline: scheme.outlineVariant,
        onNotice: scheme.onTertiaryContainer,
        todayRing: scheme.outline,
        gripShadows: inShadow(builtIn.gripShadows),
        liftedBlockShadows: inShadow(builtIn.liftedBlockShadows),
      ),
    );
  }

  /// The theme the calendar draws with.
  final CalendarThemeData data;

  /// An extension of [data] with each given field replaced, as
  /// [CalendarThemeData.copyWith] replaces it.
  @override
  CalendarThemeExtension copyWith({
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
    List<BoxShadow>? gripShadows,
    List<BoxShadow>? liftedBlockShadows,
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
    return CalendarThemeExtension(
      data: data.copyWith(
        primary: primary,
        onPrimary: onPrimary,
        primaryTint: primaryTint,
        background: background,
        surface: surface,
        outline: outline,
        text: text,
        textSecondary: textSecondary,
        textMuted: textMuted,
        error: error,
        notice: notice,
        noticeOutline: noticeOutline,
        onNotice: onNotice,
        todayRing: todayRing,
        todayRingWidth: todayRingWidth,
        draggedBlockOpacity: draggedBlockOpacity,
        entryTintOpacity: entryTintOpacity,
        pendingEntryOpacity: pendingEntryOpacity,
        gripShadows: gripShadows,
        liftedBlockShadows: liftedBlockShadows,
        motionDuration: motionDuration,
        motionCurve: motionCurve,
        beforeHoursIcon: beforeHoursIcon,
        afterHoursIcon: afterHoursIcon,
        durationIcon: durationIcon,
        entryMenuIcon: entryMenuIcon,
        addEntryIcon: addEntryIcon,
        hourLabelStyle: hourLabelStyle,
        dayHeaderWeekdayStyle: dayHeaderWeekdayStyle,
        dayHeaderNumberStyle: dayHeaderNumberStyle,
        blockTitleStyle: blockTitleStyle,
        blockSummaryStyle: blockSummaryStyle,
        detailedBlockTitleStyle: detailedBlockTitleStyle,
        detailedBlockDetailStyle: detailedBlockDetailStyle,
        landingLabelStyle: landingLabelStyle,
        badgeStyle: badgeStyle,
        noticeStyle: noticeStyle,
        messageStyle: messageStyle,
        monthDayNumberStyle: monthDayNumberStyle,
        monthDayNumberMarkedStyle: monthDayNumberMarkedStyle,
        monthMoreStyle: monthMoreStyle,
        chipTitleStyle: chipTitleStyle,
        monthCardTitleStyle: monthCardTitleStyle,
        monthCardTimeStyle: monthCardTimeStyle,
        agendaHeaderTitleStyle: agendaHeaderTitleStyle,
        agendaHeaderEmptyTitleStyle: agendaHeaderEmptyTitleStyle,
        agendaHeaderCountStyle: agendaHeaderCountStyle,
        agendaHeaderEmptyCountStyle: agendaHeaderEmptyCountStyle,
        agendaTimeStyle: agendaTimeStyle,
        entryCardTitleStyle: entryCardTitleStyle,
        entryCardSummaryStyle: entryCardSummaryStyle,
        dayNumberStyle: dayNumberStyle,
        dayNumberMarkedStyle: dayNumberMarkedStyle,
        stripWeekdayStyle: stripWeekdayStyle,
        weekdayHeaderStyle: weekdayHeaderStyle,
        weekdayLetterStyle: weekdayLetterStyle,
        monthNameStyle: monthNameStyle,
        monthNameMarkedStyle: monthNameMarkedStyle,
        actionLabelStyle: actionLabelStyle,
      ),
    );
  }

  /// This extension for a null [other], and otherwise the extension of
  /// [CalendarThemeData.lerp] of the two themes at [t].
  @override
  CalendarThemeExtension lerp(
    covariant CalendarThemeExtension? other,
    double t,
  ) {
    if (other == null) {
      return this;
    }
    return CalendarThemeExtension(
      data: CalendarThemeData.lerp(data, other.data, t),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarThemeExtension && other.data == data;
  }

  @override
  int get hashCode {
    return data.hashCode;
  }
}
