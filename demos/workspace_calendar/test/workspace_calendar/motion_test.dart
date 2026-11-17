/// The demo's motion groups, [HarborMotion], and where each applies: the
/// calendar's theme, the item form and settings sheets, the delete dialog,
/// the snack bars, the menus, and the settings sheet's own parts; and the
/// platform's request for no animations, which stops all of them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/settings_sheet.dart';

import 'calendar_harness.dart';

const Size tall = Size(390.0, 1400.0);

/// The control points of [curve], a [Cubic].
List<double> pointsOf(Curve? curve) {
  final cubic = curve! as Cubic;
  return <double>[cubic.a, cubic.b, cubic.c, cubic.d];
}

/// The control points of the [Cubic] that [curve], a [FlippedCurve],
/// flips.
List<double> flippedPointsOf(Curve? curve) {
  return pointsOf((curve! as FlippedCurve).curve);
}

const List<double> standardPoints = <double>[0.2, 0.0, 0.0, 1.0];
const List<double> surfaceInPoints = <double>[0.05, 0.7, 0.1, 1.0];
const List<double> surfaceOutPoints = <double>[0.3, 0.0, 0.8, 0.15];

/// Makes the platform ask for no animations until the test ends.
void disableAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// The route of the widget [finder] finds.
ModalRoute<Object?> routeOf(WidgetTester tester, Finder finder) {
  return ModalRoute.of(tester.element(finder))!;
}

/// Opens the form of the seed's Brainstorm from its block in Week.
Future<void> openBrainstorm(WidgetTester tester) async {
  await pickMode(tester, "Week");
  await tester.tap(blockFinder(brainstormId));
  await tester.pumpAndSettle();
  // Setup sanity: the form is open.
  expect(find.byType(BottomSheet), findsOneWidget);
}

/// The animation controller of the snack bar showing.
AnimationController snackBarController(WidgetTester tester) {
  return tester.widget<SnackBar>(find.byType(SnackBar)).animation!
      as AnimationController;
}

/// The menu buttons the calendar shows but the header's view menu.
Iterable<PopupMenuButton<Object?>> cardMenus(WidgetTester tester) {
  return tester
      .widgetList(
        find.byWidgetPredicate((widget) {
          return widget is PopupMenuButton &&
              widget is! PopupMenuButton<CalendarViewKind>;
        }),
      )
      .cast<PopupMenuButton<Object?>>();
}

