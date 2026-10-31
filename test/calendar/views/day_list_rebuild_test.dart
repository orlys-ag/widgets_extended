/// Which rows of the day list a change builds again: a store write those
/// of the day it changes, a new policy the cards whose answers it changes,
/// and a scroll none it had built; while a change to what every row reads,
/// as a new builder, format or theme, builds them all, and a day's rows
/// follow the store's writes and reads of that day.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/entries/calendar_entry.dart';
import 'package:widgets_extended/calendar/policy/edit_policy.dart';
import 'package:widgets_extended/calendar/policy/history_lock_policy.dart';
import 'package:widgets_extended/calendar/presentation/calendar_builders.dart';
import 'package:widgets_extended/calendar/presentation/calendar_localizations.dart';
import 'package:widgets_extended/calendar/presentation/calendar_theme.dart';
import 'package:widgets_extended/calendar/store/calendar_store.dart';
import 'package:widgets_extended/calendar/store/memory_calendar_store.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/timed_grid.dart'
    show CalendarCreateRange;
import 'package:widgets_extended/sliver_tree/sliver_tree.dart'
    show SyncedSliverTree, TreeAnimationStyle;

final DateTime tuesday = DateTime(2026, 4, 21);
final DateTime wednesday = DateTime(2026, 4, 22);

/// [hour]:[minute]:[second] on [day].
DateTime at(DateTime day, int hour, [int minute = 0, int second = 0]) {
  return DateTime(day.year, day.month, day.day, hour, minute, second);
}

/// The id of [day]'s entry [k], which ends in the day's [isoDate], as the
/// key of each of its rows does.
String idOn(DateTime day, int k) {
  return "$k@${isoDate(day)}";
}

/// Three entries on each of the [days] days from [first], at 09:00, 11:00
/// and 13:00, each an hour long.
List<CalendarEntry<String>> threeADay(DateTime first, int days) {
  return <CalendarEntry<String>>[
    for (var d = 0; d < days; d++)
      for (var k = 0; k < 3; k++)
        CalendarEntry<String>(
          id: idOn(addDays(first, d), k),
          start: at(addDays(first, d), 9 + 2 * k),
          end: at(addDays(first, d), 10 + 2 * k),
          title: idOn(addDays(first, d), k),
          color: const Color(0xFF336699),
          payload: idOn(addDays(first, d), k),
        ),
  ];
}

/// A memory store, disposed at the test's end, whose days [unread] holds
/// are not read yet and those [failed] holds failed to read, with [error]
/// as its load error; [changed] notifies.
final class ReadsStore extends MemoryCalendarStore<String> {
  ReadsStore({super.entries}) {
    addTearDown(dispose);
  }

  final Set<DateTime> unread = <DateTime>{};
  final Set<DateTime> failed = <DateTime>{};
  Object? error;

  @override
  bool isRead(DateTime day) {
    return !unread.contains(day) && !failed.contains(day);
  }

  @override
  bool readFailed(DateTime day) {
    return failed.contains(day);
  }

  @override
  Object? get loadError {
    return error;
  }

  void changed() {
    notifyListeners();
  }
}

/// A policy that forwards every answer to the unrestricted one's but
/// refuses an edit of the entries [uneditable] holds.
final class UneditablePolicy extends CalendarEditPolicy<String> {
  const UneditablePolicy(this.uneditable);

  final Set<String> uneditable;

  @override
  bool mayEdit(CalendarEntry<String> entry, CalendarNow now) {
    return !uneditable.contains(entry.id);
  }
}

/// A day list in edit mode over [store], in a view 400 wide and 800 tall,
/// opening on [day] as today, whose clock is [now]. Its parent builds it
/// again at [rebuild] and at each top day it reports, which becomes its
/// selected day, as the calendar does; each builder it passes is made
/// once, so those builds pass the same objects. It records each top day in
/// [topDays], each create in [creates], each card's last details in
/// [cards] and the details of each add button built in [adds].
class ListHost {
  ListHost(this.store, {required this.day, required DateTime time, this.policy})
    : now = ValueNotifier<CalendarNow>(CalendarNow(time: time, today: day)),
      selectedDay = day {
    addTearDown(() {
      now.dispose();
    });
    addTearDown(_builds.dispose);
  }

