/// Caller-placed drag handles for a [SliverReorderableTree] row.
///
/// The package ARMS a child; it does not decide where that child sits.
/// Put a [TreeDragHandle] anywhere inside a row: across the top of a
/// card, at the leading edge, inline with a title, or two of them. The
/// row is wrapped for you either way, so a handle-less row still hides
/// itself while dragged, still exposes its reorder semantics actions,
/// and is still a drop TARGET.
///
/// Ownership follows Flutter's `ReorderableDragStartListener` in
/// `widgets/reorderable_list.dart`: the handle owns NO recognizer.
/// It reports a single pointer-down to the enclosing row through
/// [TreeRowDragScope], and the ROW owns the recognizer, the per-pointer
/// bookkeeping, and one `Drag` per gesture. That is what makes two
/// handles in one row safe, a handle inside a nested scrollable
/// harmless, and an unmounted handle a non-event for a live drag.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Published by each reorderable row; found by [TreeDragHandle.build].
///
/// Deliberately NON-GENERIC, and that is load-bearing twice over.
/// [InheritedWidget] lookup keys on `runtimeType`, so a
/// `TreeRowDragScope<TKey>` could never be found by a non-generic handle;
/// and type-blind lookup is what makes the nested-tree answer correct,
/// since the nearest enclosing row wins whatever its key type is.
class TreeRowDragScope extends InheritedWidget {
  const TreeRowDragScope({
    required this.canDrag,
    required this.startDrag,
    required super.child,
    super.key,
  });

  /// Whether the enclosing row is draggable at all: the reorder policy's
  /// `canReorder` answer for this row.
  ///
  /// Public because it is how a caller renders a hidden grip that still
  /// reserves its cell, without asking its own policy a second time:
  ///
  /// ```dart
  /// Builder(
  ///   builder: (context) {
  ///     final canDrag = TreeRowDragScope.maybeOf(context)?.canDrag ?? false;
  ///     return Visibility(
  ///       visible: canDrag,
  ///       maintainSize: true,
  ///       maintainAnimation: true,
  ///       maintainState: true,
  ///       child: TreeDragHandle(child: grip),
  ///     );
  ///   },
  /// )
  /// ```
  ///
  /// `Visibility`, not `Opacity(opacity: 0.0)`: `RenderOpacity` does not
  /// override `hitTest`, so a zero-alpha grip still swallows gestures.
  /// `Visibility`'s defaults (`maintainInteractivity: false`,
  /// `maintainSemantics: false`) wrap the hidden cell in `IgnorePointer`
  /// and `ExcludeSemantics`, which is what keeps the reserved cell inert.
  final bool canDrag;

  /// A method TEAR-OFF of the publishing row's `State`, closing over its
  /// own typed node key.
  ///
  /// No key crosses this boundary, so the handle stays non-generic and no
  /// cast is needed anywhere.
  final void Function(
    PointerDownEvent event,
    MultiDragGestureRecognizer recognizer,
  )
  startDrag;

  @override
  bool updateShouldNotify(TreeRowDragScope old) {
    // `!=`, NOT `!identical`. Dart canonicalizes instance-method tear-off
    // EQUALITY but not identity: `a.foo == a.foo` is true while
    // `identical(a.foo, a.foo)` is false. Comparing by identity would
    // report a change on every rebuild and churn every handle in the
    // tree, which is precisely what this comparison exists to prevent.
    return canDrag != old.canDrag || startDrag != old.startDrag;
  }

  /// The nearest enclosing row's drag scope, or null outside a
  /// reorderable tree (including inside the floating drag proxy, which
  /// renders in the root `Overlay`).
  static TreeRowDragScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TreeRowDragScope>();
  }
}

/// Arms [child] as a drag handle for the row that encloses it.
///
/// Draws NOTHING. The appearance, the size, and the position are entirely
/// the caller's; this widget contributes a pointer-down listener and a
/// grab cursor and nothing else.
///
/// Starts the drag IMMEDIATELY, once the pointer moves past the touch
/// slop, which is the pointer convention for a dedicated grip. Wrapping a
/// WHOLE row in this is a trap: an immediate multi-drag over the full row
/// claims every pointer that lands on it and the list stops scrolling.
/// Use [TreeDelayedDragHandle] for that, or leave
/// `TreeReorderConfig.buildDefaultDragHandles` at its default and let the
/// package install one.
///
/// Outside a reorderable tree this renders [child] bare, so a row cloned
/// into the drag proxy overlay is inert rather than throwing.
class TreeDragHandle extends StatelessWidget {
  const TreeDragHandle({required this.child, this.enabled = true, super.key});

  /// The widget the user grabs.
  final Widget child;

