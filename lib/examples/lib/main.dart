import 'dart:developer';
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

/// Mutable domain node used by the example.
class Node {
  Node({required this.id, required this.name, List<Node>? children})
    : children = children ?? <Node>[];

  final String id;
  String name;
  final List<Node> children;
}

/// Builds the initial example data set.
List<Node> _buildInitialTree() {
  return <Node>[
    Node(
      id: 'docs',
      name: 'Documents',
      children: <Node>[
        Node(
          id: 'docs/work',
          name: 'Work',
          children: <Node>[
            Node(id: 'docs/work/q1', name: 'Q1 report.pdf'),
            Node(id: 'docs/work/q2', name: 'Q2 report.pdf'),
            Node(id: 'docs/work/notes', name: 'Meeting notes.md'),
          ],
        ),
        Node(
          id: 'docs/personal',
          name: 'Personal',
          children: <Node>[
            Node(id: 'docs/personal/taxes', name: 'Taxes 2025.pdf'),
            Node(id: 'docs/personal/cv', name: 'CV.docx'),
          ],
        ),
      ],
    ),
    Node(
      id: 'media',
      name: 'Media',
      children: <Node>[
        Node(
          id: 'media/photos',
          name: 'Photos',
          children: <Node>[
            Node(id: 'media/photos/trip', name: 'Trip 2024'),
            Node(id: 'media/photos/family', name: 'Family'),
          ],
        ),
        Node(id: 'media/music', name: 'Music'),
      ],
    ),
    Node(id: 'downloads', name: 'Downloads'),
  ];
}

class SyncedSliverTreeExample extends StatefulWidget {
  const SyncedSliverTreeExample({super.key});

  @override
  State<SyncedSliverTreeExample> createState() =>
      _SyncedSliverTreeExampleState();
}

class _SyncedSliverTreeExampleState extends State<SyncedSliverTreeExample> {
  List<Node> _roots = _buildInitialTree();
  String? _selectedId;
  int _nextId = 0;
  final _random = math.Random();

  // Controls bound to SyncedSliverTree configuration.
  bool _initiallyExpanded = true;
  bool _preserveExpansion = true;
  double _indentWidth = 16;

  // A Key forces SyncedSliverTree to re-create when tree-wide config changes
  // that are asserted to be immutable after construction (indentWidth, etc.).
  Key _treeKey = UniqueKey();

  String _mintId(String base) {
    _nextId += 1;
    return '$base#$_nextId';
  }

  // ---------------------------------------------------------------------------
  // Tree lookup helpers
  // ---------------------------------------------------------------------------

  Node? _findById(String id) {
    Node? result;
    void walk(List<Node> list) {
      for (final node in list) {
        if (result != null) return;
        if (node.id == id) {
          result = node;
          return;
        }
        walk(node.children);
      }
    }

    walk(_roots);
    return result;
  }

