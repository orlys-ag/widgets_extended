/// The names the module barrel shows, the imports and names of the
/// module's files, and the classes and docs of the checks a release build
/// runs.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

import 'class_source.dart';

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
      CalendarDayHours,
      CalendarWeekdaySet,
      CalendarMonthGrid,
      CalendarDates.dayNumber,
      CalendarDates.dateOfDayNumber,
      CalendarDates.defaultSlotMinutes,
      CalendarDates.slotMinuteChoices,
      CalendarDates.addDays,
      CalendarDates.dateOnly,
      CalendarDates.endAtWallMinute,
      CalendarDates.endMinuteOfDay,
      CalendarDates.endWallMinuteOf,
      CalendarDates.isLaterOccurrence,
      CalendarDates.lastDayNumberOf,
      CalendarDates.minuteOfDay,
      CalendarDates.minutesPerDay,
      CalendarDates.timeAtWallMinute,
      CalendarDates.wallMinuteOf,
      CalendarDates.weekdayColumn,
      CalendarDates.addMonths,
      CalendarDates.daysBetween,
      CalendarDates.firstWallMinuteNotBefore,
      CalendarDates.isDayStart,
      CalendarDates.isoDate,
      CalendarDates.isoTime,
      CalendarDates.lastWallMinuteNotAfter,
      CalendarDates.nextShownDay,
      CalendarDates.pieceOn,
      CalendarDates.rangeEndAtWallMinute,
      CalendarDates.repeatedStretchOf,
      CalendarDates.shownDayNear,
      CalendarDates.shownDaysOfWeek,
      CalendarDates.wallSpanOf,
      CalendarDates.weekdayColumnOfDay,
      CalendarEntry,
      CalendarDataSource,
      CalendarEditPolicy,
      CalendarNow,
      CalendarResizeEdges,
      UnrestrictedEditPolicy,
      DayLimitPolicy,
      NoOverlapsPolicy,
      CalendarEditRules,
      CalendarEarliestStart,
      HistoryLockPolicy,
      NoOverlapsPolicy.entriesShareTime,
      NoOverlapsPolicy.timesOverlap,
      NoOverlapsPolicy.rangeSharesTime,
      CalendarStore,
      compareCalendarEntries,
      CachingCalendarStore,
      MemoryCalendarStore,
      CalendarShownEntry,
      CalendarLoadStatus,
      CalendarEntryChanged,
      CalendarStoreException,
      CalendarHoursException,
      CalendarWritePendingException,
      CalendarTheme,
      CalendarThemeData,
      CalendarThemeData.builtIn,
      CalendarLocalizations,
      DefaultCalendarLocalizations,
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
      CalendarCreateRange,
      CalendarMoveRequest,
      CalendarMoveKind,
      CalendarHourLabelFormat,
      CalendarMonthLayout,
      CalendarController.minDayWidthLow,
      CalendarController.minDayWidthHigh,
      CalendarController.minSlotHeightLow,
      CalendarController.minSlotHeightHigh,
      CalendarController.defaultMinSlotHeight,
      CalendarController.maxMonthWeekScale,
    ];
  });

  test("B2 the barrel shows by name; of the views only the types the "
      "calendar's signatures use, and no view; of the localizations file "
      "the localizations and their English default; of the policy layer "
      "exactly the policies, the types their signatures name and the edit "
      "rules; and of the dates layer exactly the day hours, the weekday "
      "sets, the month grid, the hour label format and CalendarDates", () {
    final source = File(barrelPath).readAsStringSync();
    final exports = exportsOf(source);
    // Every directive the barrel holds was read.
    expect(exports, hasLength(directiveUris(source).length));
    expect(
      <String, Set<String>>{
        for (final export in exports)
          if (export.path.startsWith("lib/calendar/dates/"))
            export.path: export.shown!.toSet(),
      },
      <String, Set<String>>{
        "lib/calendar/dates/calendar_dates.dart": <String>{
          "CalendarDates",
          "CalendarDayHours",
          "CalendarHourLabelFormat",
          "CalendarMonthGrid",
          "CalendarWeekdaySet",
        },
      },
    );
    for (final export in exports) {
      expect(export.shown, isNotNull, reason: export.path);
    }
    final views = <String, Set<String>>{
      for (final export in exports)
        if (export.path.startsWith("lib/calendar/views/"))
          export.path: export.shown!.toSet(),
    };
    expect(views, <String, Set<String>>{
      "lib/calendar/views/month_board.dart": <String>{"CalendarMonthLayout"},
      "lib/calendar/views/move_request.dart": <String>{
        "CalendarMoveKind",
        "CalendarMoveRequest",
      },
    });
    expect(
      <List<String>?>[
        for (final export in exports)
          if (export.path ==
              "lib/calendar/presentation/calendar_localizations.dart")
            export.shown,
      ],
      <List<String>>[
        <String>["CalendarLocalizations", "DefaultCalendarLocalizations"],
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
          "DayLimitPolicy",
          "NoOverlapsPolicy",
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

  test("B4 each class the barrel shows says how a host builds on it: a "
      "class a host extends is base, the data source an interface, the "
      "widgets neither, and every other class final or sealed; and each "
      "function or constant it shows names the calendar", () {
    const widgets = <String>{
      "CalendarView",
      "CalendarActivityIndicator",
      "CalendarTheme",
    };
    const bases = <String>{
      "CalendarController",
      "CalendarStore",
      "MemoryCalendarStore",
      "CachingCalendarStore",
      "CalendarEditPolicy",
      "CalendarLocalizations",
      "DefaultCalendarLocalizations",
    };
    const interfaces = <String>{"CalendarDataSource"};
    final shown = <String>{
      for (final export in exportsOf(File(barrelPath).readAsStringSync()))
        ...export.shown!,
    };
    final classDeclaration = RegExp(
      r"^((?:(?:abstract|base|final|interface|sealed)\s+)*)class\s+(\w+)",
      multiLine: true,
    );
    final otherDeclaration = RegExp(
      r"^(?:enum|typedef|mixin|extension\s+type)\s+(\w+)"
      r"|^(?:const|final)\s+(?:[\w<>?, ]+\s+)?(\w+)\s*="
      r"|^[A-Za-z][\w<>?, ]*\s+(\w+)(?:<[^>(]*>)?\(",
      multiLine: true,
    );
    // A file the barrel exports may export the file that declares a name,
    // so every file of the module is read.
    final declared = <String>{};
    final kindOf = <String, String>{};
    final functionsAndConstants = <String>{};
    for (final file in moduleFiles()) {
      final source = File(file).readAsStringSync();
      for (final match in classDeclaration.allMatches(source)) {
        final name = match.group(2)!;
        declared.add(name);
        final modifiers = match.group(1)!.split(RegExp(r"\s+")).toSet();
        kindOf[name] =
            modifiers.contains("final") || modifiers.contains("sealed")
            ? "closed"
            : modifiers.contains("base")
            ? "base"
            : modifiers.contains("interface")
            ? "interface"
            : "open";
      }
      for (final match in otherDeclaration.allMatches(source)) {
        final name = (match.group(1) ?? match.group(2) ?? match.group(3))!;
        declared.add(name);
        if (match.group(1) == null) {
          functionsAndConstants.add(name);
        }
      }
    }
    // Every name the barrel shows has a declaration the scan reads, and
    // the scan reads a class of each kind.
    expect(shown.difference(declared), isEmpty);
    expect(
      kindOf.keys,
      containsAll(<String>{
        ...widgets,
        ...bases,
        ...interfaces,
        "CalendarEntry",
        "CalendarStoreException",
      }),
    );
    expect(<String, String>{
      for (final name in shown)
        if (kindOf.containsKey(name) &&
            kindOf[name] !=
                (widgets.contains(name)
                    ? "open"
                    : bases.contains(name)
                    ? "base"
                    : interfaces.contains(name)
                    ? "interface"
                    : "closed"))
          name: kindOf[name]!,
    }, isEmpty);
    // The scan reads a function and a constant the barrel shows.
    expect(
      functionsAndConstants,
      containsAll(<String>{
        "defaultCalendarHeaderBuilder",
        "calendarCardStripExtent",
      }),
    );
    expect(<String>{
      for (final name in shown)
        if (functionsAndConstants.contains(name) &&
            !name.toLowerCase().contains("calendar"))
          name,
    }, isEmpty);
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

  test("RC19 each class whose values a host gives checks them with a throw "
      "of an ArgumentError, and with no assert and no debug-only "
      "branch", () {
    const classes = <({String path, String name})>[
      (
        path: "lib/calendar/dates/calendar_dates.dart",
        name: "CalendarWeekdaySet",
      ),
      (
        path: "lib/calendar/dates/calendar_dates.dart",
        name: "CalendarDayHours",
      ),
      (path: "lib/calendar/dates/calendar_dates.dart", name: "CalendarDates"),
      (path: "lib/calendar/policy/edit_policy.dart", name: "DayLimitPolicy"),
      (
        path: "lib/calendar/policy/edit_rules.dart",
        name: "CalendarEarliestStart",
      ),
      (path: "lib/calendar/policy/edit_rules.dart", name: "CalendarEditRules"),
      (
        path: "lib/calendar/entries/calendar_data_source.dart",
        name: "CalendarDaysChanged",
      ),
      (
        path: "lib/calendar/store/calendar_store.dart",
        name: "CalendarShownEntry",
      ),
      (
        path: "lib/calendar/presentation/calendar_theme.dart",
        name: "CalendarThemeData",
      ),
      (
        path: "lib/calendar/entries/calendar_entry.dart",
        name: "CalendarCreateRange",
      ),
      (
        path: "lib/calendar/views/move_request.dart",
        name: "CalendarMoveRequest",
      ),
      (
        path: "lib/calendar/composition/calendar_controller.dart",
        name: "CalendarController",
      ),
    ];
    final asserts = RegExp(r"\bassert\(");
    for (final (:path, :name) in classes) {
      final body = classBody(File(path).readAsStringSync(), name);
      expect(body, contains("throw ArgumentError"), reason: name);
      expect(body, isNot(contains("kDebugMode")), reason: name);
      // CalendarDayHours keeps slotCountOf's assert, of a method's
      // argument.
      expect(
        asserts.allMatches(body),
        hasLength(name == "CalendarDayHours" ? 1 : 0),
        reason: name,
      );
    }
  });

  test("RC21 a check builds nothing on a valid value but the DateTime "
      "isDayStart builds: CalendarThemeData's constructor builds no list "
      "of its styles, and the day checks build no DateTime of their own", () {
    String constructorBody(String path, String declaration) {
      final source = File(path).readAsStringSync();
      final start = source.indexOf(declaration);
      expect(start, isNot(-1), reason: declaration);
      var at = source.indexOf("(", start) + 1;
      var depth = 1;
      while (depth > 0) {
        final char = source[at];
        if (char == "(") {
          depth++;
        } else if (char == ")") {
          depth--;
        }
        at++;
      }
      final open = source.indexOf("{", at);
      // The body starts at the brace after the parameters and any
      // initializers, which hold no brace.
      expect(
        source.substring(at, open),
        isNot(contains(";")),
        reason: declaration,
      );
      depth = 1;
      at = open + 1;
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

    final theme = constructorBody(
      "lib/calendar/presentation/calendar_theme.dart",
      "  CalendarThemeData({",
    );
    // Setup sanity: the body read is the one that checks the styles.
    expect(theme, contains("hourLabelStyle"));
    expect(theme, isNot(contains("_textStyles")));
    expect(theme, isNot(contains("[")));
    final dayChecks = <({String path, String declaration, bool dayStarts})>[
      (
        path: "lib/calendar/policy/edit_rules.dart",
        declaration: "  CalendarEarliestStart(",
        dayStarts: true,
      ),
      (
        path: "lib/calendar/entries/calendar_entry.dart",
        declaration: "  CalendarCreateRange({",
        dayStarts: true,
      ),
      (
        path: "lib/calendar/entries/calendar_data_source.dart",
        declaration: "  CalendarDaysChanged(",
        dayStarts: false,
      ),
    ];
    for (final (:path, :declaration, :dayStarts) in dayChecks) {
      final body = constructorBody(path, declaration);
      expect(body, contains("throw ArgumentError"), reason: declaration);
      expect(body.contains("isDayStart("), dayStarts, reason: declaration);
      expect(body, isNot(contains("DateTime(")), reason: declaration);
    }
  });

  test("RC20 the doc of each check says it throws an [ArgumentError] in "
      "every build, and none says it asserts or runs in a debug build", () {
    const declarations = <String, List<String>>{
      "dates/calendar_dates.dart": <String>[
        "factory CalendarWeekdaySet.of(",
        "CalendarWeekdaySet startingOn(",
        "CalendarDayHours(",
        "static DateTime nextShownDay(",
      ],
      "entries/calendar_data_source.dart": <String>["CalendarDaysChanged("],
      "entries/calendar_entry.dart": <String>["CalendarCreateRange({"],
      "policy/edit_policy.dart": <String>["DayLimitPolicy("],
      "policy/edit_rules.dart": <String>[
        "CalendarEarliestStart(",
        "CalendarEditRules({",
        "CalendarEditRules<T> updated(",
      ],
      "store/calendar_store.dart": <String>["CalendarShownEntry("],
      "presentation/calendar_theme.dart": <String>[
        "CalendarThemeData({",
        "CalendarThemeData copyWith(",
      ],
      "views/move_request.dart": <String>["CalendarMoveRequest({"],
      "composition/calendar_controller.dart": <String>[
        "CalendarController({",
        "double get minDayWidth",
        "double get minSlotHeight",
        "double get monthWeekScale",
        "void setZoom(",
      ],
      "composition/calendar_view.dart": <String>[
        "class CalendarView<T> ",
        "final int slotMinutes;",
        "final CalendarEditPolicy<T>? editPolicy;",
      ],
    };
    final collected = <String>[];
    for (final MapEntry(key: file, value: names) in declarations.entries) {
      final source = File("lib/calendar/$file").readAsStringSync();
      for (final declaration in names) {
        final doc = docOf(source, declaration);
        final lower = doc.toLowerCase();
        if (!doc.contains("[ArgumentError]") ||
            !doc.contains("in every build") ||
            lower.contains("assert") ||
            lower.contains("debug build")) {
          collected.add("$file: $declaration");
        }
      }
    }
    expect(collected, isEmpty);
  });
}
