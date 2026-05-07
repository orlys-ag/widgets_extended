import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  testWidgets("remove + insert + remove during exit animations stays "
      "consistent", (tester) async {
    final controller = SectionedListController<String, String, String>(
      vsync: tester,
      sectionKeyOf: (s) => s,
      itemKeyOf: (i) => i,
      animationDuration: const Duration(milliseconds: 300),
      animationCurve: Curves.easeInOut,
    );
    addTearDown(controller.dispose);

    controller.addSection(
      "a",
      items: [for (var i = 0; i < 6; i++) "a_$i"],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(slivers: [
            SectionedSliverList<String, String, String>.controlled(
              controller: controller,
              headerBuilder: (ctx, v) => Text(v.section),
              itemBuilder: (ctx, v) => Text(v.item),
            ),
          ]),
        ),
      ),
    );
    await tester.pump();

    final random = math.Random(42);
    var nextId = 100;
    for (var cycle = 0; cycle < 100; cycle++) {
      final items = controller.itemKeysOf("a");
      if (items.isNotEmpty) {
        final pick = items[random.nextInt(items.length)];
        controller.runBatch(() {
          controller.removeItem(pick);
          controller.addItem("a_${nextId++}", toSection: "a");
        });
      }
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.pumpAndSettle();
  });
}
