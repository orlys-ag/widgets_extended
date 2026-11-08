/// The scroll physics a board installs outermost around each axis's
/// physics: it answers every member as the physics it wraps, it is the
/// outermost physics of a board's scroll positions, and the board keeps
/// it, and so each position, for its life.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_scroll_physics.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';
import 'package:widgets_extended/board/render_board_viewport.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

/// A gate that wraps on every axis.
class _Gate implements BoardSpringGate {
  @override
  bool wrapsSpringsOn(Axis axis) {
    return true;
  }
}

const Duration _frame = Duration(milliseconds: 16);

/// A new controller on forty content-sized rows, which carry 18 px lanes
/// under a 4 px padding, over seven 40 px columns, with `a` and `d` laned
/// in row 39, mounted on a board of 10 px cells in a 280 x 300 frame and
/// settled. The rows end at 430, so the vertical range ends at 130.
Future<(BoardController<String, _Item>, RenderBoardViewport<String>)> _board(
  WidgetTester tester, {
  ScrollableDetails verticalDetails = const ScrollableDetails.vertical(),
}) async {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(
      axis: LazyContentAxis(40, 80.0),
      laneExtent: 18.0,
      lanePadding: 4.0,
    ),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: BoardAnimationStyle.disabled,
  );
  addTearDown(controller.dispose);
  controller.addItem(
    const _Item("a"),
    const BoardSpan(rowStart: 39, colStart: 0, colSpan: 4),
  );
  controller.addItem(
    const _Item("d"),
    const BoardSpan(rowStart: 39, colStart: 0, colSpan: 5),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 280.0,
            height: 300.0,
            child: Board<String, _Item>(
              controller: controller,
              verticalDetails: verticalDetails,
              cellBuilder: (context, view) {
                return const SizedBox(width: 40.0, height: 10.0);
              },
              itemBuilder: (context, item) {
                return const ColoredBox(color: Color(0xFF4CAF50));
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(_frame);
  final viewport = tester.allRenderObjects
      .whereType<RenderBoardViewport<String>>()
      .single;
  return (controller, viewport);
}

/// The runtime types of [physics] and of each of its parents, outermost
/// first.
List<Type> _chainOf(ScrollPhysics? physics) {
  final types = <Type>[];
  for (var link = physics; link != null; link = link.parent) {
    types.add(link.runtimeType);
  }
  return types;
}

void main() {
  testWidgets(
    "the board's scroll physics answers every member as the physics it "
    "wraps",
    (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (built) {
            context = built;
            return const SizedBox.shrink();
          },
        ),
      );
      final wrapped = <ScrollPhysics>[
        const ClampingScrollPhysics(parent: RangeMaintainingScrollPhysics()),
        const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics()),
        const NeverScrollableScrollPhysics(),
        const PageScrollPhysics(),
      ];
      for (final inner in wrapped) {
        final name = inner.runtimeType.toString();
        final record = BoardSpringRecord(Axis.vertical);
        final physics = BoardScrollPhysics(record: record).applyTo(inner);
        expect(identical(physics.record, record), isTrue, reason: name);
        expect(_chainOf(physics.parent), _chainOf(inner), reason: name);
        expect(
          physics.allowUserScrolling,
          inner.allowUserScrolling,
          reason: name,
        );
        expect(
          physics.allowImplicitScrolling,
          inner.allowImplicitScrolling,
          reason: name,
        );
        expect(physics.minFlingDistance, inner.minFlingDistance, reason: name);
        expect(physics.minFlingVelocity, inner.minFlingVelocity, reason: name);
        expect(physics.maxFlingVelocity, inner.maxFlingVelocity, reason: name);
        expect(
          physics.carriedMomentum(500.0),
          inner.carriedMomentum(500.0),
          reason: name,
        );
        expect(
          physics.dragStartDistanceMotionThreshold,
          inner.dragStartDistanceMotionThreshold,
          reason: name,
        );
        expect(physics.spring.mass, inner.spring.mass, reason: name);
        expect(physics.spring.stiffness, inner.spring.stiffness, reason: name);
        expect(physics.spring.damping, inner.spring.damping, reason: name);
        // ignore: deprecated_member_use
        final tolerance = physics.tolerance;
        // ignore: deprecated_member_use
        final innerTolerance = inner.tolerance;
        expect(tolerance.distance, innerTolerance.distance, reason: name);
        expect(tolerance.time, innerTolerance.time, reason: name);
        expect(tolerance.velocity, innerTolerance.velocity, reason: name);
        for (final pixels in <double>[50.0, 130.0]) {
          final at = "$name at $pixels";
          final metrics = FixedScrollMetrics(
            minScrollExtent: 0.0,
            maxScrollExtent: 112.0,
            pixels: pixels,
            viewportDimension: 300.0,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1.0,
          );
          expect(
            physics.applyPhysicsToUserOffset(metrics, pixels + 10.0),
            inner.applyPhysicsToUserOffset(metrics, pixels + 10.0),
            reason: at,
          );
          expect(
            physics.shouldAcceptUserOffset(metrics),
            inner.shouldAcceptUserOffset(metrics),
            reason: at,
          );
          expect(
            physics.recommendDeferredLoading(5000.0, metrics, context),
            inner.recommendDeferredLoading(5000.0, metrics, context),
            reason: at,
          );
          expect(
            physics.applyBoundaryConditions(metrics, pixels + 10.0),
            inner.applyBoundaryConditions(metrics, pixels + 10.0),
            reason: at,
          );
          final shrunk = metrics.copyWith(maxScrollExtent: 100.0);
          expect(
            physics.adjustPositionForNewDimensions(
              oldPosition: metrics,
              newPosition: shrunk,
              isScrolling: false,
              velocity: 0.0,
            ),
            inner.adjustPositionForNewDimensions(
              oldPosition: metrics,
              newPosition: shrunk,
              isScrolling: false,
              velocity: 0.0,
            ),
            reason: at,
          );
          final toleranceAt = physics.toleranceFor(metrics);
          final innerToleranceAt = inner.toleranceFor(metrics);
          expect(toleranceAt.distance, innerToleranceAt.distance, reason: at);
          expect(toleranceAt.time, innerToleranceAt.time, reason: at);
          expect(toleranceAt.velocity, innerToleranceAt.velocity, reason: at);
          for (final velocity in <double>[0.0, 2000.0]) {
            expect(
              physics.createBallisticSimulation(metrics, velocity)?.runtimeType,
              inner.createBallisticSimulation(metrics, velocity)?.runtimeType,
              reason: "$at, velocity $velocity",
            );
          }
        }
        expect(record.simulation, 0, reason: name);
        record.gate = _Gate();
        for (final pixels in <double>[50.0, 130.0]) {
          final metrics = FixedScrollMetrics(
            minScrollExtent: 0.0,
            maxScrollExtent: 112.0,
            pixels: pixels,
            viewportDimension: 300.0,
            axisDirection: AxisDirection.down,
            devicePixelRatio: 1.0,
          );
          for (final velocity in <double>[0.0, 2000.0]) {
            final label = "$name at $pixels, velocity $velocity";
            final recorded = physics.createBallisticSimulation(
              metrics,
              velocity,
            );
            final reference = inner.createBallisticSimulation(
              metrics,
              velocity,
            );
            if (reference == null) {
              expect(recorded, isNull, reason: label);
              continue;
            }
            expect(recorded, isNotNull, reason: label);
            expect(
              recorded!.tolerance.distance,
              reference.tolerance.distance,
              reason: label,
            );
            expect(
              recorded.tolerance.time,
              reference.tolerance.time,
              reason: label,
            );
            expect(
              recorded.tolerance.velocity,
              reference.tolerance.velocity,
              reason: label,
            );
            expect(record.start, pixels, reason: label);
            double? lastRead;
            for (final time in <double>[0.0, 0.016, 0.1, 0.5, 2.0, 10.0]) {
              final read = recorded.x(time);
              lastRead = read;
              expect(read, reference.x(time), reason: "$label, t $time");
              expect(
                recorded.dx(time),
                reference.dx(time),
                reason: "$label, t $time",
              );
              expect(
                recorded.isDone(time),
                reference.isDone(time),
                reason: "$label, t $time",
              );
            }
            expect(record.last, lastRead, reason: label);
          }
        }
      }
    },
  );

  testWidgets(
    "a board's scroll positions report the board's physics outermost around "
    "the physics they would have without it",
    (tester) async {
      for (final bouncing in <bool>[false, true]) {
        final (_, viewport) = await _board(
          tester,
          verticalDetails: bouncing
              ? const ScrollableDetails.vertical(
                  physics: BouncingScrollPhysics(),
                )
              : const ScrollableDetails.vertical(),
        );
        final context = tester.element(find.byType(Board<String, _Item>));
        final configured = ScrollConfiguration.of(
          context,
        ).getScrollPhysics(context);
        final vertical = viewport.verticalPosition!.physics;
        final horizontal = viewport.horizontalPosition!.physics;
        expect(vertical, isA<BoardScrollPhysics>(), reason: "$bouncing");
        expect(horizontal, isA<BoardScrollPhysics>(), reason: "$bouncing");
        expect(
          _chainOf(vertical.parent),
          _chainOf(
            bouncing
                ? const BouncingScrollPhysics().applyTo(configured)
                : configured,
          ),
          reason: "$bouncing",
        );
        expect(
          _chainOf(horizontal.parent),
          _chainOf(configured),
          reason: "$bouncing",
        );
      }
    },
  );

  testWidgets(
    "a board keeps each scroll position through a preview's start and end "
    "and an equal details rebuild",
    (tester) async {
      final (controller, viewport) = await _board(tester);
      final position = viewport.verticalPosition!;
      final epoch = controller.beginOwnMakeRoomPreview();
      controller.previewMakeRoomGap(
        draggedKey: "d",
        prospective: const BoardSpan(
          rowStart: 36,
          colStart: 0,
          rowSpan: 4,
          colSpan: 5,
        ),
      );
      await tester.pump();
      expect(identical(viewport.verticalPosition, position), isTrue);
      controller.endOwnMakeRoomPreview(epoch);
      controller.releaseMakeRoomPreview();
      await tester.pump();
      expect(identical(viewport.verticalPosition, position), isTrue);
      final (_, rebuilt) = await _board(
        tester,
        // ignore: prefer_const_constructors
        verticalDetails: ScrollableDetails.vertical(),
      );
      expect(identical(rebuilt, viewport), isTrue);
      expect(identical(rebuilt.verticalPosition, position), isTrue);
    },
  );
}
