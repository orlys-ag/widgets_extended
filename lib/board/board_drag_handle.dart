/// The caller-placed drag-handle trio: the scope the item's `State`
/// publishes, and the two handle widgets that arm a gesture against it.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'board_config.dart';

/// The channel between a handle and the item `State` that owns the key
/// and the port. NON-GENERIC on purpose: the [startDrag] field is a
/// method TEAR-OFF of the publishing `State`, closing over its own typed
/// key, so no key crosses this boundary; a generic scope would be
/// unfindable from the non-generic handles.
class BoardItemDragScope extends InheritedWidget {
  const BoardItemDragScope({
    required this.canDrag,
    required this.startDrag,
    required super.child,
    super.key,
  });

  final bool canDrag;

  /// Carries the RECOGNIZER, not just a position: the publishing `State`
  /// takes ownership of it, and its `onStart` is what yields the `Drag`
  /// whose updates reach the drag controller. [BoardResizeEdges] is the
  /// one argument beyond the tree's shape, so one handle can start a
  /// move or a resize.
  final void Function(
    PointerDownEvent event,
    MultiDragGestureRecognizer recognizer,
    BoardResizeEdges edge,
  )
  startDrag;

  static BoardItemDragScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BoardItemDragScope>();
  }

  /// `!=`, not `!identical`: Dart canonicalizes instance-method tear-off
  /// EQUALITY but not identity, so an identity comparison would report a
  /// change on every rebuild and churn every handle.
  @override
  bool updateShouldNotify(BoardItemDragScope oldWidget) {
    return canDrag != oldWidget.canDrag || startDrag != oldWidget.startDrag;
  }
}

/// Arms a pointer-down against the enclosing [BoardItemDragScope]. A
/// handle outside any scope, or one whose scope refuses, renders its
/// child unchanged, keeping the widget SHAPE stable so the subtree is
/// not re-inflated.
class BoardDragHandle extends StatelessWidget {
  const BoardDragHandle({
    required this.child,
    this.enabled = true,
    this.edge = BoardResizeEdges.none,
    this.behavior = HitTestBehavior.deferToChild,
    super.key,
  });

  final Widget child;
  final bool enabled;

  /// The [Listener]'s hit-test behavior. The default defers to the
  /// child, right for a handle wrapping visible content; a handle whose
  /// child paints nothing (an empty edge strip) is never hit that way
  /// and needs [HitTestBehavior.opaque] to be an input path at all.
  final HitTestBehavior behavior;

  /// Which drag this handle starts. `none` starts a move; anything else
  /// starts a resize on that edge.
  final BoardResizeEdges edge;

  /// The extension point the delayed subclass overrides. Must return a
  /// [MultiDragGestureRecognizer]: the item's `State` services exactly
  /// one drag protocol, and a single-pointer recognizer would mean two
  /// incompatible callback shapes.
  @protected
  MultiDragGestureRecognizer createRecognizer() {
    return ImmediateMultiDragGestureRecognizer();
  }

  @override
  Widget build(BuildContext context) {
    final scope = BoardItemDragScope.maybeOf(context);
    if (!enabled || scope == null || !scope.canDrag) {
      return child;
    }
    final settings = MediaQuery.maybeGestureSettingsOf(context);
    return Listener(
      behavior: behavior,
      onPointerDown: (event) {
        scope.startDrag(
          event,
          createRecognizer()..gestureSettings = settings,
          edge,
        );
      },
      child: child,
    );
  }
}

/// [BoardDragHandle] behind a long-press delay, for touch surfaces where
/// an immediate lift would eat every scroll gesture that starts on an
/// item.
class BoardDelayedDragHandle extends BoardDragHandle {
  const BoardDelayedDragHandle({
    required super.child,
    super.enabled,
    super.edge,
    super.behavior,
    super.key,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer();
  }
}
