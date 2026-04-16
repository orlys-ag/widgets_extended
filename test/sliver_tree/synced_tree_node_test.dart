import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

void main() {
  group('SyncedTreeNode', () {
    test('defaults children to an empty list for leaves', () {
      final node = SyncedTreeNode<String, String>(key: 'leaf', data: 'Leaf');

      expect(node.children, isEmpty);
    });

    test('freezes children as an unmodifiable list', () {
      final node = SyncedTreeNode<String, String>(
        key: 'root',
        data: 'Root',
        children: <SyncedTreeNode<String, String>>[
          SyncedTreeNode<String, String>(key: 'child', data: 'Child'),
        ],
      );

      expect(node.children, hasLength(1));
      expect(
        () => node.children.add(
          SyncedTreeNode<String, String>(key: 'other', data: 'Other'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
