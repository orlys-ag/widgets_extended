/// The theme the calendar draws with: a CalendarTheme above it, the
/// extension in the Material theme, the theme a ColorScheme gives, and
/// the built-in theme with no Material theme; the extension's copyWith
/// and lerp; and when the theme a scheme gives is derived again.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/composition/calendar_theme_extension.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';

/// 11:07 on Tuesday April 21 2026.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// TE3's dark scheme.
final ColorScheme darkScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF6750A4),
  brightness: Brightness.dark,
);

/// A Material theme of [scheme] and [extensions], with no ink splash,
/// whose shader a widget test cannot load.
ThemeData materialTheme({
  ColorScheme? colorScheme,
  VisualDensity? visualDensity,
  List<ThemeExtension<dynamic>>? extensions,
}) {
  return ThemeData(
    colorScheme: colorScheme,
    visualDensity: visualDensity,
    extensions: extensions,
    splashFactory: NoSplash.splashFactory,
  );
}

/// The parameter names of the `copyWith` that [declaration] starts in
/// [path], in order.
List<String> copyWithParameters(String path, String declaration) {
  final source = File(path).readAsStringSync();
  final start = source.indexOf(declaration);
  expect(start, isNot(-1), reason: path);
  final end = source.indexOf("})", start);
  final parameters = source.substring(start + declaration.length, end);
  return <String>[
    for (final match in RegExp(
      r"^\s*[\w<>?]+\s+(\w+),\s*$",
      multiLine: true,
    ).allMatches(parameters))
      match.group(1)!,
  ];
}

