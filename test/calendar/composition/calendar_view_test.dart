/// The calendar: the views its parameters list and the one it opens on,
/// the header built in, hidden or built by the host, what its gestures
/// report and the routes it opens, the cost of a pinch, a fold and the
/// month picker, the store's hours and range, the theme's motion and
/// strip row, a move of the calendar under a new parent, and the source
/// rules a release build depends on.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/board.dart';
import 'package:widgets_extended/calendar/composition/calendar_card.dart';
import 'package:widgets_extended/calendar/composition/calendar_header.dart';
import 'package:widgets_extended/calendar/composition/calendar_theme_extension.dart';
import 'package:widgets_extended/calendar/composition/calendar_view.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_data_source.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/history_lock_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/presentation/calendar_day_badges.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/store/caching_calendar_store.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/month_strip.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart';
import 'package:widgets_extended/calendar/views/timed_grid_layout.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';

import 'recording_store.dart';

final DateTime monday = DateTime(2026, 4, 20);
final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);
final DateTime thursday = DateTime(2026, 4, 23);
final DateTime saturday = DateTime(2026, 4, 25);
final DateTime sunday = DateTime(2026, 4, 26);

/// 11:07 on Tuesday April 21 2026.
DateTime fixedClock() {
  return DateTime(2026, 4, 21, 11, 7);
}

/// A theme with no ink splash, whose shader a widget test cannot load.
ThemeData plainTheme({List<ThemeExtension<dynamic>>? extensions}) {
  return ThemeData(
    splashFactory: NoSplash.splashFactory,
    extensions: extensions,
  );
}

/// [home] under a MaterialApp, with no Scaffold.
Widget app(
  Widget home, {
  ThemeData? theme,
  List<NavigatorObserver> observers = const <NavigatorObserver>[],
}) {
  return MaterialApp(
    theme: theme ?? plainTheme(),
    navigatorObservers: observers,
    home: home,
  );
}

/// Lays the test out in a view 800 wide and 2000 tall, in which Week's and
/// Day's grids show every slot of the day.
void useTallView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800.0, 2000.0);
  addTearDown(tester.view.reset);
}

/// An entry from [start] to [end] minutes after [day]'s midnight.
CalendarEntry<String> entryOf(String id, DateTime day, int start, int end) {
  return CalendarEntry<String>(
    id: id,
    start: DateTime(day.year, day.month, day.day, 0, start),
    end: DateTime(day.year, day.month, day.day, 0, end),
    title: id,
    color: const Color(0xFF336699),
    payload: id,
  );
}

/// [hour]:[minute] on [day].
DateTime at(DateTime day, int hour, [int minute = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// The month grid's days of [day]'s month under [weekdays].
DayRange gridRange(DateTime day, {WeekdaySet weekdays = WeekdaySet.all}) {
  final grid = MonthGrid.of(day, weekdays: weekdays);
  return (first: grid.firstDay, last: grid.lastDay);
}

/// A data source that answers each read within the call, through a
/// [SynchronousFuture], with the entries covering its days, or, while
/// [holds] is set, holds the answer until the test runs [pending].
class HeldSource implements CalendarDataSource<String> {
  HeldSource(this.entries);

  final List<CalendarEntry<String>> entries;

  bool holds = false;

  final List<VoidCallback> pending = <VoidCallback>[];

  @override
  Future<List<CalendarEntry<String>>> read(DateTime first, DateTime last) {
    final from = dayNumber(first);
    final to = dayNumber(last);
    final answer = <CalendarEntry<String>>[
      for (final entry in entries)
        if (dayNumber(entry.start) <= to &&
            lastDayNumberOf(entry.start, entry.end) >= from)
          entry,
    ];
    if (!holds) {
      return SynchronousFuture<List<CalendarEntry<String>>>(answer);
    }
    final completer = Completer<List<CalendarEntry<String>>>();
    pending.add(() {
      completer.complete(answer);
    });
    return completer.future;
  }

  @override
  Future<CalendarEntry<String>> create(CalendarEntry<String> draft) {
    throw UnimplementedError();
  }

  @override
  Future<CalendarEntry<String>> replace(CalendarEntry<String> entry) {
    return SynchronousFuture<CalendarEntry<String>>(entry);
  }

  @override
  Future<void> delete(String id) {
    return SynchronousFuture<void>(null);
  }
}

/// Records the routes pushed while [recording] is set.
class PushRecorder extends NavigatorObserver {
  bool recording = false;

  final List<Route<dynamic>> pushes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (recording) {
      pushes.add(route);
    }
  }
}

/// A canvas that records the rects drawn on it with their paints. Every
/// other call is ignored.
class RecordingCanvas implements Canvas {
  final List<({Rect rect, Paint paint})> rects = <({Rect rect, Paint paint})>[];

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add((rect: rect, paint: paint));
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
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return null;
  }
}

/// The block of [id]'s piece on [day], or with no [day] the one block of
/// [id].
Finder blockFinder(String id, [DateTime? day]) {
  if (day != null) {
    return find.byKey(blockKey(id, day));
  }
  return find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith("block-$id@");
  });
}

/// The one timed grid's viewport.
RenderBoardViewport<GridKey> gridViewport(WidgetTester tester) {
  return tester.allRenderObjects
      .whereType<RenderBoardViewport<GridKey>>()
      .single;
}

/// The grid row of the slot holding [minute], a minute after midnight, in
/// the one timed grid shown now: its first slot row, under the day header
/// in Week, the all-day strip's rows and the room above the slots, which is
/// its board's row count less its slot rows and the room below them, plus
/// the slots from its hours' start.
int gridRowOf(int minute) {
  final grid =
      find
              .byWidgetPredicate((widget) {
                return widget is TimedGrid;
              })
              .evaluate()
              .single
              .widget
          as TimedGrid;
  final board =
      find
              .byWidgetPredicate((widget) {
                return widget is Board<GridKey, Object?>;
              })
              .evaluate()
              .single
              .widget
          as Board<GridKey, Object?>;
  final hours = grid.hours;
  final firstSlotRow =
      board.controller.rows.axis.trackCount -
      hours.slotCountOf(grid.slotMinutes) -
      1;
  return firstSlotRow + (minute - hours.start) ~/ grid.slotMinutes;
}

/// Week's grid row of [minute] ([gridRowOf]).
int weekRowOf(int minute) {
  return gridRowOf(minute);
}

/// Day's grid row of [minute] ([gridRowOf]).
int dayRowOf(int minute) {
  return gridRowOf(minute);
}

/// Week's grid column of [day], Monday's being 1.
int weekColOf(DateTime day) {
  return 1 + weekdayColumnOfDay(dayNumber(day));
}

/// The global centre of the timed grid's cell at [row] and [col].
Offset cellCenter(WidgetTester tester, int row, int col) {
  final viewport = gridViewport(tester);
  return viewport.localToGlobal(viewport.rectOfCell(row, col)!.center);
}

/// Whether the timed grid's background marks a range of slots, which it
/// edges with a stroke.
bool marksRange(WidgetTester tester) {
  final viewport = gridViewport(tester);
  final canvas = RecordingCanvas();
  viewport.background!.paint(canvas, viewport);
  return canvas.rects.any((record) {
    return record.paint.style == PaintingStyle.stroke;
  });
}

/// A mouse press on the cell centred at [at] that moves 2 logical pixels
/// within it and lets go: a create of the slot.
Future<void> clickCell(WidgetTester tester, Offset at) async {
  final gesture = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
  await gesture.moveBy(const Offset(2.0, 0.0));
  await tester.pump();
  await gesture.up();
}

