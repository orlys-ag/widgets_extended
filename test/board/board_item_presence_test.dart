/// Tests for item 7Q of the board audit fixes: an item builder is handed
/// the item's enter/exit ramp as an `Animation<double>`,
/// `BoardItemView.presence`.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7Q", the
/// Tests list. Case numbers in the comments are that list's.
///
/// The field is new, so no case compiled on the tree item 7P left; each
/// TARGET was shown red by the mutation the plan's checklist names for
/// it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/board/_board_axis.dart';
import 'package:widgets_extended/board/_board_span.dart';
import 'package:widgets_extended/board/board_animation_style.dart';
import 'package:widgets_extended/board/board_controller.dart';
import 'package:widgets_extended/board/board_widget.dart';

class _Item {
  const _Item(this.key);

  final String key;
}

const BoardAnimationSpec _spec = BoardAnimationSpec(
  duration: Duration(milliseconds: 100),
  curve: Curves.linear,
);

/// itemEnterExit inherits trackResize: 100 ms, linear.
const BoardAnimationStyle _live = BoardAnimationStyle(
  trackResize: _spec,
  itemSlide: _spec,
);

Key _itemKey(String key) {
  return ValueKey<String>("i$key");
}

BoardController<String, _Item> _controller(
  WidgetTester tester, {
  BoardAnimationStyle style = _live,
}) {
  final controller = BoardController<String, _Item>(
    vsync: tester,
    rows: BoardAxisConfig(axis: UniformAxis(6, 50.0)),
    columns: BoardAxisConfig(axis: UniformAxis(7, 40.0)),
    keyOf: (item) {
      return item.key;
    },
    animationStyle: style,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Unmounts the board before the controller's own tear-down disposes it.
void _unmountFirst(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Every presence each key's builds were handed, in build order.
typedef _Seen = Map<String, List<Animation<double>>>;

Widget _board(
  BoardController<String, _Item> controller,
  _Seen seen, {
  bool fade = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280.0,
          height: 300.0,
          child: Board<String, _Item>(
            controller: controller,
            cellBuilder: (context, cell) {
              return null;
            },
            itemBuilder: (context, view) {
              (seen[view.key] ??= <Animation<double>>[]).add(view.presence);
              final box = ColoredBox(
                key: _itemKey(view.key),
                color: const Color(0xFF4CAF50),
              );
              if (!fade) {
                return box;
              }
              return FadeTransition(opacity: view.presence, child: box);
            },
          ),
        ),
      ),
    ),
  );
}

/// The listener log of one presence: how many value notifications, and
/// every status notified, in order.
class _Log {
  _Log(Animation<double> presence) {
    presence.addListener(() {
      values++;
    });
    presence.addStatusListener(statuses.add);
  }

  int values = 0;
  final List<AnimationStatus> statuses = <AnimationStatus>[];
}

const BoardSpan _spanA = BoardSpan(rowStart: 1, colStart: 1, colSpan: 2);

