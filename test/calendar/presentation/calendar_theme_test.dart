/// [CalendarThemeData]'s fields, among them the entry tint and pending
/// opacities and the action label style the default builders read, its
/// built-in values, value semantics, domains and diagnostics, and
/// [CalendarTheme]'s lookup, notification and capture into a route.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

/// The fourteen colour fields, in the order the theme declares them.
const List<String> colourNames = <String>[
  "primary",
  "onPrimary",
  "primaryTint",
  "background",
  "surface",
  "outline",
  "text",
  "textSecondary",
  "textMuted",
  "error",
  "notice",
  "noticeOutline",
  "onNotice",
  "todayRing",
];

/// The five icon fields.
const List<String> iconNames = <String>[
  "beforeHoursIcon",
  "afterHoursIcon",
  "durationIcon",
  "entryMenuIcon",
  "addEntryIcon",
];

/// The thirty-two text style fields, in the order the theme declares them.
const List<String> styleNames = <String>[
  "hourLabelStyle",
  "dayHeaderWeekdayStyle",
  "dayHeaderNumberStyle",
  "blockTitleStyle",
  "blockSummaryStyle",
  "detailedBlockTitleStyle",
  "detailedBlockDetailStyle",
  "landingLabelStyle",
  "badgeStyle",
  "noticeStyle",
  "messageStyle",
  "monthDayNumberStyle",
  "monthDayNumberMarkedStyle",
  "monthMoreStyle",
  "chipTitleStyle",
  "monthCardTitleStyle",
  "monthCardTimeStyle",
  "agendaHeaderTitleStyle",
  "agendaHeaderEmptyTitleStyle",
  "agendaHeaderCountStyle",
  "agendaHeaderEmptyCountStyle",
  "agendaTimeStyle",
  "entryCardTitleStyle",
  "entryCardSummaryStyle",
  "dayNumberStyle",
  "dayNumberMarkedStyle",
  "stripWeekdayStyle",
  "weekdayHeaderStyle",
  "weekdayLetterStyle",
  "monthNameStyle",
  "monthNameMarkedStyle",
  "actionLabelStyle",
];

/// Every field: the colours, the ring width, the dragged block's, the entry
/// tint's and the pending entry's opacities, the motion, the icons and the
/// text styles.
const List<String> fieldNames = <String>[
  ...colourNames,
  "todayRingWidth",
  "draggedBlockOpacity",
  "entryTintOpacity",
  "pendingEntryOpacity",
  "motionDuration",
  "motionCurve",
  ...iconNames,
  ...styleNames,
];

