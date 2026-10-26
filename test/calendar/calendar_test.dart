/// The names the module barrel shows, and the imports and names of the
/// module's files.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

/// The module barrel, from the package root, where `flutter test` runs.
const String barrelPath = "lib/calendar/calendar.dart";

/// The module's layers, each a directory of lib/calendar/, in the order
/// their files import up.
const List<String> layers = <String>[
  "dates",
  "entries",
  "policy",
  "store",
  "presentation",
  "views",
  "composition",
];

/// The widgets library and the Flutter libraries its own sources import.
const Set<String> widgetsAndBelow = <String>{
  "widgets",
  "animation",
  "foundation",
  "gestures",
  "painting",
  "physics",
  "rendering",
  "scheduler",
  "semantics",
  "services",
};

/// The Flutter libraries each layer's rule lets its files import.
const Map<String, Set<String>> flutterLibrariesOf = <String, Set<String>>{
  "dates": <String>{"foundation"},
  "entries": <String>{"foundation"},
  "policy": <String>{"foundation"},
  "store": <String>{"foundation"},
  "presentation": widgetsAndBelow,
  "views": widgetsAndBelow,
  "composition": <String>{...widgetsAndBelow, "material", "cupertino"},
};

/// The first directory under lib/calendar/ of [path], a path from the
/// package root.
String layerOf(String path) {
  return path.split("/")[2];
}