void main() {
  late MemoryCalendarStore<String> store;

  setUp(() {
    store = MemoryCalendarStore<String>();
  });

  tearDown(() {
    store.dispose();
  });

  CalendarView<String> calendar({bool showsHeader = true}) {
    return CalendarView<String>(
      store: store,
      clock: fixedClock,
      showsHeader: showsHeader,
    );
  }

  /// The theme the day list draws with.
  CalendarThemeData listTheme(WidgetTester tester) {
    return CalendarTheme.of(tester.element(find.byType(DayList<String>)));
  }

  testWidgets("TE1 a CalendarTheme above the calendar wins over the "
      "extension", (tester) async {
    final ambient = const CalendarThemeData().copyWith(
      primary: const Color(0xFF112233),
    );
    final extension = CalendarThemeExtension(
      data: const CalendarThemeData().copyWith(
        primary: const Color(0xFF445566),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(extensions: <ThemeExtension<dynamic>>[extension]),
        home: CalendarTheme(data: ambient, child: calendar()),
      ),
    );
    await tester.pumpAndSettle();
    expect(listTheme(tester), same(ambient));
  });

  testWidgets("TE2 with no CalendarTheme the extension's data", (tester) async {
    final extension = CalendarThemeExtension(
      data: const CalendarThemeData().copyWith(
        primary: const Color(0xFF445566),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(extensions: <ThemeExtension<dynamic>>[extension]),
        home: calendar(),
      ),
    );
    await tester.pumpAndSettle();
    expect(listTheme(tester), same(extension.data));
  });

  testWidgets("TE3 with no extension the theme the ColorScheme gives, each "
      "colour its role's and the text styles the built-in ones", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(colorScheme: darkScheme),
        home: calendar(),
      ),
    );
    await tester.pumpAndSettle();
    final theme = listTheme(tester);
    expect(theme, CalendarThemeExtension.fromColorScheme(darkScheme).data);
    final roles = <String, (Color, Color)>{
      "primary": (theme.primary, darkScheme.primary),
      "onPrimary": (theme.onPrimary, darkScheme.onPrimary),
      "primaryTint": (theme.primaryTint, darkScheme.primaryContainer),
      "background": (theme.background, darkScheme.surfaceContainer),
      "surface": (theme.surface, darkScheme.surface),
      "outline": (theme.outline, darkScheme.outlineVariant),
      "text": (theme.text, darkScheme.onSurface),
      "textSecondary": (theme.textSecondary, darkScheme.onSurfaceVariant),
      "textMuted": (theme.textMuted, darkScheme.onSurfaceVariant),
      "error": (theme.error, darkScheme.error),
      "notice": (theme.notice, darkScheme.tertiaryContainer),
      "noticeOutline": (theme.noticeOutline, darkScheme.outlineVariant),
      "onNotice": (theme.onNotice, darkScheme.onTertiaryContainer),
      "todayRing": (theme.todayRing, darkScheme.outline),
    };
    for (final MapEntry(key: name, value: (actual, role)) in roles.entries) {
      expect(actual, role, reason: name);
    }
    const builtIn = CalendarThemeData();
    // Every other field keeps its built-in value.
    expect(
      theme,
      builtIn.copyWith(
        primary: theme.primary,
        onPrimary: theme.onPrimary,
        primaryTint: theme.primaryTint,
        background: theme.background,
        surface: theme.surface,
        outline: theme.outline,
        text: theme.text,
        textSecondary: theme.textSecondary,
        textMuted: theme.textMuted,
        error: theme.error,
        notice: theme.notice,
        noticeOutline: theme.noticeOutline,
        onNotice: theme.onNotice,
        todayRing: theme.todayRing,
        gripShadows: theme.gripShadows,
        liftedBlockShadows: theme.liftedBlockShadows,
      ),
    );
    expect(theme.blockTitleStyle, builtIn.blockTitleStyle);
    expect(theme.agendaTimeStyle, builtIn.agendaTimeStyle);
  });

  testWidgets("TE4 with no Material theme above, the built-in theme and no "
      "CalendarTheme put in", (tester) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, child) {
          return calendar(showsHeader: false);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(listTheme(tester), const CalendarThemeData());
    expect(find.byType(CalendarTheme), findsNothing);
    expect(find.byType(Material), findsNothing);
  });

  testWidgets("TE5 a view on its own under a Material theme with the "
      "extension reads the built-in theme", (tester) async {
    final extension = CalendarThemeExtension(
      data: const CalendarThemeData().copyWith(
        primary: const Color(0xFF445566),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: materialTheme(extensions: <ThemeExtension<dynamic>>[extension]),
        home: const WeekdayHeader(weekdays: WeekdaySet.all),
      ),
    );
    expect(
      CalendarTheme.of(tester.element(find.byType(WeekdayHeader))),
      const CalendarThemeData(),
    );
  });

  test("TE6 the extension's copyWith and lerp follow CalendarThemeData's", () {
    final extension = CalendarThemeExtension(
      data: const CalendarThemeData().copyWith(
        primary: const Color(0xFF445566),
        todayRingWidth: 3.0,
      ),
    );
    const colour = Color(0xFF778899);
    expect(
      extension.copyWith(primary: colour).data,
      extension.data.copyWith(primary: colour),
    );
    final extensionParameters = copyWithParameters(
      "lib/calendar/composition/calendar_theme_extension.dart",
      "CalendarThemeExtension copyWith({",
    );
    final dataParameters = copyWithParameters(
      "lib/calendar/presentation/calendar_theme.dart",
      "CalendarThemeData copyWith({",
    );
    expect(dataParameters, hasLength(59));
    expect(extensionParameters, dataParameters);

    final other = CalendarThemeExtension(
      data: const CalendarThemeData().copyWith(
        primary: const Color(0xFF001122),
        todayRingWidth: 1.0,
      ),
    );
    final half = ThemeData.lerp(
      materialTheme(extensions: <ThemeExtension<dynamic>>[extension]),
      materialTheme(extensions: <ThemeExtension<dynamic>>[other]),
      0.5,
    ).extension<CalendarThemeExtension>();
    expect(
      half,
      CalendarThemeExtension(
        data: CalendarThemeData.lerp(extension.data, other.data, 0.5),
      ),
    );
    expect(half!.data, isNot(extension.data));
    expect(extension.lerp(null, 0.5), same(extension));
  });

  test("TE7 a scheme's shadow role tints the built-in shadows at their "
      "alpha", () {
    const builtIn = CalendarThemeData();
    final plain = CalendarThemeExtension.fromColorScheme(
      const ColorScheme.light(),
    ).data;
    expect(plain.gripShadows, builtIn.gripShadows);
    expect(plain.liftedBlockShadows, builtIn.liftedBlockShadows);

    const shadow = Color(0xFF102030);
    final tinted = CalendarThemeExtension.fromColorScheme(
      const ColorScheme.light(shadow: shadow),
    ).data;
    void expectTinted(List<BoxShadow> actual, List<BoxShadow> expected) {
      expect(actual, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(
          actual[i],
          expected[i].copyWith(
            color: shadow.withValues(alpha: expected[i].color.a),
          ),
        );
        expect(actual[i].color, isNot(expected[i].color));
      }
    }

    expectTinted(tinted.gripShadows, builtIn.gripShadows);
    expectTinted(tinted.liftedBlockShadows, builtIn.liftedBlockShadows);
  });

  testWidgets("TE8 the theme a scheme gives is derived again for a scheme "
      "not equal to the last, and after a reassemble", (tester) async {
    Widget themed(ThemeData theme) {
      return MaterialApp(
        theme: materialTheme(),
        home: Theme(data: theme, child: calendar()),
      );
    }

    await tester.pumpWidget(themed(materialTheme(colorScheme: darkScheme)));
    await tester.pumpAndSettle();
    final first = listTheme(tester);
    expect(first, CalendarThemeExtension.fromColorScheme(darkScheme).data);

    final compact = materialTheme(
      colorScheme: darkScheme,
      visualDensity: VisualDensity.compact,
    );
    expect(compact, isNot(materialTheme(colorScheme: darkScheme)));
    await tester.pumpWidget(themed(compact));
    await tester.pumpAndSettle();
    expect(listTheme(tester), same(first));

    final reassembled = tester.binding.reassembleApplication();
    await tester.pump();
    await reassembled;
    await tester.pumpAndSettle();
    final again = listTheme(tester);
    expect(again, first);
    expect(again, isNot(same(first)));

    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
    );
    expect(lightScheme, isNot(darkScheme));
    await tester.pumpWidget(themed(materialTheme(colorScheme: lightScheme)));
    await tester.pumpAndSettle();
    final light = listTheme(tester);
    expect(light, CalendarThemeExtension.fromColorScheme(lightScheme).data);
    expect(light, isNot(first));
  });
}