/// The value of the field [name] of [theme].
Object valueOf(CalendarThemeData theme, String name) {
  switch (name) {
    case "primary":
      return theme.primary;
    case "onPrimary":
      return theme.onPrimary;
    case "primaryTint":
      return theme.primaryTint;
    case "background":
      return theme.background;
    case "surface":
      return theme.surface;
    case "outline":
      return theme.outline;
    case "text":
      return theme.text;
    case "textSecondary":
      return theme.textSecondary;
    case "textMuted":
      return theme.textMuted;
    case "error":
      return theme.error;
    case "notice":
      return theme.notice;
    case "noticeOutline":
      return theme.noticeOutline;
    case "onNotice":
      return theme.onNotice;
    case "todayRing":
      return theme.todayRing;
    case "todayRingWidth":
      return theme.todayRingWidth;
    case "draggedBlockOpacity":
      return theme.draggedBlockOpacity;
    case "entryTintOpacity":
      return theme.entryTintOpacity;
    case "pendingEntryOpacity":
      return theme.pendingEntryOpacity;
    case "motionDuration":
      return theme.motionDuration;
    case "motionCurve":
      return theme.motionCurve;
    case "beforeHoursIcon":
      return theme.beforeHoursIcon;
    case "afterHoursIcon":
      return theme.afterHoursIcon;
    case "durationIcon":
      return theme.durationIcon;
    case "entryMenuIcon":
      return theme.entryMenuIcon;
    case "addEntryIcon":
      return theme.addEntryIcon;
    case "hourLabelStyle":
      return theme.hourLabelStyle;
    case "dayHeaderWeekdayStyle":
      return theme.dayHeaderWeekdayStyle;
    case "dayHeaderNumberStyle":
      return theme.dayHeaderNumberStyle;
    case "blockTitleStyle":
      return theme.blockTitleStyle;
    case "blockSummaryStyle":
      return theme.blockSummaryStyle;
    case "detailedBlockTitleStyle":
      return theme.detailedBlockTitleStyle;
    case "detailedBlockDetailStyle":
      return theme.detailedBlockDetailStyle;
    case "landingLabelStyle":
      return theme.landingLabelStyle;
    case "badgeStyle":
      return theme.badgeStyle;
    case "noticeStyle":
      return theme.noticeStyle;
    case "messageStyle":
      return theme.messageStyle;
    case "monthDayNumberStyle":
      return theme.monthDayNumberStyle;
    case "monthDayNumberMarkedStyle":
      return theme.monthDayNumberMarkedStyle;
    case "monthMoreStyle":
      return theme.monthMoreStyle;
    case "chipTitleStyle":
      return theme.chipTitleStyle;
    case "monthCardTitleStyle":
      return theme.monthCardTitleStyle;
    case "monthCardTimeStyle":
      return theme.monthCardTimeStyle;
    case "agendaHeaderTitleStyle":
      return theme.agendaHeaderTitleStyle;
    case "agendaHeaderEmptyTitleStyle":
      return theme.agendaHeaderEmptyTitleStyle;
    case "agendaHeaderCountStyle":
      return theme.agendaHeaderCountStyle;
    case "agendaHeaderEmptyCountStyle":
      return theme.agendaHeaderEmptyCountStyle;
    case "agendaTimeStyle":
      return theme.agendaTimeStyle;
    case "entryCardTitleStyle":
      return theme.entryCardTitleStyle;
    case "entryCardSummaryStyle":
      return theme.entryCardSummaryStyle;
    case "dayNumberStyle":
      return theme.dayNumberStyle;
    case "dayNumberMarkedStyle":
      return theme.dayNumberMarkedStyle;
    case "stripWeekdayStyle":
      return theme.stripWeekdayStyle;
    case "weekdayHeaderStyle":
      return theme.weekdayHeaderStyle;
    case "weekdayLetterStyle":
      return theme.weekdayLetterStyle;
    case "monthNameStyle":
      return theme.monthNameStyle;
    case "monthNameMarkedStyle":
      return theme.monthNameMarkedStyle;
    case "actionLabelStyle":
      return theme.actionLabelStyle;
  }
  throw ArgumentError.value(name, "name", "no such field");
}

