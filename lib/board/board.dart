/// Board: a two-axis lattice viewport with spanning items, overlap
/// lanes, animated enter/exit and slides, drag-and-drop moves and
/// resizes, cell and range selection, and frozen tracks.
///
/// Entry points: [Board] driven through a [BoardController], with
/// [BoardDragConfig] and [BoardSelectionConfig] enabling the interaction
/// layers and [BoardAxisConfig] describing each axis.
///
/// This barrel is the module's public surface; anything not exported here
/// is internal regardless of its name.
library;

export '_board_animation_coordinator.dart' show BoardAnimationReader;
export '_board_axis.dart'
    show
        BoardAxis,
        BoardAxisConfig,
        DerivedAxis,
        ExplicitAxis,
        LazyContentAxis,
        TrackAlignment,
        UniformAxis;
export '_board_span.dart' show BoardPlacement, BoardSpan;
export 'board_animation_style.dart'
    show BoardAnimationFamily, BoardAnimationSpec, BoardAnimationStyle;
export 'board_background.dart'
    show BoardBackgroundPainter, BoardGeometryView, BoardGridPainter;
export 'board_config.dart'
    show
        BoardDragConfig,
        BoardResizeEdges,
        BoardSelection,
        BoardSelectionConfig,
        BoardSelectionMode,
        BoardSemanticsActionsBuilder,
        BoardSnap,
        BoardSnapMode;
export 'board_controller.dart' show BoardController;
export 'board_drag_controller.dart'
    show BoardDragController, BoardDragKind, BoardDropTarget;
export 'board_drag_handle.dart'
    show BoardDelayedDragHandle, BoardDragHandle, BoardItemDragScope;
export 'board_render_port.dart' show BoardRenderPort;
export 'board_views.dart'
    show BoardCellBuilder, BoardCellView, BoardItemBuilder, BoardItemView;
export 'board_widget.dart' show Board;
export 'render_board_viewport.dart' show RenderBoardViewport;
