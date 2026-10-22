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
      CalendarEntry,
      CalendarEntryTime,
      CalendarDataSource,
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
      CalendarEntryOverlapException,
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
    ];
  });

  test("B2 the barrel exports no view, nor the history lock or the labels "
      "file", () {
    final exports = <String>[
      for (final uri in directiveUris(File(barrelPath).readAsStringSync()))
        Uri.parse(barrelPath).resolve(uri).path,
    ];
    expect(exports, contains("lib/calendar/dates/calendar_dates.dart"));
    for (final export in exports) {
      expect(export, isNot(startsWith("lib/calendar/views/")));
      expect(export, isNot("lib/calendar/policy/history_lock.dart"));
      expect(export, isNot("lib/calendar/dates/calendar_labels.dart"));
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
