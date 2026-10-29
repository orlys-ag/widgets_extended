/// The timed grid's hour gutter: the width it takes for the hour labels,
/// how the labels lie in it, on one line, on two or shrunk, what makes it
/// fit them again, and the grid's pinch and drags beside a gutter wider
/// than its least.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/pinch_zoom.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);

/// The size of the view every test lays the grid out in.
const Size viewSize = Size(800.0, 600.0);

/// English, but for the times of day, which [write] writes.
class _Times extends DefaultCalendarLocalizations {
  const _Times(this.write);

  final String Function(int minute) write;

  @override
  String formatTime(int minute, HourLabelFormat format) {
    return write(minute);
  }
}

class _TimesDelegate extends LocalizationsDelegate<CalendarLocalizations> {
  const _TimesDelegate(this.strings);

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
  bool shouldReload(_TimesDelegate old) {
    return !identical(old.strings, strings);
  }
}

/// A canvas that records the paragraphs drawn on it, each with the offset
/// of its top left, and the rects it is clipped to, each in the order it
/// came. Every other call is ignored.
class RecordingCanvas implements Canvas {
  final List<({ui.Paragraph paragraph, Offset offset})> paragraphs =
      <({ui.Paragraph paragraph, Offset offset})>[];

  final List<Rect> clips = <Rect>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    paragraphs.add((paragraph: paragraph, offset: offset));
  }

  @override
  void save() {}

  @override
  void restore() {}

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    clips.add(rect);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

/// One hour label as the grid's foreground paints it: the rect its text
/// takes, from its lines, in the viewport's paint space, how many lines it
/// has, where each line ends, and the rect it is clipped to.
typedef PaintedLabel = ({Rect ink, int lines, List<double> ends, Rect clip});

/// A timed grid over the week from Monday, built from the fields as they
/// are when it builds, in a view of [viewSize] at one device pixel per
/// logical pixel. The test font draws each character as a square as wide
/// as the font size, so a label 5 characters long at 11 px is 55 px wide.
class Harness {
  Harness({List<CalendarEntry<String>> entries = const []})
    : store = MemoryCalendarStore<String>(entries: entries);

  final MemoryCalendarStore<String> store;
  final ValueNotifier<CalendarNow> now = ValueNotifier<CalendarNow>(
    // A Sunday, a day the week does not show, so no line marks the time.
    CalendarNow(time: DateTime(2026, 4, 19, 9), today: DateTime(2026, 4, 19)),
  );

  HourLabelFormat format = HourLabelFormat.twentyFourHour;
  DayHours hours = const DayHours(8 * 60, 12 * 60);
  int slotMinutes = 15;
  double minSlotHeight = defaultMinSlotHeight;
  double minDayWidth = 44.0;
  TextScaler textScaler = TextScaler.noScaling;

  /// The hour labels' style, through a [CalendarTheme]; null for the
  /// theme's own.
  TextStyle? labelStyle;

  /// The localizations, through a delegate; null for the English default.
  CalendarLocalizations? strings;

  /// Whether a pinch zooms the grid, which then takes the sizes it
  /// reports.
  bool zooms = false;

  bool editable = false;

