/// The names the module barrel shows, the imports and names of the
/// module's files, and the classes and docs of the checks a release build
/// runs.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

import '../scheduling/class_source.dart';

/// The module barrel, from the package root, where `flutter test` runs.
const String barrelPath = "lib/calendar/calendar.dart";

/// The scheduling module's barrel, the one file of lib/scheduling/ the
/// calendar reaches.
const String schedulingBarrelPath = "lib/scheduling/scheduling.dart";

/// The module's layers, each a directory of lib/calendar/, in the order
/// their files import up.
const List<String> layers = <String>["presentation", "views", "composition"];

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
  "presentation": widgetsAndBelow,
  "views": widgetsAndBelow,
  "composition": <String>{...widgetsAndBelow, "material", "cupertino"},
};

/// The first directory under lib/calendar/ of [path], a path from the
/// package root.
String layerOf(String path) {
  return path.split("/")[2];
}

/// The module's Dart files but the barrel, from the package root: those
/// Git tracks and the new ones it does not ignore. Checks that the list
/// holds a file of each layer.
List<String> moduleFiles() {
  final files = <String>[
    for (final file in trackedDartFiles("lib/calendar"))
      if (file != barrelPath) file,
  ];
  expect(<String>{
    for (final file in files) layerOf(file),
  }, containsAll(layers));
  return files;
}

/// The file, from the package root, that [uri], a directive's URI in the
/// file at [path], names: a relative URI resolved against [path], and a
/// `package:widgets_extended/` URI under lib/; null for any other scheme.
String? packageFileOf(String path, String uri) {
  final parsed = Uri.parse(uri);
  if (!parsed.hasScheme) {
    return Uri.parse(path).resolve(uri).path;
  }
  if (parsed.scheme == "package" &&
      parsed.pathSegments.isNotEmpty &&
      parsed.pathSegments.first == "widgets_extended") {
    return "lib/${parsed.pathSegments.skip(1).join("/")}";
  }
  return null;
}

/// The names the scheduling barrel's exports show.
Set<String> schedulingNames() {
  return <String>{
    for (final export in exportsOf(
      File(schedulingBarrelPath).readAsStringSync(),
      schedulingBarrelPath,
    ))
      ...?export.shown,
  };
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

  test("B2 the barrel shows by name: the scheduling barrel's every name, "
      "through one export of that barrel; of the views only the types the "
      "calendar's signatures use, and no view; and of the localizations "
      "file the localizations and their English default", () {
    final source = File(barrelPath).readAsStringSync();
    final exports = exportsOf(source, barrelPath);
    // Every directive the barrel holds was read.
    expect(exports, hasLength(directiveUris(source).length));
    for (final export in exports) {
      expect(export.shown, isNotNull, reason: export.path);
    }
    final scheduling = <String, Set<String>>{
      for (final export in exports)
        if (export.path.startsWith("lib/scheduling/"))
          export.path: export.shown!.toSet(),
    };
    expect(scheduling.keys, <String>[schedulingBarrelPath]);
    // Setup sanity: the scheduling barrel's names were read.
    expect(schedulingNames(), containsAll(<String>{"CalendarEntry"}));
    expect(scheduling[schedulingBarrelPath], schedulingNames());
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
    for (final export in exports) {
      expect(
        export.shown!.toSet().intersection(viewWidgets),
        isEmpty,
        reason: export.path,
      );
    }
  });

  test("B4 each class the barrel shows of the module's own files says how "
      "a host builds on it: a class a host extends is base, the widgets "
      "neither, and every other class final or sealed; and each function "
      "or constant it shows names the calendar", () {
    const widgets = <String>{
      "CalendarView",
      "CalendarActivityIndicator",
      "CalendarTheme",
    };
    const bases = <String>{
      "CalendarController",
      "CalendarLocalizations",
      "DefaultCalendarLocalizations",
    };
    final shown = <String>{
      for (final export in exportsOf(
        File(barrelPath).readAsStringSync(),
        barrelPath,
      ))
        if (export.path.startsWith("lib/calendar/")) ...export.shown!,
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
    // Every name the barrel shows of the module's own files has a
    // declaration the scan reads, and the scan reads a class of each kind.
    expect(shown.difference(declared), isEmpty);
    expect(
      kindOf.keys,
      containsAll(<String>{
        ...widgets,
        ...bases,
        "CalendarThemeData",
        "CalendarMoveRequest",
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
      "the layer table, and the scheduling, board and sliver_tree modules "
      "only through their barrels", () {
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
            target == schedulingBarrelPath ||
            ((layer == "views" || layer == "composition") &&
                (target == "lib/board/board.dart" ||
                    target == "lib/sliver_tree/sliver_tree.dart"));
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

  test("LY5 no file under lib/calendar, the barrel included, reaches the "
      "scheduling module but through its barrel, nor a lower layer under "
      "lib/calendar", () {
    final files = trackedDartFiles("lib/calendar");
    expect(files, contains(barrelPath));
    const lowerLayers = <String>[
      "lib/calendar/dates/",
      "lib/calendar/entries/",
      "lib/calendar/policy/",
      "lib/calendar/store/",
    ];
    final reaching = <String>{};
    final wrong = <String>[];
    for (final path in files) {
      for (final uri in directiveUris(File(path).readAsStringSync())) {
        final target = packageFileOf(path, uri);
        if (target == null) {
          continue;
        }
        if (lowerLayers.any(target.startsWith) ||
            (target.startsWith("lib/scheduling/") &&
                target != schedulingBarrelPath)) {
          wrong.add("$path: $uri");
        } else if (target == schedulingBarrelPath) {
          reaching.add(path);
        }
      }
    }
    expect(wrong, isEmpty);
    // Setup sanity: the module reaches the scheduling barrel.
    expect(reaching, isNotEmpty);
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
        path: "lib/calendar/presentation/calendar_theme.dart",
        name: "CalendarThemeData",
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
      expect(asserts.allMatches(body), isEmpty, reason: name);
    }
  });

  test("RC21 a check builds nothing on a valid value: CalendarThemeData's "
      "constructor builds no list of its styles", () {
    final theme = constructorBody(
      "lib/calendar/presentation/calendar_theme.dart",
      "  CalendarThemeData({",
    );
    // Setup sanity: the body read is the one that checks the styles.
    expect(theme, contains("hourLabelStyle"));
    expect(theme, isNot(contains("_textStyles")));
    expect(theme, isNot(contains("[")));
  });

  test("RC20 the doc of each check says it throws an [ArgumentError] in "
      "every build, and none says it asserts or runs in a debug build", () {
    const declarations = <String, List<String>>{
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