  /// Returns the parent list that contains [id] (root list if top-level).
  List<Node>? _parentListOf(String id) {
    if (_roots.any((n) => n.id == id)) {
      return _roots;
    }
    List<Node>? found;
    void walk(Node node) {
      if (found != null) return;
      if (node.children.any((c) => c.id == id)) {
        found = node.children;
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    for (final root in _roots) {
      walk(root);
    }
    return found;
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  void _addRoot() {
    setState(() {
      _roots.add(Node(id: _mintId('root'), name: 'New root'));
    });
  }

  void _addChild() {
    final id = _selectedId;
    if (id == null) {
      _addRoot();
      return;
    }
    final parent = _findById(id);
    if (parent == null) return;
    setState(() {
      parent.children.add(
        Node(id: _mintId('${parent.id}/child'), name: 'New child'),
      );
    });
  }

  void _addSibling() {
    final id = _selectedId;
    if (id == null) {
      _addRoot();
      return;
    }
    final siblings = _parentListOf(id);
    if (siblings == null) return;
    final index = siblings.indexWhere((n) => n.id == id);
    if (index < 0) return;
    setState(() {
      siblings.insert(
        index + 1,
        Node(id: _mintId('sibling'), name: 'New sibling'),
      );
    });
  }

  void _removeSelected() {
    final id = _selectedId;
    if (id == null) return;
    final siblings = _parentListOf(id);
    if (siblings == null) return;
    setState(() {
      siblings.removeWhere((n) => n.id == id);
      _selectedId = null;
    });
  }

  void _moveSelected(int delta) {
    final id = _selectedId;
    if (id == null) return;
    final siblings = _parentListOf(id);
    if (siblings == null) return;
    final index = siblings.indexWhere((n) => n.id == id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= siblings.length) return;
    setState(() {
      final node = siblings.removeAt(index);
      siblings.insert(target, node);
    });
  }

  void _shuffleChildren() {
    final id = _selectedId;
    final list = id == null ? _roots : _findById(id)?.children;
    if (list == null || list.length < 2) return;
    setState(() {
      list.shuffle(_random);
    });
  }

  Future<void> _renameSelected() async {
    final id = _selectedId;
    if (id == null) return;
    final node = _findById(id);
    if (node == null) return;

    final controller = TextEditingController(text: node.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename node'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;
    setState(() {
      node.name = newName;
    });
  }

  void _reset() {
    setState(() {
      _roots = _buildInitialTree();
      _selectedId = null;
      _nextId = 0;
    });
  }

  void _rebuildTreeWidget() {
    setState(() {
      _treeKey = UniqueKey();
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SyncedSliverTree example'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reset tree',
            icon: const Icon(Icons.restart_alt),
            onPressed: _reset,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _Toolbar(
            hasSelection: hasSelection,
            selectionLabel: _selectedId == null
                ? 'No selection — actions apply to roots'
                : 'Selected: ${_findById(_selectedId!)?.name ?? _selectedId}',
            onAddRoot: _addRoot,
            onAddChild: _addChild,
            onAddSibling: _addSibling,
            onRemove: hasSelection ? _removeSelected : null,
            onRename: hasSelection ? _renameSelected : null,
            onMoveUp: hasSelection ? () => _moveSelected(-1) : null,
            onMoveDown: hasSelection ? () => _moveSelected(1) : null,
            onShuffle: _shuffleChildren,
          ),
          _ConfigBar(
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
          ),
          const Divider(height: 1),
          Expanded(
            child: CustomScrollView(
              slivers: <Widget>[
                SyncedSliverTree<String, Node>.hierarchy(
                  key: _treeKey,
                  roots: _roots,
                  keyOf: (node) => node.id,
                  childrenOf: (node) => node.children,
                  initiallyExpanded: _initiallyExpanded,
                  preserveExpansion: _preserveExpansion,
                  itemBuilder: (context, view) {
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
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Tile
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
                  '${view.childCount}',
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
// Toolbar
// =============================================================================

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.hasSelection,
    required this.selectionLabel,
    required this.onAddRoot,
    required this.onAddChild,
    required this.onAddSibling,
    required this.onRemove,
    required this.onRename,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onShuffle,
  });

  final bool hasSelection;
  final String selectionLabel;
  final VoidCallback onAddRoot;
  final VoidCallback onAddChild;
  final VoidCallback onAddSibling;
  final VoidCallback? onRemove;
  final VoidCallback? onRename;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _ToolbarButton(
                icon: Icons.add_box_outlined,
                label: 'Add root',
                onPressed: onAddRoot,
              ),
              _ToolbarButton(
                icon: Icons.subdirectory_arrow_right,
                label: 'Add child',
                onPressed: onAddChild,
              ),
              _ToolbarButton(
                icon: Icons.playlist_add,
                label: 'Add sibling',
                onPressed: onAddSibling,
              ),
              _ToolbarButton(
                icon: Icons.edit_outlined,
                label: 'Rename',
                onPressed: onRename,
              ),
              _ToolbarButton(
                icon: Icons.delete_outline,
                label: 'Remove',
                onPressed: onRemove,
              ),
              _ToolbarButton(
                icon: Icons.arrow_upward,
                label: 'Move up',
                onPressed: onMoveUp,
              ),
              _ToolbarButton(
                icon: Icons.arrow_downward,
                label: 'Move down',
                onPressed: onMoveDown,
              ),
              _ToolbarButton(
                icon: Icons.shuffle,
                label: 'Shuffle children',
                onPressed: onShuffle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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

// =============================================================================
// Config bar
// =============================================================================

class _ConfigBar extends StatelessWidget {
  const _ConfigBar({
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
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _SwitchField(
            label: 'initiallyExpanded',
            value: initiallyExpanded,
            onChanged: onInitiallyExpandedChanged,
          ),
          _SwitchField(
            label: 'preserveExpansion',
            value: preserveExpansion,
            onChanged: onPreserveExpansionChanged,
          ),
          SizedBox(
            width: 240,
            child: Row(
              children: <Widget>[
                const Text('indentWidth'),
                Expanded(
                  child: Slider(
                    value: indentWidth,
                    min: 0,
                    max: 48,
                    divisions: 12,
                    label: indentWidth.toStringAsFixed(0),
                    onChanged: onIndentWidthChanged,
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    indentWidth.toStringAsFixed(0),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
