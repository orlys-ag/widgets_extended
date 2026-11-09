/// The scheduling module's files: what each imports, the names its barrel
/// shows and how a host builds on each, the package barrel's export of that
/// barrel, the statics that hold the helpers' bodies, the imports of its
/// tests, and the classes and docs of the checks a release build runs.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'class_source.dart';

/// The module barrel, from the package root, where `flutter test` runs.
const String barrelPath = "lib/scheduling/scheduling.dart";

/// The module's layers, each a directory of lib/scheduling/, in the order
/// their files import up.
const List<String> layers = <String>["dates", "entries", "policy", "store"];

/// The first directory under lib/scheduling/ or test/scheduling/ of
/// [path], a path from the package root.
String layerOf(String path) {
  return path.split("/")[2];
}

/// The module's Dart files, the barrel included. Checks that the list
/// holds a file of each layer, so no check passes on an empty module.
List<String> schedulingFiles() {
  final files = trackedDartFiles("lib/scheduling");
  expect(<String>{
    for (final file in files)
      if (file != barrelPath) layerOf(file),
  }, containsAll(layers));
  return files;
}

/// The 31 helpers [CalendarDates] offers as public statics.
const Set<String> calendarDatesStatics = <String>{
  "defaultSlotMinutes",
  "slotMinuteChoices",
  "minutesPerDay",
  "dateOnly",
  "addDays",
  "addMonths",
  "daysBetween",
  "weekdayColumn",
  "dayNumber",
  "weekdayColumnOfDay",
  "shownDayNear",
  "nextShownDay",
  "shownDaysOfWeek",
  "dateOfDayNumber",
  "isDayStart",
  "minuteOfDay",
  "endMinuteOfDay",
  "wallMinuteOf",
  "endWallMinuteOf",
  "timeAtWallMinute",
  "endAtWallMinute",
  "rangeEndAtWallMinute",
  "repeatedStretchOf",
  "isLaterOccurrence",
  "firstWallMinuteNotBefore",
  "lastWallMinuteNotAfter",
  "lastDayNumberOf",
  "wallSpanOf",
  "pieceOn",
  "isoDate",
  "isoTime",
};

/// The overlap rule's statics on `NoOverlapsPolicy`.
const Set<String> overlapStatics = <String>{
  "entriesShareTime",
  "rangeSharesTime",
  "timesOverlap",
};

/// [source] without its comments.
String withoutComments(String source) {
  return source
      .replaceAll(RegExp(r"/\*[\s\S]*?\*/"), "")
      .replaceAll(RegExp(r"//[^\n]*"), "");
}

/// The index of the [close] bracket that matches the [open] bracket of
/// [source] at [at].
int matchingBracket(String source, int at, String open, String close) {
  var depth = 0;
  for (var index = at; index < source.length; index++) {
    if (source[index] == open) {
      depth++;
    } else if (source[index] == close) {
      depth--;
      if (depth == 0) {
        return index;
      }
    }
  }
  fail("No $close matches the $open at $at");
}

/// The static members [body], a class body without comments, declares at
/// its own depth: each one's name, and its body for a method, null for a
/// constant or field.
Map<String, String?> staticsOf(String body) {
  final statics = <String, String?>{};
  final declaration = RegExp(
    r"^  static\s+(?:const\s+|final\s+)?"
    r".*?\b([A-Za-z_]\w*)(?:<[^>]*>)?\s*(\(|=)",
    multiLine: true,
  );
  for (final match in declaration.allMatches(body)) {
    final name = match.group(1)!;
    if (match.group(2) == "=") {
      statics[name] = null;
      continue;
    }
    final close = matchingBracket(body, match.end - 1, "(", ")");
    final open = body.indexOf("{", close);
    statics[name] = body.substring(
      open + 1,
      matchingBracket(body, open, "{", "}"),
    );
  }
  return statics;
}