  CalendarStore<String> store;
  final DateTime day;
  ValueNotifier<CalendarNow> now;
  DateTime selectedDay;
  CalendarEditPolicy<String>? policy;
  CalendarWeekdaySet weekdays = CalendarWeekdaySet.all;
  CalendarHourLabelFormat format = CalendarHourLabelFormat.twentyFourHour;
  CalendarDayHours hours = CalendarDayHours.allDay;
  int slotMinutes = 15;
  bool editable = true;
  CalendarThemeData theme = const CalendarThemeData();

  final List<DateTime> topDays = <DateTime>[];
  final List<CalendarCreateRange> creates = <CalendarCreateRange>[];
  final Map<String, CalendarCardDetails> cards =
      <String, CalendarCardDetails>{};
  final List<CalendarAddButtonDetails> adds = <CalendarAddButtonDetails>[];

  late CalendarCardBuilder<String> cardBuilder = (context, entry, details) {
    cards[entry.entry.id!] = details;
    return SizedBox(height: 56.0, child: Text("card ${entry.entry.id}"));
  };

  late CalendarAddButtonBuilder addButtonBuilder = (context, details) {
    adds.add(details);
    return GestureDetector(
      onTap: details.onPressed,
      child: Text("add ${details.startMinute}"),
    );
  };

  CalendarLoadingBuilder? loadingBuilder;
  CalendarFailureBuilder? failureBuilder;

  final ValueNotifier<int> _builds = ValueNotifier<int>(0);

