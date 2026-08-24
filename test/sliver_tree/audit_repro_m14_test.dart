import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sliver_tree/sliver_tree.dart';

/// Hosts the tree and can move a `GlobalKey`-carrying widget OUT of a row
/// and into a sibling above it, without disturbing anything else.
///
/// The move is what exercises the bug. `Element.inflateWidget` routes a
/// `GlobalKey` whose element is still active through
/// `_retakeInactiveElement`, which calls `parent.forgetChild(element)` and
/// `parent.deactivateChild(element)` back to back
/// (framework.dart:4528-4529). That pair is the only path that reaches
/// `SliverTreeElement.forgetChild` for a live row.
class _Host extends StatefulWidget {
  const _Host({required this.controller, required this.sharedKey});

  final TreeController<String, String> controller;
  final Key sharedKey;

  @override
  State<_Host> createState() {
    return _HostState();
  }
}

class _HostState extends State<_Host> {
  bool outside = false;

  void moveOut() {
    setState(() {
      outside = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          if (outside)
            SizedBox(key: widget.sharedKey, height: 48, width: 48),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverTree<String, String>(
                  controller: widget.controller,
                  // The keyed widget must be the row's ROOT widget so its
                  // element is a DIRECT child of SliverTreeElement and its
                  // slot is the node key. A RepaintBoundary wrapper would
                  // take that position instead and forgetChild would never
                  // see the keyed element.
                  addRepaintBoundaries: false,
                  nodeBuilder: (context, nodeId, depth) {
                    if (nodeId == "a" && !outside) {
                      return SizedBox(
                        key: widget.sharedKey,
                        height: 48,
                        width: 48,
                      );
                    }
                    return SizedBox(height: 48, child: Text(nodeId));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets("M14: a GlobalKey reparent out of a row does not double-drop "
      "the render box", (tester) async {
    final controller = TreeController<String, String>(
      vsync: tester,
      animationStyle: TreeAnimationStyle.disabled,
    );
    addTearDown(controller.dispose);
    controller.setRoots([
      TreeNode(key: "a", data: "A"),
      TreeNode(key: "b", data: "B"),
      TreeNode(key: "c", data: "C"),
    ]);
    final sharedKey = GlobalKey();

    await tester.pumpWidget(
      _Host(controller: controller, sharedKey: sharedKey),
    );

    // Sanity 1: the keyed row is mounted, so there is a live element for
    // the retake path to take.
    final elementBefore = sharedKey.currentContext;
    expect(
      elementBefore,
      isNotNull,
      reason: "sanity: row 'a' must be mounted before the reparent",
    );

    // Sanity 2: its render box is genuinely adopted by the RenderSliverTree.
    // Without this the test could pass on a box that was never a child, and
    // the double-drop it targets could not arise.
    final sliver = tester.renderObject<RenderSliverTree<String, String>>(
      find.byType(SliverTree<String, String>),
    );
    final boxBefore =
        elementBefore!.findRenderObject()! as RenderBox;
    expect(
      identical(boxBefore.parent, sliver),
      isTrue,
      reason:
          "sanity: the keyed row's box must be adopted by RenderSliverTree, "
          "or there is no adopted box to drop twice",
    );

    // Move the keyed widget out of the row and into the sibling above.
    tester.state<_HostState>(find.byType(_Host)).moveOut();
    await tester.pump();

    // Sanity 3: the reparent actually happened via a RETAKE of the same
    // element, not a fresh build. If these were different elements the
    // forgetChild path was never entered and the case proves nothing.
    //
    // Placed BEFORE the expectation below so a broken harness fails here
    // rather than passing the expectation vacuously. On unfixed code it
    // still passes, but NOT because the retake completes: deactivateChild
    // is called BY _retakeInactiveElement (framework.dart:4529) and
    // throws at :4635, so :4531-4533 never run and the element never
    // lands under the Column; the retake would have activated it there
    // via _activateWithParent (:4582), never via mount. It passes because
    // GlobalKey.currentContext reads the binding's buildOwner global-key
    // registry (framework.dart:173, :179), which was written when this
    // element first mounted (Element.mount, :4356) and is cleared only
    // at Element.unmount (:4859); the throw at :4635 precedes the
    // _inactiveElements.add at :4636, so the ORIGINAL element is never
    // deactivated and the registry still returns it. On the failing run
    // this therefore establishes only that no fresh element replaced the
    // row, which is what rules out a rebuilt-not-retaken harness. On the
    // fixed run it establishes the full retake-and-move.
    expect(
      identical(sharedKey.currentContext, elementBefore),
      isTrue,
      reason:
          "sanity: the element must be retaken and moved, which is what "
          "calls forgetChild; a rebuilt element would bypass the path",
    );

    // The defect: forgetChild dropped the box, then deactivateChild ->
    // detachRenderObject -> removeRenderObjectChild -> removeChild dropped
    // it again, and dropChild's `child._parent == this` assert
    // (rendering/object.dart:2193) fired on the second drop.
    expect(
      tester.takeException(),
      isNull,
      reason:
          "a GlobalKey reparent out of a row must not raise; today "
          "forgetChild drops the box and the framework drops it again",
    );

    // The tree survives: the moved row rebuilt in place and its siblings
    // still paint.
    expect(find.text("a"), findsOneWidget);
    expect(find.text("b"), findsOneWidget);
    expect(find.text("c"), findsOneWidget);
  });
}