/// [theme] with its field [name] set to [value] through
/// [CalendarThemeData.copyWith].
CalendarThemeData withValue(
  CalendarThemeData theme,
  String name,
  Object value,
) {
  switch (name) {
    case "primary":
      return theme.copyWith(primary: value as Color);
    case "onPrimary":
      return theme.copyWith(onPrimary: value as Color);
    case "primaryTint":
      return theme.copyWith(primaryTint: value as Color);
    case "background":
      return theme.copyWith(background: value as Color);
    case "surface":
      return theme.copyWith(surface: value as Color);
    case "outline":
      return theme.copyWith(outline: value as Color);
    case "text":
      return theme.copyWith(text: value as Color);
    case "textSecondary":
      return theme.copyWith(textSecondary: value as Color);
    case "textMuted":
      return theme.copyWith(textMuted: value as Color);
    case "error":
      return theme.copyWith(error: value as Color);
    case "notice":
      return theme.copyWith(notice: value as Color);
    case "noticeOutline":
      return theme.copyWith(noticeOutline: value as Color);
    case "onNotice":
      return theme.copyWith(onNotice: value as Color);
    case "todayRing":
      return theme.copyWith(todayRing: value as Color);
    case "todayRingWidth":
      return theme.copyWith(todayRingWidth: value as double);
    case "draggedBlockOpacity":
      return theme.copyWith(draggedBlockOpacity: value as double);
    case "entryTintOpacity":
      return theme.copyWith(entryTintOpacity: value as double);
    case "pendingEntryOpacity":
      return theme.copyWith(pendingEntryOpacity: value as double);
    case "motionDuration":
      return theme.copyWith(motionDuration: value as Duration);
    case "motionCurve":
      return theme.copyWith(motionCurve: value as Curve);
    case "beforeHoursIcon":
      return theme.copyWith(beforeHoursIcon: value as IconData);
    case "afterHoursIcon":
      return theme.copyWith(afterHoursIcon: value as IconData);
    case "durationIcon":
      return theme.copyWith(durationIcon: value as IconData);
    case "entryMenuIcon":
      return theme.copyWith(entryMenuIcon: value as IconData);
    case "addEntryIcon":
      return theme.copyWith(addEntryIcon: value as IconData);
    case "hourLabelStyle":
      return theme.copyWith(hourLabelStyle: value as TextStyle);
    case "dayHeaderWeekdayStyle":
      return theme.copyWith(dayHeaderWeekdayStyle: value as TextStyle);
    case "dayHeaderNumberStyle":
      return theme.copyWith(dayHeaderNumberStyle: value as TextStyle);
    case "blockTitleStyle":
      return theme.copyWith(blockTitleStyle: value as TextStyle);
    case "blockSummaryStyle":
      return theme.copyWith(blockSummaryStyle: value as TextStyle);
    case "detailedBlockTitleStyle":
      return theme.copyWith(detailedBlockTitleStyle: value as TextStyle);
    case "detailedBlockDetailStyle":
      return theme.copyWith(detailedBlockDetailStyle: value as TextStyle);
    case "landingLabelStyle":
      return theme.copyWith(landingLabelStyle: value as TextStyle);
    case "badgeStyle":
      return theme.copyWith(badgeStyle: value as TextStyle);
    case "noticeStyle":
      return theme.copyWith(noticeStyle: value as TextStyle);
    case "messageStyle":
      return theme.copyWith(messageStyle: value as TextStyle);
    case "monthDayNumberStyle":
      return theme.copyWith(monthDayNumberStyle: value as TextStyle);
    case "monthDayNumberMarkedStyle":
      return theme.copyWith(monthDayNumberMarkedStyle: value as TextStyle);
    case "monthMoreStyle":
      return theme.copyWith(monthMoreStyle: value as TextStyle);
    case "chipTitleStyle":
      return theme.copyWith(chipTitleStyle: value as TextStyle);
    case "monthCardTitleStyle":
      return theme.copyWith(monthCardTitleStyle: value as TextStyle);
    case "monthCardTimeStyle":
      return theme.copyWith(monthCardTimeStyle: value as TextStyle);
    case "agendaHeaderTitleStyle":
      return theme.copyWith(agendaHeaderTitleStyle: value as TextStyle);
    case "agendaHeaderEmptyTitleStyle":
      return theme.copyWith(agendaHeaderEmptyTitleStyle: value as TextStyle);
    case "agendaHeaderCountStyle":
      return theme.copyWith(agendaHeaderCountStyle: value as TextStyle);
    case "agendaHeaderEmptyCountStyle":
      return theme.copyWith(agendaHeaderEmptyCountStyle: value as TextStyle);
    case "agendaTimeStyle":
      return theme.copyWith(agendaTimeStyle: value as TextStyle);
    case "entryCardTitleStyle":
      return theme.copyWith(entryCardTitleStyle: value as TextStyle);
    case "entryCardSummaryStyle":
      return theme.copyWith(entryCardSummaryStyle: value as TextStyle);
    case "dayNumberStyle":
      return theme.copyWith(dayNumberStyle: value as TextStyle);
    case "dayNumberMarkedStyle":
      return theme.copyWith(dayNumberMarkedStyle: value as TextStyle);
    case "stripWeekdayStyle":
      return theme.copyWith(stripWeekdayStyle: value as TextStyle);
    case "weekdayHeaderStyle":
      return theme.copyWith(weekdayHeaderStyle: value as TextStyle);
    case "weekdayLetterStyle":
      return theme.copyWith(weekdayLetterStyle: value as TextStyle);
    case "monthNameStyle":
      return theme.copyWith(monthNameStyle: value as TextStyle);
    case "monthNameMarkedStyle":
      return theme.copyWith(monthNameMarkedStyle: value as TextStyle);
    case "actionLabelStyle":
      return theme.copyWith(actionLabelStyle: value as TextStyle);
  }
  throw ArgumentError.value(name, "name", "no such field");
}

