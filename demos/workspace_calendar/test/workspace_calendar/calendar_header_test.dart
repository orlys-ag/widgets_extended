/// The calendar's header in Roboto, from the Flutter SDK's cache: a
/// proportional font, in which the titles of different months differ in
/// width, as they do in an app. Loaded for this file alone, so the other
/// files keep the test font.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_harness.dart';

/// The bytes of [file] in the SDK's Material fonts.
Future<ByteData> materialFont(String file) async {
  final root = Platform.environment["FLUTTER_ROOT"];
  if (root == null) {
    throw StateError("FLUTTER_ROOT is not set; run the tests with flutter.");
  }
  final bytes = File(
    "$root/bin/cache/artifacts/material_fonts/$file",
  ).readAsBytesSync();
  return ByteData.sublistView(bytes);
}

void main() {
  setUpAll(() async {
    final roboto = FontLoader("Roboto")
      ..addFont(materialFont("roboto-regular.ttf"))
      ..addFont(materialFont("roboto-medium.ttf"))
      ..addFont(materialFont("roboto-bold.ttf"));
    await roboto.load();
  });

  testWidgets(
    "H1 the title names the month in three letters and the next chevron "
    "stays put from month to month",
    (tester) async {
      await pumpCalendar(tester);
      await pickMode(tester, "Month");
      const titles = <String>[
        "Apr 2026",
        "May 2026",
        "Jun 2026",
        "Jul 2026",
        "Aug 2026",
        "Sep 2026",
        "Oct 2026",
        "Nov 2026",
        "Dec 2026",
        "Jan 2027",
        "Feb 2027",
        "Mar 2027",
      ];
      final widths = <double>{};
      final nexts = <double>{};
      for (final title in titles) {
        expect(find.text(title), findsOneWidget);
        widths.add(tester.getSize(find.text(title)).width);
        nexts.add(tester.getRect(find.byTooltip("Next month")).left);
        await tester.tap(find.byTooltip("Next month"));
        await tester.pump();
        await tester.pump(harnessLatency);
        await tester.pumpAndSettle();
      }
      // Sanity: the font gives the titles different widths.
      expect(widths.length, greaterThan(1));
      expect(nexts, hasLength(1));
    },
  );
}