/// The URIs of the import and export directives of [source].
List<String> directiveUris(String source) {
  return <String>[
    for (final match in RegExp(
      r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""",
      multiLine: true,
    ).allMatches(source))
      match.group(1)!,
  ];
}

/// Each export directive of [source]: the path it exports, resolved from
/// the package root against [barrelPath], and the names its `show` clause
/// lists, null for a directive with none.
List<({String path, List<String>? shown})> exportsOf(String source) {
  return <({String path, List<String>? shown})>[
    for (final match in RegExp(
      r"""^\s*export\s+['"]([^'"]+)['"]\s*(?:show\s+([^;]+))?;""",
      multiLine: true,
    ).allMatches(source))
      (
        path: Uri.parse(barrelPath).resolve(match.group(1)!).path,
        shown: match.group(2)?.split(",").map((name) {
          return name.trim();
        }).toList(),
      ),
  ];
}

/// The module's Dart files but the barrel, from the package root: those
/// Git tracks and the new ones it does not ignore. Checks that Git ran and
/// that the list holds a file of each layer from dates to views.
List<String> moduleFiles() {
  final result = Process.runSync("git", <String>[
    "ls-files",
    "--cached",
    "--others",
    "--exclude-standard",
    "--",
    "lib/calendar",
  ]);
  expect(result.exitCode, 0, reason: "${result.stderr}");
  final files = <String>[
    for (final line in (result.stdout as String).split("\n"))
      if (line.trim().endsWith(".dart") && line.trim() != barrelPath)
        line.trim(),
  ];
  expect(<String>{
    for (final file in files) layerOf(file),
  }, containsAll(layers.take(6)));
  return files;
}

void main() {
  test("B1 the barrel shows the module's public names", () {
    // Compile-time only: a name the barrel stops showing stops this file
    // compiling.
    <Object>[
      DayHours,
      WeekdaySet,
      dayNumber,
      dateOfDayNumber,
      defaultSlotMinutes,
      slotMinuteChoices,
      CalendarEntry,
      CalendarDataSource,
      CalendarEditPolicy,
      CalendarNow,
      CalendarResizeEdges,
      UnrestrictedEditPolicy,
      CalendarEditRules,
      CalendarEarliestStart,
      HistoryLockPolicy,
      CalendarStore,
      CachingCalendarStore,
      MemoryCalendarStore,
      CalendarShownEntry,
      CalendarLoadStatus,
      CalendarWriteFailure,
      CalendarWriteFailed,
      CalendarEntryChanged,
      CalendarStoreException,
      CalendarHoursException,
      CalendarWritePendingException,
      CalendarTheme,
      CalendarThemeData,
      CalendarBlockBuilder,
      CalendarChipBuilder,
      CalendarCardBuilder,
      CalendarAddButtonBuilder,
      CalendarLoadingBuilder,
      CalendarFailureBuilder,
      CalendarBlockDetails,
      CalendarChipDetails,
      CalendarCardDetails,
      CalendarAddButtonDetails,
      CalendarLoadingState,
      CalendarFailureState,
      CalendarStateSite,
      calendarCardStripExtent,
      defaultCalendarBlockBuilder,
      defaultCalendarChipBuilder,
      defaultCalendarCardBuilder,
      defaultCalendarAddButtonBuilder,
      defaultCalendarLoadingBuilder,
      defaultCalendarFailureBuilder,
      CalendarActivityIndicator,
      CalendarBadgeKind,
      CalendarDayBadges,
      CalendarView,
      CalendarController,
      CalendarViewKind,
      CalendarStepUnit,
      CalendarHeaderBuilder,
      CalendarHeaderDetails,
      defaultCalendarHeaderBuilder,
      CalendarEntryTapDetails,
      CalendarThemeExtension,
      CreateRange,
      HourLabelFormat,
      MonthLayout,
      minDayWidthLow,
      minDayWidthHigh,
      minSlotHeightLow,
      minSlotHeightHigh,
      defaultMinSlotHeight,
      maxMonthWeekScale,
    ];
  });

  test("B2 the barrel shows by name; of the views and the labels file only "
      "the types and the range constants the calendar's signatures use, and "
      "no view; and of the policy layer exactly the two edit policy files, "
      "with the policies and the types their signatures name, and the edit "
      "rules", () {
    final source = File(barrelPath).readAsStringSync();
    final exports = exportsOf(source);
    // Every directive the barrel holds was read.
    expect(exports, hasLength(directiveUris(source).length));
    expect(<String>[
      for (final export in exports) export.path,
    ], contains("lib/calendar/dates/calendar_dates.dart"));
    for (final export in exports) {
      expect(export.shown, isNotNull, reason: export.path);
    }
    final views = <String, Set<String>>{
      for (final export in exports)
        if (export.path.startsWith("lib/calendar/views/"))
          export.path: export.shown!.toSet(),
    };
    expect(views, <String, Set<String>>{
      "lib/calendar/views/month_board.dart": <String>{"MonthLayout"},
      "lib/calendar/views/pinch_zoom.dart": <String>{
        "defaultMinSlotHeight",
        "maxMonthWeekScale",
        "minDayWidthHigh",
        "minDayWidthLow",
        "minSlotHeightHigh",
        "minSlotHeightLow",
      },
      "lib/calendar/views/timed_grid.dart": <String>{"CreateRange"},
    });
    expect(
      <List<String>?>[
        for (final export in exports)
          if (export.path == "lib/calendar/dates/calendar_labels.dart")
            export.shown,
      ],
      <List<String>>[
        <String>["HourLabelFormat"],
      ],
    );
    const viewWidgets = <String>{
      "TimedGrid",
      "MonthBoard",
      "DayList",
      "WeekStrip",
      "MonthStrip",
      "MonthPicker",
      "DayCell",
    };
    expect(
      <String, Set<String>>{
        for (final export in exports)
          if (export.path.startsWith("lib/calendar/policy/"))
            export.path: export.shown!.toSet(),
      },
      <String, Set<String>>{
        "lib/calendar/policy/edit_policy.dart": <String>{
          "CalendarEditPolicy",
          "CalendarNow",
          "CalendarResizeEdges",
          "UnrestrictedEditPolicy",
        },
        "lib/calendar/policy/history_lock_policy.dart": <String>{
          "HistoryLockPolicy",
        },
        "lib/calendar/policy/edit_rules.dart": <String>{
          "CalendarEarliestStart",
          "CalendarEditRules",
        },
      },
    );
    for (final export in exports) {
      expect(
        export.shown!.toSet().intersection(viewWidgets),
        isEmpty,
        reason: export.path,
      );
    }
  });

  test("B3 the barrel's show clauses name no CalendarEntryTime", () {
    final exports = exportsOf(File(barrelPath).readAsStringSync());
    final entries = <List<String>?>[
      for (final export in exports)
        if (export.path == "lib/calendar/entries/calendar_entry.dart")
          export.shown,
    ];
    // The barrel shows the entry's file, by name.
    expect(entries, hasLength(1));
    expect(entries.single, contains("CalendarEntry"));
    for (final export in exports) {
      expect(
        export.shown,
        isNot(contains("CalendarEntryTime")),
        reason: export.path,
      );
    }
  });

  test("LY1 each file imports the package's files by relative paths, up "
      "the layer table, and the board and sliver_tree modules only "
      "through their barrels", () {
    for (final path in moduleFiles()) {
      final layer = layerOf(path);
      expect(layers, contains(layer), reason: path);
      final source = File(path).readAsStringSync();
      for (final uri in directiveUris(source)) {
        if (uri.startsWith("dart:") || uri.startsWith("package:flutter/")) {
          continue;
        }
        expect(Uri.parse(uri).hasScheme, isFalse, reason: "$path: $uri");
        final target = Uri.parse(path).resolve(uri).path;
        expect(target, isNot(barrelPath), reason: "$path: $uri");
        final upTheTable =
            target.startsWith("lib/calendar/") &&
            layers.contains(layerOf(target)) &&
            layers.indexOf(layerOf(target)) <= layers.indexOf(layer);
        final moduleBarrel =
            (layer == "views" || layer == "composition") &&
            (target == "lib/board/board.dart" ||
                target == "lib/sliver_tree/sliver_tree.dart");
        expect(upTheTable || moduleBarrel, isTrue, reason: "$path: $uri");
      }
    }
  });

  test("LY2 each layer imports only the Flutter libraries its rule "
      "allows", () {
    for (final path in moduleFiles()) {
      final allowed = flutterLibrariesOf[layerOf(path)] ?? const <String>{};
      final source = File(path).readAsStringSync();
      for (final uri in directiveUris(source)) {
        final library = RegExp(
          r"^package:flutter/([a-z_]+)\.dart$",
        ).firstMatch(uri)?.group(1);
        if (library == null) {
          continue;
        }
        expect(allowed, contains(library), reason: "$path: $uri");
      }
    }
  });

  test("LY4 no file under lib/calendar/views holds a literal colour", () {
    final views = <String>[
      for (final path in moduleFiles())
        if (layerOf(path) == "views") path,
    ];
    expect(views, isNotEmpty);
    for (final path in views) {
      final lines = File(path).readAsLinesSync();
      expect(
        <String>[
          for (var i = 0; i < lines.length; i++)
            if (lines[i].contains("Color(0x")) "${i + 1}: ${lines[i].trim()}",
        ],
        isEmpty,
        reason: path,
      );
    }
  });

  test("LY3 no file under lib/calendar names what the demo owns", () {
    final demoNames = RegExp(
      r"CalendarSettings|hoursErrorsOf|lockErrorsOf|\berrorsOf\b|"
      r"validateItemJson|ItemPayload|Harbor|[Ww]orkspace|Show all items|"
      r"Fit to screen",
    );
    for (final path in moduleFiles()) {
      final source = File(path).readAsStringSync();
      expect(
        <String>[
          for (final match in demoNames.allMatches(source)) match.group(0)!,
        ],
        isEmpty,
        reason: path,
      );
    }
  });
}