/// The built-in size, weight and height of each text style.
const Map<String, ({double? size, FontWeight? weight, double? height})>
builtInTypography =
    <String, ({double? size, FontWeight? weight, double? height})>{
      "hourLabelStyle": (size: 11.0, weight: null, height: 1.0),
      "dayHeaderWeekdayStyle": (size: 11.0, weight: null, height: null),
      "dayHeaderNumberStyle": (
        size: 14.0,
        weight: FontWeight.w700,
        height: null,
      ),
      "blockTitleStyle": (size: 11.0, weight: FontWeight.w600, height: null),
      "blockSummaryStyle": (size: 10.0, weight: null, height: null),
      "detailedBlockTitleStyle": (
        size: 13.0,
        weight: FontWeight.w600,
        height: null,
      ),
      "detailedBlockDetailStyle": (size: 12.0, weight: null, height: null),
      "landingLabelStyle": (size: 13.0, weight: FontWeight.w600, height: null),
      "badgeStyle": (size: 11.0, weight: FontWeight.w600, height: null),
      "noticeStyle": (size: 12.0, weight: FontWeight.w600, height: null),
      "messageStyle": (size: null, weight: null, height: null),
      "monthDayNumberStyle": (
        size: 13.0,
        weight: FontWeight.w400,
        height: null,
      ),
      "monthDayNumberMarkedStyle": (
        size: 13.0,
        weight: FontWeight.w600,
        height: null,
      ),
      "monthMoreStyle": (size: 11.0, weight: FontWeight.w600, height: null),
      "chipTitleStyle": (size: 11.0, weight: FontWeight.w600, height: null),
      "monthCardTitleStyle": (
        size: 12.0,
        weight: FontWeight.w600,
        height: null,
      ),
      "monthCardTimeStyle": (size: 11.0, weight: null, height: null),
      "agendaHeaderTitleStyle": (
        size: 16.0,
        weight: FontWeight.w700,
        height: null,
      ),
      "agendaHeaderEmptyTitleStyle": (
        size: 13.0,
        weight: FontWeight.w700,
        height: null,
      ),
      "agendaHeaderCountStyle": (
        size: 15.0,
        weight: FontWeight.w600,
        height: null,
      ),
      "agendaHeaderEmptyCountStyle": (
        size: 12.0,
        weight: FontWeight.w600,
        height: null,
      ),
      "agendaTimeStyle": (size: 12.0, weight: FontWeight.w600, height: null),
      "entryCardTitleStyle": (
        size: 14.0,
        weight: FontWeight.w600,
        height: null,
      ),
      "entryCardSummaryStyle": (size: 14.0, weight: null, height: null),
      "dayNumberStyle": (size: 15.0, weight: FontWeight.w400, height: null),
      "dayNumberMarkedStyle": (
        size: 15.0,
        weight: FontWeight.w600,
        height: null,
      ),
      "stripWeekdayStyle": (size: 12.0, weight: null, height: 1.2),
      "weekdayHeaderStyle": (size: 12.0, weight: null, height: null),
      "weekdayLetterStyle": (size: 15.0, weight: FontWeight.w600, height: null),
      "monthNameStyle": (size: 15.0, weight: FontWeight.w400, height: null),
      "monthNameMarkedStyle": (
        size: 15.0,
        weight: FontWeight.w600,
        height: null,
      ),
      "actionLabelStyle": (size: 14.0, weight: FontWeight.w600, height: null),
    };

/// A value for the field [name] unlike its built-in one: for a text style,
/// the built-in with a field it already sets changed, or, for one that sets
/// none, its style made italic, so a lerp from it to the built-in style
/// lands on the built-in style at 1.
Object fullValueOf(String name, int index) {
  const builtIn = CalendarThemeData();
  final colour = colourNames.indexOf(name);
  if (colour >= 0) {
    return Color(0xFF103050 + colour);
  }
  final icon = iconNames.indexOf(name);
  if (icon >= 0) {
    return const <IconData>[
      IconData(0xe100, fontFamily: "MaterialIcons"),
      IconData(0xe101, fontFamily: "MaterialIcons"),
      IconData(0xe102, fontFamily: "MaterialIcons"),
      IconData(0xe103, fontFamily: "MaterialIcons"),
      IconData(0xe104, fontFamily: "MaterialIcons"),
    ][icon];
  }
  switch (name) {
    case "todayRingWidth":
      return 3.5;
    case "draggedBlockOpacity":
      return 0.5;
    case "entryTintOpacity":
      return 0.3;
    case "pendingEntryOpacity":
      return 0.7;
    case "motionDuration":
      return const Duration(milliseconds: 450);
    case "motionCurve":
      return Curves.easeInOut;
  }
  final style = valueOf(builtIn, name) as TextStyle;
  final size = style.fontSize;
  if (size == null) {
    return style.copyWith(fontStyle: FontStyle.italic);
  }
  return style.copyWith(fontSize: size + 1.0 + index / 100.0);
}

