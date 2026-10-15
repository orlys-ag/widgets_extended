/// The Harbor palette: a mid-dark blue primary over light surfaces, the
/// colours and icon of each item type, and the theme the calendar applies
/// to itself.
library;

import 'package:flutter/material.dart';

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
    case CalendarItemType.meeting:
      return const HarborTypeStyle(
        edge: Color(0xFF1F7A72),
        tint: Color(0xFFE0ECEB),
        icon: Icons.groups,
      );
    case CalendarItemType.outOfOffice:
      return const HarborTypeStyle(
        edge: Color(0xFF5B5FA8),
        tint: Color(0xFFE8E9F3),
        icon: Icons.flight_takeoff,
      );
    case CalendarItemType.deadline:
      return const HarborTypeStyle(
        edge: Color(0xFFC2503A),
        tint: Color(0xFFF6E6E3),
        icon: Icons.flag,
      );
  }
}

/// The opacity of the block a move leaves behind on the week grid. High
/// enough that its text keeps its contrast against its own faded tint.
const double harborDraggedItemOpacity = 0.9;

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