/// The nearest Material above [element].
Material? nearestMaterial(Element element) {
  Material? found;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is Material) {
      found = widget;
      return false;
    }
    return true;
  });
  return found;
}

/// The Materials between the timed grid and the calendar above it.
int materialsAboveGrid(WidgetTester tester) {
  final grid = tester.element(find.byType(TimedGrid<String>));
  final calendar = tester.element(find.byType(CalendarView<String>));
  var count = 0;
  grid.visitAncestorElements((ancestor) {
    if (identical(ancestor, calendar)) {
      return false;
    }
    if (ancestor.widget is Material) {
      count++;
    }
    return true;
  });
  return count;
}

/// Each argument list of an `assert(` in [source], to its matching
/// parenthesis.
List<String> assertArguments(String source) {
  final found = <String>[];
  for (final match in RegExp(r"\bassert\(").allMatches(source)) {
    var depth = 1;
    var at = match.end;
    while (depth > 0) {
      final char = source[at];
      if (char == "(") {
        depth++;
      } else if (char == ")") {
        depth--;
      }
      at++;
    }
    found.add(source.substring(match.end, at - 1));
  }
  return found;
}

/// The body of the method whose declaration [signature] starts, to its
/// matching brace.
String methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: signature);
  final open = source.indexOf("{", start + signature.length);
  var depth = 1;
  var at = open + 1;
  while (depth > 0) {
    final char = source[at];
    if (char == "{") {
      depth++;
    } else if (char == "}") {
      depth--;
    }
    at++;
  }
  return source.substring(open + 1, at - 1);
}

const List<String> builtInHeaderTooltips = <String>[
  "Calendar view",
  "Previous month",
  "Pick a month",
];