  /// A local narrowing, ANDed with the package's own `canReorder` answer.
  /// It can only ever narrow, never widen.
  ///
  /// Prefer this to conditionally omitting the handle. Omitting it
  /// changes the row's widget SHAPE, so `Widget.canUpdate` fails and the
  /// framework re-inflates the whole row subtree, disposing whatever
  /// `State` the app keeps beneath it.
  ///
  /// Flipping this MID-DRAG does nothing to the live session, and needs
  /// no backstop: the recognizer belongs to the row, not to this widget,
  /// and the `onPointerDown` being nulled has already fired. Use
  /// `TreeReorderConfig.canReorder` for a refusal that must interrupt a
  /// drag in flight; the controller enforces that one for the session's
  /// whole life.
  final bool enabled;

  /// The gesture that starts a drag from this handle.
  ///
  /// Override in a subclass to change it, the way
  /// [TreeDelayedDragHandle] does. A named constructor cannot vary
  /// behaviour without a discriminating field, so subclassing is the
  /// mechanism, matching `ReorderableDelayedDragStartListener`.
  ///
  /// Must return a [MultiDragGestureRecognizer]: the row services exactly
  /// one protocol, and mixing in a single-pointer recognizer would mean
  /// two incompatible callback shapes.
  @protected
  MultiDragGestureRecognizer createRecognizer() {
    return ImmediateMultiDragGestureRecognizer(debugOwner: this);
  }

  @override
  Widget build(BuildContext context) {
    final scope = TreeRowDragScope.maybeOf(context);
    final armed = enabled && (scope?.canDrag ?? false);
    return MouseRegion(
      cursor: armed ? SystemMouseCursors.grab : MouseCursor.defer,
      // `RenderMouseRegion` defaults its hit-test behaviour to
      // `HitTestBehavior.opaque` (rendering/proxy_box.dart), which would
      // make this wrapper absorb hits on its own account. Defer instead,
      // and let the `Listener` below make the single decision.
      hitTestBehavior: HitTestBehavior.deferToChild,
      child: Listener(
        // OPAQUE while armed, and this is not cosmetic. `Listener`
        // defaults to `deferToChild`, so a handle wrapping a child that
        // does not hit-test itself (a bare `SizedBox`, a `Padding` around
        // nothing, a `CustomPaint` with no hit-test override) would
        // render, show no cursor, and silently never drag. That is
        // exactly the footgun a caller-placed handle invites, so the
        // behaviour is decided here rather than left to whatever the
        // caller happens to pass as [child].
        //
        // TRANSPARENT while disarmed, which is the other half. An opaque
        // disarmed handle would swallow taps the app wants for its own
        // menu, and would shadow whatever it overlaps during a FLIP
        // slide, where `RenderSliverTree.hitTestChildren` returns on the
        // first row that reports a hit.
        //
        // Flipping a FIELD, never the widget type, so `Widget.canUpdate`
        // still matches and a `canReorder` flip does not re-inflate the
        // row subtree beneath this handle.
        behavior: armed ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
        // Disarmed by NULLING, never by omitting, for the shape-stability
        // reason spelled out on [enabled].
        onPointerDown: armed
            ? (event) {
                _start(context, scope!, event);
              }
            : null,
        child: child,
      ),
    );
  }

  /// Builds a fresh recognizer, gives it the ambient gesture settings, and
  /// hands it to the enclosing row along with the pointer-down. The row
  /// takes ownership from there, disposing whatever it held before.
  void _start(
    BuildContext context,
    TreeRowDragScope scope,
    PointerDownEvent event,
  ) {
    // `GestureDetector` read this for us. A hand-rolled recognizer must
    // do it explicitly or the touch slop is wrong on Android, which is
    // invisible in a desktop-only test run.
    final settings = MediaQuery.maybeGestureSettingsOf(context);
    scope.startDrag(event, createRecognizer()..gestureSettings = settings);
  }
}

/// A [TreeDragHandle] that waits for a long press before lifting the row.
///
/// The touch convention, and what
/// `TreeReorderConfig.buildDefaultDragHandles` installs around the whole
/// row. Safe to wrap a whole row in, because the delay leaves the
/// enclosing scrollable free to claim a scroll first.
///
/// Mirrors `ReorderableDelayedDragStartListener`.
class TreeDelayedDragHandle extends TreeDragHandle {
  const TreeDelayedDragHandle({required super.child, super.enabled, super.key});

  @override
  MultiDragGestureRecognizer createRecognizer() {
    // No `delay:` argument. `DelayedMultiDragGestureRecognizer` already
    // defaults to `kLongPressTimeout`, matching
    // `LongPressGestureRecognizer`.
    return DelayedMultiDragGestureRecognizer(debugOwner: this);
  }
}
