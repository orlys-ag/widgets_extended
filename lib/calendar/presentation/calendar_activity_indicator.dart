/// The calendar's activity indicator: a turning arc that needs no Material
/// ancestor.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'calendar_theme.dart';

/// An arc of three quarters of a turn, turning once each [period] while the
/// theme's [CalendarThemeData.motionDuration] is positive, and standing at
/// the top while it is zero.
///
/// A frame of the turn repaints the arc alone, under a [RepaintBoundary]
/// of its own: nothing builds or lays out for it. A disabled [TickerMode]
/// stops the turn.
class CalendarActivityIndicator extends StatefulWidget {
  /// An arc of [strokeWidth] in a square of [size], in [color] or the
  /// theme's [CalendarThemeData.primary].
  const CalendarActivityIndicator({
    super.key,
    this.size = 36.0,
    this.strokeWidth = 4.0,
    this.color,
  });

  /// The side of the square the arc is drawn in, in logical pixels of the
  /// indicator's own space.
  final double size;

  /// The width of the arc's stroke, in logical pixels of the indicator's
  /// own space; the arc lies inside the square by half of it.
  final double strokeWidth;

  /// The arc's colour; null for the theme's [CalendarThemeData.primary].
  final Color? color;

  /// The time of one turn.
  static const Duration period = Duration(seconds: 1);

  @override
  State<CalendarActivityIndicator> createState() {
    return _CalendarActivityIndicatorState();
  }
}

class _CalendarActivityIndicatorState extends State<CalendarActivityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: CalendarActivityIndicator.period,
  );

  late CalendarThemeData _theme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = CalendarTheme.of(context);
    // The one site that resolves the indicator's motion: the theme's
    // switch for every motion the views run.
    if (_theme.motionDuration > Duration.zero) {
      if (!_turn.isAnimating) {
        _turn.repeat();
      }
    } else {
      _turn.reset();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _ArcPainter(
            turn: _turn,
            color: widget.color ?? _theme.primary,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

/// Paints the arc at the [turn]'s progress, repainting from it, with one
/// [Paint] and the arc's rect kept for the last size it painted at.
class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.turn,
    required this.color,
    required this.strokeWidth,
  }) : _paint = Paint()
         ..color = color
         ..style = PaintingStyle.stroke
         ..strokeCap = StrokeCap.round
         ..strokeWidth = strokeWidth,
       super(repaint: turn);

  final Animation<double> turn;
  final Color color;
  final double strokeWidth;
  final Paint _paint;
  Size? _size;
  Rect _rect = Rect.zero;

  @override
  void paint(Canvas canvas, Size size) {
    if (size != _size) {
      _size = size;
      final inset = strokeWidth / 2.0;
      _rect = Rect.fromLTWH(
        inset,
        inset,
        size.width - strokeWidth,
        size.height - strokeWidth,
      );
    }
    canvas.drawArc(
      _rect,
      -math.pi / 2.0 + 2.0 * math.pi * turn.value,
      3.0 * math.pi / 2.0,
      false,
      _paint,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) {
    return !identical(oldDelegate.turn, turn) ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