void main() {
  late RecordingStore store;

  setUp(() {
    store = RecordingStore();
  });

  tearDown(() {
    store.dispose();
  });

  testWidgets("CV1 a calendar under a MaterialApp with no Scaffold builds "
      "the header's ink and draws its views on the theme's body text, and "
      "under a Scaffold takes the Scaffold's Material", (tester) async {
    await tester.pumpWidget(
      app(CalendarView<String>(store: store, clock: fixedClock)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final calendar = find.byType(CalendarView<String>);
    expect(
      find.descendant(of: calendar, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(
      find.descendant(of: calendar, matching: find.byType(AppBar)),
      findsNothing,
    );
    expect(find.byType(DayList<String>), findsOneWidget);
    expect(find.text("Agenda"), findsOneWidget);
    final list = tester.element(find.byType(DayList<String>));
    final style = DefaultTextStyle.of(list).style;
    expect(style.decoration, anyOf(isNull, TextDecoration.none));
    final body = Theme.of(list).textTheme.bodyMedium!;
    expect(body.fontFamily, isNotNull);
    expect(style.fontFamily, body.fontFamily);

    await tester.pumpWidget(
      app(
        Scaffold(
          body: CalendarView<String>(store: store, clock: fixedClock),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scaffolds = nearestMaterial(
      tester.element(find.byType(CalendarView<String>)),
    );
    expect(scaffolds, isNotNull);
    expect(
      nearestMaterial(tester.element(find.byType(DayList<String>))),
      same(scaffolds),
    );
  });

  testWidgets("CV2 the view menu lists the views given, exactly and in "
      "their order", (tester) async {
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          clock: fixedClock,
          views: const <CalendarViewKind>[
            CalendarViewKind.month,
            CalendarViewKind.agenda,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Calendar view"));
    await tester.pumpAndSettle();
    final items = tester.widgetList<PopupMenuItem<CalendarViewKind>>(
      find.byType(PopupMenuItem<CalendarViewKind>),
    );
    expect(
      <CalendarViewKind?>[for (final item in items) item.value],
      <CalendarViewKind>[CalendarViewKind.month, CalendarViewKind.agenda],
    );
    expect(
      <String?>[
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(PopupMenuItem<CalendarViewKind>),
            matching: find.byType(Text),
          ),
        ))
          text.data,
      ],
      <String>["Month", "Agenda"],
    );
  });

  testWidgets("CV3 the calendar opens on the controller's view where the "
      "views list it, and with no controller on the first view listed", (
    tester,
  ) async {
    const views = <CalendarViewKind>[
      CalendarViewKind.month,
      CalendarViewKind.agenda,
    ];
    final controller = CalendarController(view: CalendarViewKind.agenda);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
          views: views,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DayList<String>), findsOneWidget);
    expect(find.byType(MonthBoard<String>), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      app(CalendarView<String>(store: store, clock: fixedClock, views: views)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MonthBoard<String>), findsOneWidget);
    expect(find.byType(DayList<String>), findsNothing);
  });

  testWidgets("CV4 with one view listed the header names it with no menu", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          clock: fixedClock,
          views: const <CalendarViewKind>[CalendarViewKind.week],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expect(find.text("Week"), findsOneWidget);
    expect(find.byTooltip("Calendar view"), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets("CV5 an empty views list throws an ArgumentError from the "
      "build, an error widget standing in the calendar's place alone, and a "
      "valid list brings the calendar back", (tester) async {
    Widget host(List<CalendarViewKind> views) {
      return app(
        Column(
          children: <Widget>[
            const Text("host"),
            Expanded(
              child: CalendarView<String>(
                store: store,
                clock: fixedClock,
                views: views,
              ),
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(host(const <CalendarViewKind>[]));
    final error = tester.takeException();
    expect(error, isA<ArgumentError>());
    expect((error as ArgumentError).message, "lists no view");
    expect(
      find.descendant(
        of: find.byType(CalendarView<String>),
        matching: find.byType(ErrorWidget),
      ),
      findsOneWidget,
    );
    expect(find.byType(DayList<String>), findsNothing);
    expect(find.text("host"), findsOneWidget);

    await tester.pumpWidget(
      host(const <CalendarViewKind>[CalendarViewKind.agenda]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.byType(DayList<String>), findsOneWidget);
    expect(
      calendarViewsError(const <CalendarViewKind>[]),
      isA<ArgumentError>(),
    );
  });

  testWidgets("CV6 a views list naming a view twice throws an ArgumentError "
      "at the first build and at a rebuild", (tester) async {
    Widget calendar(List<CalendarViewKind> views) {
      return app(
        CalendarView<String>(store: store, clock: fixedClock, views: views),
      );
    }

    final twice = isA<ArgumentError>().having(
      (error) {
        return error.message;
      },
      "message",
      "lists week twice",
    );
    await tester.pumpWidget(
      calendar(const <CalendarViewKind>[
        CalendarViewKind.week,
        CalendarViewKind.week,
      ]),
    );
    expect(tester.takeException(), twice);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      calendar(const <CalendarViewKind>[
        CalendarViewKind.agenda,
        CalendarViewKind.week,
      ]),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DayList<String>), findsOneWidget);
    await tester.pumpWidget(
      calendar(const <CalendarViewKind>[
        CalendarViewKind.week,
        CalendarViewKind.day,
        CalendarViewKind.week,
      ]),
    );
    expect(tester.takeException(), twice);
    expect(
      calendarViewsError(const <CalendarViewKind>[
        CalendarViewKind.week,
        CalendarViewKind.day,
        CalendarViewKind.week,
      ]),
      twice,
    );
    expect(
      calendarViewsError(const <CalendarViewKind>[
        CalendarViewKind.week,
        CalendarViewKind.day,
      ]),
      isNull,
    );
  });

  group("CV7 a controller view the views do not list", () {
    const listed = <CalendarViewKind>[
      CalendarViewKind.agenda,
      CalendarViewKind.week,
    ];

    testWidgets("at the bind fails an assertion and shows the first view "
        "listed", (tester) async {
      final controller = CalendarController(view: CalendarViewKind.day);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            controller: controller,
            clock: fixedClock,
            views: listed,
          ),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
      expect(controller.view, CalendarViewKind.agenda);
      await tester.pumpAndSettle();
      expect(find.text("Agenda"), findsOneWidget);
      expect(find.byType(DayList<String>), findsOneWidget);
    });

    testWidgets("swapped in fails an assertion and shows the first view "
        "listed", (tester) async {
      final first = CalendarController(view: CalendarViewKind.week);
      addTearDown(first.dispose);
      final second = CalendarController(view: CalendarViewKind.day);
      addTearDown(second.dispose);
      Widget calendar(CalendarController controller) {
        return app(
          CalendarView<String>(
            store: store,
            controller: controller,
            clock: fixedClock,
            views: listed,
          ),
        );
      }

      await tester.pumpWidget(calendar(first));
      await tester.pumpAndSettle();
      expect(find.byType(TimedGrid<String>), findsOneWidget);
      await tester.pumpWidget(calendar(second));
      expect(tester.takeException(), isA<AssertionError>());
      expect(second.view, CalendarViewKind.agenda);
      await tester.pumpAndSettle();
      expect(find.text("Agenda"), findsOneWidget);
      expect(find.byType(DayList<String>), findsOneWidget);
    });

    testWidgets("a host's set fails an assertion and leaves the view "
        "shown", (tester) async {
      final controller = CalendarController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            controller: controller,
            clock: fixedClock,
            views: listed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(() {
        controller.view = CalendarViewKind.month;
      }, throwsAssertionError);
      await tester.pumpAndSettle();
      expect(controller.view, CalendarViewKind.agenda);
      expect(find.byType(DayList<String>), findsOneWidget);
      expect(find.byType(MonthBoard<String>), findsNothing);
    });

    testWidgets("views that drop a host controller's view fail an "
        "assertion and show the first view listed", (tester) async {
      final controller = CalendarController(view: CalendarViewKind.week);
      addTearDown(controller.dispose);
      Widget calendar(List<CalendarViewKind> views) {
        return app(
          CalendarView<String>(
            store: store,
            controller: controller,
            clock: fixedClock,
            views: views,
          ),
        );
      }

      await tester.pumpWidget(calendar(listed));
      await tester.pumpAndSettle();
      expect(find.byType(TimedGrid<String>), findsOneWidget);
      await tester.pumpWidget(
        calendar(const <CalendarViewKind>[CalendarViewKind.agenda]),
      );
      expect(tester.takeException(), isA<AssertionError>());
      await tester.pumpAndSettle();
      expect(controller.view, CalendarViewKind.agenda);
      expect(find.byType(DayList<String>), findsOneWidget);
    });

    testWidgets("views that drop the view an own controller holds show the "
        "first view listed and fail nothing", (tester) async {
      Widget calendar(List<CalendarViewKind> views) {
        return app(
          CalendarView<String>(store: store, clock: fixedClock, views: views),
        );
      }

      await tester.pumpWidget(calendar(listed));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Calendar view"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Week").last);
      await tester.pumpAndSettle();
      expect(find.byType(TimedGrid<String>), findsOneWidget);
      await tester.pumpWidget(
        calendar(const <CalendarViewKind>[CalendarViewKind.agenda]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DayList<String>), findsOneWidget);
    });

    testWidgets("a header's onSelectView fails an assertion and leaves the "
        "view shown", (tester) async {
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            clock: fixedClock,
            views: listed,
            headerBuilder: (context, details) {
              return TextButton(
                onPressed: () {
                  details.onSelectView(CalendarViewKind.month);
                },
                child: const Text("month"),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text("month"));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<AssertionError>());
      expect(find.byType(DayList<String>), findsOneWidget);
      expect(find.byType(MonthBoard<String>), findsNothing);
    });

    test("calendarOpeningView is the view asked where the views list it, "
        "and otherwise the first view listed", () {
      const views = <CalendarViewKind>[
        CalendarViewKind.week,
        CalendarViewKind.day,
      ];
      expect(
        calendarOpeningView(views, CalendarViewKind.month),
        CalendarViewKind.week,
      );
      expect(
        calendarOpeningView(views, CalendarViewKind.day),
        CalendarViewKind.day,
      );
      expect(calendarOpeningView(views, null), CalendarViewKind.week);
    });
  });

  testWidgets("CV8 the built-in header names the month, steps by the view's "
      "unit and opens and closes the month picker", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Apr 2026"), findsOneWidget);
    expect(find.byTooltip("Previous month"), findsOneWidget);
    expect(find.byTooltip("Next month"), findsOneWidget);
    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pumpAndSettle();
    expect(find.byTooltip("Previous week"), findsOneWidget);
    expect(find.byTooltip("Previous month"), findsNothing);

    controller.view = CalendarViewKind.week;
    await tester.pumpAndSettle();
    expect(find.byTooltip("Previous week"), findsOneWidget);
    controller.view = CalendarViewKind.day;
    await tester.pumpAndSettle();
    expect(find.byTooltip("Previous day"), findsOneWidget);
    controller.view = CalendarViewKind.month;
    await tester.pumpAndSettle();
    expect(find.byTooltip("Previous month"), findsOneWidget);

    const picker = ValueKey<String>("month-picker");
    expect(find.byKey(picker), findsNothing);
    await tester.tap(find.text("Apr 2026"));
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsOneWidget);
    expect(find.text("2026"), findsOneWidget);
    expect(find.byTooltip("Previous year"), findsOneWidget);
    expect(find.byTooltip("Close the months"), findsOneWidget);
    await tester.tap(find.text("2026"));
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsNothing);
    expect(find.text("Apr 2026"), findsOneWidget);
  });

  testWidgets("CV9 showsHeader false builds no header, and in Week no "
      "header card", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
          showsHeader: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DayList<String>), findsOneWidget);
    for (final tooltip in builtInHeaderTooltips) {
      expect(find.byTooltip(tooltip), findsNothing, reason: tooltip);
    }
    controller.view = CalendarViewKind.week;
    await tester.pumpAndSettle();
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expect(find.byKey(calendarDaysAreaKey), findsNothing);
    for (final tooltip in builtInHeaderTooltips) {
      expect(find.byTooltip(tooltip), findsNothing, reason: tooltip);
    }
  });

  testWidgets("CV10 a header builder builds in the built-in header's place "
      "from what it shows and the actions it calls", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    final seen = <CalendarHeaderDetails>[];
    Widget header(BuildContext context, CalendarHeaderDetails details) {
      seen.add(details);
      return Row(
        children: <Widget>[
          TextButton(onPressed: details.onNext, child: const Text("next")),
          TextButton(
            onPressed: () {
              details.onSelectView(CalendarViewKind.week);
            },
            child: const Text("week"),
          ),
          TextButton(
            onPressed: details.onOpenPicker,
            child: const Text("open"),
          ),
          TextButton(
            onPressed: details.onClosePicker,
            child: const Text("close"),
          ),
        ],
      );
    }

    void expectNoBuiltInHeader() {
      for (final tooltip in builtInHeaderTooltips) {
        expect(find.byTooltip(tooltip), findsNothing, reason: tooltip);
      }
    }

    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
          headerBuilder: header,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expectNoBuiltInHeader();
    final first = seen.last;
    expect(first.view, CalendarViewKind.agenda);
    expect(first.views, CalendarViewKind.values);
    expect(first.day, tuesday);
    expect(first.pickerYear, isNull);
    expect(first.stepUnit, CalendarStepUnit.month);

    await tester.tap(find.text("next"));
    await tester.pumpAndSettle();
    expect(seen.last.day.month, 5);
    expect(seen.last.day.year, 2026);
    expectNoBuiltInHeader();

    await tester.tap(find.text("week"));
    await tester.pumpAndSettle();
    expect(controller.view, CalendarViewKind.week);
    expect(find.byType(TimedGrid<String>), findsOneWidget);
    expectNoBuiltInHeader();

    const picker = ValueKey<String>("month-picker");
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsOneWidget);
    expect(seen.last.pickerYear, 2026);
    expect(seen.last.stepUnit, CalendarStepUnit.year);
    expectNoBuiltInHeader();

    await tester.tap(find.text("close"));
    await tester.pumpAndSettle();
    expect(find.byKey(picker), findsNothing);
    expect(seen.last.pickerYear, isNull);
    expectNoBuiltInHeader();
  });

  testWidgets("CV11 taps, creates, edits and deletes reach the host's "
      "callbacks and open no route, and with no callbacks raise nothing and "
      "leave no slot marked", (tester) async {
    useTallView(tester);
    final memory = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("past", monday, 10 * 60, 11 * 60),
        entryOf("later", wednesday, 10 * 60, 11 * 60),
      ],
    );
    addTearDown(memory.dispose);
    final controller = CalendarController(view: CalendarViewKind.week);
    addTearDown(controller.dispose);
    final observer = PushRecorder();
    final taps = <CalendarEntryTapDetails<String>>[];
    final creates = <CreateRange>[];
    final pending = <Completer<void>>[];
    final edits = <CalendarEntry<String>>[];
    final deletes = <CalendarEntry<String>>[];

    Widget card(
      BuildContext context,
      CalendarShownEntry<String> entry,
      CalendarCardDetails details,
    ) {
      return Row(
        children: <Widget>[
          TextButton(
            onPressed: details.onEdit,
            child: Text("edit ${entry.entry.id}"),
          ),
          TextButton(
            onPressed: details.onDelete,
            child: Text("delete ${entry.entry.id}"),
          ),
        ],
      );
    }

    double cardExtent(CalendarShownEntry<String> entry) {
      return 56.0;
    }

    Widget calendar({required bool reports}) {
      return app(
        CalendarView<String>(
          store: memory,
          controller: controller,
          clock: fixedClock,
          editable: true,
          editPolicy: const HistoryLockPolicy<String>(),
          cardBuilder: card,
          cardExtentOf: cardExtent,
          onEntryTap: reports ? taps.add : null,
          onCreateRange: reports
              ? (range) {
                  creates.add(range);
                  final completer = Completer<void>();
                  pending.add(completer);
                  return completer.future;
                }
              : null,
          onEditRequest: reports ? edits.add : null,
          onDeleteRequest: reports ? deletes.add : null,
        ),
        observers: <NavigatorObserver>[observer],
      );
    }

    void expectTap(String id, {required bool editable}) {
      expect(taps.last.entry, memory.storedEntry(id));
      expect(taps.last.editable, editable);
    }

    Finder addButton(DateTime day, int start) {
      return find.descendant(
        of: find.byKey(dayListGapKey(day, start)),
        matching: find.byIcon(const CalendarThemeData().addEntryIcon),
      );
    }

    await tester.pumpWidget(calendar(reports: true));
    await tester.pumpAndSettle();
    observer.recording = true;

    // Week.
    await tester.tap(blockFinder("past"));
    await tester.pumpAndSettle();
    expectTap("past", editable: false);
    await tester.tap(blockFinder("later"));
    await tester.pumpAndSettle();
    expectTap("later", editable: true);
    expect(marksRange(tester), isFalse);
    await clickCell(
      tester,
      cellCenter(tester, weekRowOf(14 * 60), weekColOf(thursday)),
    );
    await tester.pump();
    expect(
      creates.last,
      CreateRange(start: at(thursday, 14), end: at(thursday, 14, 15)),
    );
    // The slot stays marked while the host's future runs.
    expect(marksRange(tester), isTrue);
    pending.last.complete();
    await tester.pumpAndSettle();
    expect(marksRange(tester), isFalse);

    // Day.
    controller.selectedDay = wednesday;
    controller.view = CalendarViewKind.day;
    await tester.pumpAndSettle();
    await tester.tap(blockFinder("later"));
    await tester.pumpAndSettle();
    expectTap("later", editable: true);
    await clickCell(tester, cellCenter(tester, dayRowOf(14 * 60), 1));
    await tester.pump();
    expect(
      creates.last,
      CreateRange(start: at(wednesday, 14), end: at(wednesday, 14, 15)),
    );
    pending.last.complete();
    await tester.pumpAndSettle();
    controller.selectedDay = monday;
    await tester.pumpAndSettle();
    await tester.tap(blockFinder("past"));
    await tester.pumpAndSettle();
    expectTap("past", editable: false);

    // Month.
    controller.view = CalendarViewKind.month;
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(monthChipKey(monthSegmentKey("later", monday))),
    );
    await tester.pumpAndSettle();
    expectTap("later", editable: true);
    await tester.tap(find.byKey(monthChipKey(monthSegmentKey("past", monday))));
    await tester.pumpAndSettle();
    expectTap("past", editable: false);
    await tester.longPress(find.byKey(monthStripKey(thursday)));
    await tester.pumpAndSettle();
    expect(
      creates.last,
      CreateRange(start: at(thursday, 0), end: at(thursday, 0, 15)),
    );
    pending.last.complete();

    // Agenda.
    controller.selectedDay = wednesday;
    controller.view = CalendarViewKind.agenda;
    await tester.pumpAndSettle();
    await tester.tap(addButton(wednesday, 0));
    await tester.pumpAndSettle();
    expect(
      creates.last,
      CreateRange(start: at(wednesday, 0), end: at(wednesday, 0, 15)),
    );
    pending.last.complete();
    await tester.tap(find.text("edit later"));
    await tester.pumpAndSettle();
    expect(edits, <CalendarEntry<String>>[memory.storedEntry("later")!]);
    await tester.tap(find.text("delete later"));
    await tester.pumpAndSettle();
    expect(deletes, <CalendarEntry<String>>[memory.storedEntry("later")!]);
    expect(creates, hasLength(4));
    expect(observer.pushes, isEmpty);

    // With no callbacks.
    await tester.pumpWidget(calendar(reports: false));
    await tester.pumpAndSettle();
    await tester.tap(addButton(wednesday, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text("edit later"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("delete later"));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    controller.view = CalendarViewKind.week;
    await tester.pumpAndSettle();
    await clickCell(
      tester,
      cellCenter(tester, weekRowOf(14 * 60), weekColOf(thursday)),
    );
    await tester.pump();
    await tester.pump();
    expect(marksRange(tester), isFalse);
    expect(tester.takeException(), isNull);
    expect(observer.pushes, isEmpty);
    expect(creates, hasLength(4));
    expect(edits, hasLength(1));
    expect(deletes, hasLength(1));
    expect(taps, hasLength(6));
  });

  testWidgets("CV12 Month's long press reports a create at the first slot "
      "the history lock and the entries leave free, and on a day the lock "
      "holds whole reports a refusal", (tester) async {
    final memory = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("standup", tuesday, 11 * 60 + 15, 11 * 60 + 45),
      ],
    );
    addTearDown(memory.dispose);
    final controller = CalendarController(view: CalendarViewKind.month);
    addTearDown(controller.dispose);
    final creates = <CreateRange>[];
    final refused = <DateTime>[];
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: memory,
          controller: controller,
          clock: fixedClock,
          editable: true,
          editPolicy: const HistoryLockPolicy<String>(lockEarlierToday: true),
          onCreateRange: (range) async {
            creates.add(range);
          },
          onCreateRefused: refused.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(monthStripKey(tuesday)));
    await tester.pumpAndSettle();
    expect(creates, <CreateRange>[
      CreateRange(start: at(tuesday, 11, 45), end: at(tuesday, 12)),
    ]);
    expect(refused, isEmpty);
    await tester.longPress(find.byKey(monthStripKey(monday)));
    await tester.pumpAndSettle();
    expect(refused, <DateTime>[monday]);
    expect(creates, hasLength(1));
  });

  group("CV13 a pinch update notifies once and builds the calendar zero "
      "times", () {
    late int notifies;
    late int rebuilds;

    void count(CalendarController controller) {
      notifies = 0;
      rebuilds = 0;
      controller.addListener(() {
        notifies++;
      });
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is CalendarView<String>) {
          rebuilds++;
        }
      };
    }

    /// Pinches up and down at [focal] until the zoom moves, then moves one
    /// finger once more under [check].
    Future<void> pinchOnce(
      WidgetTester tester,
      Offset focal,
      double Function() zoom,
      void Function() check,
    ) async {
      final first = await tester.startGesture(focal - const Offset(0.0, 30.0));
      final second = await tester.startGesture(focal + const Offset(0.0, 30.0));
      await tester.pump();
      final start = zoom();
      for (var i = 0; i < 3; i++) {
        await first.moveBy(const Offset(0.0, -6.0));
        await second.moveBy(const Offset(0.0, 6.0));
        await tester.pump();
      }
      expect(zoom(), isNot(start));
      final before = zoom();
      notifies = 0;
      rebuilds = 0;
      await second.moveBy(const Offset(0.0, 8.0));
      await tester.pump();
      expect(notifies, 1);
      expect(rebuilds, 0);
      expect(zoom(), isNot(before));
      check();
      await first.up();
      await second.up();
    }

    testWidgets("in Week, the grid taking the controller's sizes", (
      tester,
    ) async {
      final controller = CalendarController(view: CalendarViewKind.week);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            controller: controller,
            clock: fixedClock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      count(controller);
      try {
        await pinchOnce(
          tester,
          tester.getCenter(find.byType(TimedGrid<String>)),
          () {
            return controller.minSlotHeight;
          },
          () {
            final grid = tester.widget<TimedGrid<String>>(
              find.byType(TimedGrid<String>),
            );
            expect(grid.minSlotHeight, controller.minSlotHeight);
            expect(grid.minDayWidth, controller.minDayWidth);
          },
        );
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      await tester.pumpAndSettle();
    });

    testWidgets("in Month, the board taking the controller's sizes", (
      tester,
    ) async {
      final controller = CalendarController(view: CalendarViewKind.month);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            controller: controller,
            clock: fixedClock,
          ),
        ),
      );
      await tester.pumpAndSettle();
      count(controller);
      try {
        await pinchOnce(
          tester,
          tester.getCenter(find.byType(MonthBoard<String>)),
          () {
            return controller.monthWeekScale;
          },
          () {
            final board = tester.widget<MonthBoard<String>>(
              find.byType(MonthBoard<String>),
            );
            expect(board.weekScale, controller.monthWeekScale);
            expect(board.minDayWidth, controller.minDayWidth);
          },
        );
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      await tester.pumpAndSettle();
    });
  });

  testWidgets("CV14 a drag on the pull tab folds the card with no notify "
      "and no build of the calendar", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    var notifies = 0;
    controller.addListener(() {
      notifies++;
    });
    var rebuilds = 0;
    final grid = find.byKey(const ValueKey<String>("calendar-grid"));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(calendarPullTabKey)),
    );
    await gesture.moveBy(const Offset(0.0, -30.0));
    await tester.pump();
    final before = tester.getSize(grid).height;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is CalendarView<String>) {
        rebuilds++;
      }
    };
    try {
      await gesture.moveBy(const Offset(0.0, -20.0));
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(notifies, 0);
    expect(rebuilds, 0);
    expect(tester.getSize(grid).height, isNot(before));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("CV15 a frame of the month picker's motion notifies nothing "
      "and builds the calendar zero times", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    var notifies = 0;
    controller.addListener(() {
      notifies++;
    });
    var rebuilds = 0;
    final area = find.byKey(calendarDaysAreaKey);
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pump();
    final before = tester.getSize(area).height;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is CalendarView<String>) {
        rebuilds++;
      }
    };
    try {
      await tester.pump(const Duration(milliseconds: 16));
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(notifies, 0);
    expect(rebuilds, 0);
    expect(tester.getSize(area).height, isNot(before));
    await tester.pumpAndSettle();
  });

  testWidgets("CV17 new weekdays that hide the selected day move it at once "
      "and notify once after the frame, the range already asked", (
    tester,
  ) async {
    final controller = CalendarController(selectedDay: saturday);
    addTearDown(controller.dispose);
    final readInBuild = <DateTime>[];
    Widget calendar(WeekdaySet weekdays) {
      return app(
        Column(
          children: <Widget>[
            Expanded(
              child: CalendarView<String>(
                store: store,
                controller: controller,
                clock: fixedClock,
                weekdays: weekdays,
              ),
            ),
            Builder(
              builder: (context) {
                readInBuild.add(controller.selectedDay);
                return const SizedBox(height: 1.0);
              },
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(calendar(WeekdaySet.all));
    await tester.pumpAndSettle();
    expect(controller.selectedDay, saturday);
    final calls = <({SchedulerPhase phase, DayRange? range, DayRange shown})>[];
    controller.addListener(() {
      calls.add((
        phase: SchedulerBinding.instance.schedulerPhase,
        range: controller.visibleRange,
        shown: store.shows.last,
      ));
    });
    final moved = shownDayNear(saturday, WeekdaySet.workweek);
    expect(moved, isNot(saturday));
    final range = gridRange(moved, weekdays: WeekdaySet.workweek);
    expect(range, isNot(gridRange(saturday)));

    await tester.pumpWidget(calendar(WeekdaySet.workweek));
    expect(tester.takeException(), isNull);
    expect(readInBuild.last, moved);
    expect(calls, hasLength(1));
    expect(calls.single.phase, SchedulerPhase.postFrameCallbacks);
    expect(calls.single.range, range);
    expect(calls.single.shown, range);
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(controller.selectedDay, moved);
  });

  group("CV18 the fold and the month picker move over the theme's motion", () {
    testWidgets("its duration and curve", (tester) async {
      const slow = CalendarThemeData(
        motionDuration: Duration(seconds: 1),
        motionCurve: Curves.easeIn,
      );
      final eased = Curves.easeIn.transform(0.5);
      expect((eased - 0.5).abs(), greaterThan(0.1));
      await tester.pumpWidget(
        app(
          CalendarTheme(
            data: slow,
            child: CalendarView<String>(store: store, clock: fixedClock),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = find.byKey(const ValueKey<String>("calendar-grid"));
      final open = tester.getSize(grid).height;
      await tester.tap(find.byKey(calendarPullTabKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final midFold = tester.getSize(grid).height;
      await tester.pump(const Duration(milliseconds: 600));
      final folded = tester.getSize(grid).height;
      expect(folded, lessThan(open));
      expect(
        midFold,
        moreOrLessEquals(open + (folded - open) * eased, epsilon: 1.0),
      );

      final area = find.byKey(calendarDaysAreaKey);
      final shut = tester.getSize(area).height;
      await tester.tap(find.byTooltip("Pick a month"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final midPicker = tester.getSize(area).height;
      await tester.pump(const Duration(milliseconds: 600));
      final shown = tester.getSize(area).height;
      expect(shown, isNot(shut));
      expect(
        midPicker,
        moreOrLessEquals(shut + (shown - shut) * eased, epsilon: 1.0),
      );
      await tester.pumpAndSettle();
    });

    testWidgets("a zero duration moving each in one frame", (tester) async {
      const instant = CalendarThemeData(motionDuration: Duration.zero);
      await tester.pumpWidget(
        app(
          CalendarTheme(
            data: instant,
            child: CalendarView<String>(store: store, clock: fixedClock),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = find.byKey(const ValueKey<String>("calendar-grid"));
      final open = tester.getSize(grid).height;
      await tester.tap(find.byKey(calendarPullTabKey));
      await tester.pump();
      final folded = tester.getSize(grid).height;
      expect(folded, lessThan(open));
      await tester.pumpAndSettle();
      expect(tester.getSize(grid).height, folded);

      final area = find.byKey(calendarDaysAreaKey);
      final shut = tester.getSize(area).height;
      await tester.tap(find.byTooltip("Pick a month"));
      await tester.pump();
      final shown = tester.getSize(area).height;
      expect(shown, isNot(shut));
      await tester.pumpAndSettle();
      expect(tester.getSize(area).height, shown);
    });
  });

  testWidgets("CV19 the folded card's strip row is as tall as a strip cell "
      "under the theme the calendar resolves", (tester) async {
    final controller = CalendarController(view: CalendarViewKind.day);
    addTearDown(controller.dispose);
    final large = CalendarThemeExtension(
      data: const CalendarThemeData().copyWith(
        stripWeekdayStyle: const TextStyle(fontSize: 30.0),
      ),
    );
    Widget calendar(ThemeData theme) {
      return app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
        ),
        theme: theme,
      );
    }

    final grid = find.byKey(const ValueKey<String>("calendar-grid"));
    await tester.pumpWidget(
      calendar(plainTheme(extensions: <ThemeExtension<dynamic>>[large])),
    );
    await tester.pumpAndSettle();
    final row = tester.getSize(grid).height;
    expect(
      row,
      stripCellHeight(tester.element(find.byType(CalendarCard<String>))),
    );

    await tester.pumpWidget(calendar(plainTheme()));
    await tester.pumpAndSettle();
    final builtIn = tester.getSize(grid).height;
    expect(
      builtIn,
      stripCellHeight(tester.element(find.byType(CalendarCard<String>))),
    );
    expect(row, isNot(builtIn));
  });

  testWidgets("CV20 the store hears each range a lifecycle change asks "
      "after the frame, outside a build", (tester) async {
    final controller = CalendarController();
    addTearDown(controller.dispose);
    final heard = <SchedulerPhase>[];
    store.addListener(() {
      heard.add(SchedulerBinding.instance.schedulerPhase);
    });
    Widget calendar(WeekdaySet weekdays) {
      return app(
        Column(
          children: <Widget>[
            ListenableBuilder(
              listenable: store,
              builder: (context, child) {
                return Text("${store.shows.length} ranges");
              },
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  return CalendarView<String>(
                    store: store,
                    controller: controller,
                    clock: fixedClock,
                    weekdays: weekdays,
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(calendar(WeekdaySet.all));
    expect(tester.takeException(), isNull);
    expect(store.shows, <DayRange>[gridRange(tuesday)]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(calendar(WeekdaySet.workweek));
    expect(tester.takeException(), isNull);
    expect(store.shows, <DayRange>[
      gridRange(tuesday),
      gridRange(tuesday, weekdays: WeekdaySet.workweek),
    ]);
    expect(store.phases, <SchedulerPhase>[
      SchedulerPhase.postFrameCallbacks,
      SchedulerPhase.postFrameCallbacks,
    ]);
    expect(heard, store.phases);
    expect(controller.visibleRange, store.shows.last);
    await tester.pumpAndSettle();
    expect(find.text("2 ranges"), findsOneWidget);
  });

  testWidgets("CV21 a move of the calendar under a new parent keeps its "
      "views' state, a Material coming or going above them", (tester) async {
    final controller = CalendarController(view: CalendarViewKind.week);
    addTearDown(controller.dispose);
    final key = GlobalKey();
    var place = 0;
    late StateSetter setHost;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) {
            setHost = setState;
            final calendar = CalendarView<String>(
              key: key,
              store: store,
              controller: controller,
              clock: fixedClock,
            );
            switch (place) {
              case 0:
                return Scaffold(body: calendar);
              case 1:
                return Column(children: <Widget>[Expanded(child: calendar)]);
              default:
                return Column(
                  children: <Widget>[
                    Expanded(
                      child: CalendarTheme(
                        data: const CalendarThemeData(),
                        child: calendar,
                      ),
                    ),
                  ],
                );
            }
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.state(find.byType(TimedGrid<String>));
    expect(materialsAboveGrid(tester), 0);

    setHost(() {
      place = 1;
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.state(find.byType(TimedGrid<String>)), same(grid));
    expect(materialsAboveGrid(tester), 1);

    setHost(() {
      place = 2;
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.state(find.byType(TimedGrid<String>)), same(grid));
    expect(
      CalendarTheme.of(tester.element(find.byType(TimedGrid<String>))),
      same(const CalendarThemeData()),
    );
  });

  test("CV22 no assertion holds the views' throw, the slot length's throw "
      "or the fallback to a listed view, which run in a release build", () {
    const files = <String>[
      "lib/calendar/composition/calendar_view.dart",
      "lib/calendar/composition/calendar_controller.dart",
    ];
    final named = RegExp(
      r"\b(_viewsError|_slotMinutesError|calendarViewsError|"
      r"calendarOpeningView)\b",
    );
    var asserts = 0;
    for (final path in files) {
      for (final arguments in assertArguments(File(path).readAsStringSync())) {
        asserts++;
        expect(named.hasMatch(arguments), isFalse, reason: "$path: $arguments");
      }
    }
    // The scan reads the assertions the files hold.
    expect(asserts, greaterThan(3));

    final view = File(files.first).readAsStringSync();
    final select = methodBody(view, "void _selectView(CalendarViewKind view)");
    var outside = select;
    for (final arguments in assertArguments(select)) {
      outside = outside.replaceFirst(arguments, "");
    }
    expect(assertArguments(select), isNotEmpty);
    expect(
      RegExp(r"\bcalendarOpeningView\(").hasMatch(outside),
      isTrue,
      reason: select,
    );
    final build = methodBody(view, "Widget build(BuildContext context)");
    expect(RegExp(r"\b_viewsError\b").hasMatch(build), isTrue);
    expect(RegExp(r"\b_slotMinutesError\b").hasMatch(build), isTrue);
  });

  testWidgets("CV23 Week's and Day's grid takes as its store range the "
      "range the store is shown", (tester) async {
    final controller = CalendarController(view: CalendarViewKind.week);
    addTearDown(controller.dispose);
    Widget calendar(WeekdaySet weekdays) {
      return app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
          weekdays: weekdays,
        ),
      );
    }

    void expectRange(DayRange range) {
      final grid = tester.widget<TimedGrid<String>>(
        find.byType(TimedGrid<String>),
      );
      expect(grid.storeRange, range);
      expect(store.shows.last, range);
      expect(controller.visibleRange, range);
    }

    await tester.pumpWidget(calendar(WeekdaySet.all));
    await tester.pumpAndSettle();
    expectRange((first: monday, last: sunday));
    await tester.tap(find.byTooltip("Next week"));
    await tester.pumpAndSettle();
    expectRange((first: DateTime(2026, 4, 27), last: DateTime(2026, 5, 3)));
    controller.view = CalendarViewKind.day;
    await tester.pumpAndSettle();
    expectRange((first: DateTime(2026, 4, 27), last: DateTime(2026, 5, 3)));
    await tester.pumpWidget(calendar(WeekdaySet.workweek));
    await tester.pumpAndSettle();
    expectRange((first: DateTime(2026, 4, 27), last: DateTime(2026, 5, 1)));
  });

  testWidgets("CV24 the frame of new weekdays draws what the store has read "
      "of the range the calendar asks next", (tester) async {
    useTallView(tester);
    final source = HeldSource(<CalendarEntry<String>>[
      entryOf("talk", tuesday, 10 * 60, 11 * 60),
    ]);
    final caching = CachingCalendarStore<String>(dataSource: source);
    addTearDown(caching.dispose);
    final controller = CalendarController(view: CalendarViewKind.day);
    addTearDown(controller.dispose);
    final shownInBuild = <bool>[];
    late DayRange asked;
    Widget calendar(WeekdaySet weekdays) {
      return app(
        Column(
          children: <Widget>[
            Expanded(
              child: CalendarView<String>(
                store: caching,
                controller: controller,
                clock: fixedClock,
                weekdays: weekdays,
                loadingBuilder: (context, state) {
                  return const Text("loading");
                },
              ),
            ),
            Builder(
              builder: (context) {
                shownInBuild.add(caching.isShown(asked.first, asked.last));
                return const SizedBox(height: 1.0);
              },
            ),
          ],
        ),
      );
    }

    // Day under the workweek: the weekend is not read.
    asked = (first: monday, last: DateTime(2026, 4, 24));
    await tester.pumpWidget(calendar(WeekdaySet.workweek));
    await tester.pumpAndSettle();
    expect(blockFinder("talk"), findsOneWidget);
    expect(caching.isRead(saturday), isFalse);
    source.holds = true;
    asked = (first: monday, last: sunday);
    await tester.pumpWidget(calendar(WeekdaySet.all));
    expect(shownInBuild.last, isFalse);
    expect(find.text("loading"), findsOneWidget);
    expect(blockFinder("talk"), findsNothing);
    for (final answer in source.pending) {
      answer();
    }
    source.pending.clear();
    await tester.pumpAndSettle();
    expect(find.text("loading"), findsNothing);
    expect(blockFinder("talk"), findsOneWidget);

    // Month: hiding the weekends leaves every day of the new grid read.
    source.holds = false;
    controller.view = CalendarViewKind.month;
    await tester.pumpAndSettle();
    final chip = find.byKey(monthChipKey(monthSegmentKey("talk", monday)));
    expect(chip, findsOneWidget);
    source.holds = true;
    asked = gridRange(tuesday, weekdays: WeekdaySet.workweek);
    expect(asked, isNot(gridRange(tuesday)));
    await tester.pumpWidget(calendar(WeekdaySet.workweek));
    expect(shownInBuild.last, isFalse);
    expect(chip, findsOneWidget);
    expect(find.text("loading"), findsNothing);
    await tester.pumpAndSettle();
    expect(chip, findsOneWidget);
    expect(find.text("loading"), findsNothing);
  });

  testWidgets("CV25 a host's day set during a create drag ends the drag, "
      "which reports no create on the new days", (tester) async {
    useTallView(tester);
    final controller = CalendarController(view: CalendarViewKind.week);
    addTearDown(controller.dispose);
    final creates = <CreateRange>[];
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: store,
          controller: controller,
          clock: fixedClock,
          editable: true,
          onCreateRange: (range) async {
            creates.add(range);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      cellCenter(tester, weekRowOf(14 * 60), weekColOf(thursday)),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(
      cellCenter(tester, weekRowOf(15 * 60), weekColOf(DateTime(2026, 4, 24))),
    );
    await tester.pump();
    expect(marksRange(tester), isTrue);
    controller.goTo(DateTime(2026, 4, 28));
    await tester.pump();
    expect(
      tester.widget<TimedGrid<String>>(find.byType(TimedGrid<String>)).firstDay,
      DateTime(2026, 4, 27),
    );
    expect(marksRange(tester), isFalse);
    await gesture.moveBy(const Offset(4.0, 0.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(creates, isEmpty);
    expect(marksRange(tester), isFalse);
  });
  testWidgets("CV26 a slotMinutes of 0, -15, 7, 45 or 120 throws an "
      "ArgumentError from the build", (tester) async {
    for (final slotMinutes in const <int>[0, -15, 7, 45, 120]) {
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            clock: fixedClock,
            slotMinutes: slotMinutes,
          ),
        ),
      );
      final error = tester.takeException();
      expect(error, isA<ArgumentError>(), reason: "$slotMinutes");
      expect((error as ArgumentError).name, "slotMinutes");
      expect(error.invalidValue, slotMinutes);
      expect(find.byType(DayList<String>), findsNothing);
    }
  });

  testWidgets("CV27 the slot length is 15 minutes by default, and each of "
      "slotMinuteChoices builds Week's grid with its slots", (tester) async {
    useTallView(tester);
    expect(defaultSlotMinutes, 15);
    expect(CalendarView<String>(store: store).slotMinutes, defaultSlotMinutes);
    final controller = CalendarController(view: CalendarViewKind.week);
    addTearDown(controller.dispose);
    for (final slotMinutes in slotMinuteChoices) {
      await tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            controller: controller,
            clock: fixedClock,
            slotMinutes: slotMinutes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: "$slotMinutes");
      final grid = tester.widget<TimedGrid<String>>(
        find.byType(TimedGrid<String>),
      );
      expect(grid.slotMinutes, slotMinutes);
      // The day header, the room above the slots, the slots and the room
      // below them.
      expect(
        tester
            .widget<Board<GridKey, GridShape<String>>>(
              find.byType(Board<GridKey, GridShape<String>>),
            )
            .controller
            .rows
            .axis
            .trackCount,
        2 + minutesPerDay ~/ slotMinutes + 1,
        reason: "$slotMinutes",
      );
    }
  });

  testWidgets("CV28 hours off the grid of the slot length fail an "
      "assertion, and on it build", (tester) async {
    const hours = DayHours(8 * 60 + 10, 17 * 60 + 50);
    final office = MemoryCalendarStore<String>(hours: hours);
    addTearDown(office.dispose);
    await tester.pumpWidget(
      app(CalendarView<String>(store: office, clock: fixedClock)),
    );
    final error = tester.takeException();
    expect(error, isA<AssertionError>());
    expect("$error", contains("15-minute slots"));
    await tester.pumpWidget(
      app(
        CalendarView<String>(store: office, clock: fixedClock, slotMinutes: 10),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DayList<String>), findsOneWidget);
  });

  testWidgets("CV45 every view shows the store's hours, and a set of them "
      "reaches the view shown", (tester) async {
    const office = DayHours(8 * 60, 18 * 60);
    const late = DayHours(10 * 60, 20 * 60);
    final memory = MemoryCalendarStore<String>(hours: office);
    addTearDown(memory.dispose);
    final controller = CalendarController(view: CalendarViewKind.week);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: memory,
          controller: controller,
          clock: fixedClock,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    DayHours gridHours() {
      return tester
          .widget<TimedGrid<String>>(find.byType(TimedGrid<String>))
          .hours;
    }

    expect(gridHours(), office);
    memory.hours = late;
    await tester.pump();
    expect(gridHours(), late);
    controller.view = CalendarViewKind.agenda;
    await tester.pumpAndSettle();
    expect(
      tester.widget<DayList<String>>(find.byType(DayList<String>)).hours,
      late,
    );
    controller.view = CalendarViewKind.month;
    await tester.pumpAndSettle();
    expect(
      tester.widget<MonthBoard<String>>(find.byType(MonthBoard<String>)).hours,
      late,
    );
  });

  testWidgets("CV46 a store notify that keeps the hours builds the calendar "
      "nothing again, and a set of other hours builds it once", (tester) async {
    final memory = MemoryCalendarStore<String>();
    addTearDown(memory.dispose);
    var headers = 0;
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: memory,
          clock: fixedClock,
          headerBuilder: (context, details) {
            headers++;
            return const SizedBox(height: 40.0);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final built = headers;
    await memory.create(entryOf("talk", tuesday, 10 * 60, 11 * 60));
    await tester.pumpAndSettle();
    // Setup sanity: the create's notify reached Agenda's list.
    expect(find.text("talk"), findsOneWidget);
    expect(headers, built);
    memory.hours = const DayHours(8 * 60, 18 * 60);
    await tester.pump();
    expect(headers, built + 1);
  });

  testWidgets("CV47 a new store's hours show and its sets reach the "
      "calendar, and once the calendar leaves, a set of either store's "
      "hours reaches it no more", (tester) async {
    const office = DayHours(8 * 60, 18 * 60);
    const late = DayHours(10 * 60, 20 * 60);
    final first = MemoryCalendarStore<String>();
    addTearDown(first.dispose);
    final second = MemoryCalendarStore<String>(hours: office);
    addTearDown(second.dispose);
    Widget calendar(CalendarStore<String> store) {
      return app(CalendarView<String>(store: store, clock: fixedClock));
    }

    DayHours listHours() {
      return tester.widget<DayList<String>>(find.byType(DayList<String>)).hours;
    }

    await tester.pumpWidget(calendar(first));
    await tester.pumpAndSettle();
    expect(listHours(), DayHours.allDay);
    await tester.pumpWidget(calendar(second));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(listHours(), office);
    second.hours = late;
    await tester.pump();
    expect(listHours(), late);
    await tester.pumpWidget(app(const SizedBox()));
    // The second store's hours change first, so a listener the calendar
    // left on either store finds other hours than it last took, and would
    // build its disposed state.
    second.hours = office;
    first.hours = late;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets("CV50 after a store swap, a notify of the new store that keeps "
      "its hours builds the calendar nothing again", (tester) async {
    final first = MemoryCalendarStore<String>();
    addTearDown(first.dispose);
    final second = MemoryCalendarStore<String>(
      hours: const DayHours(8 * 60, 18 * 60),
    );
    addTearDown(second.dispose);
    var headers = 0;
    Widget calendar(CalendarStore<String> store) {
      return app(
        CalendarView<String>(
          store: store,
          clock: fixedClock,
          headerBuilder: (context, details) {
            headers++;
            return const SizedBox(height: 40.0);
          },
        ),
      );
    }

    await tester.pumpWidget(calendar(first));
    await tester.pumpAndSettle();
    await tester.pumpWidget(calendar(second));
    await tester.pumpAndSettle();
    final built = headers;
    await second.create(entryOf("talk", tuesday, 10 * 60, 11 * 60));
    await tester.pumpAndSettle();
    // Setup sanity: the create's notify reached Agenda's list.
    expect(find.text("talk"), findsOneWidget);
    expect(headers, built);
  });

  testWidgets("CV29 Month's long press at slot 30 reports a 30-minute range "
      "at the first free 30-minute slot", (tester) async {
    final memory = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("standup", tuesday, 11 * 60 + 15, 11 * 60 + 45),
      ],
    );
    addTearDown(memory.dispose);
    final controller = CalendarController(view: CalendarViewKind.month);
    addTearDown(controller.dispose);
    final creates = <CreateRange>[];
    await tester.pumpWidget(
      app(
        CalendarView<String>(
          store: memory,
          controller: controller,
          clock: fixedClock,
          editable: true,
          editPolicy: const HistoryLockPolicy<String>(lockEarlierToday: true),
          slotMinutes: 30,
          onCreateRange: (range) async {
            creates.add(range);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(monthStripKey(tuesday)));
    await tester.pumpAndSettle();
    // The lock's earliest 30-minute start is 11:30, which the standup's
    // 11:15 to 11:45 overlaps, so the first free slot starts at 12:00.
    expect(creates, <CreateRange>[
      CreateRange(start: at(tuesday, 12), end: at(tuesday, 12, 30)),
    ]);
    await tester.longPress(find.byKey(monthStripKey(wednesday)));
    await tester.pumpAndSettle();
    expect(
      creates.last,
      CreateRange(start: wednesday, end: at(wednesday, 0, 30)),
    );
  });

  testWidgets("CV41 the calendar card's month and its week strip mark the "
      "kinds dayBadges gives, and the primary dot alone once it gives none", (
    tester,
  ) async {
    const task = CalendarBadgeKind(color: Color(0xFF1F4E8C), label: "Task");
    const meeting = CalendarBadgeKind(
      color: Color(0xFF1F7A72),
      label: "Meeting",
    );
    final dayBadges = CalendarDayBadges<String>(
      kinds: const <CalendarBadgeKind>[task, meeting],
      kindOf: (entry) {
        return entry.id == "standup" ? meeting : task;
      },
    );
    final store = MemoryCalendarStore<String>(
      entries: <CalendarEntry<String>>[
        entryOf("standup", thursday, 9 * 60, 10 * 60),
        entryOf("review", thursday, 11 * 60, 12 * 60),
      ],
    );
    addTearDown(store.dispose);
    Future<void> pumpUnder(CalendarDayBadges<String>? badges) {
      return tester.pumpWidget(
        app(
          CalendarView<String>(
            store: store,
            clock: fixedClock,
            dayBadges: badges,
          ),
        ),
      );
    }

    List<List<CalendarBadgeKind?>> thursdayIn(Finder strip) {
      return <List<CalendarBadgeKind?>>[
        for (final cell in tester.widgetList<DayCell>(
          find.descendant(
            of: strip,
            matching: find.byWidgetPredicate((widget) {
              return widget is DayCell && widget.day == thursday;
            }),
          ),
        ))
          cell.badges,
      ];
    }

    await pumpUnder(dayBadges);
    await tester.pumpAndSettle();
    expect(
      thursdayIn(find.byType(MonthStrip<String>)),
      <List<CalendarBadgeKind?>>[
        <CalendarBadgeKind?>[task, meeting],
      ],
    );

    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pumpAndSettle();
    final week = find.byType(WeekStrip<String>);
    expect(thursdayIn(week), <List<CalendarBadgeKind?>>[
      <CalendarBadgeKind?>[task, meeting],
    ]);

    await pumpUnder(null);
    await tester.pump();
    expect(thursdayIn(week), <List<CalendarBadgeKind?>>[
      <CalendarBadgeKind?>[null],
    ]);
  });
}
