/// The Harbor palette: a mid-dark blue primary over light surfaces, the
/// colours and icon of each item type, the calendar theme its views draw
/// with, and the Material theme the calendar applies to itself.
library;

import 'package:material_ui/material_ui.dart';
import 'package:widgets_extended/widgets_extended.dart';

import 'calendar_schema.dart';

abstract final class HarborColors {
  static const Color primary = Color(0xFF1F4E8C);
  static const Color primaryTint = Color(0xFFE4ECF6);
  static const Color background = Color(0xFFF4F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color outline = Color(0xFFD6DEE8);
  static const Color text = Color(0xFF1B2433);
  static const Color textSecondary = Color(0xFF4A5568);
  static const Color textMuted = Color(0xFF5B6677);
  static const Color error = Color(0xFFB3261E);
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// A lighter blue than [primary], for the ring around today's number:
  /// 3:1 or more against [surface], [background] and [primaryTint], and
  /// lighter than [primary] where it rings a selected day's fill.
  static const Color todayRing = Color(0xFF4C86D0);

  /// A soft yellow for a notice row, with [noticeEdge] for its rule and
  /// [onNotice] for its text and icon.
  static const Color notice = Color(0xFFFFF4C2);
  static const Color noticeEdge = Color(0xFFF0D77A);
  static const Color onNotice = Color(0xFF5C4300);

  /// A soft red for a notice of something refused, with [errorNoticeEdge]
  /// for its rule and [onErrorNotice] for its text and icon.
  static const Color errorNotice = Color(0xFFFCE8E6);
  static const Color errorNoticeEdge = Color(0xFFF2B8B5);
  static const Color onErrorNotice = Color(0xFF8C1D18);

  /// The greys of a form field's box on [surface]: [fieldOutline] for its
  /// border, [fieldText] for its icon and value, [fieldTextDisabled] for
  /// those of a field that takes no input, and [fieldLabel] for the label
  /// above the box.
  static const Color fieldOutline = Color(0xFFEBEBEB);
  static const Color fieldText = Color(0xFF424242);
  static const Color fieldTextDisabled = Color(0xFF9B9B9B);
  static const Color fieldLabel = Color(0xFF6F6F6F);
}

/// How an item of one type is drawn: [tint] fills it, a 4 px [edge] runs
/// down its leading side, and [icon] marks its card.
@immutable
class HarborTypeStyle {
  const HarborTypeStyle({
    required this.edge,
    required this.tint,
    required this.icon,
  });

  final Color edge;

  /// [edge] at 14% over white.
  final Color tint;

  final IconData icon;
}

HarborTypeStyle harborTypeStyleOf(CalendarItemType type) {
  switch (type) {
    case CalendarItemType.task:
      return const HarborTypeStyle(
        edge: Color(0xFF1F4E8C),
        tint: Color(0xFFE0E6EF),
        icon: Icons.task_alt,
      );
    case CalendarItemType.risk:
      return const HarborTypeStyle(
        edge: Color(0xFFC2503A),
        tint: Color(0xFFF6E6E3),
        icon: Icons.warning_amber,
      );
    case CalendarItemType.request:
      return const HarborTypeStyle(
        edge: Color(0xFF5B5FA8),
        tint: Color(0xFFE8E9F3),
        icon: Icons.assignment,
      );
  }
}

/// The opacity of the block a move leaves behind on the timed grid, where
/// it marks the time the carried block came from.
const double harborDraggedItemOpacity = 0.66;

/// The groups the demo's motions run in, each a duration and a curve of the
/// framework's animation library, so none of them depends on a design
/// library: [quick] for a small control, a menu or a chip's remove button;
/// [standard], the calendar's own, for what moves, resizes or fades inside
/// a surface; and [surface] for a sheet or a snack bar coming in and
/// leaving, with [dialog] for a dialog's route, which has one duration.
///
/// A motion that reverses, as a closing does, eases out as its opening
/// does: a reverse reads its curve from 1 down to 0, so each group's
/// reverse curve is the flip ([FlippedCurve]) of the curve its reverse
/// runs on.
abstract final class HarborMotion {
  /// How long [quick] takes, each way.
  static const Duration quickDuration = Duration(milliseconds: 150);

  /// How long [standard] takes, each way.
  static const Duration standardDuration = Duration(milliseconds: 300);

  /// How long a surface takes to come in.
  static const Duration surfaceInDuration = Duration(milliseconds: 400);

  /// How long a surface takes to leave.
  static const Duration surfaceOutDuration = Duration(milliseconds: 200);

  /// The curve [quick] and [standard] ease on: it starts from rest, covers
  /// half its distance in the first fifth of its time, and settles over the
  /// rest.
  static const Curve standardCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  /// The curve a surface comes in on: it arrives fast and settles.
  static const Curve surfaceInCurve = Cubic(0.05, 0.7, 0.1, 1.0);

  /// The curve a surface leaves on: it starts slowly and speeds away.
  static const Curve surfaceOutCurve = Cubic(0.3, 0.0, 0.8, 0.15);

  /// A small control's motion: [quickDuration] each way, on
  /// [standardCurve].
  static const AnimationStyle quick = AnimationStyle(
    duration: quickDuration,
    reverseDuration: quickDuration,
    curve: standardCurve,
    reverseCurve: FlippedCurve(standardCurve),
  );

