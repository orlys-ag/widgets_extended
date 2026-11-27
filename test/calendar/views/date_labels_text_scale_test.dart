/// The dates' labels at large text: Week's day header grows with its text,
/// and each label of a day cell, of the weekday header and of Month's days
/// keeps to one line and scales down where its box cannot hold it, so
/// nothing overflows or is cut off.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';
import 'package:widgets_extended/scheduling/policy/edit_policy.dart';
import 'package:widgets_extended/scheduling/store/memory_calendar_store.dart';

import '../recording_errors.dart';
import '../view_doubles.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

/// Monday June 1 2026, which starts a week of single-digit days.
final DateTime juneFirst = DateTime(2026, 6, 1);

const DefaultCalendarLocalizations english = DefaultCalendarLocalizations();

/// English, but for each weekday's short name, which is its whole name.
final class _WholeNames extends DefaultCalendarLocalizations {
  const _WholeNames();

  static const List<String> _names = <String>[
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ];

  @override
  String weekdayShortName(int weekday) {
    return _names[weekday - 1];
  }
}

/// English, but for each weekday's abbreviation, from one letter to four.
final class _UnevenAbbreviations extends DefaultCalendarLocalizations {
  const _UnevenAbbreviations();

  static const List<String> _abbreviations = <String>[
    "M",
    "Tu",
    "Wed",
    "Thur",
    "F",
    "Sa",
    "Sun",
  ];

  @override
  String weekdayAbbreviation(int weekday) {
    return _abbreviations[weekday - 1];
  }
}

class _StringsDelegate extends LocalizationsDelegate<CalendarLocalizations> {
  const _StringsDelegate(this.strings);

  final CalendarLocalizations strings;

  @override
  bool isSupported(Locale locale) {
    return true;
  }

  @override
  Future<CalendarLocalizations> load(Locale locale) {
    return SynchronousFuture<CalendarLocalizations>(strings);
  }

  @override
  bool shouldReload(_StringsDelegate old) {
    return !identical(old.strings, strings);
  }
}

