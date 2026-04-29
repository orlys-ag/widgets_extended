import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("remove + insert + remove during exit animations stays consistent",
      (tester) async {
    final controller = SectionedListController<String, String, String, String>(
      vsync: tester,
      animationDuration: const Duration(milliseconds: 300),
      animationCurve: Curves.easeInOut,
    );
    addTearDown(controller.dispose);

    // Seed: one section with 6 items.
    controller.setSections(
      [
        SectionInput<String, String, String, String>(
          key: "a",
          section: "A",
          items: [
            for (var i = 0; i < 6; i++)
              ItemInput<String, String>(key: "a_$i", item: "Item $i"),
          ],
        ),
      ],
      animate: false,
    );

    // Render so the visible-order buffer is populated.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          SectionedSliverList<String, String, String, String>(
            controller: controller,
            sections: [
              SectionInput<String, String, String, String>(
                key: "a",
                section: "A",
                items: [
                  for (var i = 0; i < 6; i++)
                    ItemInput<String, String>(key: "a_$i", item: "Item $i"),
                ],
              ),
            ],
            headerBuilder: (ctx, v) => Text(v.section),
            itemBuilder: (ctx, v) => Text(v.item),
          ),
        ]),
      ),
    ));
    await tester.pump();

    // Mirror the example's "Random remove + add" rapid taps with random
    // pick. Multiple batches fire while prior exit animations are still
    // in flight (item is still in _pendingDeletion + _order).
    final random = math.Random(42);
    var nextId = 100;
    for (var cycle = 0; cycle < 100; cycle++) {
      final items = controller.itemsOf("a");
      if (items.isNotEmpty) {
        final pick = items[random.nextInt(items.length)];
        controller.runBatch(() {
          controller.removeItem(pick);
          controller.addItem(
            "a",
            ItemInput<String, String>(
              key: "a_${nextId++}",
              item: "Item $nextId",
            ),
          );
        });
      }
      // Pump one frame between batches to mimic real user taps (which
      // can't be faster than the frame rate but ARE faster than
      // animation completion).
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.pumpAndSettle();
  });
}
