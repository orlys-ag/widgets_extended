/// The Harbor palette's contrast and tints, computed here from the hex
/// values with the WCAG 2 formula, and the theme built from it.
library;

import 'dart:math' as math;

import 'package:examples/workspace_calendar/calendar_schema.dart';
import 'package:examples/workspace_calendar/harbor_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An sRGB colour as three 8-bit channels, fractional after compositing.
typedef Rgb = ({double r, double g, double b});

Rgb rgbOf(Color color) {
  final argb = color.toARGB32();
  return (
    r: ((argb >> 16) & 0xFF).toDouble(),
    g: ((argb >> 8) & 0xFF).toDouble(),
    b: (argb & 0xFF).toDouble(),
  );
}

/// [top] at [opacity] over [bottom], blended per channel.
Rgb over(Rgb top, double opacity, Rgb bottom) {
  return (
    r: opacity * top.r + (1 - opacity) * bottom.r,
    g: opacity * top.g + (1 - opacity) * bottom.g,
    b: opacity * top.b + (1 - opacity) * bottom.b,
  );
}

double luminance(Rgb rgb) {
  double linear(double channel) {
    final c = channel / 255;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(rgb.r) +
      0.7152 * linear(rgb.g) +
      0.0722 * linear(rgb.b);
}

/// The WCAG 2 contrast ratio of [a] and [b], rounded to one decimal.
double contrast(Rgb a, Rgb b) {
  final la = luminance(a);
  final lb = luminance(b);
  final ratio = (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  return (ratio * 10).round() / 10;
}

/// The surfaces the palette defines: surface, background, the primary
/// tint and the four type tints.
Map<String, Color> surfaces() {
  return <String, Color>{
    "surface": HarborColors.surface,
    "background": HarborColors.background,
    "primary tint": HarborColors.primaryTint,
    for (final type in CalendarItemType.values)
      "${type.label} tint": harborTypeStyleOf(type).tint,
  };
}

void main() {
  test("H1 contrast", () {
    for (final entry in surfaces().entries) {
      final surface = rgbOf(entry.value);
      expect(
        contrast(rgbOf(HarborColors.text), surface),
        greaterThanOrEqualTo(12.4),
        reason: "text on ${entry.key}",
      );
      expect(
        contrast(rgbOf(HarborColors.textSecondary), surface),
        greaterThanOrEqualTo(6.0),
        reason: "secondary text on ${entry.key}",
      );
      expect(
        contrast(rgbOf(HarborColors.textMuted), surface),
        greaterThanOrEqualTo(4.6),
        reason: "muted text on ${entry.key}",
      );
      expect(
        contrast(rgbOf(HarborColors.primary), surface),
        greaterThanOrEqualTo(6.6),
        reason: "primary on ${entry.key}",
      );
    }
    expect(
      contrast(rgbOf(HarborColors.onPrimary), rgbOf(HarborColors.primary)),
      greaterThanOrEqualTo(8.3),
    );
    expect(
      contrast(rgbOf(HarborColors.error), rgbOf(HarborColors.surface)),
      greaterThanOrEqualTo(4.5),
    );

    // A block a move leaves behind fades, text and tint together, over
    // the fills the week grid paints under it.
    const fills = <String, Color>{
      "surface": HarborColors.surface,
      "background": HarborColors.background,
      "primary tint": HarborColors.primaryTint,
    };
    for (final type in CalendarItemType.values) {
      for (final fill in fills.entries) {
        final under = rgbOf(fill.value);
        const opacity = harborDraggedItemOpacity;
        final tint = over(rgbOf(harborTypeStyleOf(type).tint), opacity, under);
        expect(
          contrast(over(rgbOf(HarborColors.text), opacity, under), tint),
          greaterThanOrEqualTo(4.5),
          reason: "faded text on the ${type.label} tint over ${fill.key}",
        );
        expect(
          contrast(
            over(rgbOf(HarborColors.textSecondary), opacity, under),
            tint,
          ),
          greaterThanOrEqualTo(4.5),
          reason:
              "faded secondary text on the ${type.label} tint over "
              "${fill.key}",
        );
      }
    }
  });

  test("H2 tints", () {
    final white = rgbOf(const Color(0xFFFFFFFF));
    for (final type in CalendarItemType.values) {
      final style = harborTypeStyleOf(type);
      final expected = over(rgbOf(style.edge), 0.14, white);
      final tint = rgbOf(style.tint);
      expect(
        <double>[tint.r, tint.g, tint.b],
        pairwiseCompare<double, double>(
          <double>[expected.r, expected.g, expected.b],
          (actual, wanted) {
            return (actual - wanted).abs() <= 1.0;
          },
          "within one per channel",
        ),
        reason: type.label,
      );
    }
  });

  test("H3 the theme", () {
    final theme = buildHarborTheme();
    expect(theme.colorScheme.primary, const Color(0xFF1F4E8C));
    expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F6FA));
    expect(theme.splashFactory, InkRipple.splashFactory);
    final foreground = theme.textButtonTheme.style!.foregroundColor!;
    expect(
      foreground.resolve(<WidgetState>{WidgetState.disabled}),
      const Color(0xFF5B6677),
    );
    expect(foreground.resolve(<WidgetState>{}), isNull);
  });
}
