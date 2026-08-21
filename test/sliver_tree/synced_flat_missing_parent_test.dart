/// Widget-level pins for `.flat`'s missing-parent validation: a
/// `parentOf` result absent from `items` throws [ArgumentError] instead
/// of silently promoting the item to a root, on the first sync (which
/// runs in `initState`) and on a rebuild sync alike.
///
/// The normalizer-level pins live in
/// `synced_input_normalizer_validation_test.dart`; these two prove the
/// throw surfaces through the widget's actual sync entry points.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

class _Item {
  const _Item({required this.id, this.parentId});

  final String id;
  final String? parentId;
}

Widget _tree(List<_Item> items) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SyncedSliverTree<String, _Item>.flat(
            items: items,
            keyOf: (item) {
              return item.id;
            },
            parentOf: (item) {
              return item.parentId;
            },
            animationStyle: TreeAnimationStyle.disabled,
            itemBuilder: (context, node) {
              return SizedBox(height: 48, child: Text(node.item.id));
            },
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets("a dangling parent key throws on the first build", (
    tester,
  ) async {
    await tester.pumpWidget(
      _tree(const <_Item>[
        _Item(id: "orphaned", parentId: "not-in-items"),
        _Item(id: "a"),
      ]),
    );

    final exception = tester.takeException();
    expect(exception, isA<ArgumentError>());
    expect(
      (exception as ArgumentError).message,
      allOf(contains("orphaned"), contains("not-in-items")),
      reason: "the error must name both the child and the missing parent",
    );
  });

  testWidgets("a dangling parent key introduced by a rebuild throws too", (
    tester,
  ) async {
    await tester.pumpWidget(
      _tree(const <_Item>[
        _Item(id: "p"),
        _Item(id: "c", parentId: "p"),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: "setup sanity: the initial input is well-formed",
    );
    expect(find.text("c"), findsOneWidget);

    // The throw happens inside didUpdateWidget, so the framework aborts
    // Element.update mid-walk and its deactivation cascade reports a
    // SECOND exception, which takeException cannot absorb. Intercept
    // FlutterError.onError for the pump instead, assert on the FIRST
    // error (ours), and clear the broken subtree while still
    // intercepting so test teardown finds a clean tree. The cascade is
    // standard framework behavior for any lifecycle throw, not
    // something the package can suppress.
    final captured = <Object>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      captured.add(details.exception);
    };
    try {
      // A fresh collection instance (so the identity gate lets the sync
      // run) that drops "p" while "c" still names it.
      await tester.pumpWidget(
        _tree(const <_Item>[_Item(id: "c", parentId: "p")]),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      FlutterError.onError = previousOnError;
    }

    expect(captured, isNotEmpty, reason: "the rebuild sync must validate");
    expect(captured.first, isA<ArgumentError>());
    expect(
      (captured.first as ArgumentError).message,
      contains("{c: p}"),
      reason: "the error must name the child and its missing parent",
    );
  });
}