/// [home] on a Material, whose text style sets a line height as an app's
/// does, or with [material] false under a plain text style, which sets
/// none, under a MaterialApp at the text scale [scale] holds, in a view of
/// [size] at one device pixel per logical pixel, with [strings] where they
/// are given and the line height override [lineHeight].
Future<void> pumpScaled(
  WidgetTester tester,
  ValueListenable<double> scale,
  Widget home, {
  Size size = const Size(800.0, 1200.0),
  CalendarLocalizations? strings,
  bool material = true,
  double? lineHeight,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: <LocalizationsDelegate<Object?>>[
        if (strings != null) _StringsDelegate(strings),
      ],
      builder: (context, child) {
        return ValueListenableBuilder<double>(
          valueListenable: scale,
          child: child,
          builder: (context, value, child) {
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(value))
                  .applyTextStyleOverrides(
                    lineHeightScaleFactorOverride: lineHeight,
                    letterSpacingOverride: null,
                    wordSpacingOverride: null,
                    paragraphSpacingOverride: null,
                  ),
              child: child!,
            );
          },
        );
      },
      home: material
          ? Material(child: home)
          : DefaultTextStyle(
              style: const TextStyle(color: Color(0xFF000000)),
              child: home,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The rect [element]'s render box paints in global coordinates, through
/// any scale its ancestors apply.
Rect paintedRect(Element element) {
  final box = element.renderObject! as RenderBox;
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

/// The painted rect of the one widget [finder] finds.
Rect paintedRectOf(WidgetTester tester, Finder finder) {
  return paintedRect(tester.element(finder));
}

/// Whether [outer] holds [inner], to a hundredth of a pixel.
bool holds(Rect outer, Rect inner) {
  const slack = 0.01;
  return inner.left >= outer.left - slack &&
      inner.top >= outer.top - slack &&
      inner.right <= outer.right + slack &&
      inner.bottom <= outer.bottom + slack;
}

/// The text of each label [labels] finds whose paragraph does not hold it
/// whole on one line: whose box is narrower than its text on one line, or
/// shorter than that line.
List<String> cutLabels(WidgetTester tester, Finder labels) {
  return <String>[
    for (final element in labels.evaluate())
      if (!_holdsWhole(element.renderObject! as RenderParagraph))
        (element.renderObject! as RenderParagraph).text.toPlainText(),
  ];
}

bool _holdsWhole(RenderParagraph paragraph) {
  const slack = 0.01;
  return paragraph.size.width >=
          paragraph.getMaxIntrinsicWidth(double.infinity) - slack &&
      paragraph.size.height >=
          paragraph.getMinIntrinsicHeight(double.infinity) - slack;
}

/// Whether the label [finder] finds paints at its full size: as large as
/// its text laid out whole on one line, unscaled.
bool atFullSize(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  final paragraph = element.renderObject! as RenderParagraph;
  final painted = paintedRect(element);
  const slack = 0.01;
  return (painted.width - paragraph.getMaxIntrinsicWidth(double.infinity))
              .abs() <
          slack &&
      (painted.height - paragraph.getMinIntrinsicHeight(double.infinity))
              .abs() <
          slack;
}

/// The text of each label [labels] finds that paints outside the rect
/// [boxOf] gives for it.
List<String> labelsOutside(Finder labels, Rect Function(Element label) boxOf) {
  return <String>[
    for (final element in labels.evaluate())
      if (!holds(boxOf(element), paintedRect(element)))
        (element.renderObject! as RenderParagraph).text.toPlainText(),
  ];
}

/// The rich texts under [scope], one per [Text].
Finder textsUnder(Finder scope) {
  return find.descendant(of: scope, matching: find.byType(RichText));
}

/// The painted rect of the nearest widget above [element] that [test]
/// accepts.
Rect enclosingWhere(Element element, bool Function(Widget widget) test) {
  Element? found;
  element.visitAncestorElements((ancestor) {
    if (test(ancestor.widget)) {
      found = ancestor;
      return false;
    }
    return true;
  });
  return paintedRect(found!);
}

/// The painted rect of the nearest [T] above [element].
Rect enclosing<T extends Widget>(Element element) {
  return enclosingWhere(element, (widget) {
    return widget is T;
  });
}

/// Finds the rich texts that write a number.
final Finder numberTexts = find.byWidgetPredicate((widget) {
  return widget is RichText &&
      RegExp(r"^\d+$").hasMatch(widget.text.toPlainText());
});

/// Week over the week from Monday April 20 2026, with Tuesday selected and
/// today.
Widget week() {
  final store = MemoryCalendarStore<String>();
  addTearDown(store.dispose);
  final now = ValueNotifier<CalendarNow>(
    CalendarNow(time: DateTime(2026, 4, 21, 9), today: tuesday),
  );
  addTearDown(now.dispose);
  return TimedGrid<String>(
    store: store,
    onMoveRequest: writeMoveTo(store),
    firstDay: monday,
    dayCount: 7,
    selectedDay: tuesday,
    now: now,
    onSelectDay: (day) {},
    onOpenEntry: (id) {},
    onCreate: (details) async {},
  );
}

/// The days of the week from [first].
List<DateTime> weekFrom(DateTime first) {
  return <DateTime>[
    for (var i = 0; i < 7; i++) CalendarDates.addDays(first, i),
  ];
}

/// The labels of [day]'s cell of Week's day header: its weekday's short
/// name and its number.
({Finder cell, Finder name, Finder number}) headerOf(DateTime day) {
  final cell = find.byKey(dayHeaderKey(day));
  return (
    cell: cell,
    name: find.descendant(
      of: cell,
      matching: find.text(english.weekdayShortName(day.weekday)),
    ),
    number: find.descendant(of: cell, matching: find.text("${day.day}")),
  );
}

void main() {
  group("LT1 Week's day header", () {
    for (final material in <bool>[true, false]) {
      testWidgets("${material ? "on a Material" : "under a plain text style"}, "
          "grows with its text, its labels whole on one line in their "
          "cells at their full size, and fits them again for a new text "
          "scale", (tester) async {
        final scale = ValueNotifier<double>(1.0);
        addTearDown(scale.dispose);
        await recordingErrors((errors) async {
          await pumpScaled(tester, scale, week(), material: material);
          final tuesdayHeader = headerOf(tuesday);
          final cellAtOne = paintedRectOf(tester, tuesdayHeader.cell);
          final nameAtOne = paintedRectOf(tester, tuesdayHeader.name);
          final numberAtOne = paintedRectOf(tester, tuesdayHeader.number);
          final ringAtOne = enclosing<Container>(
            tester.element(tuesdayHeader.number),
          );
          double ringRadius() {
            final box = tester.widget<Container>(
              find.ancestor(
                of: tuesdayHeader.number,
                matching: find.byType(Container),
              ),
            );
            final decoration = box.foregroundDecoration! as BoxDecoration;
            return (decoration.borderRadius! as BorderRadius).topLeft.x;
          }

          expect(cellAtOne.height, 40.0);
          // Setup sanity: at no scaling the ring is a pill round at each end.
          expect(ringRadius(), closeTo(ringAtOne.height / 2.0, 0.1));

          scale.value = 2.0;
          await tester.pumpAndSettle();
          expect(errors, isEmpty);
          final days = weekFrom(monday);
          final labels = find.descendant(
            of: find.byWidgetPredicate((widget) {
              return days.any((day) {
                return widget.key == dayHeaderKey(day);
              });
            }),
            matching: find.byType(RichText),
          );
          expect(labels, findsNWidgets(14));
          expect(cutLabels(tester, labels), isEmpty);
          expect(
            labelsOutside(labels, (label) {
              return enclosing<GestureDetector>(label);
            }),
            isEmpty,
          );
          final name = paintedRectOf(tester, tuesdayHeader.name);
          final number = paintedRectOf(tester, tuesdayHeader.number);
          // Days about 95 px wide take both lines at their full size.
          expect(atFullSize(tester, tuesdayHeader.name), isTrue);
          expect(atFullSize(tester, tuesdayHeader.number), isTrue);
          expect(name.height, greaterThan(nameAtOne.height));
          expect(number.height, greaterThan(numberAtOne.height));
          final ring = enclosing<Container>(
            tester.element(tuesdayHeader.number),
          );
          expect(holds(ring, number), isTrue);
          final cell = paintedRectOf(tester, tuesdayHeader.cell);
          expect(cell.height, closeTo(name.height + ring.height, 0.01));
          // Today's ring keeps its shape: the room it has around the number
          // at no scaling, a pill round at each end.
          expect(
            ring.width - number.width,
            closeTo(ringAtOne.width - numberAtOne.width, 0.1),
          );
          expect(
            ring.height - number.height,
            closeTo(ringAtOne.height - numberAtOne.height, 0.1),
          );
          expect(ringRadius(), closeTo(ring.height / 2.0, 0.1));

          scale.value = 1.0;
          await tester.pumpAndSettle();
          expect(paintedRectOf(tester, tuesdayHeader.cell).height, 40.0);
          expect(errors, isEmpty);
        });
      });
    }

    testWidgets("in days too narrow for its labels scales them down to fit "
        "whole", (tester) async {
      final scale = ValueNotifier<double>(2.0);
      addTearDown(scale.dispose);
      await recordingErrors((errors) async {
        await pumpScaled(tester, scale, week(), size: const Size(360.0, 760.0));
        expect(errors, isEmpty);
        final shown = <DateTime>[
          for (final day in weekFrom(monday))
            if (find.byKey(dayHeaderKey(day)).evaluate().isNotEmpty) day,
        ];
        // Setup sanity: the header shows some days, and a day's number is
        // wider at its full size than its column.
        expect(shown, isNotEmpty);
        final first = headerOf(shown.first);
        final paragraph = tester.renderObject<RenderParagraph>(first.number);
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          greaterThan(paintedRectOf(tester, first.cell).width),
        );
        final labels = find.descendant(
          of: find.byWidgetPredicate((widget) {
            return shown.any((day) {
              return widget.key == dayHeaderKey(day);
            });
          }),
          matching: find.byType(RichText),
        );
        expect(cutLabels(tester, labels), isEmpty);
        expect(
          labelsOutside(labels, (label) {
            return enclosing<GestureDetector>(label);
          }),
          isEmpty,
        );
      });
    });

    testWidgets("grows for a new style of its numbers at the same text "
        "scale", (tester) async {
      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);
      final theme = ValueNotifier<CalendarThemeData>(CalendarThemeData());
      addTearDown(theme.dispose);
      final grid = week();
      await pumpScaled(
        tester,
        scale,
        ValueListenableBuilder<CalendarThemeData>(
          valueListenable: theme,
          child: grid,
          builder: (context, value, child) {
            return CalendarTheme(data: value, child: child!);
          },
        ),
      );
      final header = headerOf(tuesday);
      expect(paintedRectOf(tester, header.cell).height, 40.0);
      theme.value = CalendarThemeData(
        dayHeaderNumberStyle: const TextStyle(fontSize: 30.0),
      );
      await tester.pumpAndSettle();
      final name = paintedRectOf(tester, header.name);
      final ring = enclosing<Container>(tester.element(header.number));
      expect(
        paintedRectOf(tester, header.cell).height,
        closeTo(name.height + ring.height, 0.01),
      );
      expect(paintedRectOf(tester, header.cell).height, greaterThan(40.0));
      final box = tester.widget<Container>(
        find.ancestor(of: header.number, matching: find.byType(Container)),
      );
      final decoration = box.foregroundDecoration! as BoxDecoration;
      expect(
        (decoration.borderRadius! as BorderRadius).topLeft.x,
        closeTo(ring.height / 2.0, 0.1),
      );
    });

    testWidgets("grows for a line height override at no text scaling", (
      tester,
    ) async {
      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);
      await recordingErrors((errors) async {
        await pumpScaled(tester, scale, week(), lineHeight: 2.5);
        expect(errors, isEmpty);
        final header = headerOf(tuesday);
        final name = paintedRectOf(tester, header.name);
        final ring = enclosing<Container>(tester.element(header.number));
        expect(
          paintedRectOf(tester, header.cell).height,
          closeTo(name.height + ring.height, 0.01),
        );
        expect(atFullSize(tester, header.name), isTrue);
        expect(atFullSize(tester, header.number), isTrue);
      });
    });

    testWidgets("keeps a day's number at its full size where only the "
        "weekday's name is too wide for the day, which scales down", (
      tester,
    ) async {
      final scale = ValueNotifier<double>(1.5);
      addTearDown(scale.dispose);
      await recordingErrors((errors) async {
        await pumpScaled(tester, scale, week(), strings: const _WholeNames());
        expect(errors, isEmpty);
        final header = headerOf(DateTime(2026, 4, 22));
        final name = find.descendant(
          of: header.cell,
          matching: find.text("Wednesday"),
        );
        final cell = paintedRectOf(tester, header.cell);
        // Setup sanity: the name at its full size is wider than its day.
        expect(
          tester
              .renderObject<RenderParagraph>(name)
              .getMaxIntrinsicWidth(double.infinity),
          greaterThan(cell.width),
        );
        expect(holds(cell, paintedRectOf(tester, name)), isTrue);
        expect(atFullSize(tester, header.number), isTrue);
        // Every day's name scales alike, and every number lies alike.
        final days = weekFrom(monday);
        final nameHeights = <double>{
          for (final day in days)
            paintedRectOf(
              tester,
              find
                  .descendant(
                    of: headerOf(day).cell,
                    matching: find.byType(RichText),
                  )
                  .first,
            ).height.roundToDouble(),
        };
        expect(nameHeights, hasLength(1));
        final numberTops = <double>{
          for (final day in days)
            paintedRectOf(tester, headerOf(day).number).top.roundToDouble(),
        };
        expect(numberTops, hasLength(1));
      });
    });
  });

  group("LT2 the week strip's day cells", () {
    Widget strip(double width, DateTime day, {CalendarThemeData? theme}) {
      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);
      return CalendarTheme(
        data: theme ?? CalendarThemeData(),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: WeekStrip<String>(
              store: store,
              selectedDay: day,
              today: day,
              weekdays: CalendarWeekdaySet.all,
              onSelectDay: (day) {},
              onBrowse: (day) {},
            ),
          ),
        ),
      );
    }

    /// Each day cell's weekday label and number, with the cell and the
    /// number's circle.
    Finder labelsOf() {
      return textsUnder(find.byType(DayCell));
    }

    testWidgets("in a 350 px strip at text scale 2, each label is whole on "
        "one line in its cell, each number in its circle, and nothing "
        "overflows", (tester) async {
      final scale = ValueNotifier<double>(2.0);
      addTearDown(scale.dispose);
      await recordingErrors((errors) async {
        await pumpScaled(tester, scale, strip(350.0, tuesday));
        expect(errors, isEmpty);
        final labels = labelsOf();
        // Setup sanity: the strip shows at least its week's labels.
        expect(labels.evaluate().length, greaterThanOrEqualTo(14));
        expect(cutLabels(tester, labels), isEmpty);
        expect(
          labelsOutside(labels, (label) {
            return enclosing<DayCell>(label);
          }),
          isEmpty,
        );
        final numbers = find.descendant(
          of: find.byType(DayCell),
          matching: numberTexts,
        );
        // Clear of the circle's sides by today's ring and 2 px more.
        final inset = CalendarThemeData().todayRingWidth + 2.0;
        expect(
          labelsOutside(numbers, (label) {
            final circle = enclosing<Container>(label);
            return Rect.fromLTRB(
              circle.left + inset,
              circle.top,
              circle.right - inset,
              circle.bottom,
            );
          }),
          isEmpty,
        );
      });
    });

    testWidgets("with abbreviations of uneven lengths at text scale 2, "
        "every day's abbreviation scales alike and every circle lies alike", (
      tester,
    ) async {
      final scale = ValueNotifier<double>(2.0);
      addTearDown(scale.dispose);
      await recordingErrors((errors) async {
        await pumpScaled(
          tester,
          scale,
          strip(350.0, tuesday),
          strings: const _UnevenAbbreviations(),
        );
        expect(errors, isEmpty);
        final cells = find.byType(DayCell).evaluate().toList();
        // Setup sanity: "Thur" at its full size is wider than its day.
        final thur = find.text("Thur").evaluate().first;
        expect(
          (thur.renderObject! as RenderParagraph).getMaxIntrinsicWidth(
            double.infinity,
          ),
          greaterThan(paintedRect(cells.first).width),
        );
        final labelHeights = <double>{
          for (final cell in cells)
            paintedRect(
              find
                  .descendant(
                    of: find.byElementPredicate((element) {
                      return element == cell;
                    }),
                    matching: find.byType(RichText),
                  )
                  .evaluate()
                  .first,
            ).height.roundToDouble(),
        };
        expect(labelHeights, hasLength(1));
        final circleTops = <double>{
          for (final cell in cells)
            enclosing<Container>(
              find
                  .descendant(
                    of: find.byElementPredicate((element) {
                      return element == cell;
                    }),
                    matching: numberTexts,
                  )
                  .evaluate()
                  .single,
            ).top.roundToDouble(),
        };
        expect(circleTops, hasLength(1));
      });
    });

    testWidgets("under a line height override, nothing overflows and each "
        "label is whole in its cell", (tester) async {
      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);
      await recordingErrors((errors) async {
        await pumpScaled(tester, scale, strip(350.0, tuesday), lineHeight: 2.5);
        expect(errors, isEmpty);
        final labels = labelsOf();
        expect(cutLabels(tester, labels), isEmpty);
        expect(
          labelsOutside(labels, (label) {
            return enclosing<DayCell>(label);
          }),
          isEmpty,
        );
      });
    });

    testWidgets("in a 700 px strip, each label grows with the text scale "
        "where its cell and its circle hold it", (tester) async {
      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);
      // Numbers small enough that the widest, "28", fits the circle at
      // 1.25.
      await pumpScaled(
        tester,
        scale,
        strip(
          700.0,
          juneFirst,
          theme: CalendarThemeData(
            dayNumberStyle: const TextStyle(fontSize: 8.0),
            dayNumberMarkedStyle: const TextStyle(fontSize: 8.0),
          ),
        ),
      );
      final cell = find.byType(DayCell).evaluate().firstWhere((element) {
        return CalendarDates.dayNumber((element.widget as DayCell).day) ==
            CalendarDates.dayNumber(juneFirst);
      });
      Finder label(String text) {
        return find.descendant(
          of: find.byElementPredicate((element) {
            return element == cell;
          }),
          matching: find.text(text),
        );
      }

      final name = label(english.weekdayAbbreviation(DateTime.monday));
      final number = label("1");
      final nameAtOne = paintedRectOf(tester, name);
      final numberAtOne = paintedRectOf(tester, number);
      scale.value = 1.25;
      await tester.pumpAndSettle();
      expect(atFullSize(tester, name), isTrue);
      expect(atFullSize(tester, number), isTrue);
      expect(paintedRectOf(tester, name).height, greaterThan(nameAtOne.height));
      expect(
        paintedRectOf(tester, number).height,
        greaterThan(numberAtOne.height),
      );
    });
  });

  group("LT3 the weekday header", () {
    Widget header({required bool abbreviated, double? columnWidth}) {
      return Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 350.0,
          child: WeekdayHeader(
            weekdays: CalendarWeekdaySet.all,
            abbreviated: abbreviated,
            columnWidth: columnWidth,
          ),
        ),
      );
    }

    final headerFinder = find.byType(WeekdayHeader);

    for (final abbreviated in <bool>[false, true]) {
      for (final columnWidth in <double?>[null, 50.0]) {
        testWidgets(
          "at text scale 2, ${abbreviated ? "abbreviated" : "letters"}"
          "${columnWidth == null ? "" : " in columns $columnWidth px wide"}, "
          "each label is whole on one line in its column and the header",
          (tester) async {
            final scale = ValueNotifier<double>(2.0);
            addTearDown(scale.dispose);
            await recordingErrors((errors) async {
              await pumpScaled(
                tester,
                scale,
                header(abbreviated: abbreviated, columnWidth: columnWidth),
              );
              expect(errors, isEmpty);
              final labels = textsUnder(headerFinder);
              expect(labels, findsNWidgets(7));
              final headerRect = paintedRectOf(tester, headerFinder);
              // Setup sanity: a label at its full size does not fit.
              final first = tester.renderObject<RenderParagraph>(labels.first);
              final full = Size(
                first.getMaxIntrinsicWidth(double.infinity),
                first.getMinIntrinsicHeight(double.infinity),
              );
              expect(
                full.width > headerRect.width / 7 ||
                    full.height > headerRect.height,
                isTrue,
              );
              expect(cutLabels(tester, labels), isEmpty);
              final columns = <Rect>[
                for (var i = 0; i < 7; i++)
                  Rect.fromLTWH(
                    headerRect.left + i * headerRect.width / 7,
                    headerRect.top,
                    headerRect.width / 7,
                    headerRect.height,
                  ),
              ];
              final elements = labels.evaluate().toList();
              expect(<int>[
                for (var i = 0; i < 7; i++)
                  if (!holds(columns[i], paintedRect(elements[i]))) i,
              ], isEmpty);
            });
          },
        );
      }
    }

    testWidgets("with abbreviations of uneven lengths at text scale 2, every "
        "column's abbreviation scales alike", (tester) async {
      final scale = ValueNotifier<double>(2.0);
      addTearDown(scale.dispose);
      await pumpScaled(
        tester,
        scale,
        header(abbreviated: true),
        strings: const _UnevenAbbreviations(),
      );
      final heights = <double>{
        for (final label in textsUnder(headerFinder).evaluate())
          paintedRect(label).height.roundToDouble(),
      };
      // Setup sanity: "Thur" at its full size is wider than its column.
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.descendant(of: headerFinder, matching: find.text("Thur")),
            )
            .getMaxIntrinsicWidth(double.infinity),
        greaterThan(paintedRectOf(tester, headerFinder).width / 7),
      );
      expect(heights, hasLength(1));
    });

    testWidgets("letters grow with the text scale where the header holds "
        "them", (tester) async {
      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);
      await pumpScaled(tester, scale, header(abbreviated: false));
      final m = find.descendant(of: headerFinder, matching: find.text("M"));
      final atOne = paintedRectOf(tester, m);
      scale.value = 1.25;
      await tester.pumpAndSettle();
      expect(atFullSize(tester, m), isTrue);
      expect(paintedRectOf(tester, m).height, greaterThan(atOne.height));
    });
  });

  group("LT4 Month's day numbers", () {
    Widget month(DateTime selected) {
      final store = MemoryCalendarStore<String>();
      addTearDown(store.dispose);
      final now = ValueNotifier<CalendarNow>(
        CalendarNow(time: DateTime(2026, 4, 21, 9), today: tuesday),
      );
      addTearDown(now.dispose);
      return MonthBoard<String>(
        store: store,
        grid: CalendarMonthGrid.of(selected),
        selectedDay: selected,
        now: now,
        onSelectDay: (day) {},
        onOpenDay: (day) {},
        onCreateOnDay: null,
        onOpenEntry: (id) {},
      );
    }

    /// The number of [day] in Month.
    Finder numberOf(DateTime day) {
      return find.descendant(
        of: find.byKey(monthStripKey(day)),
        matching: find.text("${day.day}"),
      );
    }

    testWidgets("at text scale 2, each number is whole on one line in its "
        "day's number strip, today's and the selected day's in their boxes", (
      tester,
    ) async {
      final scale = ValueNotifier<double>(2.0);
      addTearDown(scale.dispose);
      final selected = DateTime(2026, 4, 23);
      await recordingErrors((errors) async {
        await pumpScaled(tester, scale, month(selected));
        expect(errors, isEmpty);
        final grid = CalendarMonthGrid.of(selected);
        final days = <DateTime>[
          for (
            var day = grid.firstDay;
            !day.isAfter(grid.lastDay);
            day = CalendarDates.addDays(day, 1)
          )
            day,
        ];
        final strips = <Key>{for (final day in days) monthStripKey(day)};
        bool isStrip(Widget widget) {
          return strips.contains(widget.key);
        }

        final shown = find.descendant(
          of: find.byWidgetPredicate(isStrip),
          matching: numberTexts,
        );
        expect(shown, findsNWidgets(days.length));
        expect(cutLabels(tester, shown), isEmpty);
        expect(
          labelsOutside(shown, (label) {
            return enclosingWhere(label, isStrip);
          }),
          isEmpty,
        );
        // Today's and the selected day's numbers draw as large as the rest.
        final heights = <double>{
          for (final day in <DateTime>[
            DateTime(2026, 4, 14),
            tuesday,
            selected,
          ])
            paintedRectOf(tester, numberOf(day)).height.roundToDouble(),
        };
        expect(heights, hasLength(1));
        for (final day in <DateTime>[tuesday, selected]) {
          final number = tester.element(numberOf(day));
          final box = enclosing<Container>(number);
          expect(holds(box, paintedRect(number)), isTrue, reason: "$day");
          expect(
            holds(paintedRectOf(tester, find.byKey(monthStripKey(day))), box),
            isTrue,
            reason: "$day",
          );
        }
      });
    });

    testWidgets("numbers grow with the text scale where the number strip "
        "holds them", (tester) async {
      final scale = ValueNotifier<double>(1.0);
      addTearDown(scale.dispose);
      final selected = DateTime(2026, 4, 23);
      await pumpScaled(tester, scale, month(selected));
      final plain = DateTime(2026, 4, 7);
      final atOne = <DateTime, Rect>{
        for (final day in <DateTime>[plain, tuesday, selected])
          day: paintedRectOf(tester, numberOf(day)),
      };
      Rect boxOf(DateTime day) {
        return enclosing<Container>(tester.element(numberOf(day)));
      }

      /// The corner radius of [day]'s pill or ring.
      double radiusOf(DateTime day) {
        final box = tester.widget<Container>(
          find.ancestor(of: numberOf(day), matching: find.byType(Container)),
        );
        final decoration =
            (box.decoration ?? box.foregroundDecoration)! as BoxDecoration;
        return (decoration.borderRadius! as BorderRadius).topLeft.x;
      }

      final boxAtOne = <DateTime, Rect>{
        for (final day in <DateTime>[tuesday, selected]) day: boxOf(day),
      };
      // Setup sanity: at no scaling each box is a pill round at each end.
      for (final day in boxAtOne.keys) {
        expect(
          radiusOf(day),
          closeTo(boxAtOne[day]!.height / 2.0, 0.1),
          reason: "$day",
        );
      }
      scale.value = 1.25;
      await tester.pumpAndSettle();
      for (final day in atOne.keys) {
        expect(atFullSize(tester, numberOf(day)), isTrue, reason: "$day");
        expect(
          paintedRectOf(tester, numberOf(day)).height,
          greaterThan(atOne[day]!.height),
          reason: "$day",
        );
      }
      // Today's ring and the selected day's pill keep the room they have
      // around the number at no scaling, round at each end.
      for (final day in boxAtOne.keys) {
        final box = boxOf(day);
        final number = paintedRectOf(tester, numberOf(day));
        expect(
          box.width - number.width,
          closeTo(boxAtOne[day]!.width - atOne[day]!.width, 0.1),
          reason: "$day",
        );
        expect(
          box.height - number.height,
          closeTo(boxAtOne[day]!.height - atOne[day]!.height, 0.1),
          reason: "$day",
        );
        expect(radiusOf(day), closeTo(box.height / 2.0, 0.1), reason: "$day");
      }
    });
  });
}
