/// Tests for item 7L of the board audit fixes: the README's board quick
/// start compiles, builds, and does what its prose says.
///
/// Source: `plans/2026-09-23-board-audit-fixes-plan.md`, "Item 7L". The
/// classes below are the README's `## Board` quick start verbatim, so a
/// change to either should change both.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

// ---------------------------------------------------------------- README

class Task {
  const Task(this.id, this.title);
  final String id;
  final String title;
}

class Planner extends StatefulWidget {
  const Planner({super.key});

  @override
  State<Planner> createState() => _PlannerState();
}

class _PlannerState extends State<Planner> with TickerProviderStateMixin {
  late final controller = BoardController<String, Task>(
    vsync: this,
    rows: BoardAxisConfig(axis: UniformAxis(24, 48)), // hours
    columns: BoardAxisConfig(axis: UniformAxis(7, 120), laneExtent: 40), // days
    keyOf: (task) => task.id,
  );

  @override
  void initState() {
    super.initState();
    controller.addItem(
      const Task("standup", "Standup"),
      const BoardSpan(rowStart: 9, colStart: 1),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Board<String, Task>(
      controller: controller,
      cellBuilder: (context, cell) => const DecoratedBox(
        decoration: BoxDecoration(
          border: Border.fromBorderSide(BorderSide(color: Colors.black12)),
        ),
      ),
      itemBuilder: (context, view) => Card(child: Text(view.item.title)),
      drag: BoardDragConfig<String>(
        onItemMoved: (key, span) => controller.moveItem(key, span),
        onItemResized: (key, span) => controller.resizeItem(key, span),
        primaryResizeEdges: BoardResizeEdges.both,
      ),
      selection: BoardSelectionConfig(onChanged: (selection) {}),
    );
  }
}

// ------------------------------------------------------------ the check

void main() {
  testWidgets("the README's board quick start builds and moves its item",
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Planner())),
    );
    await tester.pumpAndSettle();
    final controller = tester.state<_PlannerState>(find.byType(Planner))
        .controller;
    // It builds, and shows the item.
    expect(find.text("Standup"), findsOneWidget);
    expect(
      controller.spanOf("standup"),
      const BoardSpan(rowStart: 9, colStart: 1),
    );

    // A long press lifts it; a day to the right drops it on the next day.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text("Standup")),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(120.0, 0.0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      controller.spanOf("standup"),
      const BoardSpan(rowStart: 9, colStart: 2),
    );
  });
}