  /// A motion inside a surface: [standardDuration] each way, on
  /// [standardCurve].
  static const AnimationStyle standard = AnimationStyle(
    duration: standardDuration,
    reverseDuration: standardDuration,
    curve: standardCurve,
    reverseCurve: FlippedCurve(standardCurve),
  );

  /// A surface's motion: in over [surfaceInDuration] on [surfaceInCurve],
  /// and out over [surfaceOutDuration] on [surfaceOutCurve].
  static const AnimationStyle surface = AnimationStyle(
    duration: surfaceInDuration,
    reverseDuration: surfaceOutDuration,
    curve: surfaceInCurve,
    reverseCurve: FlippedCurve(surfaceOutCurve),
  );

  /// A dialog's motion: a surface's curves, over [surfaceOutDuration] both
  /// ways, since a dialog's route takes its one duration from
  /// [AnimationStyle.duration] and reverses over it too
  /// ([TransitionRoute.reverseTransitionDuration]).
  static const AnimationStyle dialog = AnimationStyle(
    duration: surfaceOutDuration,
    reverseDuration: surfaceOutDuration,
    curve: surfaceInCurve,
    reverseCurve: FlippedCurve(surfaceOutCurve),
  );

  /// Whether [context] may animate: false where the platform asks for no
  /// animations ([MediaQuery.disableAnimationsOf]), and true where it does
  /// not or [context] has no [MediaQuery].
  static bool animates(BuildContext context) {
    return !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  }

  /// [style] where [context] [animates], and [AnimationStyle.noAnimation]
  /// where it does not.
  static AnimationStyle of(BuildContext context, AnimationStyle style) {
    return animates(context) ? style : AnimationStyle.noAnimation;
  }

  /// [duration] where [context] [animates], and [Duration.zero] where it
  /// does not.
  static Duration durationOf(BuildContext context, Duration duration) {
    return animates(context) ? duration : Duration.zero;
  }
}

/// How long each animation the calendar runs takes: the month's fold into
/// its week, and every animation of the timed grid and the day list;
/// [HarborMotion.standardDuration].
const Duration harborMotionDuration = HarborMotion.standardDuration;

/// The curve each animation the calendar runs eases on;
/// [HarborMotion.standardCurve].
const Curve harborMotionCurve = HarborMotion.standardCurve;

/// The calendar views' theme in the Harbor palette: each colour the
/// [HarborColors] value of its name, the notice outline [HarborColors.noticeEdge],
/// [harborDraggedItemOpacity], [harborMotionDuration] on
/// [harborMotionCurve], and the Material icons the views draw, over the
/// built-in text styles and shadows.
final CalendarThemeData harborCalendarTheme = CalendarThemeData(
  primary: HarborColors.primary,
  onPrimary: HarborColors.onPrimary,
  primaryTint: HarborColors.primaryTint,
  background: HarborColors.background,
  surface: HarborColors.surface,
  outline: HarborColors.outline,
  text: HarborColors.text,
  textSecondary: HarborColors.textSecondary,
  textMuted: HarborColors.textMuted,
  error: HarborColors.error,
  notice: HarborColors.notice,
  noticeOutline: HarborColors.noticeEdge,
  onNotice: HarborColors.onNotice,
  todayRing: HarborColors.todayRing,
  todayRingWidth: 2.0,
  draggedBlockOpacity: harborDraggedItemOpacity,
  motionDuration: harborMotionDuration,
  motionCurve: harborMotionCurve,
  beforeHoursIcon: Icons.keyboard_arrow_up,
  afterHoursIcon: Icons.keyboard_arrow_down,
  durationIcon: Icons.hourglass_empty,
  entryMenuIcon: Icons.more_horiz,
  addEntryIcon: Icons.add,
);

/// The calendar's own Material 3 theme, independent of the host's.
ThemeData buildHarborTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: HarborColors.primary,
    onPrimary: HarborColors.onPrimary,
    primaryContainer: HarborColors.primaryTint,
    onPrimaryContainer: HarborColors.primary,
    secondary: HarborColors.primary,
    onSecondary: HarborColors.onPrimary,
    secondaryContainer: HarborColors.primaryTint,
    onSecondaryContainer: HarborColors.primary,
    error: HarborColors.error,
    onError: HarborColors.onPrimary,
    surface: HarborColors.surface,
    onSurface: HarborColors.text,
    onSurfaceVariant: HarborColors.textSecondary,
    surfaceContainerLowest: HarborColors.surface,
    surfaceContainerLow: HarborColors.surface,
    surfaceContainer: HarborColors.surface,
    surfaceContainerHigh: HarborColors.surface,
    surfaceContainerHighest: HarborColors.surface,
    outline: HarborColors.outline,
    outlineVariant: HarborColors.outline,
    inverseSurface: HarborColors.text,
    onInverseSurface: HarborColors.onPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: HarborColors.background,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: HarborColors.primary,
      foregroundColor: HarborColors.onPrimary,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: HarborColors.primary,
      foregroundColor: HarborColors.onPrimary,
    ),
    // Null for every state but disabled keeps an enabled button's default
    // foreground; a disabled one would otherwise take onSurface at 38%,
    // too faint on white.
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return HarborColors.textMuted;
          }
          return null;
        }),
      ),
    ),
  );
}