/// A theme naming every constructor parameter, each with a value unlike its
/// built-in one; each call builds a new instance.
CalendarThemeData fullTheme() {
  T full<T>(String name) {
    return fullValueOf(name, fieldNames.indexOf(name)) as T;
  }

  return CalendarThemeData(
    primary: full("primary"),
    onPrimary: full("onPrimary"),
    primaryTint: full("primaryTint"),
    background: full("background"),
    surface: full("surface"),
    outline: full("outline"),
    text: full("text"),
    textSecondary: full("textSecondary"),
    textMuted: full("textMuted"),
    error: full("error"),
    notice: full("notice"),
    noticeOutline: full("noticeOutline"),
    onNotice: full("onNotice"),
    todayRing: full("todayRing"),
    todayRingWidth: full("todayRingWidth"),
    draggedBlockOpacity: full("draggedBlockOpacity"),
    entryTintOpacity: full("entryTintOpacity"),
    pendingEntryOpacity: full("pendingEntryOpacity"),
    motionDuration: full("motionDuration"),
    motionCurve: full("motionCurve"),
    beforeHoursIcon: full("beforeHoursIcon"),
    afterHoursIcon: full("afterHoursIcon"),
    durationIcon: full("durationIcon"),
    entryMenuIcon: full("entryMenuIcon"),
    addEntryIcon: full("addEntryIcon"),
    hourLabelStyle: full("hourLabelStyle"),
    dayHeaderWeekdayStyle: full("dayHeaderWeekdayStyle"),
    dayHeaderNumberStyle: full("dayHeaderNumberStyle"),
    blockTitleStyle: full("blockTitleStyle"),
    blockSummaryStyle: full("blockSummaryStyle"),
    detailedBlockTitleStyle: full("detailedBlockTitleStyle"),
    detailedBlockDetailStyle: full("detailedBlockDetailStyle"),
    landingLabelStyle: full("landingLabelStyle"),
    badgeStyle: full("badgeStyle"),
    noticeStyle: full("noticeStyle"),
    messageStyle: full("messageStyle"),
    monthDayNumberStyle: full("monthDayNumberStyle"),
    monthDayNumberMarkedStyle: full("monthDayNumberMarkedStyle"),
    monthMoreStyle: full("monthMoreStyle"),
    chipTitleStyle: full("chipTitleStyle"),
    monthCardTitleStyle: full("monthCardTitleStyle"),
    monthCardTimeStyle: full("monthCardTimeStyle"),
    agendaHeaderTitleStyle: full("agendaHeaderTitleStyle"),
    agendaHeaderEmptyTitleStyle: full("agendaHeaderEmptyTitleStyle"),
    agendaHeaderCountStyle: full("agendaHeaderCountStyle"),
    agendaHeaderEmptyCountStyle: full("agendaHeaderEmptyCountStyle"),
    agendaTimeStyle: full("agendaTimeStyle"),
    entryCardTitleStyle: full("entryCardTitleStyle"),
    entryCardSummaryStyle: full("entryCardSummaryStyle"),
    dayNumberStyle: full("dayNumberStyle"),
    dayNumberMarkedStyle: full("dayNumberMarkedStyle"),
    stripWeekdayStyle: full("stripWeekdayStyle"),
    weekdayHeaderStyle: full("weekdayHeaderStyle"),
    weekdayLetterStyle: full("weekdayLetterStyle"),
    monthNameStyle: full("monthNameStyle"),
    monthNameMarkedStyle: full("monthNameMarkedStyle"),
    actionLabelStyle: full("actionLabelStyle"),
  );
}

/// An sRGB colour as three 8-bit channels.
typedef Rgb = ({double r, double g, double b});

Rgb rgbOf(Color color) {
  final argb = color.toARGB32();
  return (
    r: ((argb >> 16) & 0xFF).toDouble(),
    g: ((argb >> 8) & 0xFF).toDouble(),
    b: (argb & 0xFF).toDouble(),
  );
}