void main() {
  // Test 1.
  testWidgets("an entering item's presence rises to 1 and completes",
      (tester) async {
    final controller = _controller(tester);
    final seen = <String, List<Animation<double>>>{};
    _unmountFirst(tester);
    await tester.pumpWidget(_board(controller, seen));
    controller.addItem(const _Item("a"), _spanA);
    await tester.pump();
    // Setup sanity: built once (`single`), at the ramp's start.
    final presence = seen["a"]!.single;
    expect(presence.status, AnimationStatus.forward);
    expect(presence.value, 0.0);
    final log = _Log(presence);

    await tester.pump(const Duration(milliseconds: 50));
    // TARGET: half way, and the listeners heard it.
    expect(presence.value, closeTo(0.5, 0.01));
    expect(log.values, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 60));
    // TARGET: at rest.
    expect(presence.value, 1.0);
    expect(log.statuses, <AnimationStatus>[AnimationStatus.completed]);
  });

  // Test 2.
  testWidgets("a leaving item's presence falls to 0 and is dismissed",
      (tester) async {
    final controller = _controller(tester);
    final seen = <String, List<Animation<double>>>{};
    _unmountFirst(tester);
    controller.addItem(const _Item("a"), _spanA);
    await tester.pumpWidget(_board(controller, seen));
    await tester.pumpAndSettle();
    final presence = seen["a"]!.last;
    // Setup sanity: at rest.
    expect(presence.status, AnimationStatus.completed);
    expect(presence.value, 1.0);
    final log = _Log(presence);

    controller.removeItem("a");
    await tester.idle();
    // TARGET: the status is heard before any frame runs the ramp.
    expect(log.statuses, <AnimationStatus>[AnimationStatus.reverse]);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Setup sanity: still mounted, half way out.
    expect(find.byKey(_itemKey("a")), findsOneWidget);
    expect(presence.value, closeTo(0.5, 0.01));

    await tester.pumpAndSettle();
    // Setup sanity: the exit has run out.
    expect(find.byKey(_itemKey("a")), findsNothing);
    // TARGET: dismissed.
    expect(presence.value, 0.0);
    expect(log.statuses, <AnimationStatus>[
      AnimationStatus.reverse,
      AnimationStatus.dismissed,
    ]);
  });

  // Test 3. The removal finalizes the enter and then installs the exit;
  // listeners hear the end state only.
  testWidgets("a removal mid-enter reports reverse and never completed",
      (tester) async {
    final controller = _controller(tester);
    final seen = <String, List<Animation<double>>>{};
    _unmountFirst(tester);
    await tester.pumpWidget(_board(controller, seen));
    controller.addItem(const _Item("a"), _spanA);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final presence = seen["a"]!.last;
    // Setup sanity: mid-enter.
    expect(presence.status, AnimationStatus.forward);
    expect(presence.value, closeTo(0.5, 0.01));
    final log = _Log(presence);

    controller.removeItem("a");
    await tester.pump();
    // TARGET.
    expect(log.statuses, <AnimationStatus>[AnimationStatus.reverse]);
    expect(presence.value, closeTo(0.5, 0.01));
    await tester.pumpAndSettle();
  });

  // Test 4.
  testWidgets("every build of one item hands the same presence",
      (tester) async {
    final controller = _controller(tester);
    final seen = <String, List<Animation<double>>>{};
    _unmountFirst(tester);
    controller.addItem(const _Item("a"), _spanA);
    await tester.pumpWidget(_board(controller, seen));
    await tester.pumpAndSettle();
    final builds = seen["a"]!.length;

    // A structural change elsewhere rebuilds the delegate, and with it
    // every item built.
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 3, colStart: 4),
    );
    await tester.pump();
    // Setup sanity: "a" was built again.
    expect(seen["a"]!.length, greaterThan(builds));
    // TARGET.
    expect(identical(seen["a"]!.last, seen["a"]!.first), isTrue);
    await tester.pumpAndSettle();
  });

  // Test 5. Ids are recycled off a LIFO free list; the old incarnation's
  // presence must not follow the new one.
  testWidgets("a released id's presence does not follow its next occupant",
      (tester) async {
    final controller = _controller(tester, style: BoardAnimationStyle.disabled);
    final seen = <String, List<Animation<double>>>{};
    _unmountFirst(tester);
    controller.addItem(const _Item("a"), _spanA);
    await tester.pumpWidget(_board(controller, seen));
    final presence = seen["a"]!.last;
    final id = controller.idOfKey("a");
    final log = _Log(presence);

    controller.removeItem("a");
    controller.addItem(
      const _Item("b"),
      const BoardSpan(rowStart: 3, colStart: 4),
    );
    await tester.pump();
    // Setup sanity: "b" holds the id "a" held, and was built.
    expect(controller.idOfKey("b"), id);
    expect(seen["b"], isNotNull);
    // TARGET: "a"'s presence is over; "b" has its own.
    expect(presence.value, 0.0);
    expect(presence.status, AnimationStatus.dismissed);
    expect(log.statuses, <AnimationStatus>[AnimationStatus.dismissed]);
    expect(identical(seen["b"]!.last, presence), isFalse);
  });

  // Test 6. Read before any frame, through the accessor the view is
  // built from: a frame's tick would settle a zero-duration ramp before
  // the build, so a build alone cannot tell "never ramped" from "ramped
  // and settled".
  testWidgets("under a zero itemEnterExit family the presence is 1 and "
      "completed from the add", (tester) async {
    final controller = _controller(tester, style: BoardAnimationStyle.disabled);
    final seen = <String, List<Animation<double>>>{};
    _unmountFirst(tester);
    await tester.pumpWidget(_board(controller, seen));
    controller.addItem(const _Item("a"), _spanA);
    final presence = controller.presenceOfId(controller.idOfKey("a"));
    // TARGET.
    expect(presence.value, 1.0);
    expect(presence.status, AnimationStatus.completed);
    await tester.pump();
    // TARGET: and the builder was handed that one.
    expect(identical(seen["a"]!.single, presence), isTrue);
  });

  // Test 7. Item 7D's reversal: the same incarnation, turned around.
  testWidgets("re-adding a key mid-exit turns its presence forward from "
      "where it reached", (tester) async {
    final controller = _controller(tester);
    final seen = <String, List<Animation<double>>>{};
    _unmountFirst(tester);
    controller.addItem(const _Item("a"), _spanA);
    await tester.pumpWidget(_board(controller, seen));
    await tester.pumpAndSettle();
    final presence = seen["a"]!.last;
    controller.removeItem("a");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Setup sanity: half way out.
    expect(presence.status, AnimationStatus.reverse);
    expect(presence.value, closeTo(0.5, 0.01));
    final log = _Log(presence);

    controller.addItem(const _Item("a"), _spanA);
    await tester.idle();
    // TARGET: turned, heard before any frame, from where it was.
    expect(log.statuses, <AnimationStatus>[AnimationStatus.forward]);
    expect(presence.value, closeTo(0.5, 0.01));

    await tester.pump();
    await tester.pumpAndSettle();
    // TARGET: the same presence, at rest.
    expect(identical(seen["a"]!.last, presence), isTrue);
    expect(log.statuses, <AnimationStatus>[
      AnimationStatus.forward,
      AnimationStatus.completed,
    ]);
    expect(presence.value, 1.0);
  });

  // Test 8. What the field is for: a FadeTransition on it paints the
  // item at the ramp's opacity.
  testWidgets("a FadeTransition on the presence fades the item in",
      (tester) async {
    final controller = _controller(tester);
    final seen = <String, List<Animation<double>>>{};
    _unmountFirst(tester);
    await tester.pumpWidget(_board(controller, seen, fade: true));
    controller.addItem(const _Item("a"), _spanA);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Setup sanity: mounted, half way in.
    expect(find.byKey(_itemKey("a")), findsOneWidget);
    expect(seen["a"]!.last.value, closeTo(0.5, 0.01));
    // The route has FadeTransitions of its own; this is the item's.
    final fade = tester.renderObject<RenderAnimatedOpacity>(
      find.byWidgetPredicate((widget) {
        return widget is FadeTransition &&
            identical(widget.opacity, seen["a"]!.last);
      }),
    );
    // TARGET: painted at half opacity.
    expect((fade.debugLayer! as OpacityLayer).alpha, closeTo(128, 2));
    await tester.pumpAndSettle();
  });
}
