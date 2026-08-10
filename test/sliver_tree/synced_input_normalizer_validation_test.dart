/// The input normalizers are the ONLY validation layer between caller
/// data and controller state: there is no second sweep behind them in any
/// build mode. So each malformed shape below must throw [ArgumentError]
/// from the normalizer itself.
///
/// `normalizeHierarchy`'s walk establishes its invariants on the way
/// past (cycles, key uniqueness, sibling uniqueness, reachability by
/// construction). `normalizeFlat`'s two-pass build cannot establish
/// reachability by construction, so it runs an explicit mark-from-roots
/// walk; the mutual-cycle case below is the first executable pin of that
/// behavior (its predecessor, `TreeSnapshot._validate`, was only ever
/// exercised for it implicitly).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/_synced_input_normalizer.dart';
import 'package:widgets_extended/sliver_tree/types.dart';

class _N {
  _N(this.id, [this.kids = const []]);
  final String id;
  final List<_N> kids;
}

NormalizedTreeInput<String, _N> _build(List<_N> roots) {
  return normalizeHierarchy<String, _N>(
    roots: roots,
    keyOf: (n) => n.id,
    childrenOf: (n) => n.kids,
  );
}

List<K> _keys<K, V>(Iterable<TreeNode<K, V>> nodes) {
  return <K>[for (final node in nodes) node.key];
}

void main() {
  group("normalizeHierarchy", () {
    test("rejects a duplicated root key", () {
      expect(() => _build([_N("a"), _N("a")]), throwsA(isA<ArgumentError>()));
    });

    test("rejects a child that is also a root", () {
      final shared = _N("dup");
      expect(
        () => _build([
          _N("r", [shared]),
          _N("dup"),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test("rejects the same child under two parents", () {
      final shared = _N("shared");
      expect(
        () => _build([
          _N("p1", [shared]),
          _N("p2", [shared]),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test("rejects a duplicated sibling under one parent", () {
      expect(
        () => _build([
          _N("p", [_N("c"), _N("c")]),
        ]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test("rejects a cycle", () {
      // `childrenOf` is asked per node, so a self-referential structure is
      // built by hand rather than by _N's constructor.
      expect(
        () => normalizeHierarchy<String, String>(
          roots: const ["a"],
          keyOf: (n) => n,
          childrenOf: (n) {
            return switch (n) {
              "a" => const ["b"],
              "b" => const ["a"],
              _ => const <String>[],
            };
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test("accepts a well-formed hierarchy and preserves order and data", () {
      final normalized = _build([
        _N("r0", [
          _N("r0c0"),
          _N("r0c1", [_N("r0c1g")]),
        ]),
        _N("r1"),
      ]);

      expect(_keys(normalized.roots), equals(["r0", "r1"]));
      expect(
        _keys(normalized.childrenByParent["r0"]!),
        equals(["r0c0", "r0c1"]),
      );
      expect(_keys(normalized.childrenByParent["r0c1"]!), equals(["r0c1g"]));
      // Leaves get no entry.
      expect(normalized.childrenByParent.containsKey("r1"), isFalse);
      // The payload rides each TreeNode.
      expect(normalized.roots.first.data.id, equals("r0"));
      expect(normalized.childrenByParent["r0"]!.first.data.id, equals("r0c0"));
    });

    test("accepts an empty hierarchy", () {
      final normalized = _build(const []);
      expect(normalized.roots, isEmpty);
      expect(normalized.childrenByParent, isEmpty);
    });
  });

  group("normalizeFlat", () {
    test("rejects a duplicated key", () {
      expect(
        () => normalizeFlat<String, String>(
          items: const ["a", "a"],
          keyOf: (item) => item,
          parentOf: (item) => null,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test("rejects a mutual parent cycle as unreachable", () {
      // "a" claims "b" as parent while "b" claims "a": both are present
      // in items, so neither is treated as a root, and no path from any
      // root reaches them. Without the reachability walk they would
      // silently never render.
      expect(
        () => normalizeFlat<String, String>(
          items: const ["a", "b", "r"],
          keyOf: (item) => item,
          parentOf: (item) {
            return switch (item) {
              "a" => "b",
              "b" => "a",
              _ => null,
            };
          },
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            "message",
            contains("unreachable"),
          ),
        ),
      );
    });

    test("accepts a well-formed flat list and preserves data", () {
      final normalized = normalizeFlat<String, String>(
        items: const ["r", "c"],
        keyOf: (item) => item,
        parentOf: (item) => item == "c" ? "r" : null,
      );
      expect(_keys(normalized.roots), equals(["r"]));
      expect(_keys(normalized.childrenByParent["r"]!), equals(["c"]));
      expect(normalized.roots.single.data, equals("r"));
    });
  });
}
