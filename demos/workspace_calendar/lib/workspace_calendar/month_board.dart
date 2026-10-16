/// The calendar's Month mode: the selected day's month on the board, one
/// row per week and one column per shown weekday, each item a one-lane
/// chip on the days it covers in each calendar week.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_data.dart';
import 'calendar_item.dart';
import 'calendar_model.dart';
import 'harbor_theme.dart';

/// The height of a day's number strip, which the weeks' lanes start
/// below: the row axis's lane padding.
const double monthStripHeight = 28.0;

/// The height of one chip lane: the row axis's lane extent.
const double monthLaneExtent = 18.0;

/// The height a week of the month board rests at: [height] shared by
/// [weekCount] weeks, floored to a multiple of 1/64 so the weeks never add
/// up past [height], and never less than the strip and one lane. A
/// non-finite [height] gives that least.
double fittedWeekExtent(double height, int weekCount) {
  const least = monthStripHeight + monthLaneExtent;
  if (!height.isFinite || weekCount <= 0) {
    return least;
  }
  final share = (height / weekCount * 64.0).floorToDouble() / 64.0;
  return math.max(share, least);
}

/// The style the month board animates with: every family over
/// [harborMotionDuration] on [harborMotionCurve]. The one site that
/// declares the month board's motion.
const BoardAnimationStyle monthBoardAnimationStyle =
    BoardAnimationStyle.uniform(
      BoardAnimationSpec(
        duration: harborMotionDuration,
        curve: harborMotionCurve,
      ),
    );

/// The key of the item [id]'s bar in the calendar week starting on
/// [weekStart], a Monday: `"<id>@<yyyy-mm-dd>"`.
String monthSegmentKey(String id, DateTime weekStart) {
  return "$id@${isoDate(weekStart)}";
}

/// The key of the chip of the bar [segmentKey] names.
ValueKey<String> monthChipKey(String segmentKey) {
  return ValueKey<String>("month-chip-$segmentKey");
}

/// The key of the month board's cell showing [day].
ValueKey<String> monthDayKey(DateTime day) {
  return ValueKey<String>("month-day-${isoDate(day)}");
}

/// The key of the number strip of the cell showing [day].
ValueKey<String> monthStripKey(DateTime day) {
  return ValueKey<String>("month-strip-${isoDate(day)}");
}