  Widget app() {
    final strings = this.strings;
    return MaterialApp(
      localizationsDelegates: <LocalizationsDelegate<Object?>>[
        if (strings != null) _TimesDelegate(strings),
      ],
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        );
      },
      home: StatefulBuilder(
        builder: (context, setState) {
          final Widget grid = TimedGrid<String>(
            store: store,
            firstDay: monday,
            dayCount: 7,
            selectedDay: tuesday,
            now: now,
            onSelectDay: (day) {},
            onOpenEntry: (id) {},
            onCreate: (range) async {},
            onZoom: zooms
                ? (slot, day) {
                    setState(() {
                      minSlotHeight = slot;
                      minDayWidth = day;
                    });
                  }
                : null,
            editable: editable,
            hours: hours,
            slotMinutes: slotMinutes,
            hourLabelFormat: format,
            minSlotHeight: minSlotHeight,
            minDayWidth: minDayWidth,
          );
          // Always under a theme, so a new style keeps the grid's state.
          const theme = CalendarThemeData();
          return CalendarTheme(
            data: theme.copyWith(hourLabelStyle: labelStyle),
            child: grid,
          );
        },
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewSize;
    addTearDown(tester.view.reset);
    addTearDown(store.dispose);
    addTearDown(now.dispose);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  /// Builds the grid again with the fields as they are now.
  Future<void> rebuild(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }
}

/// The grid's viewport: the one board keyed by [GridKey]s.
RenderBoardViewport<GridKey> viewportOf(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
}

/// The hour gutter's width: the board's frozen band across.
double gutterOf(WidgetTester tester) {
  return viewportOf(tester).frozenInsetOf(Axis.horizontal);
}

/// The hour labels the grid's foreground paints, in the order it paints
/// them: the labelled lines from the top, then the end of the hours.
List<PaintedLabel> labelsOf(WidgetTester tester) {
  final viewport = viewportOf(tester);
  final canvas = RecordingCanvas();
  viewport.foreground!.paint(canvas, viewport);
  return <PaintedLabel>[
    for (var i = 0; i < canvas.paragraphs.length; i++)
      (
        ink: inkOf(canvas.paragraphs[i]),
        lines: canvas.paragraphs[i].paragraph.computeLineMetrics().length,
        ends: <double>[
          for (final line
              in canvas.paragraphs[i].paragraph.computeLineMetrics())
            canvas.paragraphs[i].offset.dx + line.left + line.width,
        ],
        clip: canvas.clips[i],
      ),
  ];
}

/// The rect [label]'s lines take, offset to where it was drawn.
Rect inkOf(({ui.Paragraph paragraph, Offset offset}) label) {
  var left = double.infinity;
  var right = double.negativeInfinity;
  for (final line in label.paragraph.computeLineMetrics()) {
    left = math.min(left, line.left);
    right = math.max(right, line.left + line.width);
  }
  return Rect.fromLTRB(
    left,
    0.0,
    right,
    label.paragraph.height,
  ).shift(label.offset);
}

/// The line between the slot rows above and below [row]: the top edge of
/// [row]'s cell in the first day column.
double lineAbove(WidgetTester tester, int row) {
  return viewportOf(tester).rectOfCell(row, 1)!.top;
}

void main() {
  testWidgets("GF1 labels wider than the least gutter's room with no break "
      "in them widen the gutter to the widest and 6 px on each side, and "
      "the days share the rest", (tester) async {
    final harness = Harness()..hours = const DayHours(8 * 60, 18 * 60);
    await harness.pump(tester);
    // "08:00" and the rest are 55 px, 5 px past the least gutter's 50.
    expect(gutterOf(tester), 67.0);
    final labels = labelsOf(tester);
    expect(labels.map((label) => label.lines).toSet(), <int>{1});
    expect(
      labels.map((label) => (label.ink.left, label.ink.right)).toSet(),
      <(double, double)>{(6.0, 61.0)},
    );
    final viewport = viewportOf(tester);
    expect(viewport.rectOfCell(2, 7)!.right, moreOrLessEquals(viewSize.width));
  });

  testWidgets("GF2 labels that fit the least gutter's room keep it 56 px "
      "wide, each on one line 6 px inside its right edge", (tester) async {
    // At 10 px, "08:00" is 50 px, the room's width.
    final harness = Harness()
      ..labelStyle = const TextStyle(fontSize: 10.0, height: 1.0);
    await harness.pump(tester);
    expect(gutterOf(tester), 56.0);
    final labels = labelsOf(tester);
    expect(
      labels.map((label) => (label.ink.right, label.ink.width)).toSet(),
      <(double, double)>{(50.0, 50.0)},
    );
  });

  testWidgets("GF3 labels that break between words into two lines that fit "
      "the least gutter's room do so, where the closest labelled lines at "
      "the least slot height a pinch reaches are a two-line label apart; "
      "each lies centred on its line, and the room above the first line "
      "holds the tallest", (tester) async {
    // 8 px slots of 15 minutes make 32 px hours, which hold the 22 px of
    // two lines.
    final harness = Harness()
      ..format = HourLabelFormat.twelveHour
      ..zooms = true;
    await harness.pump(tester);
    expect(gutterOf(tester), 56.0);
    final labels = labelsOf(tester);
    // 8 AM, 9 AM, 10 AM, 11 AM and the end, 12 PM.
    expect(labels.map((label) => label.lines), <int>[1, 1, 2, 2, 2]);
    expect(labels.map((label) => label.ink.right).toSet(), <double>{50.0});
    // The first slot is row 2, under the day header and the room.
    expect(labels[0].ink.center.dy, lineAbove(tester, 2));
    expect(labels[2].ink.center.dy, lineAbove(tester, 10));
    expect(viewportOf(tester).rectOfCell(1, 1)!.height, 22.0 / 2 + 2.0);
  });

  group("GF4 labels too wide for the least gutter's room stay on one line "
      "and widen the gutter where two lines would not fit between the "
      "closest labelled lines", () {
    testWidgets("at the least slot height a pinch reaches", (tester) async {
      // 8 px slots of 30 minutes make 16 px hours.
      final harness = Harness()
        ..format = HourLabelFormat.twelveHour
        ..slotMinutes = 30
        ..zooms = true;
      await harness.pump(tester);
      expect(gutterOf(tester), 67.0);
      expect(labelsOf(tester).map((label) => label.lines).toSet(), <int>{1});
    });

    testWidgets("at the grid's least slot height where no pinch zooms it", (
      tester,
    ) async {
      // 4 px slots of 15 minutes make 16 px hours.
      final harness = Harness()
        ..format = HourLabelFormat.twelveHour
        ..minSlotHeight = 4.0;
      await harness.pump(tester);
      expect(gutterOf(tester), 67.0);
      // 5.5 px slots make 22 px hours, which just hold two lines.
      harness.minSlotHeight = 5.5;
      await harness.rebuild(tester);
      expect(gutterOf(tester), 56.0);
    });

    testWidgets("where the hours start on a half hour, half an hour from "
        "the next", (tester) async {
      final harness = Harness()
        ..strings = _Times((minute) {
          return "ab cd";
        })
        ..zooms = true;
      await harness.pump(tester);
      expect(gutterOf(tester), 56.0);
      // 07:30 to 08:00 is two 8 px slots.
      harness.hours = const DayHours(7 * 60 + 30, 12 * 60);
      await harness.rebuild(tester);
      expect(gutterOf(tester), 67.0);
    });
  });

  testWidgets("GF5 labels wider than 96 px less 6 px on each side shrink "
      "until the widest fits a gutter 96 px wide, and a label that fits it "
      "does not", (tester) async {
    final harness = Harness()
      ..strings = _Times((minute) {
        return "abcdefghij";
      });
    await harness.pump(tester);
    expect(gutterOf(tester), 96.0);
    final labels = labelsOf(tester);
    expect(labels.map((label) => label.ink.right).toSet(), <double>{90.0});
    for (final label in labels) {
      expect(label.ink.width, lessThanOrEqualTo(84.0));
      expect(label.ink.width, greaterThan(83.0));
    }
    // At 12 px, 7 characters are 84 px.
    harness
      ..strings = _Times((minute) {
        return "abcdefg";
      })
      ..labelStyle = const TextStyle(fontSize: 12.0, height: 1.0);
    await harness.rebuild(tester);
    expect(gutterOf(tester), 96.0);
    expect(labelsOf(tester).map((label) => label.ink.width).toSet(), <double>{
      84.0,
    });
  });

  group("GF6 the gutter fits the labels again for a new", () {
    testWidgets("text scale", (tester) async {
      final harness = Harness();
      await harness.pump(tester);
      expect(gutterOf(tester), 67.0);
      harness.textScaler = const TextScaler.linear(1.5);
      await harness.rebuild(tester);
      expect(gutterOf(tester), 55.0 * 1.5 + 12.0);
    });

    testWidgets("hour format", (tester) async {
      final harness = Harness()..hours = const DayHours(13 * 60, 18 * 60);
      await harness.pump(tester);
      expect(gutterOf(tester), 67.0);
      // "1 PM" to "6 PM" are 44 px.
      harness.format = HourLabelFormat.twelveHour;
      await harness.rebuild(tester);
      expect(gutterOf(tester), 56.0);
    });

    testWidgets("localizations", (tester) async {
      final harness = Harness()
        ..strings = _Times((minute) {
          return "abcdef";
        });
      await harness.pump(tester);
      expect(gutterOf(tester), 78.0);
      harness.strings = _Times((minute) {
        return "abcd";
      });
      await harness.rebuild(tester);
      expect(gutterOf(tester), 56.0);
    });

    testWidgets("label style", (tester) async {
      final harness = Harness();
      await harness.pump(tester);
      expect(gutterOf(tester), 67.0);
      harness.labelStyle = const TextStyle(fontSize: 9.0, height: 1.0);
      await harness.rebuild(tester);
      expect(gutterOf(tester), 56.0);
    });

    testWidgets("hours", (tester) async {
      // 4 px slots make 16 px hours, too short for two lines.
      final harness = Harness()
        ..format = HourLabelFormat.twelveHour
        ..minSlotHeight = 4.0
        ..hours = const DayHours(13 * 60, 18 * 60);
      await harness.pump(tester);
      expect(gutterOf(tester), 56.0);
      // 10 AM is 55 px.
      harness.hours = const DayHours(8 * 60, 18 * 60);
      await harness.rebuild(tester);
      expect(gutterOf(tester), 67.0);
    });

    testWidgets("slot length", (tester) async {
      // 4 px slots of 15 minutes make 16 px hours, and of 5 minutes 48 px.
      final harness = Harness()
        ..format = HourLabelFormat.twelveHour
        ..minSlotHeight = 4.0;
      await harness.pump(tester);
      expect(gutterOf(tester), 67.0);
      harness.slotMinutes = 5;
      await harness.rebuild(tester);
      expect(gutterOf(tester), 56.0);
    });
  });

  testWidgets("GF7 a pinch zooms the grid and leaves the gutter and its "
      "labels as they are", (tester) async {
    // 30-minute slots: the hours hold two lines at the 16 px the grid
    // opens at, and not at the 8 px the pinch reaches. All day, the slots
    // are taller than the view and do not stretch.
    final harness = Harness()
      ..format = HourLabelFormat.twelveHour
      ..hours = DayHours.allDay
      ..slotMinutes = 30
      ..zooms = true;
    await harness.pump(tester);
    final before = gutterOf(tester);
    final focal = viewportOf(tester).localToGlobal(const Offset(400.0, 300.0));
    final first = await tester.startGesture(focal - const Offset(0.0, 60.0));
    final second = await tester.startGesture(focal + const Offset(0.0, 60.0));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await first.moveBy(const Offset(0.0, 5.0));
      await second.moveBy(const Offset(0.0, -5.0));
      await tester.pump();
      expect(gutterOf(tester), before);
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(harness.minSlotHeight, minSlotHeightLow);
    expect(gutterOf(tester), before);
    expect(before, 67.0);
  });

  testWidgets("GF8 a block moved over the gutter where it is wider than "
      "its least is over the gutter, and the landing label centres between "
      "the gutter and the grid's right edge", (tester) async {
    final harness = Harness(
      entries: <CalendarEntry<String>>[
        CalendarEntry<String>(
          id: "standup",
          start: DateTime(2026, 4, 21, 9),
          end: DateTime(2026, 4, 21, 10),
          title: "standup",
          color: const Color(0xFF336699),
          payload: "standup",
        ),
      ],
    )..editable = true;
    await harness.pump(tester);
    expect(gutterOf(tester), 67.0);
    final block = tester.getCenter(find.byKey(blockKey("standup", tuesday)));
    final gesture = await tester.startGesture(block);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await gesture.moveBy(const Offset(0.0, 40.0));
    await tester.pump();
    final landing = tester.getRect(find.byKey(landingLabelKey));
    expect(landing.center.dx, (67.0 + 8.0 + viewSize.width - 8.0) / 2);
    await gesture.moveTo(Offset(60.0, block.dy + 40.0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("GF9 beside a row counting entries outside the hours, a "
      "one-line label among two-line ones reaches past the row's edge by "
      "half its own height", (tester) async {
    final harness =
        Harness(
            entries: <CalendarEntry<String>>[
              CalendarEntry<String>(
                id: "early",
                start: DateTime(2026, 4, 21, 6),
                end: DateTime(2026, 4, 21, 7),
                title: "early",
                color: const Color(0xFF336699),
                payload: "early",
              ),
            ],
          )
          ..format = HourLabelFormat.twelveHour
          ..zooms = true;
    await harness.pump(tester);
    final labels = labelsOf(tester);
    final region = viewportOf(tester).scrolledRegion;
    // 8 AM, on the region's top edge, is one line among two-line ones.
    expect(labels.first.lines, 1);
    expect(labels.map((label) => label.lines), contains(2));
    expect(labels.first.ink.center.dy, region.top);
    expect(labels.first.clip.top, region.top - 11.0 / 2);
  });

  testWidgets("GF10 each line of a two-line label ends 6 px inside the "
      "gutter's right edge", (tester) async {
    final harness = Harness()
      ..strings = _Times((minute) {
        return "abc de";
      })
      ..zooms = true;
    await harness.pump(tester);
    expect(gutterOf(tester), 56.0);
    final labels = labelsOf(tester);
    expect(labels.map((label) => label.lines).toSet(), <int>{2});
    expect(labels.expand((label) => label.ends).toSet(), <double>{50.0});
  });
}