/// The opacity of the nearest [FadeTransition] above what [finder] finds.
double fadeAbove(WidgetTester tester, Finder finder) {
  return tester
      .widget<FadeTransition>(
        find.ancestor(of: finder, matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;
}

/// The nearest [AnimatedSize] above what [finder] finds.
AnimatedSize sizeAbove(WidgetTester tester, Finder finder) {
  return tester.widget<AnimatedSize>(
    find.ancestor(of: finder, matching: find.byType(AnimatedSize)).first,
  );
}

void main() {
  test("M1 quick is 150 ms, standard 300 ms, and a surface 400 ms in and "
      "200 ms out; quick and standard ease on Cubic(0.2, 0.0, 0.0, 1.0), a "
      "surface in on Cubic(0.05, 0.7, 0.1, 1.0) and out on "
      "Cubic(0.3, 0.0, 0.8, 0.15); each reverses on the flip of its out "
      "curve; and Harbor's motion and the calendar's theme are standard's", () {
    const quick = HarborMotion.quick;
    expect(quick.duration, const Duration(milliseconds: 150));
    expect(quick.reverseDuration, const Duration(milliseconds: 150));
    expect(pointsOf(quick.curve), standardPoints);
    expect(flippedPointsOf(quick.reverseCurve), standardPoints);

    const standard = HarborMotion.standard;
    expect(standard.duration, const Duration(milliseconds: 300));
    expect(standard.reverseDuration, const Duration(milliseconds: 300));
    expect(pointsOf(standard.curve), standardPoints);
    expect(flippedPointsOf(standard.reverseCurve), standardPoints);

    const surface = HarborMotion.surface;
    expect(surface.duration, const Duration(milliseconds: 400));
    expect(surface.reverseDuration, const Duration(milliseconds: 200));
    expect(pointsOf(surface.curve), surfaceInPoints);
    expect(flippedPointsOf(surface.reverseCurve), surfaceOutPoints);

    expect(harborMotionDuration, const Duration(milliseconds: 300));
    expect(pointsOf(harborMotionCurve), standardPoints);
    expect(harborCalendarTheme.motionDuration, harborMotionDuration);
    expect(pointsOf(harborCalendarTheme.motionCurve), standardPoints);
  });

  testWidgets("M2 the item form and the settings sheet come in and leave as "
      "a surface", (tester) async {
    await pumpCalendar(tester, editing: true, size: tall);
    await openBrainstorm(tester);
    final form =
        routeOf(tester, find.byType(BottomSheet))
            as ModalBottomSheetRoute<Object?>;
    expect(form.sheetAnimationStyle, HarborMotion.surface);
    expect(form.transitionDuration, const Duration(milliseconds: 400));
    expect(form.reverseTransitionDuration, const Duration(milliseconds: 200));
    await tester.tap(find.widgetWithText(TextButton, "Cancel"));
    await tester.pumpAndSettle();

    await openSettings(tester);
    final settings = routeOf(tester, find.byType(CalendarSettingsSheet));
    expect(
      (settings as ModalBottomSheetRoute<Object?>).sheetAnimationStyle,
      HarborMotion.surface,
    );
  });

  testWidgets("M3 the delete dialog comes in on the surface's in curve and "
      "leaves on its out curve, over the surface's out duration both ways, "
      "since its route has one duration", (tester) async {
    await pumpCalendar(tester, editing: true, size: tall);
    await openBrainstorm(tester);
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pumpAndSettle();
    final dialog = routeOf(tester, find.byType(AlertDialog));
    expect(dialog.transitionDuration, const Duration(milliseconds: 200));
    final fades = tester
        .widgetList<FadeTransition>(
          find.ancestor(
            of: find.byType(AlertDialog),
            matching: find.byType(FadeTransition),
          ),
        )
        .map((fade) {
          return fade.opacity;
        })
        .whereType<CurvedAnimation>()
        .single;
    expect(pointsOf(fades.curve), surfaceInPoints);
    expect(flippedPointsOf(fades.reverseCurve), surfaceOutPoints);
  });

  // A messenger keeps its snack bar's controller for the next snack bar
  // where that one passes no style
  // ([ScaffoldMessengerState.showSnackBar]), so M4 and M9 each check the
  // first snack bar their messenger shows.
  testWidgets("M4 a failed move's snack bar comes in over 400 ms and leaves "
      "over 200 ms", (tester) async {
    final api = MockCalendarApi(latency: harnessLatency);
    await createBeforePump(tester, api, taskJson("Moved", today, 600, 660));
    await pumpCalendar(
      tester,
      editing: true,
      api: api,
      size: tall,
      readAhead: 0,
    );
    await pickMode(tester, "Week");
    final items = await listAll(tester, api, today, today);
    final moved = blockFinder(
      items.singleWhere((item) {
            return item["title"] == "Moved";
          })["id"]!
          as String,
    );
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.update ? "Moving failed." : null;
    };
    await moveBlock(
      tester,
      moved,
      cellRect(tester, rowOf(14 * 60), colOf(2)).topLeft,
    );
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    // Setup sanity: the failed move shows its snack bar.
    expect(find.widgetWithText(SnackBar, "Moving failed."), findsOneWidget);
    final controller = snackBarController(tester);
    expect(controller.duration, const Duration(milliseconds: 400));
    expect(controller.reverseDuration, const Duration(milliseconds: 200));
  });

  testWidgets("M5 Agenda's card menus, the week start menu and a zone chip's "
      "remove button run quick", (tester) async {
    await pumpCalendar(tester, editing: true);
    final menus = cardMenus(tester).toList();
    // Setup sanity: Agenda shows cards with menus.
    expect(menus, isNotEmpty);
    for (final menu in menus) {
      expect(menu.popUpAnimationStyle, HarborMotion.quick);
    }

    await openSettings(tester);
    expect(
      tester
          .widget<PopupMenuButton<int>>(find.byKey(weekStartKey))
          .popUpAnimationStyle,
      HarborMotion.quick,
    );
    expect(
      tester
          .widget<InputChip>(find.byKey(zoneChipKey("")))
          .chipAnimationStyle
          ?.deleteDrawerAnimation,
      HarborMotion.quick,
    );
  });

  testWidgets("M6 the settings sheet's zone chips and modes resize over "
      "standard, its zone rows enter and leave over it, and its modes "
      "swap in sequence: the leaving one fades out over the first half, "
      "the coming one in over the second, each easing out", (tester) async {
    await pumpCalendar(tester);
    await openSettings(tester);
    final chips = sizeAbove(tester, find.byKey(zoneChoicesKey));
    expect(chips.duration, HarborMotion.standardDuration);
    expect(chips.curve, HarborMotion.standardCurve);
    final modes = sizeAbove(tester, find.byKey(weekStartKey));
    expect(modes.duration, HarborMotion.standardDuration);
    expect(modes.curve, HarborMotion.standardCurve);

    await tester.tap(find.byKey(manageZonesKey));
    await tester.pump();
    final half = HarborMotion.standardCurve.transform(0.5);
    // A quarter of the motion: half the leaving fade.
    await tester.pump(HarborMotion.standardDuration ~/ 4);
    expect(
      fadeAbove(tester, find.byKey(weekStartKey)),
      moreOrLessEquals(1.0 - half, epsilon: 0.001),
    );
    expect(fadeAbove(tester, find.byKey(zoneSearchKey)), 0.0);
    // Three quarters: half the coming fade.
    await tester.pump(HarborMotion.standardDuration ~/ 2);
    expect(
      fadeAbove(tester, find.byKey(zoneSearchKey)),
      moreOrLessEquals(half, epsilon: 0.001),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SyncedSliverTree<String, Location>>(
            find.byType(
              SyncedSliverTree<String, Location>,
              skipOffstage: false,
            ),
          )
          .animationStyle,
      TreeAnimationStyle.uniform(
        duration: HarborMotion.standardDuration,
        curve: HarborMotion.standardCurve,
      ),
    );
  });

  testWidgets("M7 where the platform asks for no animations the calendar's "
      "theme has no motion, and the sheets, the dialog, the snack bars, the "
      "menus and the settings sheet's parts run none", (tester) async {
    disableAnimations(tester);
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await pumpCalendar(tester, editing: true, api: api, size: tall);
    expect(
      CalendarTheme.of(
        tester.element(find.byType(CalendarView<ItemPayload>)),
      ).motionDuration,
      Duration.zero,
    );
    for (final menu in cardMenus(tester)) {
      expect(menu.popUpAnimationStyle, AnimationStyle.noAnimation);
    }

    await openBrainstorm(tester);
    expect(
      (routeOf(tester, find.byType(BottomSheet))
              as ModalBottomSheetRoute<Object?>)
          .sheetAnimationStyle,
      AnimationStyle.noAnimation,
    );
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.delete
          ? "Deleting failed."
          : null;
    };
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pumpAndSettle();
    expect(
      routeOf(tester, find.byType(AlertDialog)).transitionDuration,
      Duration.zero,
    );
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final controller = snackBarController(tester);
    expect(controller.duration, Duration.zero);
    expect(controller.reverseDuration, Duration.zero);
    ScaffoldMessenger.of(
      tester.element(find.byType(SnackBar)),
    ).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await openSettings(tester);
    expect(
      (routeOf(tester, find.byType(CalendarSettingsSheet))
              as ModalBottomSheetRoute<Object?>)
          .sheetAnimationStyle,
      AnimationStyle.noAnimation,
    );
    expect(
      tester
          .widget<PopupMenuButton<int>>(find.byKey(weekStartKey))
          .popUpAnimationStyle,
      AnimationStyle.noAnimation,
    );
    for (final key in <Key>[zoneChoicesKey, weekStartKey]) {
      expect(
        find.ancestor(of: find.byKey(key), matching: find.byType(AnimatedSize)),
        findsNothing,
        reason: "$key",
      );
    }
    await tester.tap(find.byKey(manageZonesKey));
    await tester.pump();
    // The modes swapped in the tap's own frame.
    expect(find.byKey(weekStartKey), findsNothing);
    // Setup sanity: the search field the next check looks above shows.
    expect(find.byKey(zoneSearchKey), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(zoneSearchKey),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<InputChip>(find.byKey(zoneChipKey("")))
          .chipAnimationStyle
          ?.deleteDrawerAnimation,
      AnimationStyle.noAnimation,
    );
    expect(
      tester
          .widget<SyncedSliverTree<String, Location>>(
            find.byType(
              SyncedSliverTree<String, Location>,
              skipOffstage: false,
            ),
          )
          .animationStyle,
      TreeAnimationStyle.disabled,
    );
  });

  testWidgets("M8 as a keyboard comes, the settings sheet scrolls its zone "
      "search field into view over standard, not at once", (tester) async {
    await pumpCalendar(tester);
    // Month, whose scaffold keeps its height under a keyboard.
    await pickMode(tester, "Month");
    await openSettings(tester);
    await tester.tap(find.byKey(manageZonesKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(zoneSearchKey));
    await tester.pump();
    final position = Scrollable.of(
      tester.element(find.byKey(zoneSearchKey)),
    ).position;
    final start = position.pixels;
    tester.view.viewInsets = const FakeViewPadding(bottom: 600.0);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    final seen = <double>[position.pixels];
    for (var elapsed = 0; elapsed < 640; elapsed += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(position.pixels);
    }
    final end = seen.last;
    // Setup sanity: the field's reveal scrolls the sheet.
    expect(end, greaterThan(start + 50.0));
    final between = seen.where((pixels) {
      return pixels > start + 1.0 && pixels < end - 1.0;
    });
    // Most of standard's 300 ms, frame by frame, lies between the two.
    expect(between.length, greaterThanOrEqualTo(12));
  });

  testWidgets("M9 a failed delete's snack bar from the item form comes in "
      "over 400 ms and leaves over 200 ms", (tester) async {
    final api = MockCalendarApi.seeded(today, latency: harnessLatency);
    await pumpCalendar(tester, editing: true, api: api, size: tall);
    await openBrainstorm(tester);
    api.failurePolicy = (request) {
      return request.method == CalendarMethod.delete
          ? "Deleting failed."
          : null;
    };
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    // Setup sanity: the failed delete shows its snack bar.
    expect(find.widgetWithText(SnackBar, "Deleting failed."), findsOneWidget);
    final controller = snackBarController(tester);
    expect(controller.duration, const Duration(milliseconds: 400));
    expect(controller.reverseDuration, const Duration(milliseconds: 200));
  });
}
