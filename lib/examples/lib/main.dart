import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:widgets_extended/widgets_extended.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SyncedSliverTreeExample(),
    );
  }
}

/// Discriminator for the kind of row a [Node] renders as.
enum NodeKind { entry, menuRoot, menuSection, menuPanel }

/// Mutable domain node used by the example.
class Node {
  Node({
    required this.id,
    required this.name,
    this.kind = NodeKind.entry,
    List<Node>? children,
  }) : children = children ?? <Node>[];

  final String id;
  String name;
  final NodeKind kind;
  final List<Node> children;
}

const String _menuRootId = "__menu_root__";
const String _menuActionsId = "__menu_actions__";
const String _menuActionsPanelId = "__menu_actions_panel__";
const String _menuSettingsId = "__menu_settings__";
const String _menuSettingsPanelId = "__menu_settings_panel__";
const String _menuScrollId = "__menu_scroll__";
const String _menuScrollPanelId = "__menu_scroll_panel__";

/// Builds the initial example data set. A few extra-large folders are
/// included so the `animateScrollToKey` demo has somewhere to scroll to.
List<Node> _buildInitialTree() {
  return <Node>[
    Node(
      id: "docs",
      name: "Documents",
      children: <Node>[
        Node(
          id: "docs/work",
          name: "Work",
          children: <Node>[
            Node(id: "docs/work/q1", name: "Q1 report.pdf"),
            Node(id: "docs/work/q2", name: "Q2 report.pdf"),
            Node(id: "docs/work/notes", name: "Meeting notes.md"),
          ],
        ),
        Node(
          id: "docs/personal",
          name: "Personal",
          children: <Node>[
            Node(id: "docs/personal/taxes", name: "Taxes 2025.pdf"),
            Node(id: "docs/personal/cv", name: "CV.docx"),
          ],
        ),
      ],
    ),
    Node(
      id: "media",
      name: "Media",
      children: <Node>[
        Node(
          id: "media/photos",
          name: "Photos",
          children: <Node>[
            Node(id: "media/photos/trip", name: "Trip 2024"),
            Node(id: "media/photos/family", name: "Family"),
          ],
        ),
        Node(id: "media/music", name: "Music"),
      ],
    ),
    Node(id: "downloads", name: "Downloads"),
    Node(
      id: "gallery",
      name: "Gallery",
      children: <Node>[
        for (int i = 0; i < 40; i++)
          Node(id: "gallery/img$i", name: "image_$i.png"),
      ],
    ),
    Node(
      id: "logs",
      name: "Logs",
      children: <Node>[
        for (int i = 0; i < 60; i++) Node(id: "logs/log$i", name: "log_$i.txt"),
      ],
    ),
  ];
}

class SyncedSliverTreeExample extends StatefulWidget {
  const SyncedSliverTreeExample({super.key});

  @override
  State<SyncedSliverTreeExample> createState() =>
      _SyncedSliverTreeExampleState();
}

class _SyncedSliverTreeExampleState extends State<SyncedSliverTreeExample> {
  List<Node> _userRoots = _buildInitialTree();
  String? _selectedId;
  int _nextId = 0;
  final _random = math.Random();
  final ScrollController _scrollController = ScrollController();

  // Controls bound to SyncedSliverTree configuration.
  bool _initiallyExpanded = true;
  bool _preserveExpansion = true;
  double _indentWidth = 16;

  // Controls for animateScrollToKey.
  double _scrollAlignment = 0.0;
  int _scrollDurationMs = 300;
  AncestorExpansionMode _ancestorExpansion = AncestorExpansionMode.animated;

  // A Key forces SyncedSliverTree to re-create when tree-wide config changes
  // that are asserted to be immutable after construction (indentWidth, etc.).
  Key _treeKey = UniqueKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// The full root list shown by the tree: a synthetic Menu root followed
  /// by the user's data roots. The menu has three collapsible sub-sections,
  /// each containing a panel widget.
  List<Node> get _allRoots {
    return <Node>[
      Node(
        id: _menuRootId,
        name: "Menu",
        kind: NodeKind.menuRoot,
        children: <Node>[
          Node(
            id: _menuActionsId,
            name: "Actions",
            kind: NodeKind.menuSection,
            children: <Node>[
              Node(
                id: _menuActionsPanelId,
                name: "actions_panel",
                kind: NodeKind.menuPanel,
              ),
            ],
          ),
          Node(
            id: _menuSettingsId,
            name: "Settings",
            kind: NodeKind.menuSection,
            children: <Node>[
              Node(
                id: _menuSettingsPanelId,
                name: "settings_panel",
                kind: NodeKind.menuPanel,
              ),
            ],
          ),
          Node(
            id: _menuScrollId,
            name: "animateScrollToKey",
            kind: NodeKind.menuSection,
            children: <Node>[
              Node(
                id: _menuScrollPanelId,
                name: "scroll_panel",
                kind: NodeKind.menuPanel,
              ),
            ],
          ),
        ],
      ),
      ..._userRoots,
    ];
  }