/// The callee of [body], a method body, where the body is one `return` of
/// one call whose arguments call nothing: the called name without its
/// qualifier. Null for any other body.
String? forwardedCallOf(String body) {
  final match = RegExp(
    r"^\s*return\s+(?:[A-Za-z_]\w*\.)*([A-Za-z_]\w*)\s*\(([^()]*)\)\s*;\s*$",
  ).firstMatch(body);
  return match?.group(1);
}

void main() {
  test("SY1 each file imports, of packages, only Flutter's foundation, of "
      "dart:ui only Color, and nothing of the calendar, board, sliver_tree "
      "or sectioned_sliver_list modules, nor the package barrel", () {
    const outside = <String>[
      "lib/calendar/",
      "lib/board/",
      "lib/sliver_tree/",
      "lib/sectioned_sliver_list/",
    ];
    for (final path in schedulingFiles()) {
      final source = File(path).readAsStringSync();
      for (final uri in directiveUris(source)) {
        if (uri.startsWith("dart:")) {
          continue;
        }
        if (Uri.parse(uri).hasScheme) {
          expect(uri, "package:flutter/foundation.dart", reason: path);
          continue;
        }
        final target = Uri.parse(path).resolve(uri).path;
        expect(target, isNot("lib/widgets_extended.dart"), reason: path);
        for (final module in outside) {
          expect(target, isNot(startsWith(module)), reason: "$path: $uri");
        }
      }
      for (final match in RegExp(
        r"""^\s*import\s+['"]dart:ui['"]([^;]*);""",
        multiLine: true,
      ).allMatches(source)) {
        expect(match.group(1)!.trim(), "show Color", reason: path);
      }
    }
  });

  test("SY2 each file imports the module's files only from its own layer "
      "and the layers before it, and never the barrel", () {
    for (final path in schedulingFiles()) {
      if (path == barrelPath) {
        continue;
      }
      final layer = layerOf(path);
      expect(layers, contains(layer), reason: path);
      for (final uri in directiveUris(File(path).readAsStringSync())) {
        if (Uri.parse(uri).hasScheme) {
          continue;
        }
        final target = Uri.parse(path).resolve(uri).path;
        expect(target, isNot(barrelPath), reason: "$path: $uri");
        expect(target, startsWith("lib/scheduling/"), reason: "$path: $uri");
        expect(
          layers.indexOf(layerOf(target)),
          inInclusiveRange(0, layers.indexOf(layer)),
          reason: "$path: $uri",
        );
      }
    }
  });

  test("SY3 the barrel exports each file by name, the shown names of each "
      "file exactly those of the module's public surface; and the package "
      "barrel exports the barrel", () {
    schedulingFiles();
    final source = File(barrelPath).readAsStringSync();
    final exports = exportsOf(source, barrelPath);
    // Every directive the barrel holds was read.
    expect(exports, hasLength(directiveUris(source).length));
    expect(
      <String, Set<String>?>{
        for (final export in exports) export.path: export.shown?.toSet(),
      },
      <String, Set<String>>{
        "lib/scheduling/dates/calendar_dates.dart": <String>{
          "CalendarDates",
          "CalendarDayHours",
          "CalendarHourLabelFormat",
          "CalendarMonthGrid",
          "CalendarWeekdaySet",
        },
        "lib/scheduling/entries/calendar_data_source.dart": <String>{
          "CalendarAllChanged",
          "CalendarDataSource",
          "CalendarDaysChanged",
          "CalendarEntryPut",
          "CalendarEntryRemoved",
          "CalendarSourceChange",
        },
        "lib/scheduling/entries/calendar_entry.dart": <String>{
          "CalendarCreateRange",
          "CalendarEntry",
        },
        "lib/scheduling/policy/edit_policy.dart": <String>{
          "CalendarEditPolicy",
          "CalendarNow",
          "CalendarOverlapCandidate",
          "CalendarResizeEdges",
          "DayLimitPolicy",
          "NoOverlapsPolicy",
          "UnrestrictedEditPolicy",
        },
        "lib/scheduling/policy/edit_rules.dart": <String>{
          "CalendarEarliestStart",
          "CalendarEditRules",
        },
        "lib/scheduling/policy/history_lock_policy.dart": <String>{
          "HistoryLockPolicy",
        },
        "lib/scheduling/store/caching_calendar_store.dart": <String>{
          "CachingCalendarStore",
        },
        "lib/scheduling/store/calendar_store.dart": <String>{
          "CalendarHoursException",
          "CalendarLoadStatus",
          "CalendarShownEntry",
          "CalendarStore",
          "CalendarStoreException",
          "CalendarWritePendingException",
          "compareCalendarEntries",
        },
        "lib/scheduling/store/memory_calendar_store.dart": <String>{
          "CalendarEntryChanged",
          "MemoryCalendarStore",
        },
      },
    );

    // The calendar barrel's show brings every name to the package barrel
    // without this export, so no compiled read of the package barrel sees
    // it go.
    final package = File("lib/widgets_extended.dart").readAsStringSync();
    expect(package, contains("export 'scheduling/scheduling.dart';"));
  });

  test("SY4 the barrel's show clauses name no CalendarEntryTime", () {
    schedulingFiles();
    final exports = exportsOf(File(barrelPath).readAsStringSync(), barrelPath);
    final entries = <List<String>?>[
      for (final export in exports)
        if (export.path == "lib/scheduling/entries/calendar_entry.dart")
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

  test("SY5 each class the barrel shows says how a host builds on it: the "
      "stores and the edit policy base, the data source an interface, and "
      "every other class final or sealed; and each function or constant it "
      "shows names the calendar", () {
    final files = schedulingFiles();
    const bases = <String>{
      "CalendarStore",
      "MemoryCalendarStore",
      "CachingCalendarStore",
      "CalendarEditPolicy",
    };
    const interfaces = <String>{"CalendarDataSource"};
    final shown = <String>{
      for (final export in exportsOf(
        File(barrelPath).readAsStringSync(),
        barrelPath,
      ))
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
    final declared = <String>{};
    final kindOf = <String, String>{};
    final functionsAndConstants = <String>{};
    for (final file in files) {
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
                (bases.contains(name)
                    ? "base"
                    : interfaces.contains(name)
                    ? "interface"
                    : "closed"))
          name: kindOf[name]!,
    }, isEmpty);
    // The scan reads a function the barrel shows.
    expect(functionsAndConstants, contains("compareCalendarEntries"));
    expect(<String>{
      for (final name in shown)
        if (functionsAndConstants.contains(name) &&
            !name.toLowerCase().contains("calendar"))
          name,
    }, isEmpty);
  });

  test("SY6 no file under lib/scheduling names what the demo owns", () {
    final demoNames = RegExp(
      r"CalendarSettings|hoursErrorsOf|lockErrorsOf|\berrorsOf\b|"
      r"validateItemJson|ItemPayload|Harbor|[Ww]orkspace|Show all items|"
      r"Fit to screen",
    );
    for (final path in schedulingFiles()) {
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

  test("SY7 the layers' tests and the helpers beside them import of the "
      "package only the scheduling module, and nothing of test/calendar", () {
    final files = <String>[
      for (final file in trackedDartFiles("test/scheduling"))
        if (layers.contains(layerOf(file)) ||
            file == "test/scheduling/dst_days.dart" ||
            file == "test/scheduling/class_source.dart")
          file,
    ];
    expect(<String>{
      for (final file in files)
        if (file.endsWith("_test.dart")) layerOf(file),
    }, containsAll(layers));
    expect(
      files,
      containsAll(<String>[
        "test/scheduling/dst_days.dart",
        "test/scheduling/class_source.dart",
      ]),
    );
    for (final path in files) {
      for (final uri in directiveUris(File(path).readAsStringSync())) {
        if (uri.startsWith("package:widgets_extended/")) {
          expect(
            uri,
            startsWith("package:widgets_extended/scheduling/"),
            reason: path,
          );
        } else if (!Uri.parse(uri).hasScheme) {
          expect(
            Uri.parse(path).resolve(uri).path,
            isNot(startsWith("test/calendar/")),
            reason: "$path: $uri",
          );
        }
      }
    }
  });

  group("SY8 the checks a release build runs", () {
    setUp(schedulingFiles);

    test("each class whose values a host gives checks them with a throw of "
        "an ArgumentError, and with no assert and no debug-only branch", () {
      const classes = <({String path, String name})>[
        (
          path: "lib/scheduling/dates/calendar_dates.dart",
          name: "CalendarWeekdaySet",
        ),
        (
          path: "lib/scheduling/dates/calendar_dates.dart",
          name: "CalendarDayHours",
        ),
        (
          path: "lib/scheduling/dates/calendar_dates.dart",
          name: "CalendarDates",
        ),
        (
          path: "lib/scheduling/policy/edit_policy.dart",
          name: "DayLimitPolicy",
        ),
        (
          path: "lib/scheduling/policy/edit_rules.dart",
          name: "CalendarEarliestStart",
        ),
        (
          path: "lib/scheduling/policy/edit_rules.dart",
          name: "CalendarEditRules",
        ),
        (
          path: "lib/scheduling/entries/calendar_data_source.dart",
          name: "CalendarDaysChanged",
        ),
        (
          path: "lib/scheduling/store/calendar_store.dart",
          name: "CalendarShownEntry",
        ),
        (
          path: "lib/scheduling/entries/calendar_entry.dart",
          name: "CalendarCreateRange",
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

    test("the day checks build no DateTime of their own on a valid value "
        "but the one isDayStart builds", () {
      final dayChecks = <({String path, String declaration, bool dayStarts})>[
        (
          path: "lib/scheduling/policy/edit_rules.dart",
          declaration: "  CalendarEarliestStart(",
          dayStarts: true,
        ),
        (
          path: "lib/scheduling/entries/calendar_entry.dart",
          declaration: "  CalendarCreateRange({",
          dayStarts: true,
        ),
        (
          path: "lib/scheduling/entries/calendar_data_source.dart",
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

    test("the doc of each check says it throws an [ArgumentError] in every "
        "build, and none says it asserts or runs in a debug build", () {
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
      };
      final collected = <String>[];
      for (final MapEntry(key: file, value: names) in declarations.entries) {
        final source = File("lib/scheduling/$file").readAsStringSync();
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
  });

  test("SY9 CalendarDates and NoOverlapsPolicy declare exactly their "
      "public statics, which hold their bodies: no top-level declaration "
      "shares a name with one, and none but the two wall-minute statics "
      "only forwards to another declaration of the module", () {
    final sources = <String, String>{
      for (final path in schedulingFiles())
        path: withoutComments(File(path).readAsStringSync()),
    };
    final dates = staticsOf(
      classBody(
        File("lib/scheduling/dates/calendar_dates.dart").readAsStringSync(),
        "CalendarDates",
      ),
    );
    final overlap = staticsOf(
      classBody(
        File("lib/scheduling/policy/edit_policy.dart").readAsStringSync(),
        "NoOverlapsPolicy",
      ),
    );
    expect(<String>{
      for (final name in dates.keys)
        if (!name.startsWith("_")) name,
    }, calendarDatesStatics);
    expect(
      <String>{
        for (final name in dates.keys)
          if (name.startsWith("_")) name,
      },
      <String>{"_instantAtWallMinute"},
    );
    expect(overlap.keys.toSet(), overlapStatics);
    // A declaration at a line's start, outside every class: a function,
    // a getter or a variable of the name.
    final allSource = sources.values.join("\n");
    for (final name in <String>{...calendarDatesStatics, ...overlapStatics}) {
      expect(
        RegExp(
          "^(?![\\s/}@]).*[\\s)?>]$name\\s*(?:<[^>\\n]*>)?\\s*(?:\\(|=)",
          multiLine: true,
        ).hasMatch(allSource),
        isFalse,
        reason: name,
      );
    }
    // The names of the functions and methods the module declares: a type
    // and a name before a parameter list, at a line's start, where no
    // statement's keyword stands for the type.
    final declaredFunctions = <String>{
      for (final match in RegExp(
        r"^\s*(?:static\s+)?"
        r"(?!(?:return|throw|await|yield|else|new|const|final|var|case)\b)"
        r"(?:[\w<>?,\[\]]+|\([^)\n]*\))\??\s+([A-Za-z_]\w*)"
        r"\s*(?:<[^>()\n]*>)?\s*\(",
        multiLine: true,
      ).allMatches(allSource))
        match.group(1)!,
    };
    expect(
      declaredFunctions,
      containsAll(<String>{"_instantAtWallMinute", "daysInMonth"}),
    );
    expect(declaredFunctions, isNot(contains("DateTime")));
    final forwards = <String, String>{
      for (final MapEntry(key: name, value: body) in <String, String?>{
        ...dates,
        ...overlap,
      }.entries)
        if (!name.startsWith("_") &&
            body != null &&
            declaredFunctions.contains(forwardedCallOf(body)))
          name: forwardedCallOf(body)!,
    };
    // The two wall-minute statics are one call of the instant they share,
    // which the reading of the bodies finds.
    expect(forwards, <String, String>{
      "timeAtWallMinute": "_instantAtWallMinute",
      "endAtWallMinute": "_instantAtWallMinute",
    });
  });
  test(
    "SY10 only calendar_dates.dart imports package:timezone, and nothing "
    "imports its data",
    skip: true,
    () {
      const importer = "lib/scheduling/dates/calendar_dates.dart";
      const barrels = <String>[
        "lib/scheduling/scheduling.dart",
        "lib/calendar/calendar.dart",
        "lib/widgets_extended.dart",
      ];
      const timezoneUri = "package:timezone/timezone.dart";
      final files = trackedDartFiles("lib");
      expect(files, containsAll(<String>[importer, ...barrels]));
      var imports = 0;
      final foreign = RegExp(
        r"package:timezone/(?:data/|browser\.dart|standalone\.dart)",
      );
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final importing = directiveUris(source).contains(timezoneUri);
        if (importing) {
          imports++;
          expect(path, importer);
        }
        expect(foreign.hasMatch(source), isFalse, reason: path);
      }
      expect(imports, 1);
      for (final barrel in barrels) {
        expect(
          File(barrel).readAsStringSync(),
          isNot(contains("package:timezone")),
          reason: barrel,
        );
      }
    },
  );

  test("SY11 a device-path helper keeps its body after its guard", skip: true, () {
    const guards = <String, String>{
      "dateOnly": "if (date is TZDateTime) {",
      "addDays": "if (date is TZDateTime) {",
      "addMonths": "if (date is TZDateTime) {",
      "isDayStart": "if (time is TZDateTime) {",
      "rangeEndAtWallMinute": "if (start is TZDateTime) {",
      "repeatedStretchOf": "if (day is TZDateTime) {",
      "isLaterOccurrence": "if (time is TZDateTime) {",
      "firstWallMinuteNotBefore": "if (time is TZDateTime) {",
      "lastWallMinuteNotAfter": "if (time is TZDateTime) {",
      "dateOfDayNumber": "if (zone != null) {",
      "_instantAtWallMinute":
          "final location = zone ?? (from is TZDateTime ? from.location : null); if (location != null) {",
    };
    const deviceBodies = <String, String>{
      "dateOnly": "return DateTime(date.year, date.month, date.day);",
      "addDays": "return DateTime(date.year, date.month, date.day + days);",
      "addMonths":
          "final first = DateTime(date.year, date.month + months); final day "
          "= math.min(date.day, daysInMonth(first.year, first.month)); return "
          "DateTime(first.year, first.month, day);",
      "isDayStart": "return time == DateTime(time.year, time.month, time.day);",
      "rangeEndAtWallMinute":
          "final moved = start.add(Duration(minutes: wall - "
          "wallMinuteOf(start))); if (moved.isAfter(start) && "
          "wallMinuteOf(moved) <= wallMinuteOf(start) && moved.timeZoneOffset "
          "< moved.subtract(const Duration(minutes: 1)).timeZoneOffset) { "
          "return moved; } return endAtWallMinute(wall, from: from);",
      "repeatedStretchOf":
          "final date = dateOnly(day); final change = date.timeZoneOffset - "
          "addDays(date, 1).timeZoneOffset; return change > Duration.zero ? "
          "change : Duration.zero;",
      "isLaterOccurrence":
          "final minute = time.subtract( Duration( seconds: time.second, "
          "milliseconds: time.millisecond, microseconds: time.microsecond, ), "
          "); return minute != timeAtWallMinute(wallMinuteOf(time));",
      "firstWallMinuteNotBefore":
          "var wall = wallMinuteOf(time); while (!(timeAtWallMinute(wall - 1, "
          "from: from)?.isBefore(time) ?? true)) { wall--; } while "
          "(timeAtWallMinute(wall, from: from)?.isBefore(time) ?? true) { "
          "wall++; } return wall;",
      "lastWallMinuteNotAfter":
          "DateTime? endAt(int wall) { return start == null ? "
          "endAtWallMinute(wall, from: from) : rangeEndAtWallMinute(start, "
          "wall, from: from); } var wall = endWallMinuteOf(time); while "
          "(!(endAt(wall + 1)?.isAfter(time) ?? true)) { wall++; } while "
          "(endAt(wall)?.isAfter(time) ?? true) { wall--; } return wall;",
      "dateOfDayNumber":
          "final utc = DateTime.fromMillisecondsSinceEpoch( day * "
          "Duration.millisecondsPerDay, isUtc: true, ); return "
          "DateTime(utc.year, utc.month, utc.day);",
      "_instantAtWallMinute":
          "final minute = wall % minutesPerDay; final day = (wall - minute) "
          "~/ minutesPerDay; final date = dateOfDayNumber(day); final hour = "
          "minute ~/ 60; final ofHour = minute % 60; bool reads(DateTime "
          "time) { return time.year == date.year && time.month == date.month "
          "&& time.day == date.day && time.hour == hour && time.minute == "
          "ofHour; } final time = minute == 0 ? date : DateTime(date.year, "
          "date.month, date.day, hour, ofHour); if (!reads(time)) { return "
          "end && minute == 0 ? date : null; } final change = "
          "repeatedStretchOf(date); if (change == Duration.zero) { return "
          "time; } DateTime? earliest; DateTime? latest; for (final candidate "
          "in <DateTime>[ time.subtract(change), time, time.add(change), ]) { "
          "if (reads(candidate)) { earliest ??= candidate; latest = "
          "candidate; } } if (from != null && dayNumber(from) == day && "
          "isLaterOccurrence(from)) { return latest; } return earliest;",
    };
    final statics = staticsOf(
      classBody(
        File("lib/scheduling/dates/calendar_dates.dart").readAsStringSync(),
        "CalendarDates",
      ),
    );
    for (final MapEntry(key: name, value: guard) in guards.entries) {
      final body = statics[name]!.replaceAll(RegExp(r"\s+"), " ").trim();
      expect(body, startsWith(guard), reason: name);
      final close = matchingBracket(body, guard.length - 1, "{", "}");
      expect(
        body.substring(close + 1).trim(),
        deviceBodies[name],
        reason: name,
      );
    }
  });
}