/// One item's bar in one calendar week: the month board's payload.
@immutable
class MonthChip {
  const MonthChip({
    required this.key,
    required this.entry,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  /// [monthSegmentKey] of the item's id and the week's Monday.
  final String key;

  final ShownItem entry;

  /// Whether the item's first day precedes the week's Monday, whatever
  /// weekdays show.
  final bool continuesBefore;

  /// Whether the item's last day follows the week's Sunday, whatever
  /// weekdays show.
  final bool continuesAfter;

  @override
  bool operator ==(Object other) {
    return other is MonthChip &&
        other.key == key &&
        other.entry == entry &&
        other.continuesBefore == continuesBefore &&
        other.continuesAfter == continuesAfter;
  }

  @override
  int get hashCode {
    return Object.hash(key, entry, continuesBefore, continuesAfter);
  }

  @override
  String toString() {
    return "MonthChip($key, $entry)";
  }
}

/// Where each of [shown] sits on the month board of [grid]: one placement
/// per week of the grid whose shown days the item covers, on that week's
/// row and on the columns from the first shown day on or after the item's
/// first day to the last shown day on or before its last. A week whose
/// shown days the item misses has none, which is the clipping
/// `gridSpanOf` applies to the timed grid's columns.
List<BoardPlacement<MonthChip>> monthPlacementsOf(
  Iterable<ShownItem> shown,
  MonthGrid grid,
) {
  final weeks = grid.weekCount;
  final columns = grid.columnCount;
  // The dayNumber of each cell, read once per call.
  final days = Int32List(weeks * columns);
  for (var row = 0; row < weeks; row++) {
    for (var col = 0; col < columns; col++) {
      days[row * columns + col] = dayNumber(grid.dateAt(row, col));
    }
  }
  final placements = <BoardPlacement<MonthChip>>[];
  for (final entry in shown) {
    final item = entry.item;
    final first = dayNumber(item.day);
    final last = first + item.dayCount - 1;
    for (var row = 0; row < weeks; row++) {
      final rowFirst = days[row * columns];
      final monday = rowFirst - weekdayColumnOfDay(rowFirst);
      final sunday = monday + DateTime.daysPerWeek - 1;
      if (last < monday || first > sunday) {
        continue;
      }
      var from = -1;
      var to = -1;
      for (var col = 0; col < columns; col++) {
        final day = days[row * columns + col];
        if (day >= first && day <= last) {
          if (from < 0) {
            from = col;
          }
          to = col;
        }
      }
      if (from < 0) {
        continue;
      }
      placements.add(
        BoardPlacement<MonthChip>(
          MonthChip(
            key: monthSegmentKey(entry.id, dateOfDayNumber(monday)),
            entry: entry,
            continuesBefore: first < monday,
            continuesAfter: last > sunday,
          ),
          BoardSpan(rowStart: row, colStart: from, colSpan: to - from + 1),
        ),
      );
    }
  }
  return placements;
}

/// The month board's lane order among bars whose columns in a week are
/// the same: the item that starts on an earlier day first, then the one
/// covering more days, then the earlier start time, the title and the id.
/// The board orders bars by their first and their last column before it,
/// so a week's chips stack by the day each starts in the week, the longer
/// first, and a bar continuing from the week before stacks above a chip
/// starting on its first shown day.
int compareMonthChips(MonthChip a, MonthChip b) {
  final x = a.entry.item;
  final y = b.entry.item;
  // `day` is the first day at local midnight, so this compares days and
  // allocates nothing.
  final byDay = x.day.compareTo(y.day);
  if (byDay != 0) {
    return byDay;
  }
  final byLength = y.dayCount.compareTo(x.dayCount);
  if (byLength != 0) {
    return byLength;
  }
  final byStart = x.startMinute.compareTo(y.startMinute);
  if (byStart != 0) {
    return byStart;
  }
  final byTitle = x.title.compareTo(y.title);
  if (byTitle != 0) {
    return byTitle;
  }
  return a.entry.id.compareTo(b.entry.id);
}

/// The month of [grid] on the board, showing what [model] shows for its
/// days.
///
/// The weeks fill the board's height and grow, past that, to hold their
/// chips; the board then scrolls. Each day shows its number in a strip
/// across its top, today's in the primary colour and the selected day's on
/// the primary pill. Each item shows as one bar per calendar week it
/// covers, a chip one lane tall in its type's colours, square where it
/// continues into the week before or after; a pending item's chip is
/// dimmed and takes no tap. Lines part the weeks and the days, and each
/// day of another month lies on the background colour.
///
/// A tap on a chip reports [onOpenItem], on a day's number strip
/// [onOpenDay], and on the rest of a day [onCreateOnDay]; the last two
/// give the board the keyboard, whose arrow keys move the selected day and
/// report it through [onSelectDay]. While the days load, a progress
/// indicator covers the board, and after a failed read the error and a
/// Retry that reads again. A change of the model animates; a new month or
/// a new set of weekdays does not, and settles at once whatever chip was
/// still growing in or shrinking out. A new size alone refits the weeks
/// at once and leaves the chips' motion running.
class MonthBoard extends StatefulWidget {
  const MonthBoard({
    super.key,
    required this.model,
    required this.grid,
    required this.selectedDay,
    required this.today,
    required this.onSelectDay,
    required this.onOpenDay,
    required this.onCreateOnDay,
    required this.onOpenItem,
  });

  final CalendarModel model;

  /// The month the board shows.
  final MonthGrid grid;

  /// A shown day of [grid]'s month.
  final DateTime selectedDay;

  /// The day marked as today.
  final ValueListenable<DateTime> today;

  /// A key moved the selection onto this day.
  final ValueChanged<DateTime> onSelectDay;

  /// This day's number strip was tapped.
  final ValueChanged<DateTime> onOpenDay;

  /// This day's empty part was tapped.
  final ValueChanged<DateTime> onCreateOnDay;

  /// The chip of this item, which is not pending, was tapped.
  final ValueChanged<String> onOpenItem;

  @override
  State<MonthBoard> createState() {
    return _MonthBoardState();
  }
}

/// A chip the item builder built, and the payload it built it for.
typedef _KeptChip = ({MonthChip chip, Widget widget});

/// A day cell the cell builder built, and the day and selection it built
/// it for.
typedef _KeptDay = ({DateTime day, bool selected, Widget widget});

class _MonthBoardState extends State<MonthBoard> with TickerProviderStateMixin {
  /// The columns' width before the first layout, which replaces it.
  static const double _placeholderColumnWidth = 48.0;

  /// What the cell builder answers for a cell outside [MonthBoard.grid].
  static const Widget _outsideGrid = SizedBox.shrink();

  late final BoardController<String, MonthChip> _board;

  /// The vertical scroll, which [_revealSelected] reads.
  final ScrollController _scroll = ScrollController();

  /// The board's focus, which a tap on a day's strip or empty part asks
  /// for, so the arrow keys reach the board.
  final FocusNode _focusNode = FocusNode(debugLabel: "MonthBoard");

  /// Held in fields because `Board` replaces its delegate, and so rebuilds
  /// every cell and chip, whenever a builder it gets is not identical to
  /// the previous one; the selection config likewise.
  late final BoardCellBuilder<String, MonthChip> _cellBuilder = _buildDay;
  late final BoardItemBuilder<String, MonthChip> _itemBuilder = _buildChip;
  late final BoardSelectionConfig _selectionConfig = BoardSelectionConfig(
    mode: BoardSelectionMode.cell,
    onChanged: _handleBoardSelection,
  );

  /// [MonthBoard.today], which the kept day cells listen to, so a new
  /// listenable reaches the cells this state keeps.
  late final ValueNotifier<DateTime> _today = ValueNotifier<DateTime>(
    widget.today.value,
  );

  /// The grid, the week extent and the column width the axes were last
  /// given; null and zero before the first layout.
  MonthGrid? _fittedGrid;
  double _fitted = 0.0;
  double _columnWidth = 0.0;

  /// Whether the next layout sets the board's items: set at the start, by
  /// the model and by a new grid.
  bool _syncPending = true;

  /// Whether the last sync found its days ready.
  bool _syncedReady = false;

  /// Whether a sync still owes a reveal of the selected day: set at the
  /// start and by a new grid, cleared by the first sync after it that
  /// finds the days ready.
  bool _revealPending = true;

  /// Whether a frame will put [monthBoardAnimationStyle] back.
  bool _restoreScheduled = false;

  /// True only while this state writes the board's selection itself, so
  /// the write reports nothing to [MonthBoard.onSelectDay].
  bool _writingSelection = false;

  /// The chips the item builder returned, by chip key, kept so a payload
  /// that did not change returns the same instance and builds nothing.
  /// Holds no key but those the latest sync placed and those in [_dropped].
  final Map<String, _KeptChip> _chips = <String, _KeptChip>{};

  /// The day cells the cell builder returned, one entry per cell of the
  /// grid at `row * columnCount + col`, refilled with nulls for each new
  /// grid.
  late List<_KeptDay?> _days = _emptyDays(widget.grid);

  /// The board's background for [MonthBoard.grid], made once per grid, so
  /// a build that keeps the grid hands the board the same painter.
  late _MonthGridPainter _background = _MonthGridPainter(widget.grid);

  /// The latest sync's placements, by chip key.
  Map<String, BoardPlacement<MonthChip>> _placed =
      <String, BoardPlacement<MonthChip>>{};

  /// Over the animated syncs since the last sync that did not animate: the
  /// placements they stopped placing, by chip key, and the chip keys they
  /// started placing. Every exit and enter in flight is among them, since
  /// only an animated sync starts one; the controller's key reads cannot
  /// tell an exiting key from a retired one.
  final Map<String, BoardPlacement<MonthChip>> _dropped =
      <String, BoardPlacement<MonthChip>>{};
  final Set<String> _added = <String>{};

  @override
  void initState() {
    super.initState();
    final grid = widget.grid;
    _board = BoardController<String, MonthChip>(
      vsync: this,
      // Both replaced by the first layout, which knows the size.
      rows: _rowsConfig(grid, fittedWeekExtent(double.infinity, 1)),
      columns: BoardAxisConfig(
        axis: UniformAxis(grid.columnCount, _placeholderColumnWidth),
      ),
      keyOf: (chip) {
        return chip.key;
      },
      animationStyle: monthBoardAnimationStyle,
      laneOrder: compareMonthChips,
    );
    // Before the board subscribes, so it starts on the selected day and a
    // key moves from there.
    _writeSelection();
    widget.model.addListener(_handleModel);
    widget.today.addListener(_handleToday);
  }

  @override
  void didUpdateWidget(MonthBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.model != oldWidget.model) {
      oldWidget.model.removeListener(_handleModel);
      widget.model.addListener(_handleModel);
      _syncPending = true;
    }
    if (widget.today != oldWidget.today) {
      oldWidget.today.removeListener(_handleToday);
      widget.today.addListener(_handleToday);
      _today.value = widget.today.value;
    }
    final gridChanged = !_sameGrid(widget.grid, oldWidget.grid);
    if (gridChanged) {
      _syncPending = true;
      _revealPending = true;
      _days = _emptyDays(widget.grid);
      _background = _MonthGridPainter(widget.grid);
    }
    if (gridChanged || widget.selectedDay != oldWidget.selectedDay) {
      // Reaches the cells through the board's post-frame relay, since this
      // runs in the build.
      _writeSelection();
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_handleModel);
    widget.today.removeListener(_handleToday);
    // The board has unmounted by now: an element's children unmount
    // before its state disposes.
    _scroll.dispose();
    _focusNode.dispose();
    _board.dispose();
    _today.dispose();
    super.dispose();
  }

  static List<_KeptDay?> _emptyDays(MonthGrid grid) {
    return List<_KeptDay?>.filled(grid.weekCount * grid.columnCount, null);
  }

  static bool _sameGrid(MonthGrid a, MonthGrid b) {
    return a.year == b.year && a.month == b.month && a.weekdays == b.weekdays;
  }

  /// [weekCount] weeks resting at [fitted], each growing past it to its
  /// strip plus its lanes.
  static BoardAxisConfig _rowsConfig(MonthGrid grid, double fitted) {
    return BoardAxisConfig(
      axis: LazyContentAxis(grid.weekCount, fitted, minTrackExtent: fitted),
      laneExtent: monthLaneExtent,
      lanePadding: monthStripHeight,
    );
  }

  void _handleModel() {
    setState(() {
      _syncPending = true;
    });
  }

  void _handleToday() {
    _today.value = widget.today.value;
  }

  /// Whether the model shows exactly this grid's days, every one of them
  /// read. False for a build between the calendar taking a new month and
  /// the model showing it.
  bool get _daysReady {
    final model = widget.model;
    final grid = widget.grid;
    return model.status == CalendarLoadStatus.ready &&
        model.isShown(grid.firstDay, grid.lastDay);
  }

  /// Selects the selected day's cell on the board. The board reports the
  /// write at once, which [_handleBoardSelection] ignores while
  /// [_writingSelection] holds.
  void _writeSelection() {
    final cell = widget.grid.cellOf(widget.selectedDay);
    _writingSelection = true;
    try {
      _board.setSelection(BoardSelection(anchor: cell, focus: cell));
    } finally {
      _writingSelection = false;
    }
  }

  /// A key moved the board's selection: reports the day of its focus cell
  /// when the cell lies in the grid. Two keys before a frame both report,
  /// the second stepping from the cell the first selected.
  void _handleBoardSelection(BoardSelection selection) {
    if (_writingSelection) {
      return;
    }
    final focus = selection.focus;
    final grid = widget.grid;
    if (focus == null ||
        focus.row >= grid.weekCount ||
        focus.col >= grid.columnCount) {
      return;
    }
    widget.onSelectDay(grid.dateAt(focus.row, focus.col));
  }

  void _openDay(DateTime day) {
    _focusNode.requestFocus();
    widget.onOpenDay(day);
  }

  void _createOnDay(DateTime day) {
    _focusNode.requestFocus();
    widget.onCreateOnDay(day);
  }

  void _openItem(String id) {
    widget.onOpenItem(id);
  }

  /// Gives the board the axes [size] and the grid ask for and, when a sync
  /// is pending, the items the model shows on the grid's days, none while
  /// they are not ready, all in one batch and so one structural
  /// notification. Called from the layout callback, so the first frame
  /// lays the board out at its size.
  ///
  /// A sync animates only when it follows the model alone, its days are
  /// ready and the last sync's were. Any other sync runs under
  /// [BoardAnimationStyle.disabled], which [_scheduleStyleRestore] lifts,
  /// and settles in its batch every enter and exit in flight
  /// ([_setItemsSettled]). A refit alone leaves the style as it is, so the
  /// motion in flight runs on: the replaced axis lands its own track
  /// resizes, and a new row axis takes each week's first measurement
  /// without animating it.
  void _layoutBoard(Size size) {
    final grid = widget.grid;
    final fitted = fittedWeekExtent(size.height, grid.weekCount);
    final width = size.width.isFinite && size.width > 0.0
        ? size.width / grid.columnCount
        : _columnWidth;
    final fittedGrid = _fittedGrid;
    final rowsChanged =
        fittedGrid == null || !_sameGrid(grid, fittedGrid) || fitted != _fitted;
    final columnsChanged =
        width > 0.0 &&
        (width != _columnWidth ||
            _board.columns.axis.trackCount != grid.columnCount);
    final sync = _syncPending;
    if (!rowsChanged && !columnsChanged && !sync) {
      return;
    }
    final ready = _daysReady;
    final placements = !sync
        ? null
        : ready
        ? monthPlacementsOf(
            widget.model.itemsBetween(grid.firstDay, grid.lastDay),
            grid,
          )
        : const <BoardPlacement<MonthChip>>[];
    final next = <String, BoardPlacement<MonthChip>>{
      if (placements != null)
        for (final placement in placements) placement.item.key: placement,
    };
    final animated = !rowsChanged && !columnsChanged && ready && _syncedReady;
    final settles = placements != null && !animated;
    _board.runBatch(() {
      if (settles) {
        _board.animationStyle = BoardAnimationStyle.disabled;
      }
      if (rowsChanged) {
        // A new axis instance each time, so no measurement outlives its
        // month or its fit.
        _board.rows = _rowsConfig(grid, fitted);
      }
      if (columnsChanged) {
        _board.columns = BoardAxisConfig(
          axis: UniformAxis(grid.columnCount, width),
        );
      }
      if (placements == null) {
        return;
      }
      if (settles) {
        _setItemsSettled(placements, next);
      } else {
        _board.setItems(placements);
      }
    });
    if (settles) {
      _scheduleStyleRestore();
    }
    _fittedGrid = grid;
    _fitted = fitted;
    if (columnsChanged) {
      _columnWidth = width;
    }
    if (placements == null) {
      return;
    }
    if (animated) {
      _recordMotion(next);
    }
    _syncPending = false;
    _syncedReady = ready;
    _placed = next;
    // A key in `_dropped` may still be exiting: the board keeps its child
    // and calls the item builder for it on every delegate rebuild, which
    // must hand back the kept instance.
    _chips.removeWhere((key, kept) {
      return !next.containsKey(key) && !_dropped.containsKey(key);
    });
    if (_revealPending) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _revealSelected(grid, again: true);
      });
      if (ready) {
        _revealPending = false;
      }
    }
  }

  /// Records what the animated sync placing [next] starts: each key
  /// [_placed] holds and [next] lacks exits, each key [next] holds and
  /// [_placed] lacks enters.
  void _recordMotion(Map<String, BoardPlacement<MonthChip>> next) {
    for (final entry in _placed.entries) {
      if (!next.containsKey(entry.key)) {
        _dropped[entry.key] = entry.value;
        _added.remove(entry.key);
      }
    }
    for (final key in next.keys) {
      if (!_placed.containsKey(key)) {
        _added.add(key);
        _dropped.remove(key);
      }
    }
  }

  /// Sets [placements], whose placements by key are [next], under the
  /// disabled style, so that no enter or exit is in flight afterwards.
  ///
  /// With the item enter and exit family off, `setItems` brings back whole
  /// a key whose exit runs, adds whole a key the board holds no item for,
  /// and retires at once a key it leaves out, an entering one included.
  /// So the first call carries every dropped key [next] lacks, bringing
  /// back an exiting one, and leaves out every added key [next] holds,
  /// retiring an entering one; the second retires the carried keys and
  /// adds the left-out ones whole, under new ids. Inside the sync's batch
  /// the two calls make one notification.
  void _setItemsSettled(
    List<BoardPlacement<MonthChip>> placements,
    Map<String, BoardPlacement<MonthChip>> next,
  ) {
    final carry = <BoardPlacement<MonthChip>>[
      for (final entry in _dropped.entries)
        if (!next.containsKey(entry.key)) entry.value,
    ];
    final renew = <String>{
      for (final key in _added)
        if (next.containsKey(key)) key,
    };
    _dropped.clear();
    _added.clear();
    if (carry.isEmpty && renew.isEmpty) {
      _board.setItems(placements);
      return;
    }
    _board.setItems(<BoardPlacement<MonthChip>>[
      for (final placement in placements)
        if (!renew.contains(placement.item.key)) placement,
      ...carry,
    ]);
    _board.setItems(placements);
  }

  /// Puts [monthBoardAnimationStyle] back in a frame callback scheduled
  /// after the batch of the sync that disabled it, so it runs at the next
  /// frame's start, before that frame's layout and after the sync's own
  /// layout has measured the weeks under the disabled style. That sync
  /// left nothing in flight ([_setItemsSettled]), so a sync the next frame
  /// lays out animates.
  void _scheduleStyleRestore() {
    if (_restoreScheduled) {
      return;
    }
    _restoreScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _restoreScheduled = false;
      if (mounted) {
        _board.animationStyle = monthBoardAnimationStyle;
      }
    });
  }

  /// Scrolls the least that shows the selected day, while [scheduledFor]
  /// is still the grid. The first reveal of a new grid can read a week at
  /// its estimate, and the layout it causes measures that week, so a
  /// reveal that moved asks once more after it.
  void _revealSelected(MonthGrid scheduledFor, {required bool again}) {
    if (!mounted ||
        !_sameGrid(widget.grid, scheduledFor) ||
        !_scroll.hasClients) {
      return;
    }
    final before = _scroll.position.pixels;
    final cell = widget.grid.cellOf(widget.selectedDay);
    _board.revealCell(cell.row, cell.col);
    if (again && _scroll.position.pixels != before) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _revealSelected(scheduledFor, again: false);
      });
    }
  }

  Widget? _buildDay(
    BuildContext context,
    BoardCellView<String, MonthChip> cell,
  ) {
    final grid = widget.grid;
    // A key moving the selection rebuilds the cells whose answer changed in
    // the layout callback's build scope, after the callback hands the board
    // a new grid and before its layout drops the cells the grid lacks.
    if (cell.row >= grid.weekCount || cell.col >= grid.columnCount) {
      return _outsideGrid;
    }
    final index = cell.row * grid.columnCount + cell.col;
    final selected = cell.isSelected;
    final kept = _days[index];
    if (kept != null && kept.selected == selected) {
      return kept.widget;
    }
    final day = kept?.day ?? grid.dateAt(cell.row, cell.col);
    final built = _MonthDayCell(
      key: monthDayKey(day),
      day: day,
      inMonth: grid.contains(day),
      isSelected: selected,
      today: _today,
      onOpen: _openDay,
      onCreate: _createOnDay,
    );
    _days[index] = (day: day, selected: selected, widget: built);
    return built;
  }

  Widget _buildChip(
    BuildContext context,
    BoardItemView<String, MonthChip> view,
  ) {
    final chip = view.item;
    final kept = _chips[chip.key];
    if (kept != null && kept.chip == chip) {
      return kept.widget;
    }
    final built = Align(
      alignment: Alignment.topLeft,
      child: _MonthChipBox(
        key: monthChipKey(chip.key),
        chip: chip,
        onOpen: _openItem,
      ),
    );
    _chips[chip.key] = (chip: chip, widget: built);
    return built;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _layoutBoard(constraints.biggest);
        final model = widget.model;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: Board<String, MonthChip>(
                controller: _board,
                cellBuilder: _cellBuilder,
                itemBuilder: _itemBuilder,
                background: _background,
                selection: _selectionConfig,
                focusNode: _focusNode,
                // The board scrolls on its own, not with the screen's
                // primary scroll controller.
                primary: false,
                verticalDetails: ScrollableDetails.vertical(
                  controller: _scroll,
                ),
                // As wide as its lattice, so it never scrolls across.
                horizontalDetails: const ScrollableDetails.horizontal(
                  physics: NeverScrollableScrollPhysics(),
                ),
              ),
            ),
            if (!_daysReady)
              Positioned.fill(
                child: _MonthLoadOverlay(
                  error: model.status == CalendarLoadStatus.failed
                      ? model.error
                      : null,
                  onRetry: model.retry,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The month board's background: each day of another month on the
/// background colour, and a line in the outline colour between every two
/// weeks and every two shown weekdays, none around the board's edge.
class _MonthGridPainter extends BoardBackgroundPainter {
  _MonthGridPainter(this.grid)
    : _outside = <bool>[
        for (var row = 0; row < grid.weekCount; row++)
          for (var col = 0; col < grid.columnCount; col++)
            !grid.contains(grid.dateAt(row, col)),
      ];

  static final Paint _outsidePaint = Paint()..color = HarborColors.background;
  static final Paint _linePaint = Paint()
    ..color = HarborColors.outline
    ..strokeWidth = 1.0;

  final MonthGrid grid;

  /// Whether each cell of [grid], at `row * columnCount + col`, shows a day
  /// of another month.
  final List<bool> _outside;

  @override
  void paint(Canvas canvas, BoardGeometryView geometry) {
    final firstRow = geometry.firstVisibleRow;
    final lastRow = geometry.lastVisibleRow;
    final firstCol = geometry.firstVisibleCol;
    final lastCol = geometry.lastVisibleCol;
    if (firstRow > lastRow || firstCol > lastCol) {
      return;
    }
    final columns = grid.columnCount;
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = firstCol; col <= lastCol; col++) {
        if (_outside[row * columns + col]) {
          canvas.drawRect(geometry.visibleCellRect(row, col), _outsidePaint);
        }
      }
    }
    final first = geometry.visibleCellRect(firstRow, firstCol);
    final last = geometry.visibleCellRect(lastRow, lastCol);
    for (var row = math.max(firstRow, 1); row <= lastRow; row++) {
      final y = geometry.visibleCellRect(row, firstCol).top;
      canvas.drawLine(Offset(first.left, y), Offset(last.right, y), _linePaint);
    }
    for (var col = math.max(firstCol, 1); col <= lastCol; col++) {
      final x = geometry.visibleCellRect(firstRow, col).left;
      canvas.drawLine(Offset(x, first.top), Offset(x, last.bottom), _linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthGridPainter old) {
    return !_MonthBoardState._sameGrid(old.grid, grid);
  }
}

/// "Tuesday, April 21": [day] as the month board names it to a screen
/// reader.
String _dayLabel(DateTime day) {
  return "${weekdayNames[weekdayColumn(day)]}, "
      "${monthNames[day.month - 1]} ${day.day}";
}

/// What a screen reader says for [entry]'s chip: its title, type, days
/// and times, and that it is pending while it is.
String _chipLabel(ShownItem entry) {
  final item = entry.item;
  final times =
      "${clockLabel(item.startMinute)} to ${clockLabel(item.endMinute)}";
  final String when;
  if (item.dayCount == 1) {
    when = "${_dayLabel(item.day)}, $times";
  } else {
    final last = addDays(item.day, item.dayCount - 1);
    when = "${_dayLabel(item.day)} to ${_dayLabel(last)}, $times each day";
  }
  final label = "${item.title}, ${item.type.label}, $when";
  return entry.pending ? "$label, pending" : label;
}

/// One day of the month board: its empty part, where a tap creates, and
/// over it the number strip across the top, where a tap opens the day.
class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    super.key,
    required this.day,
    required this.inMonth,
    required this.isSelected,
    required this.today,
    required this.onOpen,
    required this.onCreate,
  });

  final DateTime day;

  /// Whether [day] is a day of the grid's month; another's number is
  /// muted.
  final bool inMonth;

  final bool isSelected;
  final ValueListenable<DateTime> today;
  final ValueChanged<DateTime> onOpen;
  final ValueChanged<DateTime> onCreate;

  @override
  Widget build(BuildContext context) {
    final name = weekdayNames[weekdayColumn(day)];
    final date = "${monthNames[day.month - 1]} ${day.day}";
    void create() {
      onCreate(day);
    }

    void open() {
      onOpen(day);
    }

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Semantics(
            button: true,
            label: "New item on $name, $date",
            onTap: create,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: create,
            ),
          ),
        ),
        // Not positioned, so a cell measures the strip's height and a week
        // with no chips rests at its fitted extent.
        SizedBox(
          key: monthStripKey(day),
          height: monthStripHeight,
          child: ValueListenableBuilder<DateTime>(
            valueListenable: today,
            builder: (context, today, child) {
              final isToday = day == today;
              return Semantics(
                button: true,
                selected: isSelected,
                label: isToday ? "$name, $date, today" : "$name, $date",
                hint: "Opens the day",
                onTap: open,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: open,
                  child: Center(child: _buildNumber(isToday)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNumber(bool isToday) {
    final Color color;
    if (isSelected) {
      color = HarborColors.onPrimary;
    } else if (isToday) {
      color = HarborColors.primary;
    } else if (inMonth) {
      color = HarborColors.text;
    } else {
      color = HarborColors.textMuted;
    }
    final number = Text(
      "${day.day}",
      style: TextStyle(
        fontSize: 13.0,
        fontWeight: isSelected || isToday ? FontWeight.w600 : FontWeight.w400,
        color: color,
      ),
    );
    if (!isSelected) {
      return number;
    }
    return Container(
      width: 30.0,
      height: 22.0,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HarborColors.primary,
        borderRadius: BorderRadius.circular(11.0),
      ),
      child: number,
    );
  }
}

/// One chip: a lane-tall box over its lane band's top, holding the bar
/// inside a 1 px inset. The bar is the type's tint with a 4 px edge in the
/// type's colour, as [HarborTypeStyle] draws an item, and the title on one
/// line, rounded at an end where the item starts or ends and square where
/// it continues. Dimmed while pending, when a tap on it does nothing.
class _MonthChipBox extends StatelessWidget {
  const _MonthChipBox({super.key, required this.chip, required this.onOpen});

  final MonthChip chip;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final entry = chip.entry;
    final item = entry.item;
    final pending = entry.pending;
    final style = harborTypeStyleOf(item.type);
    const radius = Radius.circular(4.0);
    void open() {
      onOpen(entry.id);
    }

    Widget bar = ClipRRect(
      borderRadius: BorderRadius.horizontal(
        left: chip.continuesBefore ? Radius.zero : radius,
        right: chip.continuesAfter ? Radius.zero : radius,
      ),
      child: ColoredBox(
        color: style.tint,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: 4.0, child: ColoredBox(color: style.edge)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w600,
                      color: HarborColors.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (pending) {
      bar = Opacity(opacity: 0.5, child: bar);
    }
    return Semantics(
      container: true,
      button: !pending,
      label: _chipLabel(entry),
      onTap: pending ? null : open,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: monthLaneExtent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Takes a tap while pending too, doing nothing, so neither the
          // day under the chip nor the board's own tap gets it.
          onTap: pending ? () {} : open,
          child: Padding(
            padding: const EdgeInsets.all(1.0),
            // The bar keeps its height while the board grows or shrinks
            // the chip's band, and is clipped to it.
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minHeight: monthLaneExtent - 2.0,
                maxHeight: monthLaneExtent - 2.0,
                child: bar,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Covers the board while its days are not ready, taking every press: a
/// progress indicator while it loads, the error and Retry when the read
/// failed. The timed grid's overlay looks and acts the same.
class _MonthLoadOverlay extends StatelessWidget {
  const _MonthLoadOverlay({required this.error, required this.onRetry});

  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error;
    // A ColoredBox hit-tests as opaque, so no press reaches the board.
    return ColoredBox(
      color: HarborColors.background.withValues(alpha: 0.85),
      child: Center(
        child: message == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: HarborColors.error),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  TextButton(onPressed: onRetry, child: const Text("Retry")),
                ],
              ),
      ),
    );
  }
}