  static const Set<String> _menuKeys = <String>{
    _menuRootId,
    _menuActionsId,
    _menuSettingsId,
    _menuScrollId,
  };

  String _mintId(String base) {
    _nextId += 1;
    return "$base#$_nextId";
  }

  // ---------------------------------------------------------------------------
  // Tree lookup helpers (operate on user data only — menu nodes are excluded)
  // ---------------------------------------------------------------------------

  Node? _findById(String id) {
    Node? result;
    void walk(List<Node> list) {
      for (final node in list) {
        if (result != null) {
          return;
        }
        if (node.id == id) {
          result = node;
          return;
        }
        walk(node.children);
      }
    }

    walk(_userRoots);
    return result;
  }

  /// Returns the parent list that contains [id] (root list if top-level).
  List<Node>? _parentListOf(String id) {
    if (_userRoots.any((n) => n.id == id)) {
      return _userRoots;
    }
    List<Node>? found;
    void walk(Node node) {
      if (found != null) {
        return;
      }
      if (node.children.any((c) => c.id == id)) {
        found = node.children;
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _userRoots) {
      walk(root);
    }
    return found;
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  void _addRoot() {
    setState(() {
      _userRoots.add(Node(id: _mintId("root"), name: "New root"));
    });
  }

  void _addChild() {
    final id = _selectedId;
    if (id == null) {
      _addRoot();
      return;
    }
    final parent = _findById(id);
    if (parent == null) {
      return;
    }
    setState(() {
      parent.children.add(
        Node(id: _mintId("${parent.id}/child"), name: "New child"),
      );
    });
  }

  void _addTenChildren() {
    final id = _selectedId;
    final parent = id == null ? null : _findById(id);
    setState(() {
      if (parent == null) {
        for (var i = 0; i < 10; i++) {
          _userRoots.add(Node(id: _mintId("root"), name: "New root"));
        }
      } else {
        for (var i = 0; i < 10; i++) {
          parent.children.add(
            Node(id: _mintId("${parent.id}/child"), name: "New child"),
          );
        }
      }
    });
  }

  void _addSibling() {
    final id = _selectedId;
    if (id == null) {
      _addRoot();
      return;
    }
    final siblings = _parentListOf(id);
    if (siblings == null) {
      return;
    }
    final index = siblings.indexWhere((n) => n.id == id);
    if (index < 0) {
      return;
    }
    setState(() {
      siblings.insert(
        index + 1,
        Node(id: _mintId("sibling"), name: "New sibling"),
      );
    });
  }

  void _removeSelected() {
    final id = _selectedId;
    if (id == null) {
      return;
    }
    final siblings = _parentListOf(id);
    if (siblings == null) {
      return;
    }
    setState(() {
      siblings.removeWhere((n) => n.id == id);
      _selectedId = null;
    });
  }

  void _moveSelected(int delta) {
    final id = _selectedId;
    if (id == null) {
      return;
    }
    final siblings = _parentListOf(id);
    if (siblings == null) {
      return;
    }
    final index = siblings.indexWhere((n) => n.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= siblings.length) {
      return;
    }
    setState(() {
      final node = siblings.removeAt(index);
      siblings.insert(target, node);
    });
  }

  void _shuffleChildren() {
    final id = _selectedId;
    final list = id == null ? _userRoots : _findById(id)?.children;
    if (list == null || list.length < 2) {
      return;
    }
    setState(() {
      list.shuffle(_random);
    });
  }

  Future<void> _renameSelected() async {
    final id = _selectedId;
    if (id == null) {
      return;
    }
    final node = _findById(id);
    if (node == null) {
      return;
    }

    final controller = TextEditingController(text: node.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Rename node"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text("Rename"),
            ),
          ],
        );
      },
    );

    if (newName == null || newName.isEmpty) {
      return;
    }
    setState(() {
      node.name = newName;
    });
  }

  void _reset() {
    setState(() {
      _userRoots = _buildInitialTree();
      _selectedId = null;
      _nextId = 0;
    });
  }

  void _rebuildTreeWidget() {
    setState(() {
      _treeKey = UniqueKey();
    });
  }

  void _expandAll(TreeController<String, Node> controller) {
    controller.expandAll();
  }

  void _collapseAll(TreeController<String, Node> controller) {
    // Snapshot the menu's expansion state so collapseAll only collapses the
    // file tree from the user's perspective — the menu controls stay where
    // the user left them.
    final wasExpanded = <String>{
      for (final key in _menuKeys)
        if (controller.isExpanded(key)) key,
    };
    controller.collapseAll();
    for (final key in wasExpanded) {
      controller.expand(key: key);
    }
  }

  Future<void> _scrollToSelected(
    TreeController<String, Node> controller,
  ) async {
    final id = _selectedId;
    if (id == null) return;
    await controller.animateScrollToKey(
      id,
      scrollController: _scrollController,
      duration: Duration(milliseconds: _scrollDurationMs),
      alignment: _scrollAlignment,
      ancestorExpansion: _ancestorExpansion,
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedId != null;
    final selectionLabel = _selectedId == null
        ? "No selection — actions apply to roots"
        : "Selected: ${_findById(_selectedId!)?.name ?? _selectedId}";

    return Scaffold(
      appBar: AppBar(
        title: const Text("SyncedSliverTree example"),
        actions: <Widget>[
          IconButton(
            tooltip: "Reset tree",
            icon: const Icon(Icons.restart_alt),
            onPressed: _reset,
          ),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: <Widget>[
          SyncedSliverTree<String, Node>.hierarchy(
            key: _treeKey,
            roots: _allRoots,
            keyOf: (node) => node.id,
            childrenOf: (node) => node.children,
            initiallyExpanded: _initiallyExpanded,
            preserveExpansion: _preserveExpansion,
            indentWidth: _indentWidth,
            itemBuilder: (context, view) {
              switch (view.item.kind) {
                case NodeKind.menuRoot:
                  return _MenuHeaderTile(view: view);
                case NodeKind.menuSection:
                  return _MenuSectionTile(view: view);
                case NodeKind.menuPanel:
                  switch (view.key) {
                    case _menuActionsPanelId:
                      return _ActionsPanel(
                        hasSelection: hasSelection,
                        selectionLabel: selectionLabel,
                        onAddRoot: _addRoot,
                        onAddChild: _addChild,
                        onAdd10Children: _addTenChildren,
                        onAddSibling: _addSibling,
                        onRemove: hasSelection ? _removeSelected : null,
                        onRename: hasSelection ? _renameSelected : null,
                        onMoveUp: hasSelection ? () => _moveSelected(-1) : null,
                        onMoveDown: hasSelection
                            ? () => _moveSelected(1)
                            : null,
                        onShuffle: _shuffleChildren,
                        onExpandAll: () => _expandAll(view.controller),
                        onCollapseAll: () => _collapseAll(view.controller),
                      );
                    case _menuSettingsPanelId:
                      return _SettingsPanel(
                        initiallyExpanded: _initiallyExpanded,
                        preserveExpansion: _preserveExpansion,
                        indentWidth: _indentWidth,
                        onInitiallyExpandedChanged: (value) {
                          setState(() => _initiallyExpanded = value);
                          _rebuildTreeWidget();
                        },
                        onPreserveExpansionChanged: (value) {
                          setState(() => _preserveExpansion = value);
                        },
                        onIndentWidthChanged: (value) {
                          setState(() => _indentWidth = value);
                          _rebuildTreeWidget();
                        },
                      );
                    case _menuScrollPanelId:
                      return _ScrollPanel(
                        scrollAlignment: _scrollAlignment,
                        scrollDurationMs: _scrollDurationMs,
                        ancestorExpansion: _ancestorExpansion,
                        onScrollAlignmentChanged: (value) {
                          setState(() => _scrollAlignment = value);
                        },
                        onScrollDurationChanged: (value) {
                          setState(() => _scrollDurationMs = value.round());
                        },
                        onAncestorExpansionChanged: (value) {
                          setState(() => _ancestorExpansion = value);
                        },
                        onScrollToSelected: hasSelection
                            ? () => _scrollToSelected(view.controller)
                            : null,
                      );
                    default:
                      return const SizedBox.shrink();
                  }
                case NodeKind.entry:
                  final isSelected = view.key == _selectedId;
                  return _TreeTile(
                    view: view,
                    indent: view.depth * _indentWidth,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedId = isSelected ? null : view.key;
                      });
                    },
                  );
              }
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// =============================================================================
// File / folder tile
// =============================================================================

class _TreeTile extends StatelessWidget {
  const _TreeTile({
    required this.view,
    this.indent = 8,
    required this.isSelected,
    required this.onTap,
  });

  final TreeItemView<String, Node> view;
  final double indent;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isSelected
        ? theme.colorScheme.primaryContainer
        : Colors.transparent;
    final fg = isSelected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: indent,
            right: 8.0,
            top: 6.0,
            bottom: 6.0,
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                height: 28,
                child: view.hasChildren
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        icon: Icon(
                          view.isExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_right,
                          color: fg,
                        ),
                        onPressed: view.toggle,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 4),
              Icon(
                view.hasChildren
                    ? (view.isExpanded ? Icons.folder_open : Icons.folder)
                    : Icons.insert_drive_file_outlined,
                color: fg,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  view.item.name,
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (view.hasChildren)
                Text(
                  "${view.childCount}",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Menu header (collapsible "Menu" tree row)
// =============================================================================

class _MenuHeaderTile extends StatelessWidget {
  const _MenuHeaderTile({required this.view});

  final TreeItemView<String, Node> view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: view.toggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(
                view.isExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 20,
              ),
              const SizedBox(width: 6),
              const Icon(Icons.tune, size: 20),
              const SizedBox(width: 8),
              Text(
                "Menu",
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                view.isExpanded ? "tap to collapse" : "tap to expand",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Sub-section header (collapsible row inside the Menu)
// =============================================================================

class _MenuSectionTile extends StatelessWidget {
  const _MenuSectionTile({required this.view});

  final TreeItemView<String, Node> view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: view.toggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 6, 12, 6),
          child: Row(
            children: <Widget>[
              Icon(
                view.isExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                view.item.name.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Sub-section panels — Actions, Settings, and animateScrollToKey
// =============================================================================

class _PanelContainer extends StatelessWidget {
  const _PanelContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(28, 8, 12, 12),
      child: child,
    );
  }
}

class _ActionsPanel extends StatelessWidget {
  const _ActionsPanel({
    required this.hasSelection,
    required this.selectionLabel,
    required this.onAddRoot,
    required this.onAddChild,
    required this.onAdd10Children,
    required this.onAddSibling,
    required this.onRemove,
    required this.onRename,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onShuffle,
    required this.onExpandAll,
    required this.onCollapseAll,
  });

  final bool hasSelection;
  final String selectionLabel;
  final VoidCallback onAddRoot;
  final VoidCallback onAddChild;
  final VoidCallback onAdd10Children;
  final VoidCallback onAddSibling;
  final VoidCallback? onRemove;
  final VoidCallback? onRename;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onShuffle;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _PanelContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            selectionLabel,
            style: theme.textTheme.labelMedium?.copyWith(
              color: hasSelection
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _ToolbarButton(
                icon: Icons.add_box_outlined,
                label: "Add root",
                onPressed: onAddRoot,
              ),
              _ToolbarButton(
                icon: Icons.subdirectory_arrow_right,
                label: "Add child",
                onPressed: onAddChild,
              ),
              _ToolbarButton(
                icon: Icons.library_add_outlined,
                label: "Add 10 children",
                onPressed: onAdd10Children,
              ),
              _ToolbarButton(
                icon: Icons.playlist_add,
                label: "Add sibling",
                onPressed: onAddSibling,
              ),
              _ToolbarButton(
                icon: Icons.edit_outlined,
                label: "Rename",
                onPressed: onRename,
              ),
              _ToolbarButton(
                icon: Icons.delete_outline,
                label: "Remove",
                onPressed: onRemove,
              ),
              _ToolbarButton(
                icon: Icons.arrow_upward,
                label: "Move up",
                onPressed: onMoveUp,
              ),
              _ToolbarButton(
                icon: Icons.arrow_downward,
                label: "Move down",
                onPressed: onMoveDown,
              ),
              _ToolbarButton(
                icon: Icons.shuffle,
                label: "Shuffle children",
                onPressed: onShuffle,
              ),
              _ToolbarButton(
                icon: Icons.unfold_more,
                label: "Expand all",
                onPressed: onExpandAll,
              ),
              _ToolbarButton(
                icon: Icons.unfold_less,
                label: "Collapse all",
                onPressed: onCollapseAll,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.initiallyExpanded,
    required this.preserveExpansion,
    required this.indentWidth,
    required this.onInitiallyExpandedChanged,
    required this.onPreserveExpansionChanged,
    required this.onIndentWidthChanged,
  });

  final bool initiallyExpanded;
  final bool preserveExpansion;
  final double indentWidth;
  final ValueChanged<bool> onInitiallyExpandedChanged;
  final ValueChanged<bool> onPreserveExpansionChanged;
  final ValueChanged<double> onIndentWidthChanged;

  @override
  Widget build(BuildContext context) {
    return _PanelContainer(
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _SwitchField(
            label: "initiallyExpanded",
            value: initiallyExpanded,
            onChanged: onInitiallyExpandedChanged,
          ),
          _SwitchField(
            label: "preserveExpansion",
            value: preserveExpansion,
            onChanged: onPreserveExpansionChanged,
          ),
          _LabeledSlider(
            label: "indentWidth",
            value: indentWidth,
            min: 0,
            max: 48,
            divisions: 12,
            width: 240,
            valueLabel: indentWidth.toStringAsFixed(0),
            onChanged: onIndentWidthChanged,
          ),
        ],
      ),
    );
  }
}

class _ScrollPanel extends StatelessWidget {
  const _ScrollPanel({
    required this.scrollAlignment,
    required this.scrollDurationMs,
    required this.ancestorExpansion,
    required this.onScrollAlignmentChanged,
    required this.onScrollDurationChanged,
    required this.onAncestorExpansionChanged,
    required this.onScrollToSelected,
  });

  final double scrollAlignment;
  final int scrollDurationMs;
  final AncestorExpansionMode ancestorExpansion;
  final ValueChanged<double> onScrollAlignmentChanged;
  final ValueChanged<double> onScrollDurationChanged;
  final ValueChanged<AncestorExpansionMode> onAncestorExpansionChanged;
  final VoidCallback? onScrollToSelected;

  @override
  Widget build(BuildContext context) {
    return _PanelContainer(
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _LabeledSlider(
            label: "alignment",
            value: scrollAlignment,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            width: 280,
            valueLabel: scrollAlignment.toStringAsFixed(1),
            onChanged: onScrollAlignmentChanged,
          ),
          _LabeledSlider(
            label: "duration (ms)",
            value: scrollDurationMs.toDouble(),
            min: 0,
            max: 2000,
            divisions: 20,
            width: 300,
            valueLabel: "$scrollDurationMs",
            onChanged: onScrollDurationChanged,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text("ancestors:"),
              const SizedBox(width: 8),
              SegmentedButton<AncestorExpansionMode>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const <ButtonSegment<AncestorExpansionMode>>[
                  ButtonSegment<AncestorExpansionMode>(
                    value: AncestorExpansionMode.none,
                    label: Text("none"),
                  ),
                  ButtonSegment<AncestorExpansionMode>(
                    value: AncestorExpansionMode.immediate,
                    label: Text("immediate"),
                  ),
                  ButtonSegment<AncestorExpansionMode>(
                    value: AncestorExpansionMode.animated,
                    label: Text("animated"),
                  ),
                ],
                selected: <AncestorExpansionMode>{ancestorExpansion},
                onSelectionChanged: (selection) {
                  onAncestorExpansionChanged(selection.first);
                },
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: onScrollToSelected,
            icon: const Icon(Icons.center_focus_strong, size: 18),
            label: const Text("Scroll to selected"),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Small UI helpers
// =============================================================================

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _SwitchField extends StatelessWidget {
  const _SwitchField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Switch.adaptive(value: value, onChanged: onChanged),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.width,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final double width;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Row(
        children: <Widget>[
          Text(label),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(valueLabel, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