double luminance(Rgb rgb) {
  double linear(double channel) {
    final c = channel / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(rgb.r) +
      0.7152 * linear(rgb.g) +
      0.0722 * linear(rgb.b);
}

/// The WCAG 2 contrast ratio of [a] and [b], rounded to one decimal.
double contrast(Color a, Color b) {
  final la = luminance(rgbOf(a));
  final lb = luminance(rgbOf(b));
  final ratio = (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  return (ratio * 10).round() / 10;
}

/// Pumps [child] under [data], or under no theme where [data] is null.
Widget themed(CalendarThemeData? data, Widget child) {
  final host = Directionality(textDirection: TextDirection.ltr, child: child);
  if (data == null) {
    return host;
  }
  return CalendarTheme(data: data, child: host);
}

void main() {
  const builtIn = CalendarThemeData();

  test("the field lists name 57 distinct fields, 32 of them text styles", () {
    expect(fieldNames.toSet(), hasLength(57));
    expect(colourNames, hasLength(14));
    expect(styleNames, hasLength(32));
    final full = fullTheme();
    for (final name in fieldNames) {
      expect(valueOf(full, name), isNot(valueOf(builtIn, name)), reason: name);
    }
  });

  testWidgets("CT1 of answers the nearest theme, or the built-in values", (
    tester,
  ) async {
    CalendarThemeData? read;
    final reader = Builder(
      builder: (context) {
        read = CalendarTheme.of(context);
        return const SizedBox();
      },
    );
    await tester.pumpWidget(themed(null, reader));
    expect(read, builtIn);
    expect(read, isNot(fullTheme()));

    final outer = fullTheme();
    await tester.pumpWidget(themed(outer, reader));
    expect(identical(read, outer), isTrue);

    final inner = outer.copyWith(primary: const Color(0xFF204060));
    await tester.pumpWidget(
      CalendarTheme(
        data: outer,
        child: CalendarTheme(
          data: inner,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: reader,
          ),
        ),
      ),
    );
    expect(identical(read, inner), isTrue);
  });

  test("CT2 equal themes are ==, and each field takes part in == and "
      "hashCode", () {
    final a = fullTheme();
    final b = fullTheme();
    expect(identical(a, b), isFalse);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    for (final name in fieldNames) {
      final other = withValue(a, name, valueOf(builtIn, name));
      expect(other, isNot(a), reason: name);
      expect(other.hashCode, isNot(a.hashCode), reason: name);
    }
  });

  test("CT3 copyWith of a field changes that field alone", () {
    final full = fullTheme();
    for (final name in fieldNames) {
      final changed = withValue(full, name, valueOf(builtIn, name));
      for (final other in fieldNames) {
        expect(
          valueOf(changed, other),
          other == name ? valueOf(builtIn, name) : valueOf(full, other),
          reason: "$name: $other",
        );
      }
    }
    expect(full.copyWith(), full);
  });

  test("CT4 lerp interpolates colours, styles, the duration and the "
      "doubles, and switches the icons and the curve at 0.5", () {
    final a = fullTheme();
    const b = builtIn;
    expect(CalendarThemeData.lerp(a, b, 0.0), a);
    expect(CalendarThemeData.lerp(a, b, 1.0), b);
    expect(identical(CalendarThemeData.lerp(a, a, 0.3), a), isTrue);

    final half = CalendarThemeData.lerp(a, b, 0.5);
    for (final name in colourNames) {
      expect(
        valueOf(half, name),
        Color.lerp(valueOf(a, name) as Color, valueOf(b, name) as Color, 0.5),
        reason: name,
      );
    }
    for (final name in styleNames) {
      expect(
        valueOf(half, name),
        TextStyle.lerp(
          valueOf(a, name) as TextStyle,
          valueOf(b, name) as TextStyle,
          0.5,
        ),
        reason: name,
      );
    }
    expect(
      half.motionDuration,
      lerpDuration(a.motionDuration, b.motionDuration, 0.5),
    );
    expect(
      half.todayRingWidth,
      moreOrLessEquals((a.todayRingWidth + b.todayRingWidth) / 2.0),
    );
    expect(
      half.draggedBlockOpacity,
      moreOrLessEquals((a.draggedBlockOpacity + b.draggedBlockOpacity) / 2.0),
    );
    expect(
      half.entryTintOpacity,
      moreOrLessEquals((a.entryTintOpacity + b.entryTintOpacity) / 2.0),
    );
    expect(
      half.pendingEntryOpacity,
      moreOrLessEquals((a.pendingEntryOpacity + b.pendingEntryOpacity) / 2.0),
    );
    expect(half.motionCurve, b.motionCurve);
    for (final name in iconNames) {
      expect(valueOf(half, name), valueOf(b, name), reason: name);
    }

    final before = CalendarThemeData.lerp(a, b, 0.49);
    expect(before.motionCurve, a.motionCurve);
    for (final name in iconNames) {
      expect(valueOf(before, name), valueOf(a, name), reason: name);
    }
  });

  testWidgets("CT5 a dependent rebuilds for a theme that is not == and not "
      "for an equal one", (tester) async {
    var builds = 0;
    final reader = Builder(
      builder: (context) {
        CalendarTheme.of(context);
        builds++;
        return const SizedBox();
      },
    );
    await tester.pumpWidget(themed(fullTheme(), reader));
    expect(builds, 1);
    await tester.pumpWidget(themed(fullTheme(), reader));
    expect(builds, 1);
    await tester.pumpWidget(
      themed(fullTheme().copyWith(text: const Color(0xFF204060)), reader),
    );
    expect(builds, 2);
  });

  testWidgets("CT6 a route captures a theme placed below the navigator", (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final full = fullTheme();
    late BuildContext page;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Navigator(
          key: navigator,
          onGenerateRoute: (settings) {
            return PageRouteBuilder<void>(
              pageBuilder: (context, animation, secondaryAnimation) {
                return CalendarTheme(
                  data: full,
                  child: Builder(
                    builder: (context) {
                      page = context;
                      return const SizedBox();
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );

    Future<CalendarThemeData?> readInRoute({required bool capture}) async {
      CalendarThemeData? read;
      final Widget reader = Builder(
        builder: (context) {
          read = CalendarTheme.of(context);
          return const SizedBox();
        },
      );
      final themes = InheritedTheme.capture(
        from: page,
        to: navigator.currentContext,
      );
      navigator.currentState!.push(
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) {
            return capture ? themes.wrap(reader) : reader;
          },
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      return read;
    }

    expect(identical(await readInRoute(capture: true), full), isTrue);
    expect(await readInRoute(capture: false), builtIn);
  });

  test("CT7 the built-in values: the palette's contrast, the typography, "
      "the motion, the ring and the opacities", () {
    for (final surface in <Color>[
      builtIn.surface,
      builtIn.background,
      builtIn.primaryTint,
    ]) {
      expect(contrast(builtIn.text, surface), greaterThanOrEqualTo(12.4));
      expect(
        contrast(builtIn.textSecondary, surface),
        greaterThanOrEqualTo(6.0),
      );
      expect(contrast(builtIn.textMuted, surface), greaterThanOrEqualTo(4.6));
      expect(contrast(builtIn.primary, surface), greaterThanOrEqualTo(6.6));
    }
    expect(
      contrast(builtIn.onPrimary, builtIn.primary),
      greaterThanOrEqualTo(8.3),
    );
    expect(contrast(builtIn.error, builtIn.surface), greaterThanOrEqualTo(4.5));

    expect(builtInTypography.keys, styleNames);
    for (final name in styleNames) {
      final style = valueOf(builtIn, name) as TextStyle;
      final expected = builtInTypography[name]!;
      expect(style.inherit, isTrue, reason: name);
      expect(style.color, isNull, reason: name);
      expect(style.fontSize, expected.size, reason: name);
      expect(style.fontWeight, expected.weight, reason: name);
      expect(style.height, expected.height, reason: name);
    }
    expect(builtIn.motionDuration, const Duration(milliseconds: 300));
    expect(builtIn.motionCurve, Curves.fastOutSlowIn);
    expect(builtIn.todayRingWidth, 2.0);
    expect(builtIn.draggedBlockOpacity, 0.66);
    expect(builtIn.entryTintOpacity, 0.14);
    expect(builtIn.pendingEntryOpacity, 0.5);
  });

  test("CT8 the built-in icons are MaterialIcons code points", () {
    const expected = <String, int>{
      "beforeHoursIcon": 0xe356,
      "afterHoursIcon": 0xe353,
      "durationIcon": 0xe325,
      "entryMenuIcon": 0xe402,
      "addEntryIcon": 0xe047,
    };
    for (final entry in expected.entries) {
      final icon = valueOf(builtIn, entry.key) as IconData;
      expect(icon.codePoint, entry.value, reason: entry.key);
      expect(icon.fontFamily, "MaterialIcons", reason: entry.key);
      expect(icon.fontPackage, isNull, reason: entry.key);
    }
  });

  testWidgets("CT9 the value domains are asserted, and lerp clamps into "
      "them", (tester) async {
    expect(() {
      return CalendarThemeData(draggedBlockOpacity: 1.5);
    }, throwsAssertionError);
    expect(() {
      return CalendarThemeData(draggedBlockOpacity: -0.1);
    }, throwsAssertionError);
    expect(() {
      return CalendarThemeData(todayRingWidth: -1.0);
    }, throwsAssertionError);
    expect(() {
      return CalendarThemeData(entryTintOpacity: 1.5);
    }, throwsAssertionError);
    expect(() {
      return CalendarThemeData(entryTintOpacity: -0.1);
    }, throwsAssertionError);
    expect(() {
      return CalendarThemeData(pendingEntryOpacity: 1.5);
    }, throwsAssertionError);
    expect(() {
      return CalendarThemeData(pendingEntryOpacity: -0.1);
    }, throwsAssertionError);

    final reader = Builder(
      builder: (context) {
        CalendarTheme.of(context);
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      themed(
        const CalendarThemeData(motionDuration: Duration(milliseconds: -1)),
        reader,
      ),
    );
    expect(tester.takeException(), isA<AssertionError>());
    await tester.pumpWidget(
      themed(
        const CalendarThemeData(
          noticeStyle: TextStyle(inherit: false, fontSize: 12.0),
        ),
        reader,
      ),
    );
    expect(tester.takeException(), isA<AssertionError>());
    await tester.pumpWidget(themed(builtIn, reader));
    expect(tester.takeException(), isNull);

    const low = CalendarThemeData(
      motionDuration: Duration(milliseconds: 100),
      draggedBlockOpacity: 0.2,
      entryTintOpacity: 0.2,
      pendingEntryOpacity: 0.2,
      todayRingWidth: 1.0,
    );
    const high = CalendarThemeData(
      motionDuration: Duration(milliseconds: 900),
      draggedBlockOpacity: 0.9,
      entryTintOpacity: 0.9,
      pendingEntryOpacity: 0.9,
      todayRingWidth: 3.0,
    );
    final under = CalendarThemeData.lerp(low, high, -1.0);
    expect(under.motionDuration, Duration.zero);
    expect(under.draggedBlockOpacity, 0.0);
    expect(under.entryTintOpacity, 0.0);
    expect(under.pendingEntryOpacity, 0.0);
    expect(under.todayRingWidth, 0.0);
    final over = CalendarThemeData.lerp(low, high, 2.0);
    expect(over.draggedBlockOpacity, 1.0);
    expect(over.entryTintOpacity, 1.0);
    expect(over.pendingEntryOpacity, 1.0);
    expect(over.motionDuration, const Duration(milliseconds: 1700));
    expect(over.todayRingWidth, moreOrLessEquals(5.0));
  });

  test("CT10 the diagnostics list every field, filtered at its built-in "
      "value", () {
    List<DiagnosticsNode> propertiesOf(Diagnosticable value) {
      return value.toDiagnosticsNode().getProperties();
    }

    final full = propertiesOf(fullTheme());
    expect(
      full.map((property) {
        return property.name;
      }).toList(),
      fieldNames,
    );
    for (final property in full) {
      expect(
        property.isFiltered(DiagnosticLevel.info),
        isFalse,
        reason: property.name,
      );
    }
    final defaults = propertiesOf(builtIn);
    expect(
      defaults.map((property) {
        return property.name;
      }).toList(),
      fieldNames,
    );
    for (final property in defaults) {
      expect(
        property.isFiltered(DiagnosticLevel.info),
        isTrue,
        reason: property.name,
      );
    }
    final widget = CalendarTheme(data: fullTheme(), child: const SizedBox());
    expect(
      propertiesOf(widget).map((property) {
        return property.name;
      }).toList(),
      fieldNames,
    );
  });
}
