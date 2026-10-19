/// [CalendarActivityIndicator]: its arc and colour, its turn on the theme's
/// motion, and what a frame of it builds, lays out and paints.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';

const Color red = Color(0xFFB0302A);

/// Counts its own layouts.
class _LayoutProbe extends SingleChildRenderObjectWidget {
  const _LayoutProbe({super.key, required super.child});

  @override
  _RenderLayoutProbe createRenderObject(BuildContext context) {
    return _RenderLayoutProbe();
  }
}

class _RenderLayoutProbe extends RenderProxyBox {
  int layouts = 0;

  @override
  void performLayout() {
    layouts++;
    super.performLayout();
  }
}

/// [child] at the top left of the view, under [theme] where given.
Widget host(Widget child, {CalendarThemeData? theme}) {
  final Widget placed = Directionality(
    textDirection: TextDirection.ltr,
    child: Align(alignment: Alignment.topLeft, child: child),
  );
  if (theme == null) {
    return placed;
  }
  return CalendarTheme(data: theme, child: placed);
}

final Finder indicator = find.byType(CalendarActivityIndicator);

/// The one arc the indicator paints: its rect, its angles and its paint.
({Rect rect, double start, double sweep, Paint paint}) arcOf(
  WidgetTester tester,
) {
  final paint = tester.renderObject<RenderCustomPaint>(
    find.descendant(of: indicator, matching: find.byType(CustomPaint)),
  );
  final canvas = TestRecordingCanvas();
  paint.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  final arcs = canvas.invocations.where((call) {
    return call.invocation.memberName == #drawArc;
  }).toList();
  expect(arcs, hasLength(1));
  final arguments = arcs.single.invocation.positionalArguments;
  return (
    rect: arguments[0] as Rect,
    start: arguments[1] as double,
    sweep: arguments[2] as double,
    paint: arguments[4] as Paint,
  );
}

/// Whether [node] lies below [ancestor] in the render tree.
bool isBelow(RenderObject node, RenderObject ancestor) {
  var current = node.parent;
  while (current != null) {
    if (identical(current, ancestor)) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

void main() {
  testWidgets("AI1 it paints three quarters of a turn in its colour, or the "
      "theme's primary, turning a quarter in 250 ms", (tester) async {
    await tester.pumpWidget(
      host(
        const CalendarActivityIndicator(
          size: 20.0,
          strokeWidth: 3.0,
          color: red,
        ),
      ),
    );
    expect(tester.getSize(indicator), const Size(20.0, 20.0));
    final given = arcOf(tester);
    expect(given.sweep, moreOrLessEquals(3.0 * math.pi / 2.0));
    expect(given.rect, const Rect.fromLTWH(1.5, 1.5, 17.0, 17.0));
    expect(given.paint.color, red);
    expect(given.paint.strokeWidth, 3.0);
    expect(given.paint.style, PaintingStyle.stroke);
    expect(given.paint.strokeCap, StrokeCap.round);

    const theme = CalendarThemeData(primary: Color(0xFF0B5A3A));
    await tester.pumpWidget(
      host(const CalendarActivityIndicator(), theme: theme),
    );
    expect(tester.getSize(indicator), const Size(36.0, 36.0));
    expect(
      tester.renderObject(
        find.descendant(of: indicator, matching: find.byType(CustomPaint)),
      ),
      paints..arc(
        sweepAngle: 3.0 * math.pi / 2.0,
        strokeWidth: 4.0,
        color: theme.primary,
      ),
    );
    await tester.pump();
    final before = arcOf(tester).start;
    await tester.pump(const Duration(milliseconds: 250));
    expect(arcOf(tester).start - before, moreOrLessEquals(math.pi / 2.0));
  });

  testWidgets("AI2 a frame paints only the indicator's own layer, and builds "
      "and lays out nothing", (tester) async {
    final probeKey = GlobalKey();
    await tester.pumpWidget(
      host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _LayoutProbe(
              key: probeKey,
              child: const CalendarActivityIndicator(),
            ),
            const SizedBox(
              width: 20.0,
              height: 20.0,
              child: ColoredBox(color: red),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final probe = tester.renderObject<_RenderLayoutProbe>(find.byKey(probeKey));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(of: indicator, matching: find.byType(RepaintBoundary)),
    );
    final arc = tester.renderObject<RenderCustomPaint>(
      find.descendant(of: indicator, matching: find.byType(CustomPaint)),
    );
    final sibling = tester.renderObject<RenderBox>(find.byType(ColoredBox));
    final top = tester.element(indicator);
    probe.layouts = 0;
    final rebuilt = <Element>[];
    final painted = <RenderObject>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      var under = identical(element, top);
      element.visitAncestorElements((ancestor) {
        under = under || identical(ancestor, top);
        return !under;
      });
      if (under) {
        rebuilt.add(element);
      }
    };
    debugOnProfilePaint = painted.add;
    try {
      for (var frame = 1; frame <= 10; frame++) {
        painted.clear();
        final angle = arcOf(tester).start;
        await tester.pump(const Duration(milliseconds: 16));
        expect(arcOf(tester).start, isNot(moreOrLessEquals(angle)));
        expect(
          painted.where((object) {
            return identical(object, arc);
          }),
          hasLength(1),
          reason: "frame $frame",
        );
        expect(painted, isNot(contains(sibling)), reason: "frame $frame");
        for (final object in painted) {
          expect(isBelow(object, boundary), isTrue, reason: "$object");
        }
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
      debugOnProfilePaint = null;
    }
    expect(rebuilt, isEmpty);
    expect(probe.layouts, 0);
  });

  testWidgets("AI3 under zero motion it stands at the top and schedules no "
      "frame, and turns once motion is positive", (tester) async {
    const still = CalendarThemeData(motionDuration: Duration.zero);
    const moving = CalendarThemeData(motionDuration: Duration(seconds: 2));
    await tester.pumpWidget(
      host(const CalendarActivityIndicator(), theme: still),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(arcOf(tester).start, -math.pi / 2.0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(
      host(const CalendarActivityIndicator(), theme: moving),
    );
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(arcOf(tester).start, isNot(moreOrLessEquals(-math.pi / 2.0)));

    await tester.pumpWidget(
      host(const CalendarActivityIndicator(), theme: still),
    );
    await tester.pump();
    expect(arcOf(tester).start, -math.pi / 2.0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets("AI4 a spinning indicator removed raises nothing", (
    tester,
  ) async {
    await tester.pumpWidget(host(const CalendarActivityIndicator()));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(host(const SizedBox()));
    expect(tester.takeException(), isNull);
    expect(indicator, findsNothing);
  });
}
