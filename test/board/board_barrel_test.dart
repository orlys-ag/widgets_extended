/// Tests for the board Testing Plan.
///
/// Source: `plans/2026-08-29-board-view-plan.md`, the Testing Plan section
/// (anchor `testing-plan`). Case names are the plan's names VERBATIM unless
/// a comment marks the name DERIVED, which means the plan describes the case
/// in prose and quotes no name for it.
///
/// Landed at Landing Order step 13 with the barrel.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  // DERIVED name. No AC.
  // Asserts: every name the plan marks exported is nameable through
  // package:widgets_extended/widgets_extended.dart. The compile of the
  // references below IS the check; the length assertion keeps the list
  // from silently losing an entry.
  test(
    "every name the plan marks exported is nameable through the barrel",
    () {
      const types = <Type>[
        BoardAxis,
        BoardAxisConfig,
        UniformAxis,
        ExplicitAxis,
        DerivedAxis,
        LazyContentAxis,
        TrackAlignment,
        BoardSpan,
        BoardPlacement,
        BoardController,
        BoardAnimationSpec,
        BoardAnimationStyle,
        BoardAnimationFamily,
        BoardAnimationReader,
        BoardRenderPort,
        RenderBoardViewport,
        BoardBackgroundPainter,
        BoardGridPainter,
        BoardGeometryView,
        Board,
        BoardCellView,
        BoardItemView,
        BoardDragConfig,
        BoardDropFit,
        BoardSelectionConfig,
        BoardDragHandle,
        BoardDelayedDragHandle,
        BoardItemDragScope,
        BoardSnap,
        BoardSnapMode,
        BoardSelectionMode,
        BoardResizeEdges,
        BoardSelection,
        BoardDragController,
        BoardDropTarget,
        BoardDragKind,
      ];
      expect(types, hasLength(36));
      // The three typedefs are not type literals; a nullable declaration
      // per name is the compile-level reference.
      BoardCellBuilder<String, Object?>? cellBuilder;
      BoardItemBuilder<String, Object?>? itemBuilder;
      BoardSemanticsActionsBuilder<String>? semanticsBuilder;
      expect(cellBuilder, isNull);
      expect(itemBuilder, isNull);
      expect(semanticsBuilder, isNull);
    },
  );

  // DERIVED name. No AC.
  // Asserts: no internal name is nameable through the package barrel. A
  // negative compile cannot be a passing test, so the check is on the
  // barrel FILE: every export carries a show clause, the union of shown
  // names is exactly the exported list above, and the package barrel
  // re-exports the module barrel.
  test("no internal name is nameable through the barrel", () {
    final barrel = File("lib/board/board.dart").readAsStringSync();
    final shows = RegExp(
      "export '[^']+'\\s+show\\s+([^;]+);",
    ).allMatches(barrel);
    final bareExports = RegExp(
      "export '[^']+';",
    ).allMatches(barrel);
    expect(bareExports, isEmpty);
    // EVERY export statement must be a single-quoted, unconditional
    // show: a bare export, a hide, a double-quoted uri, or a
    // configuration-specific export would each widen the surface past
    // the show-clause union inspected below.
    final statements = barrel
        .split(";")
        .where(
          (statement) =>
              RegExp(r"(^|\n)\s*export\s").hasMatch(statement),
        )
        .toList();
    for (final statement in statements) {
      expect(RegExp(r"\bshow\b").hasMatch(statement), isTrue);
      expect(RegExp(r"\bhide\b").hasMatch(statement), isFalse);
      expect(statement, isNot(contains('"')));
      expect(RegExp(r"\bif\s*\(").hasMatch(statement), isFalse);
    }
    expect(statements, hasLength(shows.length));
    final shown = <String>{};
    for (final match in shows) {
      for (final name in match.group(1)!.split(",")) {
        shown.add(name.trim());
      }
    }
    expect(shown, hasLength(39));
    const internals = <String>{
      "BoardStore",
      "SpanIndex",
      "OverlapLaneResolver",
      "Fenwick",
      "BoardScrollOrchestrator",
      "ItemSlideEngine",
      "TrackResizeAnimator",
      "ItemEnterExitAnimator",
      "MakeRoomEngine",
      "BoardAnimationCoordinator",
      "BoardDropResolver",
      "BoardAutoScroller",
    };
    expect(shown.intersection(internals), isEmpty);

    final package = File("lib/widgets_extended.dart").readAsStringSync();
    expect(package, contains("export 'board/board.dart';"));
  });
}
