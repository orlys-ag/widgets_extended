/// The demo app builds on the package's public API alone: every file under
/// lib/ imports the package only through its barrel.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The package's barrel, the one import of the package the app takes.
const String barrel = "package:widgets_extended/widgets_extended.dart";

void main() {
  test("PA1 each file of the app imports the package only through its "
      "barrel", () {
    final directive = RegExp(
      r"""^\s*(?:import|export)\s+['"](package:widgets_extended/[^'"]+)['"]""",
      multiLine: true,
    );
    final urisOf = <String, Set<String>>{};
    for (final entity in Directory("lib").listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith(".dart")) {
        continue;
      }
      for (final match in directive.allMatches(entity.readAsStringSync())) {
        (urisOf[entity.path] ??= <String>{}).add(match.group(1)!);
      }
    }
    // The scan reads the app's imports of the package.
    expect(urisOf, isNotEmpty);
    expect(<String, Set<String>>{
      for (final entry in urisOf.entries)
        if (entry.value.any((uri) {
          return uri != barrel;
        }))
          entry.key: entry.value,
    }, isEmpty);
  });
}