  void rebuild() {
    _builds.value++;
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400.0, 800.0);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: _builds,
          builder: (context, child) {
            return CalendarTheme(
              data: theme,
              child: DayList<String>(
                store: store,
                weekdays: weekdays,
                format: format,
                hours: hours,
                slotMinutes: slotMinutes,
                editable: editable,
                editPolicy: policy,
                selectedDay: selectedDay,
                now: now,
                onTopDay: (day) {
                  topDays.add(day);
                  selectedDay = day;
                  rebuild();
                },
                onCreateRange: (range) {
                  creates.add(range);
                },
                onEdit: (id) {},
                onDelete: (id) {},
                cardBuilder: cardBuilder,
                cardExtentOf: (entry) {
                  return 56.0;
                },
                addButtonBuilder: addButtonBuilder,
                loadingBuilder: loadingBuilder,
                failureBuilder: failureBuilder,
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// The keys of the rows, mounted before [body], that build again during
/// it: for each widget [debugOnRebuildDirtyWidget] reports, the key of the
/// nearest widget at or above it keyed by a string, where that widget's
/// element was mounted before [body].
Future<Set<String>> rowsRebuilt(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final mounted = <Element>{
    ...find.byWidgetPredicate((widget) {
      return widget.key is ValueKey<String>;
    }, skipOffstage: false).evaluate(),
  };
  final rebuilt = <String>{};
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    Element? keyed = element.widget.key is ValueKey<String> ? element : null;
    if (keyed == null) {
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget.key is ValueKey<String>) {
          keyed = ancestor;
          return false;
        }
        return true;
      });
    }
    final found = keyed;
    if (found != null && mounted.contains(found)) {
      rebuilt.add((found.widget.key! as ValueKey<String>).value);
    }
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rebuilt;
}

/// Whether [key] is the key of a card, a header or a gap row.
bool isRowKey(String key) {
  return key.startsWith("card-") ||
      key.startsWith("day-list-header-") ||
      key.startsWith("day-list-gap-");
}

/// The text [text] under the widget [key] names.
Finder textUnder(Key key, String text) {
  return find.descendant(
    of: find.byKey(key, skipOffstage: false),
    matching: find.text(text, skipOffstage: false),
    skipOffstage: false,
  );
}

const DefaultCalendarLocalizations english = DefaultCalendarLocalizations();

void main() {
  testWidgets("DR1 a store write builds again, of the rows it had built, "
      "only those of the day it changes", (tester) async {
    final store = ReadsStore(entries: threeADay(tuesday, 7));
    final host = ListHost(store, day: tuesday, time: at(tuesday, 8));
    await host.pump(tester);
    // Setup sanity: Wednesday's rows are built too.
    expect(
      find.byKey(entryCardKey(idOn(wednesday, 0)), skipOffstage: false),
      findsOneWidget,
    );
    final moved = store.entries.firstWhere((entry) {
      return entry.id == idOn(tuesday, 0);
    });
    final rebuilt = await rowsRebuilt(tester, () async {
      await store.update(
        moved.copyWith(start: at(tuesday, 10), end: at(tuesday, 11)),
      );
      await tester.pumpAndSettle();
    });
    // Setup sanity: the write reached the moved entry's card.
    expect(rebuilt, contains(entryCardKey(idOn(tuesday, 0)).value));
    final ofTuesday = isoDate(tuesday);
    expect(
      rebuilt.where((key) {
        return key.startsWith("card-") && !key.endsWith(ofTuesday);
      }),
      isEmpty,
    );
    expect(
      rebuilt.where((key) {
        return key.startsWith("day-list-gap-") && !key.endsWith(ofTuesday);
      }),
      isEmpty,
    );
    expect(
      rebuilt.where((key) {
        return key.startsWith("day-list-header-");
      }),
      isEmpty,
    );
  });

  testWidgets("DR2 a scroll across days, whose top days the parent takes as "
      "the selected day, builds again none of the rows it had built", (
    tester,
  ) async {
    final store = ReadsStore(entries: threeADay(tuesday, 30));
    final host = ListHost(store, day: tuesday, time: at(tuesday, 8));
    await host.pump(tester);
    final list = find.byType(DayList<String>);
    final rebuilt = await rowsRebuilt(tester, () async {
      final gesture = await tester.startGesture(tester.getCenter(list));
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(0.0, -50.0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    });
    // Setup sanity: the scroll passed two days or more, each of which the
    // parent built the list again with.
    expect(host.topDays.toSet().length, greaterThanOrEqualTo(2));
    expect(rebuilt.where(isRowKey), isEmpty);
  });

  testWidgets("DR3 a new policy builds again only the card whose answers it "
      "changes", (tester) async {
    final store = ReadsStore(entries: threeADay(tuesday, 3));
    final host = ListHost(
      store,
      day: tuesday,
      time: at(tuesday, 8),
      policy: const UnrestrictedEditPolicy<String>(),
    );
    await host.pump(tester);
    final card = idOn(tuesday, 1);
    // Setup sanity: the card can be edited.
    expect(host.cards[card]!.onEdit, isNotNull);
    final rebuilt = await rowsRebuilt(tester, () async {
      host.policy = UneditablePolicy(<String>{card});
      host.rebuild();
      await tester.pumpAndSettle();
    });
    // Setup sanity: the new policy reached the card.
    expect(host.cards[card]!.onEdit, isNull);
    expect(
      rebuilt.where((key) {
        return key.startsWith("card-");
      }),
      <String>[entryCardKey(card).value],
    );
    expect(
      rebuilt.where((key) {
        return key.startsWith("day-list-gap-") ||
            key.startsWith("day-list-header-");
      }),
      isEmpty,
    );
  });

  group("DR4 a build that changes what every row reads builds them all "
      "again", () {
    /// Pumps a host over three days from Tuesday, with Wednesday unread
    /// where [unread] and failed to read where [failed], and a loading row
    /// that reads "loading", runs [change] on it and builds it again.
    Future<ListHost> changed(
      WidgetTester tester,
      void Function(ListHost host) change, {
      bool unread = false,
      bool failed = false,
    }) async {
      final store = ReadsStore(entries: threeADay(tuesday, 3));
      if (unread) {
        store.unread.add(wednesday);
      }
      if (failed) {
        store.failed.add(wednesday);
      }
      final host = ListHost(store, day: tuesday, time: at(tuesday, 8));
      // A loading row that does not animate, so the frames settle.
      host.loadingBuilder = (context, state) {
        return const Text("loading");
      };
      await host.pump(tester);
      change(host);
      host.rebuild();
      await tester.pumpAndSettle();
      return host;
    }

    testWidgets("the hour format", (tester) async {
      final nine = english.formatTime(
        9 * 60,
        CalendarHourLabelFormat.twelveHour,
      );
      final time = dayListTimeKey(idOn(tuesday, 0));
      await changed(tester, (host) {
        // Setup sanity: the time column reads the other format first.
        expect(textUnder(time, nine), findsNothing);
        host.format = CalendarHourLabelFormat.twelveHour;
      });
      expect(textUnder(time, nine), findsOneWidget);
    });

    testWidgets("the hours", (tester) async {
      final banner = dayListHiddenKey(tuesday, above: true);
      await changed(tester, (host) {
        // Setup sanity: all day long, no banner.
        expect(find.byKey(banner, skipOffstage: false), findsNothing);
        host.hours = const CalendarDayHours(10 * 60, 18 * 60);
      });
      expect(find.byKey(banner, skipOffstage: false), findsOneWidget);
    });

    testWidgets("edit mode", (tester) async {
      final gap = dayListGapKey(tuesday, 0);
      await changed(tester, (host) {
        // Setup sanity: edit mode shows the gap.
        expect(find.byKey(gap, skipOffstage: false), findsOneWidget);
        host.editable = false;
      });
      expect(find.byKey(gap, skipOffstage: false), findsNothing);
    });

    testWidgets("a new card builder", (tester) async {
      final card = entryCardKey(idOn(tuesday, 0));
      await changed(tester, (host) {
        host.cardBuilder = (context, entry, details) {
          return Text("other ${entry.entry.id}");
        };
      });
      expect(textUnder(card, "other ${idOn(tuesday, 0)}"), findsOneWidget);
    });

    testWidgets("a new add button builder", (tester) async {
      final gap = dayListGapKey(tuesday, 0);
      await changed(tester, (host) {
        // Setup sanity: the gap holds the first builder's button.
        expect(textUnder(gap, "add 0"), findsOneWidget);
        host.addButtonBuilder = (context, details) {
          return Text("plus ${details.startMinute}");
        };
      });
      expect(textUnder(gap, "plus 0"), findsOneWidget);
    });

    testWidgets("the slot length", (tester) async {
      final host = await changed(tester, (host) {
        host.slotMinutes = 30;
      });
      await tester.tap(textUnder(dayListGapKey(tuesday, 10 * 60), "add 600"));
      await tester.pumpAndSettle();
      expect(host.creates, <CalendarCreateRange>[
        CalendarCreateRange(start: at(tuesday, 10), end: at(tuesday, 10, 30)),
      ]);
    });

    testWidgets("a new store", (tester) async {
      final other = ReadsStore(
        entries: <CalendarEntry<String>>[
          CalendarEntry<String>(
            id: "other",
            start: at(tuesday, 15),
            end: at(tuesday, 16),
            title: "other",
            color: const Color(0xFF336699),
            payload: "other",
          ),
        ],
      );
      await changed(tester, (host) {
        host.store = other;
      });
      expect(
        find.byKey(entryCardKey("other"), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(entryCardKey(idOn(tuesday, 0)), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets("a new clock", (tester) async {
      late double before;
      await changed(tester, (host) {
        before = tester.getTopLeft(find.byKey(dayListNowKey)).dy;
        // Setup sanity: the old clock's marker lies above Tuesday's first
        // card, at 09:00.
        expect(
          before,
          lessThan(
            tester.getTopLeft(find.byKey(entryCardKey(idOn(tuesday, 0)))).dy,
          ),
        );
        addTearDown(host.now.dispose);
        host.now = ValueNotifier<CalendarNow>(
          CalendarNow(time: at(tuesday, 12, 30), today: tuesday),
        );
      });
      expect(
        tester.getTopLeft(find.byKey(dayListNowKey)).dy,
        greaterThan(before),
      );
    });

    testWidgets("a new theme", (tester) async {
      const green = Color(0xFF00AA00);
      final title = textUnder(
        dayListHeaderKey(tuesday),
        english.dayTitle(tuesday, tuesday),
      );
      await changed(tester, (host) {
        // Setup sanity: the title is drawn in another colour first.
        expect(tester.widget<Text>(title).style?.color, isNot(green));
        host.theme = const CalendarThemeData(text: green);
      });
      expect(tester.widget<Text>(title).style?.color, green);
    });

    testWidgets("a new loading builder", (tester) async {
      final loading = dayListLoadingKey(wednesday);
      await changed(tester, unread: true, (host) {
        // Setup sanity: Wednesday is loading.
        expect(find.byKey(loading, skipOffstage: false), findsOneWidget);
        host.loadingBuilder = (context, state) {
          return Text("loading ${isoDate(state.first)}");
        };
      });
      expect(
        textUnder(loading, "loading ${isoDate(wednesday)}"),
        findsOneWidget,
      );
    });

    testWidgets("a new failure builder", (tester) async {
      final failedRow = dayListFailedKey(wednesday);
      await changed(tester, failed: true, (host) {
        // Setup sanity: Wednesday failed to read.
        expect(find.byKey(failedRow, skipOffstage: false), findsOneWidget);
        host.failureBuilder = (context, state) {
          return Text("failed ${isoDate(state.first)}");
        };
      });
      expect(
        textUnder(failedRow, "failed ${isoDate(wednesday)}"),
        findsOneWidget,
      );
    });

    testWidgets("the weekdays", (tester) async {
      final header = dayListHeaderKey(wednesday);
      await changed(tester, (host) {
        // Setup sanity: Wednesday shows first.
        expect(find.byKey(header, skipOffstage: false), findsOneWidget);
        host.weekdays = CalendarWeekdaySet.of(<int>[0, 1, 3, 4, 5, 6]);
      });
      expect(find.byKey(header, skipOffstage: false), findsNothing);
    });

    testWidgets("a minute on the next day, which moves the marker of the "
        "current time to the next day's block", (tester) async {
      final host = await changed(tester, (host) {
        // Setup sanity: the marker lies in Tuesday's block, above
        // Wednesday's header.
        expect(
          tester.getTopLeft(find.byKey(dayListNowKey)).dy,
          lessThan(
            tester.getTopLeft(find.byKey(dayListHeaderKey(wednesday))).dy,
          ),
        );
      });
      host.now.value = CalendarNow(
        time: at(wednesday, 0, 0, 30),
        today: host.now.value.today,
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(dayListNowKey)).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(dayListHeaderKey(wednesday))).dy,
        ),
      );
    });
  });

  group("DR5 a day's rows follow the store's writes and reads of the day", () {
    testWidgets("an entry a write adds shows in its day's count and block", (
      tester,
    ) async {
      final store = ReadsStore(entries: threeADay(tuesday, 3));
      final host = ListHost(store, day: tuesday, time: at(tuesday, 8));
      await host.pump(tester);
      final header = dayListHeaderKey(wednesday);
      // Setup sanity: Wednesday counts its three entries.
      expect(textUnder(header, english.entryCount(3)), findsOneWidget);
      await store.create(
        CalendarEntry<String>(
          id: "added",
          start: at(wednesday, 15),
          end: at(wednesday, 16),
          title: "added",
          color: const Color(0xFF336699),
          payload: "added",
        ),
      );
      await tester.pumpAndSettle();
      expect(textUnder(header, english.entryCount(4)), findsOneWidget);
      expect(
        find.byKey(entryCardKey("added"), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets("a day read after the list builds swaps its loading row for "
        "its entries and its count", (tester) async {
      final store = ReadsStore(entries: threeADay(tuesday, 3));
      store.unread.add(wednesday);
      final host = ListHost(store, day: tuesday, time: at(tuesday, 8));
      // A loading row that does not animate, so the frames settle.
      host.loadingBuilder = (context, state) {
        return const Text("loading");
      };
      await host.pump(tester);
      final loading = dayListLoadingKey(wednesday);
      // Setup sanity: Wednesday is loading, with no count.
      expect(find.byKey(loading, skipOffstage: false), findsOneWidget);
      expect(
        textUnder(dayListHeaderKey(wednesday), english.entryCount(3)),
        findsNothing,
      );
      store.unread.clear();
      store.changed();
      await tester.pumpAndSettle();
      expect(find.byKey(loading, skipOffstage: false), findsNothing);
      expect(
        find.byKey(entryCardKey(idOn(wednesday, 0)), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        textUnder(dayListHeaderKey(wednesday), english.entryCount(3)),
        findsOneWidget,
      );
    });

    testWidgets("a failed day's row shows the store's error as it changes", (
      tester,
    ) async {
      final store = ReadsStore(entries: threeADay(tuesday, 3));
      store.failed.add(wednesday);
      store.error = "first";
      final host = ListHost(store, day: tuesday, time: at(tuesday, 8));
      host.failureBuilder = (context, state) {
        return Text("error ${state.error}");
      };
      await host.pump(tester);
      final failedRow = dayListFailedKey(wednesday);
      // Setup sanity: the row shows the first error.
      expect(textUnder(failedRow, "error first"), findsOneWidget);
      store.error = "second";
      store.changed();
      await tester.pumpAndSettle();
      expect(textUnder(failedRow, "error second"), findsOneWidget);
    });
  });

  testWidgets("DR6 a hot reload gives the tree the styles it makes anew", (
    tester,
  ) async {
    final host = ListHost(
      ReadsStore(entries: threeADay(tuesday, 3)),
      day: tuesday,
      time: at(tuesday, 8),
    );
    await host.pump(tester);
    TreeAnimationStyle treeStyle() {
      return tester
          .widget<SyncedSliverTree<String, DayListRow>>(
            find.byType(SyncedSliverTree<String, DayListRow>),
          )
          .animationStyle;
    }

    final style = treeStyle();
    tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
    await tester.pumpAndSettle();
    expect(identical(treeStyle(), style), isFalse);
  });

  testWidgets("DR7 a new today its clock alone brings, with no build from "
      "above, titles the days by it and has the rows ask the policy at it", (
    tester,
  ) async {
    final host = ListHost(
      ReadsStore(entries: threeADay(tuesday, 2)),
      day: tuesday,
      time: at(tuesday, 8),
      policy: const HistoryLockPolicy<String>(),
    );
    await host.pump(tester);
    final header = dayListHeaderKey(tuesday);
    final title = english.dayTitle(tuesday, wednesday);
    // Setup sanity: Tuesday is titled as today, and its card, at or after
    // the start of today, is editable.
    expect(textUnder(header, title), findsNothing);
    expect(host.cards[idOn(tuesday, 0)]!.onEdit, isNotNull);

    host.now.value = CalendarNow(time: host.now.value.time, today: wednesday);
    await tester.pumpAndSettle();
    expect(textUnder(header, title), findsOneWidget);
    expect(host.cards[idOn(tuesday, 0)]!.onEdit, isNull);
  });
}
