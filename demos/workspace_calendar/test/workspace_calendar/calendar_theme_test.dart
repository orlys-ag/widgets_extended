/// The calendar views, and Harbor's builders they draw their items and
/// states with, draw what [CalendarTheme] holds: two sentinel themes,
/// whose every value differs from Harbor's, from the built-in ones and from
/// each other in each field the views and Harbor's builders read, and a
/// probe that reads what each view paints.
library;

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_bar.dart';
import 'package:widgets_extended/calendar/dates/calendar_dates.dart';
import 'package:widgets_extended/calendar/dates/calendar_labels.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/calendar/views/day_list.dart';
import 'package:widgets_extended/calendar/views/month_board.dart';
import 'package:widgets_extended/calendar/views/month_picker.dart';
import 'package:widgets_extended/calendar/views/week_strip.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_item.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/item_builders.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar_example.dart';

import 'calendar_harness.dart';

/// The fourteen colour fields, numbered from 1 in this order.
const List<String> colourNames = <String>[
  "primary",
  "onPrimary",
  "primaryTint",
  "background",
  "surface",
  "outline",
  "text",
  "textSecondary",
  "textMuted",
  "error",
  "notice",
  "noticeOutline",
  "onNotice",
  "todayRing",
];

/// The five icon fields.
const List<String> iconNames = <String>[
  "beforeHoursIcon",
  "afterHoursIcon",
  "durationIcon",
  "entryMenuIcon",
  "addEntryIcon",
];

/// The thirty-one text style fields the views and Harbor's builders read,
/// numbered from 1 in this order.
const List<String> styleNames = <String>[
  "hourLabelStyle",
  "dayHeaderWeekdayStyle",
  "dayHeaderNumberStyle",
  "blockTitleStyle",
  "blockSummaryStyle",
  "detailedBlockTitleStyle",
  "detailedBlockDetailStyle",
  "landingLabelStyle",
  "badgeStyle",
  "noticeStyle",
  "messageStyle",
  "monthDayNumberStyle",
  "monthDayNumberMarkedStyle",
  "monthMoreStyle",
  "chipTitleStyle",
  "monthCardTitleStyle",
  "monthCardTimeStyle",
  "agendaHeaderTitleStyle",
  "agendaHeaderEmptyTitleStyle",
  "agendaHeaderCountStyle",
  "agendaHeaderEmptyCountStyle",
  "agendaTimeStyle",
  "entryCardTitleStyle",
  "entryCardSummaryStyle",
  "dayNumberStyle",
  "dayNumberMarkedStyle",
  "stripWeekdayStyle",
  "weekdayHeaderStyle",
  "weekdayLetterStyle",
  "monthNameStyle",
  "monthNameMarkedStyle",
];

List<Color> coloursOf(CalendarThemeData theme) {
  return <Color>[
    theme.primary,
    theme.onPrimary,
    theme.primaryTint,
    theme.background,
    theme.surface,
    theme.outline,
    theme.text,
    theme.textSecondary,
    theme.textMuted,
    theme.error,
    theme.notice,
    theme.noticeOutline,
    theme.onNotice,
    theme.todayRing,
  ];
}

List<IconData> iconsOf(CalendarThemeData theme) {
  return <IconData>[
    theme.beforeHoursIcon,
    theme.afterHoursIcon,
    theme.durationIcon,
    theme.entryMenuIcon,
    theme.addEntryIcon,
  ];
}

List<TextStyle> stylesOf(CalendarThemeData theme) {
  return <TextStyle>[
    theme.hourLabelStyle,
    theme.dayHeaderWeekdayStyle,
    theme.dayHeaderNumberStyle,
    theme.blockTitleStyle,
    theme.blockSummaryStyle,
    theme.detailedBlockTitleStyle,
    theme.detailedBlockDetailStyle,
    theme.landingLabelStyle,
    theme.badgeStyle,
    theme.noticeStyle,
    theme.messageStyle,
    theme.monthDayNumberStyle,
    theme.monthDayNumberMarkedStyle,
    theme.monthMoreStyle,
    theme.chipTitleStyle,
    theme.monthCardTitleStyle,
    theme.monthCardTimeStyle,
    theme.agendaHeaderTitleStyle,
    theme.agendaHeaderEmptyTitleStyle,
    theme.agendaHeaderCountStyle,
    theme.agendaHeaderEmptyCountStyle,
    theme.agendaTimeStyle,
    theme.entryCardTitleStyle,
    theme.entryCardSummaryStyle,
    theme.dayNumberStyle,
    theme.dayNumberMarkedStyle,
    theme.stripWeekdayStyle,
    theme.weekdayHeaderStyle,
    theme.weekdayLetterStyle,
    theme.monthNameStyle,
    theme.monthNameMarkedStyle,
  ];
}

/// [colour]'s red, green and blue, without its alpha.
int rgbOf(Color colour) {
  return colour.toARGB32() & 0xFFFFFF;
}

/// The letter spacing that tags text style [index], numbered from 1, in a
/// sentinel whose tags start after [offset].
double tagOf(int index, int offset) {
  return 0.001 * (offset + index);
}

/// A theme whose colour field i is `colourBase + i` and whose text style i
/// is the built-in one with the letter spacing [tagOf] i, after [adjust]
/// changes the styles it names.
CalendarThemeData sentinelOf({
  required int colourBase,
  required int tagOffset,
  required Duration duration,
  required Curve curve,
  required double ring,
  required double opacity,
  required List<IconData> icons,
  Map<String, TextStyle Function(TextStyle style)> adjust =
      const <String, TextStyle Function(TextStyle style)>{},
}) {
  const builtIn = CalendarThemeData();
  final builtInStyles = stylesOf(builtIn);
  Color colour(String name) {
    return Color(colourBase + colourNames.indexOf(name) + 1);
  }

  TextStyle style(String name) {
    final index = styleNames.indexOf(name);
    final tagged = builtInStyles[index].copyWith(
      letterSpacing: tagOf(index + 1, tagOffset),
    );
    final change = adjust[name];
    return change == null ? tagged : change(tagged);
  }

  return CalendarThemeData(
    primary: colour("primary"),
    onPrimary: colour("onPrimary"),
    primaryTint: colour("primaryTint"),
    background: colour("background"),
    surface: colour("surface"),
    outline: colour("outline"),
    text: colour("text"),
    textSecondary: colour("textSecondary"),
    textMuted: colour("textMuted"),
    error: colour("error"),
    notice: colour("notice"),
    noticeOutline: colour("noticeOutline"),
    onNotice: colour("onNotice"),
    todayRing: colour("todayRing"),
    todayRingWidth: ring,
    draggedBlockOpacity: opacity,
    motionDuration: duration,
    motionCurve: curve,
    beforeHoursIcon: icons[0],
    afterHoursIcon: icons[1],
    durationIcon: icons[2],
    entryMenuIcon: icons[3],
    addEntryIcon: icons[4],
    hourLabelStyle: style("hourLabelStyle"),
    dayHeaderWeekdayStyle: style("dayHeaderWeekdayStyle"),
    dayHeaderNumberStyle: style("dayHeaderNumberStyle"),
    blockTitleStyle: style("blockTitleStyle"),
    blockSummaryStyle: style("blockSummaryStyle"),
    detailedBlockTitleStyle: style("detailedBlockTitleStyle"),
    detailedBlockDetailStyle: style("detailedBlockDetailStyle"),
    landingLabelStyle: style("landingLabelStyle"),
    badgeStyle: style("badgeStyle"),
    noticeStyle: style("noticeStyle"),
    messageStyle: style("messageStyle"),
    monthDayNumberStyle: style("monthDayNumberStyle"),
    monthDayNumberMarkedStyle: style("monthDayNumberMarkedStyle"),
    monthMoreStyle: style("monthMoreStyle"),
    chipTitleStyle: style("chipTitleStyle"),
    monthCardTitleStyle: style("monthCardTitleStyle"),
    monthCardTimeStyle: style("monthCardTimeStyle"),
    agendaHeaderTitleStyle: style("agendaHeaderTitleStyle"),
    agendaHeaderEmptyTitleStyle: style("agendaHeaderEmptyTitleStyle"),
    agendaHeaderCountStyle: style("agendaHeaderCountStyle"),
    agendaHeaderEmptyCountStyle: style("agendaHeaderEmptyCountStyle"),
    agendaTimeStyle: style("agendaTimeStyle"),
    entryCardTitleStyle: style("entryCardTitleStyle"),
    entryCardSummaryStyle: style("entryCardSummaryStyle"),
    dayNumberStyle: style("dayNumberStyle"),
    dayNumberMarkedStyle: style("dayNumberMarkedStyle"),
    stripWeekdayStyle: style("stripWeekdayStyle"),
    weekdayHeaderStyle: style("weekdayHeaderStyle"),
    weekdayLetterStyle: style("weekdayLetterStyle"),
    monthNameStyle: style("monthNameStyle"),
    monthNameMarkedStyle: style("monthNameMarkedStyle"),
  );
}

/// The first sentinel: 900 ms on [Curves.linear], a 3 px ring, the
/// dragged block at 0.4, and the hour labels at size 9.
final CalendarThemeData sentinelA = sentinelOf(
  colourBase: 0xFF2A0000,
  tagOffset: 0,
  duration: const Duration(milliseconds: 900),
  curve: Curves.linear,
  ring: 3.0,
  opacity: 0.4,
  icons: const <IconData>[
    Icons.north,
    Icons.south,
    Icons.timer,
    Icons.menu,
    Icons.add_circle,
  ],
  adjust: <String, TextStyle Function(TextStyle style)>{
    "hourLabelStyle": (style) {
      return style.copyWith(fontSize: 9.0);
    },
    "dayNumberStyle": (style) {
      return style.copyWith(fontWeight: FontWeight.w300);
    },
    "dayNumberMarkedStyle": (style) {
      return style.copyWith(fontWeight: FontWeight.w800);
    },
  },
);

/// The second sentinel: 600 ms on [Curves.easeIn], a 4 px ring, the
/// dragged block at 0.3, the hour labels at size 10, the strip's weekday
/// names at size 13, and the other measured styles, the notice text, the
/// picker's marked month and Agenda's day title, a size smaller than the
/// built-in ones.
final CalendarThemeData sentinelB = sentinelOf(
  colourBase: 0xFF2B0000,
  tagOffset: 40,
  duration: const Duration(milliseconds: 600),
  curve: Curves.easeIn,
  ring: 4.0,
  opacity: 0.3,
  icons: const <IconData>[
    Icons.arrow_upward,
    Icons.arrow_downward,
    Icons.schedule,
    Icons.more_vert,
    Icons.add_box,
  ],
  adjust: <String, TextStyle Function(TextStyle style)>{
    "hourLabelStyle": (style) {
      return style.copyWith(fontSize: 10.0);
    },
    "dayNumberStyle": (style) {
      return style.copyWith(fontWeight: FontWeight.w200);
    },
    "dayNumberMarkedStyle": (style) {
      return style.copyWith(fontWeight: FontWeight.w900);
    },
    "stripWeekdayStyle": (style) {
      return style.copyWith(fontSize: 13.0);
    },
    "noticeStyle": (style) {
      return style.copyWith(fontSize: 11.0);
    },
    "monthNameMarkedStyle": (style) {
      return style.copyWith(fontSize: 14.0);
    },
    "agendaHeaderTitleStyle": (style) {
      return style.copyWith(fontSize: 15.0);
    },
  },
);

/// The tag of each text style of [theme], by field.
Map<double, String> tagsOf(CalendarThemeData theme) {
  final styles = stylesOf(theme);
  return <double, String>{
    for (var i = 0; i < styles.length; i++)
      if (styles[i].letterSpacing != null)
        styles[i].letterSpacing!: styleNames[i],
  };
}

/// The colours, icon of each item type.
final List<Color> typeColours = <Color>[
  for (final type in CalendarItemType.values) ...<Color>[
    harborTypeStyleOf(type).edge,
    harborTypeStyleOf(type).tint,
  ],
];

final List<IconData> typeIcons = <IconData>[
  for (final type in CalendarItemType.values) harborTypeStyleOf(type).icon,
];

/// The clock of [pumpThemed]: 09:30 on [today].
DateTime clockAtNineThirty() {
  return DateTime(2026, 4, 21, 9, 30);
}

/// An item envelope of [type] titled [title] on [day] from [start] to
/// [end] minutes after midnight, with [fields].
Map<String, Object?> itemJson(
  CalendarItemType type,
  String title,
  DateTime day,
  int start,
  int end,
  Map<String, Object?> fields,
) {
  return <String, Object?>{
    "type": type.id,
    "title": title,
    "day": isoDate(day),
    "startMinute": start,
    "endMinute": end,
    "dayCount": 1,
    "fields": fields,
  };
}

/// The seed of [pumpThemed], which has no task, whose edge is
/// [HarborColors.primary]'s value: on Tuesday 21 a meeting from 09:00 to
/// 10:00 with a location; on Wednesday 22 meetings from 07:00 to 09:00 and
/// from 17:00 to 19:00; on Thursday 23 deadlines from 05:00 to 06:00 and
/// from 20:00 to 21:00; on Friday 24 seven 30-minute meetings from 08:00;
/// on Saturday 25 an out-of-office from 09:00 to 12:00; and nothing on
/// Monday 20.
List<Map<String, Object?>> themeSeed() {
  const meeting = CalendarItemType.meeting;
  const deadline = CalendarItemType.deadline;
  return <Map<String, Object?>>[
    itemJson(meeting, "Planning", DateTime(2026, 4, 21), 9 * 60, 10 * 60, {
      "location": "Room 2",
    }),
    itemJson(meeting, "Early sync", DateTime(2026, 4, 22), 7 * 60, 9 * 60, {
      "location": "Room 3",
    }),
    itemJson(meeting, "Late sync", DateTime(2026, 4, 22), 17 * 60, 19 * 60, {
      "location": "Room 4",
    }),
    itemJson(deadline, "Report", DateTime(2026, 4, 23), 5 * 60, 6 * 60, {
      "project": "Atlas",
    }),
    itemJson(deadline, "Release", DateTime(2026, 4, 23), 20 * 60, 21 * 60, {
      "project": "Atlas",
    }),
    for (var i = 0; i < 7; i++)
      itemJson(
        meeting,
        "Slot ${i + 1}",
        DateTime(2026, 4, 24),
        8 * 60 + 30 * i,
        8 * 60 + 30 * (i + 1),
        <String, Object?>{},
      ),
    itemJson(
      CalendarItemType.outOfOffice,
      "Away",
      DateTime(2026, 4, 25),
      9 * 60,
      12 * 60,
      {"reason": "travel"},
    ),
  ];
}

/// The app [pumpThemed] pumps, under [theme].
Widget themedApp(MockCalendarApi api, CalendarThemeData theme) {
  return MaterialApp(
    // The M3 ink sparkle shader cannot load under the test binding.
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: WorkspaceCalendarExample(
      editing: true,
      today: today,
      clock: clockAtNineThirty,
      api: api,
      calendarTheme: theme,
    ),
  );
}

/// Pumps the editing calendar on [today] at 09:30 under [theme], over the
/// [themeSeed] at [harnessLatency] with [failurePolicy], at [size], and
/// settles. Returns the mock.
Future<MockCalendarApi> pumpThemed(
  WidgetTester tester,
  CalendarThemeData theme, {
  Size size = const Size(390.0, 844.0),
  CalendarFailurePolicy? failurePolicy,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final api = MockCalendarApi(
    seed: themeSeed(),
    latency: harnessLatency,
    failurePolicy: failurePolicy,
  );
  // A calendar pumped before in the same test goes, so this one starts
  // anew over [api].
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(themedApp(api, theme));
  await tester.pump(api.latency);
  await tester.pumpAndSettle();
  return api;
}

/// Installs [theme] over the calendar [api] serves: one frame.
Future<void> installTheme(
  WidgetTester tester,
  MockCalendarApi api,
  CalendarThemeData theme,
) {
  return tester.pumpWidget(themedApp(api, theme));
}

/// What the probe found drawn under its roots.
class Drawn {
  /// The colour of every [Paint] the roots painted with, every span's
  /// colour, and the colours passed to [Material] and [PopupMenuButton].
  final List<Color> colours = <Color>[];

  /// The root span's style of every paragraph painted, but an icon's.
  final List<TextStyle> styles = <TextStyle>[];

  /// Every paragraph painted, icons included.
  final List<RenderParagraph> paragraphs = <RenderParagraph>[];

  /// Every [Icon]'s data.
  final List<IconData> icons = <IconData>[];

  /// The border width of every ring: each foreground decoration's.
  final List<double> rings = <double>[];

  /// Every alpha pushed through [PaintingContext.pushOpacity].
  final List<int> alphas = <int>[];

  /// The red, green and blue of [colours].
  Set<int> get rgbs {
    return <int>{for (final colour in colours) rgbOf(colour)};
  }

  /// The letter spacings of [styles].
  Set<double?> get spacings {
    return <double?>{for (final style in styles) style.letterSpacing};
  }
}

/// A recording context that paints no child in [skip], notes each
/// paragraph it paints, and records each alpha pushed. Its opacity layer
/// is the one handed in, or a new one it does not keep: the board keeps
/// the layer a push returns in its own handle, so this context must not
/// dispose it.
class _ProbeContext extends TestRecordingPaintingContext {
  _ProbeContext(super.canvas, this.skip, this.drawn);

  final Set<RenderObject> skip;
  final Drawn drawn;

  @override
  void paintChild(RenderObject child, Offset offset) {
    if (skip.contains(child)) {
      return;
    }
    if (child is RenderParagraph) {
      drawn.paragraphs.add(child);
    }
    super.paintChild(child, offset);
  }

  @override
  OpacityLayer pushOpacity(
    Offset offset,
    int alpha,
    PaintingContextCallback painter, {
    OpacityLayer? oldLayer,
  }) {
    drawn.alphas.add(alpha);
    painter(this, offset);
    return oldLayer ?? OpacityLayer();
  }
}

/// Paints each of [roots]' render objects into a recording context, past
/// every [CircularProgressIndicator] and [TextButton], whose colours the
/// ambient [ThemeData] resolves, and reads what it drew.
Drawn drawnUnder(WidgetTester tester, List<Finder> roots) {
  final drawn = Drawn();
  final skip = <RenderObject>{};
  for (final root in roots) {
    for (final type in <Type>[CircularProgressIndicator, TextButton]) {
      for (final element
          in find
              .descendant(of: root, matching: find.byType(type))
              .evaluate()) {
        skip.add(element.renderObject!);
      }
    }
  }
  for (final root in roots) {
    for (final element in root.evaluate()) {
      final canvas = TestRecordingCanvas();
      final context = _ProbeContext(canvas, skip, drawn);
      final renderObject = element.renderObject!;
      if (renderObject is RenderParagraph) {
        drawn.paragraphs.add(renderObject);
      }
      renderObject.paint(context, Offset.zero);
      context.dispose();
      for (final call in canvas.invocations) {
        for (final argument in call.invocation.positionalArguments) {
          if (argument is Paint) {
            drawn.colours.add(argument.color);
          }
        }
      }
    }
    for (final material in tester.widgetList<Material>(
      find.descendant(of: root, matching: find.byType(Material)),
    )) {
      final colour = material.color;
      if (colour != null) {
        drawn.colours.add(colour);
      }
    }
    for (final menu in tester.widgetList<PopupMenuButton<Object?>>(
      find.descendant(
        of: root,
        matching: find.byWidgetPredicate((widget) {
          return widget is PopupMenuButton;
        }),
      ),
    )) {
      final colour = menu.color;
      if (colour != null) {
        drawn.colours.add(colour);
      }
    }
    for (final icon in tester.widgetList<Icon>(
      find.descendant(of: root, matching: find.byType(Icon)),
    )) {
      final data = icon.icon;
      if (data != null) {
        drawn.icons.add(data);
      }
    }
    for (final box in tester.widgetList<DecoratedBox>(
      find.descendant(
        of: root,
        matching: find.byWidgetPredicate((widget) {
          return widget is DecoratedBox &&
              widget.position == DecorationPosition.foreground;
        }),
      ),
    )) {
      final border = (box.decoration as BoxDecoration).border;
      if (border is Border) {
        drawn.rings.add(border.top.width);
      }
    }
  }
  for (final paragraph in drawn.paragraphs) {
    paragraph.text.visitChildren((span) {
      final style = span.style;
      final colour = style?.color ?? style?.foreground?.color;
      if (colour != null) {
        drawn.colours.add(colour);
      }
      return true;
    });
    final style = paragraph.text.style;
    if (style != null && style.fontFamily != "MaterialIcons") {
      drawn.styles.add(style);
    }
  }
  return drawn;
}

/// The themes every sentinel check forbids: Harbor's and the built-in one.
final List<CalendarThemeData> harborAndBuiltIn = <CalendarThemeData>[
  harborCalendarTheme,
  const CalendarThemeData(),
];

/// Asserts that [drawn] holds only [theme]'s values: every colour, but
/// black, is one of [theme]'s or of an item type's and none of a
/// [forbidden] theme's or Harbor's; every text style carries one of
/// [theme]'s tags; every icon is [theme]'s or an item type's and none of a
/// [forbidden] theme's; every ring is [theme]'s width; and no alpha is a
/// [forbidden] theme's dragged-block alpha.
void expectOnly(
  Drawn drawn,
  CalendarThemeData theme, {
  required List<CalendarThemeData> forbidden,
  String reason = "",
}) {
  final banned = <CalendarThemeData>[...forbidden, ...harborAndBuiltIn];
  final bannedRgb = <int>{
    for (final other in banned)
      for (final colour in coloursOf(other)) rgbOf(colour),
  };
  final allowedRgb = <int>{
    for (final colour in coloursOf(theme)) rgbOf(colour),
    for (final colour in typeColours) rgbOf(colour),
  };
  for (final colour in drawn.colours) {
    final rgb = rgbOf(colour);
    if (rgb == 0) {
      continue;
    }
    expect(
      bannedRgb.contains(rgb),
      isFalse,
      reason: "$reason: forbidden colour $colour",
    );
    expect(
      allowedRgb.contains(rgb),
      isTrue,
      reason: "$reason: colour $colour is not the theme's",
    );
  }
  final tags = tagsOf(theme);
  for (final style in drawn.styles) {
    expect(
      tags.containsKey(style.letterSpacing),
      isTrue,
      reason: "$reason: untagged text style $style",
    );
  }
  final bannedIcons = <IconData>{for (final other in banned) ...iconsOf(other)};
  final allowedIcons = <IconData>{...iconsOf(theme), ...typeIcons};
  for (final icon in drawn.icons) {
    expect(
      bannedIcons.contains(icon),
      isFalse,
      reason: "$reason: forbidden $icon",
    );
    expect(
      allowedIcons.contains(icon),
      isTrue,
      reason: "$reason: $icon is not the theme's",
    );
  }
  for (final ring in drawn.rings) {
    expect(ring, theme.todayRingWidth, reason: "$reason: ring width");
  }
  final bannedAlphas = <int>{
    for (final other in banned)
      Color.getAlphaFromOpacity(other.draggedBlockOpacity),
  };
  for (final alpha in drawn.alphas) {
    expect(
      bannedAlphas.contains(alpha),
      isFalse,
      reason: "$reason: forbidden alpha $alpha",
    );
  }
}

/// The fields of [theme] whose values [drawn] holds: each colour by its
/// red, green and blue, each text style by its tag, each icon,
/// [CalendarThemeData.todayRingWidth] by a ring and
/// [CalendarThemeData.draggedBlockOpacity] by its alpha.
Set<String> fieldsOf(Drawn drawn, CalendarThemeData theme) {
  final rgbs = drawn.rgbs;
  final colours = coloursOf(theme);
  final icons = iconsOf(theme);
  final tags = tagsOf(theme);
  return <String>{
    for (var i = 0; i < colours.length; i++)
      if (rgbs.contains(rgbOf(colours[i]))) colourNames[i],
    for (var i = 0; i < icons.length; i++)
      if (drawn.icons.contains(icons[i])) iconNames[i],
    for (final spacing in drawn.spacings)
      if (tags.containsKey(spacing)) tags[spacing]!,
    if (drawn.rings.contains(theme.todayRingWidth)) "todayRingWidth",
    if (drawn.alphas.contains(
      Color.getAlphaFromOpacity(theme.draggedBlockOpacity),
    ))
      "draggedBlockOpacity",
  };
}

/// The colour of the screen's pixel at the global [point], as 32-bit ARGB,
/// read from the repaint boundary nearest above [over].
Future<int> pixelAt(
  WidgetTester tester,
  RenderObject over,
  Offset point,
) async {
  RenderObject? node = over;
  while (node != null && node is! RenderRepaintBoundary) {
    node = node.parent;
  }
  final boundary = node! as RenderRepaintBoundary;
  final local = boundary.globalToLocal(point);
  var argb = 0;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final index = (local.dy.floor() * image.width + local.dx.floor()) * 4;
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    argb =
        bytes[index + 3] << 24 |
        bytes[index] << 16 |
        bytes[index + 1] << 8 |
        bytes[index + 2];
  });
  return argb;
}

/// Checks the hour labels, which the timed grid's foreground paints as
/// bare paragraphs: each is as tall as [theme]'s
/// [CalendarThemeData.hourLabelStyle] lays out over the grid's text style,
/// and a pixel inside the last digit of a label the grid shows whole is
/// [theme]'s [CalendarThemeData.textSecondary]. Returns the field it
/// checks, for [fieldsOf]'s union.
Future<Set<String>> labelsOf(
  WidgetTester tester,
  CalendarThemeData theme,
) async {
  final viewport = gridViewport(tester);
  final context = tester.element(find.byType(TimedGrid<ItemPayload>));
  final painter = TextPainter(
    text: TextSpan(
      text: "00:00",
      style: DefaultTextStyle.of(context).style.merge(theme.hourLabelStyle),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  final labels = paintGridForeground(tester).paragraphs;
  expect(labels, isNotEmpty);
  for (final label in labels) {
    expect(label.paragraph.height, height, reason: "an hour label's height");
  }
  final region = viewport.scrolledRegion;
  final whole = labels.where((label) {
    return label.offset.dy >= region.top + 2.0 &&
        label.offset.dy + label.paragraph.height <= region.bottom - 2.0;
  }).first;
  final ink = viewport.localToGlobal(
    whole.offset +
        Offset(
          whole.paragraph.maxIntrinsicWidth - 2.0,
          whole.paragraph.height - 2.0,
        ),
  );
  expect(
    await pixelAt(tester, viewport, ink),
    theme.textSecondary.toARGB32(),
    reason: "an hour label's ink",
  );
  return <String>{"hourLabelStyle"};
}

/// Fails every read [api] answers from here on, and selects in Agenda the
/// day a month on ([selectNextMonth]) until a read fails, at most three
/// times.
Future<void> failNextMonthRead(
  WidgetTester tester,
  MockCalendarApi api,
) async {
  api.failurePolicy = (request) {
    return request.method == CalendarMethod.list ? "Reading failed." : null;
  };
  for (var i = 0; i < 3; i++) {
    await selectNextMonth(tester);
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    if (find.text("Reading failed.").evaluate().isNotEmpty) {
      return;
    }
  }
}

/// Fails every read [api] answers from here on, and taps [tooltip]'s
/// chevron until a read fails, onto days no read has prefetched, at most
/// three times.
Future<void> failNextRead(
  WidgetTester tester,
  MockCalendarApi api,
  String tooltip,
) async {
  api.failurePolicy = (request) {
    return request.method == CalendarMethod.list ? "Reading failed." : null;
  };
  for (var i = 0; i < 3; i++) {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    if (find.text("Reading failed.").evaluate().isNotEmpty) {
      return;
    }
  }
}

DateTime april(int day) {
  return DateTime(2026, 4, day);
}

DateTime may(int day) {
  return DateTime(2026, 5, day);
}

/// Agenda's cell of [day] in the calendar card's month.
Finder cellOf(DateTime day) {
  return find.byKey(dayCellKey(day));
}

/// The cell of [day] in a blank cell of Agenda's month, which shows only
/// while the month folds, and has no key.
Finder neighbourCellOf(DateTime day) {
  return find.byWidgetPredicate((widget) {
    return widget is DayCell && widget.day == day && widget.key == null;
  });
}

/// The week strip's cell of [day].
Finder stripCellOf(DateTime day) {
  return find.descendant(
    of: find.byKey(weekStripDayKey(day)),
    matching: find.byType(DayCell),
  );
}

/// The style of the number [cell] draws for [day].
TextStyle numberStyleOf(WidgetTester tester, Finder cell, DateTime day) {
  return tester
      .widget<Text>(
        find.descendant(of: cell, matching: find.text("${day.day}")),
      )
      .style!;
}

/// How far the week strip has scrolled.
double stripOffset(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(WeekStrip<ItemPayload>),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;
}

/// The picker's position: the year whose months it shows, fractional
/// while it slides, read from where it shows [year]'s months.
double pickerPosition(WidgetTester tester, int year) {
  final shown = tester.widget<FractionalTranslation>(
    find.descendant(
      of: find.byType(MonthPicker),
      matching: find.byKey(ValueKey<int>(year)),
    ),
  );
  return year - shown.translation.dx;
}

/// A line of [style] over the ambient text style at [context], as Text
/// lays it out there.
double lineHeightAt(BuildContext context, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: "Mon",
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// [theme]'s unmarked number at either end of the fold: unfolded in the
/// shown month and in another, and folded.
({TextStyle from, TextStyle fromMuted, TextStyle to}) foldStylesOf(
  CalendarThemeData theme,
) {
  return (
    from: theme.dayNumberStyle.copyWith(color: theme.text),
    fromMuted: theme.dayNumberStyle.copyWith(color: theme.textMuted),
    to: theme.dayNumberMarkedStyle.copyWith(color: theme.text),
  );
}

/// [sentinelA] with its marked day number its unmarked one at w800, so the
/// two differ in weight alone.
final CalendarThemeData sentinelA2 = sentinelA.copyWith(
  dayNumberMarkedStyle: sentinelA.dayNumberStyle.copyWith(
    fontWeight: FontWeight.w800,
  ),
);

/// Rebuilds every element as a hot reload does, through
/// [BuildOwner.reassemble]; the next pump builds them.
void hotReload(WidgetTester tester) {
  tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
}

/// Opens the calendar bar, sets the hours to [start] to [end] o'clock and
/// closes it.
Future<void> pickHours(WidgetTester tester, int start, int end) async {
  await openBar(tester);
  setHours(tester, start, end);
  await tester.pumpAndSettle();
  await closeBar(tester);
}

/// Sets the hours of the open calendar bar to [start] to [end] o'clock
/// through its slider's own callback. Pumps nothing.
void setHours(WidgetTester tester, int start, int end) {
  tester.widget<RangeSlider>(find.byKey(hoursSliderKey)).onChanged!(
    RangeValues(start.toDouble(), end.toDouble()),
  );
}

/// Agenda's tree, whose controller holds the list's animation style.
SliverTree<String, DayListRow> agendaTree(WidgetTester tester) {
  return tester.widget<SliverTree<String, DayListRow>>(
    find.byType(SliverTree<String, DayListRow>),
  );
}

/// How far Agenda's list has scrolled.
double listOffset(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(DayList<ItemPayload>),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;
}

/// Expects every family of Agenda's tree style to run [duration] on
/// [curve].
void expectListMotion(WidgetTester tester, Duration duration, Curve curve) {
  final style = agendaTree(tester).controller.animationStyle;
  for (final family in TreeAnimationFamily.values) {
    final spec = style.specFor(family);
    expect(spec.duration, duration, reason: family.name);
    expect(spec.curve, curve, reason: family.name);
  }
}

/// The size factor of the row under [key] as it grows in or shrinks away.
double sizeFactorOf(WidgetTester tester, Key key) {
  return tester
      .widget<SizeTransition>(
        find
            .ancestor(
              of: find.byKey(key),
              matching: find.byType(SizeTransition),
            )
            .first,
      )
      .sizeFactor
      .value;
}

/// Taps [day]'s cell in Agenda's month, or in its strip where the month is
/// folded, and settles, which brings its header to the list's top.
Future<void> revealDay(WidgetTester tester, DateTime day) async {
  final cell = cellOf(day);
  await tester.tap(
    cell.evaluate().isEmpty ? find.byKey(weekStripDayKey(day)) : cell,
  );
  await tester.pumpAndSettle();
}

/// Expects every family of [board]'s animation style to run [duration]
/// on [curve].
void expectBoardMotion(
  BoardController<String, Object?> board,
  Duration duration,
  Curve curve,
) {
  final style = board.animationStyle;
  for (final family in BoardAnimationFamily.values) {
    final spec = style.specFor(family);
    expect(spec.duration, duration, reason: family.name);
    expect(spec.curve, curve, reason: family.name);
  }
}

/// Month's board controller.
BoardController<String, MonthChip<ItemPayload>> monthController(
  WidgetTester tester,
) {
  return tester
      .widget<Board<String, MonthChip<ItemPayload>>>(
        find.byType(Board<String, MonthChip<ItemPayload>>),
      )
      .controller;
}

/// The timed grid's board.
Board<String, ShownItem> gridBoard(WidgetTester tester) {
  return tester.widget<Board<String, ShownItem>>(
    find.byType(Board<String, ShownItem>),
  );
}

/// The title [Text] of the block of the item [id], whose title is [title].
Text blockTitleOf(WidgetTester tester, String id, String title) {
  return tester.widget<Text>(
    find.descendant(of: blockFinder(id), matching: find.text(title)),
  );
}

/// The ids and titles of [themeSeed]'s items, in the mock's numbering.
const Map<String, String> seedTitles = <String, String>{
  "item-1": "Planning",
  "item-2": "Early sync",
  "item-3": "Late sync",
  "item-4": "Report",
  "item-5": "Release",
  "item-6": "Slot 1",
  "item-7": "Slot 2",
  "item-8": "Slot 3",
  "item-9": "Slot 4",
  "item-10": "Slot 5",
  "item-11": "Slot 6",
  "item-12": "Slot 7",
  "item-13": "Away",
};

/// Expects every block the grid has built to draw its title in
/// [theme]'s block title colour and tag.
void expectBlockTitles(WidgetTester tester, CalendarThemeData theme) {
  var seen = 0;
  for (final entry in seedTitles.entries) {
    final title = find.descendant(
      of: blockFinder(entry.key),
      matching: find.text(entry.value),
    );
    for (final element in title.evaluate()) {
      final style = (element.widget as Text).style!;
      expect(style.color, theme.text, reason: entry.value);
      expect(
        style.letterSpacing,
        anyOf(
          theme.blockTitleStyle.letterSpacing,
          theme.detailedBlockTitleStyle.letterSpacing,
        ),
        reason: entry.value,
      );
      seen++;
    }
  }
  expect(seen, greaterThan(0));
}

/// The calendar's [CalendarStore], read from the view that shows, which a
/// test writes through as the calendar does.
CalendarStore<ItemPayload> storeOf(WidgetTester tester) {
  final grid = find.byType(TimedGrid<ItemPayload>);
  if (grid.evaluate().isNotEmpty) {
    return tester.widget<TimedGrid<ItemPayload>>(grid).store;
  }
  final list = find.byType(DayList<ItemPayload>);
  if (list.evaluate().isNotEmpty) {
    return tester.widget<DayList<ItemPayload>>(list).store;
  }
  return tester
      .widget<MonthBoard<ItemPayload>>(find.byType(MonthBoard<ItemPayload>))
      .store;
}

/// The gutter cells the grid has built, in tree order.
List<Widget> gutterCells(WidgetTester tester) {
  return tester
      .widgetList(
        find.byWidgetPredicate((widget) {
          return widget.runtimeType.toString() == "_GutterCell";
        }),
      )
      .toList();
}

/// The roots of every view the calendar shows now.
List<Finder> viewRoots() {
  return <Finder>[
    for (final type in <Type>[
      TimedGrid<ItemPayload>,
      MonthBoard<ItemPayload>,
      DayList<ItemPayload>,
      DayCell,
      WeekdayHeader,
      MonthPicker,
    ])
      if (find.byType(type).evaluate().isNotEmpty) find.byType(type),
  ];
}

/// The fill of the first box under [finder], a [DecoratedBox] or a
/// [Container], whose decoration has a colour.
Color boxFillOf(WidgetTester tester, Finder finder) {
  for (final element
      in find
          .descendant(
            of: finder,
            matching: find.byWidgetPredicate((widget) {
              return widget is DecoratedBox || widget is Container;
            }),
          )
          .evaluate()) {
    final widget = element.widget;
    final decoration = widget is DecoratedBox
        ? widget.decoration
        : (widget as Container).decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration.color!;
    }
  }
  throw StateError("No coloured box under $finder.");
}

/// The [BoxDecoration] of the first [DecoratedBox] [finder] finds or
/// holds, in [position].
BoxDecoration decorationOf(
  WidgetTester tester,
  Finder finder, {
  DecorationPosition position = DecorationPosition.background,
}) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: finder,
          matching: find.byWidgetPredicate((widget) {
            return widget is DecoratedBox && widget.position == position;
          }),
          matchRoot: true,
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

/// The colour of the first [Icon] under [of] showing [icon].
Color iconColourOf(WidgetTester tester, Finder of, IconData icon) {
  return tester
      .widgetList<Icon>(find.descendant(of: of, matching: find.byType(Icon)))
      .firstWhere((widget) {
        return widget.icon == icon;
      })
      .color!;
}

/// The colour of the first line the [CustomPaint] under [of] draws.
Color lineColourOf(WidgetTester tester, Finder of) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: of, matching: find.byType(CustomPaint)).first,
  );
  final canvas = RecordingCanvas();
  paint.painter!.paint(canvas, const Size(40.0, 8.0));
  return canvas.lines.first.color;
}

/// Expects [colour] to be [field]'s, compared as 32-bit ARGB.
void expectColour(Color colour, Color field, String reason) {
  expect(colour.toARGB32(), field.toARGB32(), reason: reason);
}

/// The [Text] widgets reading [text] under [of].
Finder textIn(Finder of, String text) {
  return find.descendant(
    of: of,
    matching: find.byWidgetPredicate((widget) {
      return widget is Text && widget.data == text;
    }),
  );
}

/// Expects the [Text] [finder] finds first to draw in [theme]'s text style
/// [name], by its tag, and in [colour].
void expectText(
  WidgetTester tester,
  Finder finder,
  CalendarThemeData theme,
  String name,
  Color colour,
) {
  final style = tester.widget<Text>(finder.first).style!;
  expect(
    style.letterSpacing,
    stylesOf(theme)[styleNames.indexOf(name)].letterSpacing,
    reason: name,
  );
  expect(style.color, colour, reason: name);
}

/// Lifts the block of the item [id] and moves it [slots] of its own
/// heights down; returns the gesture, still down.
Future<TestGesture> liftBlock(
  WidgetTester tester,
  String id, {
  double slots = 0.0,
}) async {
  final rect = tester.getRect(blockFinder(id));
  final gesture = await tester.startGesture(rect.center);
  await tester.pump(kLongPressTimeout + kPressTimeout);
  if (slots != 0.0) {
    await gesture.moveBy(Offset(0.0, rect.height * slots));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
  return gesture;
}

/// Starts a drag on the calendar card's pull tab and moves it [distance]
/// up, folding the month that far; returns the gesture, still down.
Future<TestGesture> foldBy(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(calendarPullTabKey)),
  );
  await gesture.moveBy(const Offset(0.0, -20.0));
  await gesture.moveBy(Offset(0.0, -distance));
  await tester.pump();
  return gesture;
}

void main() {
  test("the sentinels' values differ from Harbor's, the built-in ones and "
      "each other's", () {
    final themes = <CalendarThemeData>[
      sentinelA,
      sentinelB,
      ...harborAndBuiltIn,
    ];
    for (var i = 0; i < themes.length; i++) {
      for (var j = i + 1; j < themes.length; j++) {
        if (i >= 2 && j >= 2) {
          continue;
        }
        final a = themes[i];
        final b = themes[j];
        final aColours = coloursOf(a).map(rgbOf).toSet();
        for (final colour in coloursOf(b)) {
          expect(aColours.contains(rgbOf(colour)), isFalse, reason: "$i $j");
        }
        final aIcons = iconsOf(a).toSet();
        for (final icon in iconsOf(b)) {
          expect(aIcons.contains(icon), isFalse, reason: "$i $j");
        }
        expect(a.motionDuration, isNot(b.motionDuration));
        expect(a.motionCurve, isNot(b.motionCurve));
        expect(a.todayRingWidth, isNot(b.todayRingWidth));
        expect(a.draggedBlockOpacity, isNot(b.draggedBlockOpacity));
      }
    }
    expect(tagsOf(sentinelA), hasLength(31));
    expect(tagsOf(sentinelB), hasLength(31));
    expect(
      tagsOf(
        sentinelA,
      ).keys.toSet().intersection(tagsOf(sentinelB).keys.toSet()),
      isEmpty,
    );
    for (final colour in <Color>[
      ...coloursOf(sentinelA),
      ...coloursOf(sentinelB),
    ]) {
      expect(typeColours.map(rgbOf).contains(rgbOf(colour)), isFalse);
    }
  });

  test("C1 no built-in colour is a Harbor colour", () {
    const harbor = <Color>[
      HarborColors.primary,
      HarborColors.primaryTint,
      HarborColors.background,
      HarborColors.surface,
      HarborColors.outline,
      HarborColors.text,
      HarborColors.textSecondary,
      HarborColors.textMuted,
      HarborColors.error,
      HarborColors.onPrimary,
      HarborColors.todayRing,
      HarborColors.notice,
      HarborColors.noticeEdge,
      HarborColors.onNotice,
    ];
    final harborArgb = <int>{for (final colour in harbor) colour.toARGB32()};
    for (final colour in coloursOf(const CalendarThemeData())) {
      expect(
        harborArgb.contains(colour.toARGB32()),
        isFalse,
        reason: "$colour",
      );
    }
  });

  testWidgets("C2 under Harbor the probe finds the timed grid's colours and "
      "the ambient letter spacing, and skips a failed read's Retry", (
    tester,
  ) async {
    final api = await pumpThemed(tester, harborCalendarTheme);
    await pickMode(tester, "Week");
    final drawn = drawnUnder(tester, <Finder>[
      find.byType(TimedGrid<ItemPayload>),
    ]);
    for (final colour in <Color>[
      HarborColors.surface,
      HarborColors.outline,
      HarborColors.text,
      HarborColors.textSecondary,
    ]) {
      expect(drawn.rgbs.contains(rgbOf(colour)), isTrue, reason: "$colour");
    }
    expect(drawn.styles, isNotEmpty);
    expect(drawn.spacings, <double?>{0.25});
    final tags = <double>{...tagsOf(sentinelA).keys, ...tagsOf(sentinelB).keys};
    expect(drawn.spacings.intersection(tags), isEmpty);

    await failNextRead(tester, api, "Next week");
    final message = find.descendant(
      of: find.byType(TimedGrid<ItemPayload>),
      matching: find.text("Reading failed."),
    );
    final retry = find.descendant(
      of: find.byType(TimedGrid<ItemPayload>),
      matching: find.text("Retry"),
    );
    expect(message, findsOneWidget);
    expect(retry, findsOneWidget);
    final failed = drawnUnder(tester, <Finder>[
      find.byType(TimedGrid<ItemPayload>),
    ]);
    final retryLabel = tester.renderObject<RenderParagraph>(retry);
    expect(failed.paragraphs.contains(tester.renderObject(message)), isTrue);
    expect(failed.paragraphs.contains(retryLabel), isFalse);
    expect(failed.styles.contains(retryLabel.text.style), isFalse);
  });

  testWidgets("C3 day cells, weekday headers, the strip and the picker draw "
      "and run on A, and on B from the frame that installs it", (tester) async {
    final api = await pumpThemed(tester, sentinelA);
    final fields = <String>{};
    final agendaRoots = <Finder>[
      find.byType(DayCell),
      find.byType(WeekdayHeader),
    ];

    // Agenda's month, unfolded.
    var drawn = drawnUnder(tester, agendaRoots);
    expectOnly(drawn, sentinelA, forbidden: const [], reason: "Agenda");
    fields.addAll(fieldsOf(drawn, sentinelA));
    await installTheme(tester, api, sentinelB);
    expectOnly(
      drawnUnder(tester, agendaRoots),
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "Agenda under B",
    );
    await installTheme(tester, api, sentinelA);
    await tester.pumpAndSettle();

    // Day's strip, and its slide to the next week on A's motion.
    await pickMode(tester, "Day");
    final stripRoots = <Finder>[find.byType(DayCell)];
    drawn = drawnUnder(tester, stripRoots);
    expectOnly(drawn, sentinelA, forbidden: const [], reason: "Day");
    fields.addAll(fieldsOf(drawn, sentinelA));
    final week = tester.getSize(find.byType(WeekStrip<ItemPayload>)).width;
    await tester.tap(find.byKey(weekStripDayKey(april(26))));
    await tester.pumpAndSettle();
    var from = stripOffset(tester);
    await tester.tap(find.byTooltip("Next day"));
    // The frame that rebuilds the strip starts the slide after it; the
    // slide's first tick is the next frame.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      stripOffset(tester) - from,
      moreOrLessEquals(week / 2, epsilon: 1.0),
    );
    await tester.pump(const Duration(milliseconds: 450));
    expect(stripOffset(tester) - from, moreOrLessEquals(week, epsilon: 0.01));
    await tester.pumpAndSettle();

    // B from the frame that installs it, the strip as tall as B's weekday
    // line makes it, and its next slide on B's motion.
    await installTheme(tester, api, sentinelB);
    expectOnly(
      drawnUnder(tester, stripRoots),
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "Day under B",
    );
    final strip = tester.element(find.byType(WeekStrip<ItemPayload>));
    expect(
      tester.getSize(find.byType(WeekStrip<ItemPayload>)).height,
      moreOrLessEquals(
        lineHeightAt(strip, sentinelB.stripWeekdayStyle) +
            stripLabelGap +
            dayCircleSize,
      ),
    );
    // Setup sanity: B's weekday line is not A's, which the strip had.
    expect(
      lineHeightAt(strip, sentinelB.stripWeekdayStyle),
      isNot(lineHeightAt(strip, sentinelA.stripWeekdayStyle)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(weekStripDayKey(may(3))));
    await tester.pumpAndSettle();
    from = stripOffset(tester);
    await tester.tap(find.byTooltip("Next day"));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      stripOffset(tester) - from,
      moreOrLessEquals(week * Curves.easeIn.transform(0.5), epsilon: 1.0),
    );
    await tester.pumpAndSettle();
    await installTheme(tester, api, sentinelA);
    await tester.pumpAndSettle();

    // Month's letters with the picker open, and the picker's slide to the
    // next year on A's motion.
    await pickMode(tester, "Month");
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    final pickerRoots = <Finder>[
      find.byType(WeekdayHeader),
      find.byType(MonthPicker),
    ];
    drawn = drawnUnder(tester, pickerRoots);
    expectOnly(drawn, sentinelA, forbidden: const [], reason: "Month");
    fields.addAll(fieldsOf(drawn, sentinelA));
    await tester.tap(find.byTooltip("Next year"));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(pickerPosition(tester, 2026), moreOrLessEquals(2026.5));
    await tester.pumpAndSettle();

    // B from the frame that installs it, and the picker's names scaled by
    // a measure of B's marked month name, the widest fitting its pill.
    await installTheme(tester, api, sentinelB);
    expectOnly(
      drawnUnder(tester, pickerRoots),
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "Month under B",
    );
    final picker = tester.element(find.byType(MonthPicker));
    final scaler = tester
        .widget<MonthCell>(find.byType(MonthCell).first)
        .nameScaler;
    final room =
        tester.getSize(find.byType(MonthPicker)).width / monthPickerColumns -
        MonthCell.pillMargin.horizontal -
        MonthCell.pillPadding.horizontal;
    var widest = 0.0;
    for (final name in monthNames) {
      final painter = TextPainter(
        text: TextSpan(
          text: name,
          style: DefaultTextStyle.of(
            picker,
          ).style.merge(sentinelB.monthNameMarkedStyle),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) {
        widest = painter.width;
      }
      painter.dispose();
    }
    expect(widest, lessThanOrEqualTo(room));
    expect(widest, greaterThan(room - 1.0));

    expect(
      fields,
      containsAll(<String>[
        "primary",
        "onPrimary",
        "background",
        "surface",
        "text",
        "textMuted",
        "todayRing",
        "todayRingWidth",
        ...styleNames.sublist(24),
      ]),
    );
  });

  testWidgets("C3 as the month folds an unmarked number draws the lerp of "
      "the theme's prepared styles, the folded strip their marked one, and "
      "the prepared styles are kept across frames and rebuilds", (
    tester,
  ) async {
    final api = await pumpThemed(tester, sentinelA);
    final a = foldStylesOf(sentinelA);
    // Today, April 21, apart from the selected day.
    await tester.tap(cellOf(april(23)));
    await tester.pumpAndSettle();

    // Unfolded, an unmarked number is A's prepared style itself, kept by a
    // cell the next tap rebuilds.
    final unmarked = numberStyleOf(tester, cellOf(april(22)), april(22));
    expect(unmarked, a.from);
    await tester.tap(cellOf(april(24)));
    await tester.pumpAndSettle();
    expect(
      identical(numberStyleOf(tester, cellOf(april(23)), april(23)), unmarked),
      isTrue,
    );

    var gesture = await foldBy(tester, 90.0);
    final t = tester.widget<DayCell>(cellOf(april(22))).collapse.value;
    expect(t, inExclusiveRange(0.0, 1.0));
    expect(
      numberStyleOf(tester, cellOf(april(22)), april(22)),
      TextStyle.lerp(a.from, a.to, t),
    );
    expect(
      numberStyleOf(tester, neighbourCellOf(may(1)), may(1)),
      TextStyle.lerp(a.fromMuted, a.to, t),
    );
    final selected = numberStyleOf(tester, cellOf(april(24)), april(24));
    final todays = numberStyleOf(tester, cellOf(april(21)), april(21));
    await gesture.moveBy(const Offset(0.0, -10.0));
    await tester.pump();
    expect(tester.widget<DayCell>(cellOf(april(22))).collapse.value, isNot(t));
    expect(
      identical(numberStyleOf(tester, cellOf(april(24)), april(24)), selected),
      isTrue,
    );
    expect(
      identical(numberStyleOf(tester, cellOf(april(21)), april(21)), todays),
      isTrue,
    );
    await gesture.moveBy(const Offset(0.0, -400.0));
    await gesture.up();
    await tester.pumpAndSettle();

    // Folded, every number carries the marked style's tag, and an unmarked
    // one is A's prepared folded style, kept across the rebuild a tap
    // makes.
    final numbers = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(DayCell),
        matching: find.byWidgetPredicate((widget) {
          return widget is Text &&
              widget.data != null &&
              int.tryParse(widget.data!) != null;
        }),
      ),
    );
    expect(numbers, isNotEmpty);
    for (final number in numbers) {
      expect(number.style!.letterSpacing, tagOf(26, 0));
    }
    final folded = numberStyleOf(tester, stripCellOf(april(22)), april(22));
    expect(folded, a.to);
    await tester.tap(find.byKey(weekStripDayKey(april(25))));
    await tester.pumpAndSettle();
    expect(
      identical(
        numberStyleOf(tester, stripCellOf(april(22)), april(22)),
        folded,
      ),
      isTrue,
    );

    // Under A2, whose two number styles differ in weight alone, a number
    // of another month draws the lerp of A2's styles, and one of the shown
    // month that lerp in A2's own text colour.
    await tester.tap(find.byKey(calendarPullTabKey));
    await tester.pumpAndSettle();
    await installTheme(tester, api, sentinelA2);
    await tester.pumpAndSettle();
    final a2 = foldStylesOf(sentinelA2);
    gesture = await foldBy(tester, 90.0);
    final t2 = tester.widget<DayCell>(cellOf(april(22))).collapse.value;
    expect(t2, inExclusiveRange(0.0, 1.0));
    expect(
      numberStyleOf(tester, neighbourCellOf(may(1)), may(1)),
      TextStyle.lerp(a2.fromMuted, a2.to, t2),
    );
    final inMonth = numberStyleOf(tester, cellOf(april(22)), april(22));
    expect(
      inMonth,
      TextStyle.lerp(a2.from, a2.to, t2)!.copyWith(color: sentinelA2.text),
    );
    expect(identical(inMonth.color, sentinelA2.text), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets("C3 a hot reload makes the day cells' and the picker's styles "
      "anew", (tester) async {
    await pumpThemed(tester, sentinelA);
    final number = numberStyleOf(tester, cellOf(april(21)), april(21));
    final letter = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(WeekdayHeader),
            matching: find.text("Mon"),
          ),
        )
        .style!;
    hotReload(tester);
    await tester.pump();
    final remade = numberStyleOf(tester, cellOf(april(21)), april(21));
    expect(remade, number);
    expect(identical(remade, number), isFalse);
    final remadeLetter = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(WeekdayHeader),
            matching: find.text("Mon"),
          ),
        )
        .style!;
    expect(remadeLetter, letter);
    expect(identical(remadeLetter, letter), isFalse);

    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    Finder april2026() {
      return find.descendant(
        of: find.byKey(monthPickerMonthKey(DateTime(2026, 4))),
        matching: find.text("April"),
      );
    }

    final name = tester.widget<Text>(april2026()).style!;
    hotReload(tester);
    await tester.pump();
    final remadeName = tester.widget<Text>(april2026()).style!;
    expect(remadeName, name);
    expect(identical(remadeName, name), isFalse);
  });

  testWidgets("C4 Agenda's list draws and runs on A, and on B from the frame "
      "that installs it", (tester) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickHours(tester, 8, 18);
    final roots = <Finder>[find.byType(DayList<ItemPayload>)];
    final fields = <String>{};
    void probe(String where) {
      final drawn = drawnUnder(tester, roots);
      expectOnly(drawn, sentinelA, forbidden: const [], reason: where);
      fields.addAll(fieldsOf(drawn, sentinelA));
    }

    // Tuesday's marker of the current time, Wednesday's strips, Thursday's
    // banners, Sunday's empty header and a failed read of the next month.
    probe("Tuesday");
    await revealDay(tester, april(22));
    probe("Wednesday");
    await revealDay(tester, april(23));
    probe("Thursday");
    await revealDay(tester, april(26));
    probe("Sunday");
    expectListMotion(tester, const Duration(milliseconds: 900), Curves.linear);

    // A gap row coming in on new hours grows on A's motion.
    await revealDay(tester, april(21));
    await openBar(tester);
    setHours(tester, 7, 18);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      sizeFactorOf(tester, dayListGapKey(april(21), 7 * 60)),
      moreOrLessEquals(0.5),
    );
    await tester.pumpAndSettle();
    setHours(tester, 8, 18);
    await tester.pumpAndSettle();
    await closeBar(tester);

    // A reveal from rest scrolls on A's motion: linear, its two middle
    // quarters each a quarter of the way, and done at 900 ms.
    final from = listOffset(tester);
    await tester.tap(cellOf(april(23)));
    await tester.pump();
    await tester.pump();
    final at = <double>[listOffset(tester)];
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 225));
      at.add(listOffset(tester));
    }
    await tester.pumpAndSettle();
    final to = listOffset(tester);
    final distance = to - from;
    expect(distance.abs(), greaterThan(100.0));
    for (final step in <double>[at[2] - at[1], at[3] - at[2]]) {
      expect(step / distance, inInclusiveRange(0.2, 0.3));
    }
    expect(at[4], moreOrLessEquals(to, epsilon: 0.5));

    await failNextMonthRead(tester, api);
    expect(
      find.descendant(
        of: find.byType(DayList<ItemPayload>),
        matching: find.text("Reading failed."),
      ),
      findsWidgets,
    );
    probe("a failed read");
    expect(
      fields,
      containsAll(<String>[
        "background",
        "primaryTint",
        "primary",
        "onPrimary",
        "error",
        "outline",
        "notice",
        "noticeOutline",
        "onNotice",
        "surface",
        ...iconNames,
        "badgeStyle",
        "noticeStyle",
        "messageStyle",
        ...styleNames.sublist(17, 24),
      ]),
    );

    await installTheme(tester, api, sentinelB);
    expectOnly(
      drawnUnder(tester, roots),
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "B",
    );
    expectListMotion(tester, const Duration(milliseconds: 600), Curves.easeIn);
  });

  testWidgets("C4 under B an empty day's header keeps the height of a busy "
      "day's, measured in B's day title", (tester) async {
    await pumpThemed(tester, sentinelB);
    await revealDay(tester, april(25));
    final busy = tester.getSize(find.byKey(dayListHeaderKey(april(25)))).height;
    final empty = tester
        .getSize(find.byKey(dayListHeaderKey(april(26))))
        .height;
    expect(empty, busy);
    // Setup sanity: April 26 shows no item, and B's day title lays out
    // apart from the built-in one.
    final header = tester.element(find.byKey(dayListHeaderKey(april(26))));
    expect(find.text("No items"), findsWidgets);
    expect(
      lineHeightAt(header, sentinelB.agendaHeaderTitleStyle),
      isNot(
        lineHeightAt(header, const CalendarThemeData().agendaHeaderTitleStyle),
      ),
    );
  });

  testWidgets("C4 a pinned day header whose row the list no longer builds, "
      "and a row growing in, draw B from the frame that installs it", (
    tester,
  ) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickHours(tester, 8, 18);
    await revealDay(tester, april(24));
    final list = find.byType(DayList<ItemPayload>);
    await tester.drag(list, const Offset(0.0, -420.0));
    await tester.pumpAndSettle();
    final header = find.byKey(dayListHeaderKey(april(24)));
    // Setup sanity: Friday's header is pinned at the list's top, over a
    // block scrolled further than the list builds rows above its top.
    expect(tester.getRect(header).top, tester.getRect(list).top);
    final headerRow = agendaTree(
      tester,
    ).controller.scrollOffsetOf(DayListHeader.headerKeyOf(april(24)))!;
    expect(
      listOffset(tester) - headerRow - tester.getSize(header).height,
      greaterThan(RenderAbstractViewport.defaultCacheExtent),
    );
    await installTheme(tester, api, sentinelB);
    final title = tester.widget<Text>(
      find.descendant(of: header, matching: find.byType(Text)).first,
    );
    expect(title.style!.letterSpacing, tagOf(18, 40));
    expect(title.style!.color, sentinelB.text);
    expect(tester.widget<ColoredBox>(header).color, sentinelB.background);
    expectOnly(
      drawnUnder(tester, <Finder>[list]),
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "pinned",
    );
    await tester.pumpAndSettle();

    // A gap row growing in on new hours draws B from the frame that
    // installs it, and runs on to its end.
    await installTheme(tester, api, sentinelA);
    await tester.pumpAndSettle();
    await revealDay(tester, april(21));
    await openBar(tester);
    setHours(tester, 7, 18);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final gap = dayListGapKey(april(21), 7 * 60);
    expect(sizeFactorOf(tester, gap), inExclusiveRange(0.0, 1.0));
    await installTheme(tester, api, sentinelB);
    final time = tester.widget<Text>(
      find.descendant(of: find.byKey(gap), matching: find.byType(Text)),
    );
    expect(time.style!.letterSpacing, tagOf(22, 40));
    expect(time.style!.color, sentinelB.textMuted);
    expectOnly(
      drawnUnder(tester, <Finder>[find.byKey(gap)]),
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "entering row",
    );
    await tester.pumpAndSettle();
    expect(sizeFactorOf(tester, gap), 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("C4 a hot reload makes the list's and the cards' styles anew", (
    tester,
  ) async {
    await pumpThemed(tester, sentinelA);
    TextStyle headerTitle() {
      return tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(dayListHeaderKey(april(21))),
                  matching: find.byType(Text),
                )
                .first,
          )
          .style!;
    }

    TextStyle cardTitle() {
      return tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(itemCardKey("item-1")),
              matching: find.text("Planning"),
            ),
          )
          .style!;
    }

    final header = headerTitle();
    final card = cardTitle();
    hotReload(tester);
    await tester.pump();
    expect(headerTitle(), header);
    expect(identical(headerTitle(), header), isFalse);
    expect(cardTitle(), card);
    expect(identical(cardTitle(), card), isFalse);
  });

  testWidgets("C5 Month's board draws and runs on A at both sizes, and on "
      "B from the frame that installs it", (tester) async {
    final fields = <String>{};
    final roots = <Finder>[find.byType(MonthBoard<ItemPayload>)];
    for (final size in const <Size>[Size(390.0, 844.0), Size(1100.0, 900.0)]) {
      final api = await pumpThemed(tester, sentinelA, size: size);
      await pickMode(tester, "Month");
      var drawn = drawnUnder(tester, roots);
      expectOnly(drawn, sentinelA, forbidden: const [], reason: "$size");
      fields.addAll(fieldsOf(drawn, sentinelA));
      expectBoardMotion(
        monthController(tester),
        const Duration(milliseconds: 900),
        Curves.linear,
      );
      if (size.width < 400.0) {
        // Friday's seven meetings take more lanes than a week holds.
        expect(
          find.descendant(
            of: find.byType(MonthBoard<ItemPayload>),
            matching: find.textContaining("more"),
          ),
          findsWidgets,
        );
      }

      await installTheme(tester, api, sentinelB);
      drawn = drawnUnder(tester, roots);
      expectOnly(
        drawn,
        sentinelB,
        forbidden: <CalendarThemeData>[sentinelA],
        reason: "$size under B",
      );
      expect(
        fieldsOf(drawn, sentinelB),
        containsAll(<String>[
          "monthDayNumberStyle",
          "monthDayNumberMarkedStyle",
          "weekdayLetterStyle",
          "background",
          "outline",
          "text",
          "textMuted",
          "primary",
          "onPrimary",
          "todayRing",
          "todayRingWidth",
        ]),
      );
      expectBoardMotion(
        monthController(tester),
        const Duration(milliseconds: 600),
        Curves.easeIn,
      );
      await tester.pumpAndSettle();
      await installTheme(tester, api, sentinelA);
      await tester.pumpAndSettle();

      await failNextRead(tester, api, "Next month");
      expect(
        find.descendant(
          of: find.byType(MonthBoard<ItemPayload>),
          matching: find.text("Reading failed."),
        ),
        findsOneWidget,
      );
      drawn = drawnUnder(tester, roots);
      expectOnly(
        drawn,
        sentinelA,
        forbidden: const [],
        reason: "$size, a failed read",
      );
      fields.addAll(fieldsOf(drawn, sentinelA));
    }
    expect(
      fields,
      containsAll(<String>[
        ...styleNames.sublist(10, 17),
        "weekdayLetterStyle",
        "background",
        "outline",
        "text",
        "textSecondary",
        "textMuted",
        "primary",
        "onPrimary",
        "error",
        "notice",
        "onNotice",
        "todayRing",
        "todayRingWidth",
      ]),
    );
  });

  testWidgets("C5 a chip still shrinking away draws B from the frame that "
      "installs it, and a hot reload makes Month's styles anew", (
    tester,
  ) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Month");
    final chip = find.byKey(monthChipKey(monthSegmentKey("item-1", april(20))));
    TextStyle chipTitle() {
      return tester
          .widget<Text>(
            find.descendant(of: chip, matching: find.text("Planning")),
          )
          .style!;
    }

    final title = chipTitle();
    hotReload(tester);
    await tester.pump();
    expect(chipTitle(), title);
    expect(identical(chipTitle(), title), isFalse);

    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, "Delete").last);
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    // Setup sanity: the chip is shrinking away.
    expect(chip, findsOneWidget);
    final height = tester.getSize(chip).height;
    expect(height, greaterThan(0.0));
    expect(height, lessThan(monthLaneExtent));

    await installTheme(tester, api, sentinelB);
    final leaving = chipTitle();
    expect(leaving.letterSpacing, tagOf(15, 40));
    expect(leaving.color, sentinelB.text);
    expectOnly(
      drawnUnder(tester, <Finder>[chip]),
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "a leaving chip",
    );
    await tester.pumpAndSettle();
    expect(chip, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("C6 Week's and Day's grid draws and runs on A, and on B "
      "from the frame that installs it, during a lift that then drops", (
    tester,
  ) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);
    final roots = <Finder>[find.byType(TimedGrid<ItemPayload>)];
    final fields = <String>{};
    void probe(String where, {CalendarThemeData? theme}) {
      final drawn = drawnUnder(tester, roots);
      expectOnly(
        drawn,
        theme ?? sentinelA,
        forbidden: theme == null ? const [] : <CalendarThemeData>[sentinelA],
        reason: where,
      );
      if (theme == null) {
        fields.addAll(fieldsOf(drawn, sentinelA));
      }
    }

    probe("Week");
    fields.addAll(await labelsOf(tester, sentinelA));
    expectBoardMotion(
      gridBoard(tester).controller,
      const Duration(milliseconds: 900),
      Curves.linear,
    );

    // A selected block's outline and grips.
    await selectBlock(tester, "item-1");
    expect(find.byKey(blockHandlesKey("item-1")), findsOneWidget);
    probe("a selected block");

    // A lift and its landing label, the block left behind at A's opacity
    // and the lift's shadow coming in on A's motion.
    final block = blockFinder("item-6");
    final slot = tester.getRect(block);
    final gesture = await tester.startGesture(slot.center);
    await tester.pump(kLongPressTimeout + kPressTimeout);
    expect(gridBoard(tester).drag!.draggedItemOpacity, 0.4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    final shadow = tester.widget<DecoratedBox>(find.byKey(liftedBlockKey));
    expect(
      (shadow.decoration as BoxDecoration).boxShadow!.first.color.a,
      moreOrLessEquals(liftedBlockShadows.first.color.a * 0.5, epsilon: 0.01),
    );
    await gesture.moveBy(Offset(0.0, slot.height * 2.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(landingLabelKey), findsOneWidget);
    probe("a lift");

    // B from the frame that installs it: the carried block and the lattice,
    // the drag configs and the faded block's alpha.
    await installTheme(tester, api, sentinelB);
    final carried = tester.widget<Text>(
      find.descendant(
        of: find.byKey(liftedBlockKey),
        matching: find.text("Slot 1"),
      ),
    );
    expect(carried.style!.color, sentinelB.text);
    expect(carried.style!.letterSpacing, tagOf(4, 40));
    expectBlockTitles(tester, sentinelB);
    expect(gridBoard(tester).drag!.draggedItemOpacity, 0.3);
    final underB = drawnUnder(tester, roots);
    expect(underB.alphas, contains(Color.getAlphaFromOpacity(0.3)));
    expectOnly(
      underB,
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "a lift under B",
    );

    // The lift moves on and drops where the pointer is: four hours below
    // where it lifted, past Friday's other meetings.
    await gesture.moveBy(Offset(0.0, slot.height * 6.0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final target = tester.getRect(find.byKey(liftedBlockKey));
    await gesture.up();
    await tester.pump();
    await tester.pump(gridAnimationStyle(tester).effectiveDropSettle.duration);
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final stored = (await listAll(
      tester,
      api,
      april(24),
      april(24),
    )).firstWhere((item) => item["title"] == "Slot 1");
    expect(stored["startMinute"], 12 * 60);
    expect(
      tester.getRect(block).top,
      moreOrLessEquals(target.top, epsilon: 1.0),
    );
    probe("after the drop under B", theme: sentinelB);
    await labelsOf(tester, sentinelB);
    expectBoardMotion(
      gridBoard(tester).controller,
      const Duration(milliseconds: 600),
      Curves.easeIn,
    );
    await installTheme(tester, api, sentinelA);
    await tester.pumpAndSettle();

    // Weekends hidden, then Day, then a failed read.
    await openBar(tester);
    flipWeekends(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);
    probe("Week without weekends");
    await pickMode(tester, "Day");
    probe("Day");
    await labelsOf(tester, sentinelA);
    await pickMode(tester, "Week");
    await failNextRead(tester, api, "Next week");
    expect(
      find.descendant(
        of: find.byType(TimedGrid<ItemPayload>),
        matching: find.text("Reading failed."),
      ),
      findsOneWidget,
    );
    probe("a failed read");
    expect(
      fields,
      containsAll(<String>[
        ...styleNames.sublist(1, 8),
        "noticeStyle",
        "draggedBlockOpacity",
      ]),
    );
  });

  testWidgets("C6 over all-day hours, a theme with taller hour labels keeps "
      "the hour at the top of a grid lifting a block", (tester) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    final viewport = gridViewport(tester);
    final region = viewport.scrolledRegion;
    final block = blockFinder("item-7");
    final center = viewport.globalToLocal(tester.getCenter(block));
    // Setup sanity: the block to lift shows, and the grid is scrolled into
    // the slots, past A's label room.
    expect(region.contains(center), isTrue);
    final gesture = await tester.startGesture(tester.getCenter(block));
    await tester.pump(kLongPressTimeout + kPressTimeout);
    await tester.pump();
    final before = viewport.verticalPosition!.pixels;
    expect(before, greaterThan(6.5));
    await installTheme(tester, api, sentinelB);
    expect(
      gridViewport(tester).verticalPosition!.pixels,
      moreOrLessEquals(before + 0.5),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets("C6 a theme change in the frame of a week step leaves the "
      "board under the disabled style until the restore frame, which puts "
      "back the new theme's", (tester) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    storeOf(tester).requestDelete("item-6");
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));
    // Setup sanity: the deleted block is shrinking away across its day.
    final block = blockFinder("item-6");
    expect(block, findsOneWidget);
    final width = tester.getSize(block).width;
    final controller = gridBoard(tester).controller;
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getSize(block).width, lessThan(width));

    // The week step's sync disables the style and schedules its restore;
    // the theme installed in the same frame leaves it so, and the exit's
    // next tick, before the restore, ends it.
    await tester.tap(find.byTooltip("Next week"));
    await installTheme(tester, api, sentinelB);
    expect(controller.animationStyle, same(BoardAnimationStyle.disabled));
    await tester.pump();
    expect(block, findsNothing);
    expectBoardMotion(
      controller,
      const Duration(milliseconds: 600),
      Curves.easeIn,
    );
  });

  testWidgets("C7 the grid's, Month's and Agenda's painters keep their "
      "paints across a rebuild that keeps the theme, and take B's", (
    tester,
  ) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    Paint fillIn(RecordingCanvas canvas, Color colour) {
      return canvas.records.firstWhere((record) {
        return !record.isLine && record.isIn(colour);
      }).paint;
    }

    Paint lineIn(RecordingCanvas canvas, Color colour) {
      return canvas.lines.firstWhere((record) {
        return record.isIn(colour);
      }).paint;
    }

    var background = paintGridBackground(tester);
    final body = fillIn(background, sentinelA.surface);
    final line = lineIn(background, sentinelA.outline);
    final now = lineIn(paintGridForeground(tester), sentinelA.error);
    await tester.tap(find.byKey(dayHeaderKey(april(23))));
    await tester.pumpAndSettle();
    background = paintGridBackground(tester);
    expect(identical(fillIn(background, sentinelA.surface), body), isTrue);
    expect(identical(lineIn(background, sentinelA.outline), line), isTrue);
    expect(
      identical(lineIn(paintGridForeground(tester), sentinelA.error), now),
      isTrue,
    );
    await installTheme(tester, api, sentinelB);
    background = paintGridBackground(tester);
    final bodyB = fillIn(background, sentinelB.surface);
    expect(identical(bodyB, body), isFalse);
    expect(identical(lineIn(background, sentinelB.outline), line), isFalse);
    expect(
      identical(lineIn(paintGridForeground(tester), sentinelB.error), now),
      isFalse,
    );
    await installTheme(tester, api, sentinelA);
    await tester.pumpAndSettle();

    // Month's background, around a rebuild of an equal theme.
    await pickMode(tester, "Month");
    final month = paintGridBackground(tester);
    final outside = fillIn(month, sentinelA.background);
    final monthLine = lineIn(month, sentinelA.outline);
    await installTheme(tester, api, sentinelA.copyWith());
    await tester.pumpAndSettle();
    expect(
      identical(
        fillIn(paintGridBackground(tester), sentinelA.background),
        outside,
      ),
      isTrue,
    );
    expect(
      identical(
        lineIn(paintGridBackground(tester), sentinelA.outline),
        monthLine,
      ),
      isTrue,
    );
    await installTheme(tester, api, sentinelB);
    expect(
      identical(
        lineIn(paintGridBackground(tester), sentinelB.outline),
        monthLine,
      ),
      isFalse,
    );
    await installTheme(tester, api, sentinelA);
    await tester.pumpAndSettle();

    // Agenda's dashed line, around a rebuild of its rows.
    await pickMode(tester, "Agenda");
    Paint dashed() {
      final paint = tester.widget<CustomPaint>(
        find.byWidgetPredicate((widget) {
          return widget is CustomPaint &&
              widget.painter.runtimeType.toString() == "_DashedLinePainter";
        }).first,
      );
      final canvas = RecordingCanvas();
      paint.painter!.paint(canvas, const Size(40.0, 24.0));
      return canvas.lines.first.paint;
    }

    final dash = dashed();
    expect(dash.color.toARGB32(), sentinelA.outline.toARGB32());
    storeOf(tester).requestDelete("item-13");
    await tester.pump();
    expect(identical(dashed(), dash), isTrue);
    await tester.pumpAndSettle();
    await installTheme(tester, api, sentinelB);
    final dashB = dashed();
    expect(identical(dashB, dash), isFalse);
    expect(dashB.color.toARGB32(), sentinelB.outline.toARGB32());
  });

  testWidgets("C8 the first hour label's paragraph is kept across a rebuild "
      "that keeps the theme, and laid out again for B", (tester) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    final first = paintGridForeground(tester).paragraphs.first.paragraph;
    await tester.tap(find.byKey(dayHeaderKey(april(23))));
    await tester.pumpAndSettle();
    expect(
      identical(paintGridForeground(tester).paragraphs.first.paragraph, first),
      isTrue,
    );
    await installTheme(tester, api, sentinelB);
    expect(
      identical(paintGridForeground(tester).paragraphs.first.paragraph, first),
      isFalse,
    );
  });

  testWidgets("C9 blocks, chips, cards and strip days share their prepared "
      "styles, and a rebuild that mounts nothing keeps them and the prepared "
      "widgets", (tester) async {
    await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    await pickHours(tester, 8, 18);
    final planning = blockTitleOf(tester, "item-1", "Planning").style!;
    expect(
      identical(blockTitleOf(tester, "item-6", "Slot 1").style, planning),
      isTrue,
    );
    final gutter = gutterCells(tester);
    expect(gutter.length, greaterThan(4));
    Widget cutArrow() {
      return tester.widget(
        find.descendant(
          of: blockFinder("item-2"),
          matching: find.byType(Positioned),
        ),
      );
    }

    final arrow = cutArrow();
    final element = tester.element(blockFinder("item-1"));
    final widget = element.widget;
    // A write's sync rebuilds the board's delegate, which mounts nothing.
    storeOf(tester).requestDelete("item-12");
    await tester.pump();
    expect(identical(tester.element(blockFinder("item-1")), element), isTrue);
    expect(
      identical(tester.element(blockFinder("item-1")).widget, widget),
      isFalse,
    );
    expect(
      identical(blockTitleOf(tester, "item-1", "Planning").style, planning),
      isTrue,
    );
    final gutterAfter = gutterCells(tester);
    expect(gutterAfter, hasLength(gutter.length));
    for (var i = 0; i < gutter.length; i++) {
      expect(identical(gutterAfter[i], gutter[i]), isTrue, reason: "gutter $i");
    }
    expect(identical(cutArrow(), arrow), isTrue);
    await tester.pumpAndSettle();

    // Month's chips.
    await pickMode(tester, "Month");
    TextStyle chipTitle(String id, String title) {
      return tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(monthChipKey(monthSegmentKey(id, april(20)))),
              matching: find.text(title),
            ),
          )
          .style!;
    }

    expect(
      identical(
        chipTitle("item-1", "Planning"),
        chipTitle("item-2", "Early sync"),
      ),
      isTrue,
    );

    // Agenda's cards and prepared widgets, across a rebuild of its rows.
    await pickMode(tester, "Agenda");
    TextStyle cardTitle(String id, String title) {
      return tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(itemCardKey(id)),
              matching: find.text(title),
            ),
          )
          .style!;
    }

    await revealDay(tester, april(21));
    final cards = cardTitle("item-2", "Early sync");
    expect(identical(cardTitle("item-3", "Late sync"), cards), isTrue);
    List<Widget> prepared() {
      final themed = iconsOf(sentinelA);
      final icons = tester
          .widgetList<Icon>(
            find.descendant(
              of: find.byType(DayList<ItemPayload>),
              matching: find.byType(Icon),
            ),
          )
          .where((icon) {
            return themed.contains(icon.icon);
          })
          .toList();
      final lines = tester
          .widgetList(
            find.descendant(
              of: find.byType(DayList<ItemPayload>),
              matching: find.byWidgetPredicate((widget) {
                if (widget is! Expanded) {
                  return false;
                }
                final child = widget.child;
                return child is CustomPaint ||
                    child is SizedBox && child.child is CustomPaint;
              }),
            ),
          )
          .toList();
      return <Widget>[...icons, ...lines];
    }

    final widgets = prepared();
    // Setup sanity: the prepared widgets include the current-time line and
    // a gap's dashed line.
    expect(
      widgets.whereType<Expanded>().map((line) {
        return line.child.runtimeType;
      }).toSet(),
      <Type>{CustomPaint, SizedBox},
    );
    final card = tester.element(find.byKey(itemCardKey("item-2")));
    final cardWidget = card.widget;
    storeOf(tester).requestDelete("item-13");
    await tester.pump();
    expect(
      identical(tester.element(find.byKey(itemCardKey("item-2"))), card),
      isTrue,
    );
    expect(
      identical(
        tester.element(find.byKey(itemCardKey("item-2"))).widget,
        cardWidget,
      ),
      isFalse,
    );
    final after = prepared();
    expect(after, hasLength(widgets.length));
    for (var i = 0; i < widgets.length; i++) {
      expect(identical(after[i], widgets[i]), isTrue, reason: "${widgets[i]}");
    }
    expect(identical(cardTitle("item-2", "Early sync"), cards), isTrue);
    await tester.pumpAndSettle();

    // Strip days' weekday names, across the rebuild a tap makes.
    await pickMode(tester, "Day");
    TextStyle weekday(DateTime day, String name) {
      return tester
          .widget<Text>(
            find.descendant(of: stripCellOf(day), matching: find.text(name)),
          )
          .style!;
    }

    final name = weekday(april(22), "Wed");
    expect(identical(weekday(april(23), "Thu"), name), isTrue);
    await tester.tap(find.byKey(weekStripDayKey(april(24))));
    await tester.pumpAndSettle();
    expect(identical(weekday(april(22), "Wed"), name), isTrue);
  });

  testWidgets("C6 a hot reload makes the grid's styles anew", (tester) async {
    await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    final title = blockTitleOf(tester, "item-1", "Planning").style!;
    hotReload(tester);
    await tester.pump();
    final remade = blockTitleOf(tester, "item-1", "Planning").style!;
    expect(remade, title);
    expect(identical(remade, title), isFalse);
  });

  testWidgets("C15 bold text lays the hour labels out again, merged over "
      "the theme's hour label style", (tester) async {
    await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    await labelsOf(tester, sentinelA);
    final first = paintGridForeground(tester).paragraphs.first.paragraph;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(boldText: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(
      identical(paintGridForeground(tester).paragraphs.first.paragraph, first),
      isFalse,
    );
    await labelsOf(tester, sentinelA);
    expect(tester.takeException(), isNull);
  });

  test("C1 harborCalendarTheme takes each HarborColors value, the Harbor "
      "constants, the Material icons the views drew, and the built-in text "
      "styles", () {
    const harbor = harborCalendarTheme;
    expect(coloursOf(harbor), const <Color>[
      HarborColors.primary,
      HarborColors.onPrimary,
      HarborColors.primaryTint,
      HarborColors.background,
      HarborColors.surface,
      HarborColors.outline,
      HarborColors.text,
      HarborColors.textSecondary,
      HarborColors.textMuted,
      HarborColors.error,
      HarborColors.notice,
      HarborColors.noticeEdge,
      HarborColors.onNotice,
      HarborColors.todayRing,
    ]);
    expect(harbor.todayRingWidth, 2.0);
    expect(harbor.draggedBlockOpacity, harborDraggedItemOpacity);
    expect(harbor.motionDuration, harborMotionDuration);
    expect(harbor.motionCurve, harborMotionCurve);
    expect(iconsOf(harbor), const <IconData>[
      Icons.keyboard_arrow_up,
      Icons.keyboard_arrow_down,
      Icons.hourglass_empty,
      Icons.more_horiz,
      Icons.add,
    ]);
    expect(stylesOf(harbor), stylesOf(const CalendarThemeData()));
  });

  testWidgets("C10 each text draws the style and the colour field the "
      "theme names for it", (tester) async {
    final theme = sentinelA;
    final api = await pumpThemed(tester, theme);
    await pickHours(tester, 8, 18);

    // Agenda's month and list, today apart from the selected Thursday.
    await revealDay(tester, april(23));
    expectText(
      tester,
      textIn(cellOf(april(22)), "22"),
      theme,
      "dayNumberStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(cellOf(april(23)), "23"),
      theme,
      "dayNumberMarkedStyle",
      theme.onPrimary,
    );
    expectText(
      tester,
      textIn(cellOf(april(21)), "21"),
      theme,
      "dayNumberMarkedStyle",
      theme.primary,
    );
    expectText(
      tester,
      textIn(find.byType(WeekdayHeader), "Mon"),
      theme,
      "weekdayHeaderStyle",
      theme.textMuted,
    );
    final thursday = find.byKey(dayListHeaderKey(april(23)));
    expectText(
      tester,
      textIn(thursday, dayTitle(april(23), april(21))),
      theme,
      "agendaHeaderTitleStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(thursday, "2 items"),
      theme,
      "agendaHeaderCountStyle",
      theme.textSecondary,
    );
    expectText(
      tester,
      find.descendant(
        of: find.byKey(dayListHiddenKey(april(23), above: true)),
        matching: find.byType(Text),
      ),
      theme,
      "noticeStyle",
      theme.onNotice,
    );
    expectText(
      tester,
      textIn(find.byKey(dayListGapKey(april(23), 8 * 60)), "08:00"),
      theme,
      "agendaTimeStyle",
      theme.textMuted,
    );
    await revealDay(tester, april(21));
    expectText(
      tester,
      textIn(find.byKey(dayListTimeKey("item-1")), "09:00"),
      theme,
      "agendaTimeStyle",
      theme.textSecondary,
    );
    expectText(
      tester,
      textIn(find.byKey(dayListDurationKey("item-1")), "1h"),
      theme,
      "badgeStyle",
      theme.primary,
    );
    expectText(
      tester,
      textIn(find.byKey(dayListNowKey), "09:30"),
      theme,
      "badgeStyle",
      theme.onPrimary,
    );
    expectText(
      tester,
      textIn(find.byKey(itemCardKey("item-1")), "Planning"),
      theme,
      "entryCardTitleStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(find.byKey(itemCardKey("item-1")), "Room 2"),
      theme,
      "entryCardSummaryStyle",
      theme.textSecondary,
    );
    await revealDay(tester, april(22));
    expectText(
      tester,
      find.descendant(
        of: find.byKey(itemCardStartsAtKey("item-2")),
        matching: find.byType(Text),
      ),
      theme,
      "noticeStyle",
      theme.onNotice,
    );
    await revealDay(tester, april(26));
    final sunday = find.byKey(dayListHeaderKey(april(26)));
    expectText(
      tester,
      textIn(sunday, dayTitle(april(26), april(21))),
      theme,
      "agendaHeaderEmptyTitleStyle",
      theme.textMuted,
    );
    expectText(
      tester,
      textIn(sunday, "No items"),
      theme,
      "agendaHeaderEmptyCountStyle",
      theme.textMuted,
    );

    // Day's strip and detailed blocks.
    await revealDay(tester, april(21));
    await pickMode(tester, "Day");
    expectText(
      tester,
      textIn(stripCellOf(april(22)), "Wed"),
      theme,
      "stripWeekdayStyle",
      theme.textMuted,
    );
    expectText(
      tester,
      textIn(stripCellOf(april(22)), "22"),
      theme,
      "dayNumberMarkedStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(blockFinder("item-1"), "Planning"),
      theme,
      "detailedBlockTitleStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(blockFinder("item-1"), "09:00-10:00"),
      theme,
      "detailedBlockDetailStyle",
      theme.textSecondary,
    );

    // Week's header, blocks, notice cells, landing label and hidden pill.
    await pickMode(tester, "Week");
    expectText(
      tester,
      textIn(find.byKey(dayHeaderKey(april(22))), "We"),
      theme,
      "dayHeaderWeekdayStyle",
      theme.textSecondary,
    );
    expectText(
      tester,
      textIn(find.byKey(dayHeaderKey(april(22))), "22"),
      theme,
      "dayHeaderNumberStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(find.byKey(dayHeaderKey(april(21))), "21"),
      theme,
      "dayHeaderNumberStyle",
      theme.primary,
    );
    expectText(
      tester,
      textIn(blockFinder("item-1"), "Planning"),
      theme,
      "blockTitleStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(blockFinder("item-1"), "Room 2"),
      theme,
      "blockSummaryStyle",
      theme.textSecondary,
    );
    expectText(
      tester,
      find.descendant(
        of: find.byKey(hiddenAboveKey(april(23))),
        matching: find.byType(Text),
      ),
      theme,
      "noticeStyle",
      theme.onNotice,
    );
    final gesture = await liftBlock(tester, "item-6", slots: 8.0);
    expectText(
      tester,
      find.descendant(
        of: find.byKey(landingLabelKey),
        matching: find.byType(Text),
      ),
      theme,
      "landingLabelStyle",
      theme.onPrimary,
    );
    await gesture.cancel();
    await tester.pumpAndSettle();
    await openBar(tester);
    flipWeekends(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);
    expectText(
      tester,
      textIn(find.byKey(hiddenCountKey), "+1"),
      theme,
      "badgeStyle",
      theme.primary,
    );
    await openBar(tester);
    flipWeekends(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);

    // Month's numbers, letters, "+N more", chips and picker.
    await tester.tap(find.byKey(dayHeaderKey(april(23))));
    await tester.pumpAndSettle();
    await pickMode(tester, "Month");
    expectText(
      tester,
      textIn(find.byKey(monthDayKey(april(22))), "22"),
      theme,
      "monthDayNumberStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(find.byKey(monthDayKey(DateTime(2026, 3, 30))), "30"),
      theme,
      "monthDayNumberStyle",
      theme.textMuted,
    );
    expectText(
      tester,
      textIn(find.byKey(monthDayKey(april(23))), "23"),
      theme,
      "monthDayNumberMarkedStyle",
      theme.onPrimary,
    );
    expectText(
      tester,
      textIn(find.byKey(monthDayKey(april(21))), "21"),
      theme,
      "monthDayNumberMarkedStyle",
      theme.primary,
    );
    expectText(
      tester,
      find.descendant(
        of: find.byKey(monthMoreKey(april(24))),
        matching: find.byType(Text),
      ),
      theme,
      "monthMoreStyle",
      theme.onNotice,
    );
    expectText(
      tester,
      textIn(
        find.byKey(monthChipKey(monthSegmentKey("item-1", april(20)))),
        "Planning",
      ),
      theme,
      "chipTitleStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(find.byType(WeekdayHeader), "M"),
      theme,
      "weekdayLetterStyle",
      theme.text,
    );
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(monthPickerMonthKey(DateTime(2026, 5))));
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expectText(
      tester,
      textIn(find.byKey(monthPickerMonthKey(DateTime(2026, 5))), "May"),
      theme,
      "monthNameMarkedStyle",
      theme.onPrimary,
    );
    expectText(
      tester,
      textIn(find.byKey(monthPickerMonthKey(DateTime(2026, 4))), "April"),
      theme,
      "monthNameMarkedStyle",
      theme.primary,
    );
    expectText(
      tester,
      textIn(find.byKey(monthPickerMonthKey(DateTime(2026, 6))), "June"),
      theme,
      "monthNameStyle",
      theme.text,
    );
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();

    // A failed read's message.
    await pickMode(tester, "Week");
    await failNextRead(tester, api, "Next week");
    expectText(
      tester,
      textIn(find.byType(TimedGrid<ItemPayload>), "Reading failed."),
      theme,
      "messageStyle",
      theme.error,
    );

    // Month's cards, at a size whose days hold them.
    await pumpThemed(tester, theme, size: const Size(1100.0, 900.0));
    await pickMode(tester, "Month");
    final card = find.byKey(monthChipKey(monthSegmentKey("item-1", april(20))));
    expectText(
      tester,
      textIn(card, "Planning"),
      theme,
      "monthCardTitleStyle",
      theme.text,
    );
    expectText(
      tester,
      textIn(card, "09:00-10:00"),
      theme,
      "monthCardTimeStyle",
      theme.textSecondary,
    );
  });

  testWidgets("C10 each fill, edge, ring, line and icon draws the colour "
      "field the theme names for it", (tester) async {
    final theme = sentinelA;
    final api = await pumpThemed(tester, theme);
    await pickHours(tester, 8, 18);

    // Agenda's month and list, today apart from the selected Thursday.
    await revealDay(tester, april(23));
    expectColour(
      boxFillOf(tester, cellOf(april(23))),
      theme.primary,
      "selected day",
    );
    expectColour(
      boxFillOf(tester, cellOf(april(22))),
      theme.background,
      "a day",
    );
    final ring = decorationOf(
      tester,
      cellOf(april(21)),
      position: DecorationPosition.foreground,
    );
    expectColour(
      (ring.border! as Border).top.color,
      theme.todayRing,
      "today's ring",
    );
    expect((ring.border! as Border).top.width, theme.todayRingWidth);
    final badge = decorationOf(tester, find.byKey(dayBadgeKey(april(22))));
    expectColour(badge.color!, theme.primary, "badge");
    expectColour(
      (badge.border! as Border).top.color,
      theme.surface,
      "badge ring",
    );
    expectColour(
      tester.widget<ColoredBox>(find.byKey(dayListHeaderKey(april(23)))).color,
      theme.background,
      "header band",
    );
    final above = find.byKey(dayListHiddenKey(april(23), above: true));
    final banner = decorationOf(tester, above);
    expectColour(banner.color!, theme.notice, "banner");
    expectColour(
      (banner.border! as Border).top.color,
      theme.noticeOutline,
      "banner edge",
    );
    expectColour(
      iconColourOf(tester, above, theme.beforeHoursIcon),
      theme.onNotice,
      "banner arrow",
    );
    final below = find.byKey(dayListHiddenKey(april(23), above: false));
    expectColour(
      iconColourOf(tester, below, theme.afterHoursIcon),
      theme.onNotice,
      "banner arrow",
    );
    await revealDay(tester, april(21));
    final chip = find.byKey(dayListDurationKey("item-1"));
    expectColour(
      decorationOf(tester, chip).color!,
      theme.primaryTint,
      "duration chip",
    );
    expectColour(
      iconColourOf(tester, chip, theme.durationIcon),
      theme.primary,
      "hourglass",
    );
    final now = find.byKey(dayListNowKey);
    expectColour(decorationOf(tester, now).color!, theme.error, "time pill");
    expectColour(lineColourOf(tester, now), theme.error, "time line");
    final card = find.byKey(itemCardKey("item-1"));
    expectColour(
      iconColourOf(tester, card, theme.entryMenuIcon),
      theme.textMuted,
      "menu icon",
    );
    expectColour(
      tester
          .widget<PopupMenuButton<Object?>>(
            find.descendant(
              of: card,
              matching: find.byWidgetPredicate((widget) {
                return widget is PopupMenuButton;
              }),
            ),
          )
          .color!,
      theme.surface,
      "menu",
    );
    final gap = find.byKey(dayListGapKey(april(21), 10 * 60));
    expectColour(lineColourOf(tester, gap), theme.outline, "dashed line");
    expectColour(
      tester
          .widget<Material>(
            find.descendant(of: gap, matching: find.byType(Material)),
          )
          .color!,
      theme.primaryTint,
      "add button",
    );
    expectColour(
      iconColourOf(tester, gap, theme.addEntryIcon),
      theme.primary,
      "plus",
    );
    await revealDay(tester, april(22));
    expectColour(
      decorationOf(tester, find.byKey(itemCardStartsAtKey("item-2"))).color!,
      theme.notice,
      "card strip",
    );

    // Week's paints, notice cells, header, blocks, handles and pills.
    await revealDay(tester, april(21));
    await pickMode(tester, "Week");
    final viewport = gridViewport(tester);
    final background = paintGridBackground(tester);
    Color fillAt(int col) {
      final left = viewport.rectOfCell(2, col)!.left;
      return background.records.lastWhere((record) {
        return !record.isLine &&
            record.isFill &&
            (record.rect!.left - left).abs() < 0.5 &&
            record.rect!.height > 100.0;
      }).color;
    }

    expectColour(fillAt(colOf(1)), theme.primaryTint, "today's column");
    expectColour(fillAt(colOf(5)), theme.background, "Saturday");
    expectColour(background.records.first.color, theme.surface, "body");
    for (final line in background.lines) {
      expectColour(line.color, theme.outline, "a grid line");
    }
    expectColour(
      paintGridForeground(tester).lines.first.color,
      theme.error,
      "time line",
    );
    final notice = find.byKey(hiddenAboveKey(april(23)));
    final noticeBox = decorationOf(tester, notice);
    expectColour(noticeBox.color!, theme.notice, "notice cell");
    expectColour(
      (noticeBox.border! as Border).bottom.color,
      theme.noticeOutline,
      "notice rule",
    );
    expectColour(
      iconColourOf(tester, notice, theme.beforeHoursIcon),
      theme.onNotice,
      "notice arrow",
    );
    final header = find.byKey(dayHeaderKey(april(21)));
    expectColour(
      tester
          .widget<ColoredBox>(
            find
                .descendant(of: header, matching: find.byType(ColoredBox))
                .first,
          )
          .color,
      theme.primaryTint,
      "selected header",
    );
    expectColour(
      tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byKey(dayHeaderKey(april(22))),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color,
      theme.surface,
      "header",
    );
    expectColour(
      (decorationOf(
                tester,
                header,
                position: DecorationPosition.foreground,
              ).border!
              as Border)
          .top
          .color,
      theme.todayRing,
      "header ring",
    );
    expectColour(
      iconColourOf(tester, blockFinder("item-2"), theme.beforeHoursIcon),
      theme.textSecondary,
      "cut arrow",
    );
    final gutter = find.byWidgetPredicate((widget) {
      return widget.runtimeType.toString() == "_GutterCell";
    }).first;
    expectColour(
      tester
          .widget<ColoredBox>(
            find.descendant(of: gutter, matching: find.byType(ColoredBox)),
          )
          .color,
      theme.surface,
      "gutter",
    );
    await selectBlock(tester, "item-1");
    final handles = find.byKey(blockHandlesKey("item-1"));
    expectColour(
      (decorationOf(tester, handles).border! as Border).top.color,
      theme.primary,
      "selection outline",
    );
    final grip = decorationOf(
      tester,
      find.byKey(blockGripKey("item-1", AxisDirection.down)),
    );
    expectColour(grip.color!, theme.primary, "grip");
    expectColour(
      (grip.border! as Border).top.color,
      theme.surface,
      "grip ring",
    );
    final gesture = await liftBlock(tester, "item-6", slots: 8.0);
    expectColour(
      decorationOf(tester, find.byKey(landingLabelKey)).color!,
      theme.primary,
      "landing pill",
    );
    await gesture.cancel();
    await tester.pumpAndSettle();
    await openBar(tester);
    flipWeekends(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);
    expectColour(
      decorationOf(tester, find.byKey(hiddenCountKey)).color!,
      theme.primaryTint,
      "hidden pill",
    );
    await openBar(tester);
    flipWeekends(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);

    // Month's paints, pills, ring and "+N more".
    await tester.tap(find.byKey(dayHeaderKey(april(23))));
    await tester.pumpAndSettle();
    await pickMode(tester, "Month");
    final month = paintGridBackground(tester);
    final monthViewport = gridViewport(tester);
    final march = monthViewport.rectOfCell(0, 0)!;
    expectColour(
      month.records.firstWhere((record) {
        return !record.isLine &&
            (record.rect!.topLeft - march.topLeft).distance < 0.5;
      }).color,
      theme.background,
      "a day of another month",
    );
    for (final line in month.lines) {
      expectColour(line.color, theme.outline, "a month line");
    }
    expectColour(
      decorationOf(tester, find.byKey(monthMoreKey(april(24)))).color!,
      theme.notice,
      "+N more",
    );
    expectColour(
      boxFillOf(tester, find.byKey(monthStripKey(april(23)))),
      theme.primary,
      "selected pill",
    );
    expectColour(
      (decorationOf(
                tester,
                find.byKey(monthStripKey(april(21))),
                position: DecorationPosition.foreground,
              ).border!
              as Border)
          .top
          .color,
      theme.todayRing,
      "Month's ring",
    );
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(monthPickerMonthKey(DateTime(2026, 5))));
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    expectColour(
      boxFillOf(tester, find.byKey(monthPickerMonthKey(DateTime(2026, 5)))),
      theme.primary,
      "selected month",
    );
    expectColour(
      boxFillOf(tester, find.byKey(monthPickerMonthKey(DateTime(2026, 6)))),
      theme.background,
      "a month",
    );
    expectColour(
      (decorationOf(
                tester,
                find.byKey(monthPickerMonthKey(DateTime(2026, 4))),
                position: DecorationPosition.foreground,
              ).border!
              as Border)
          .top
          .color,
      theme.todayRing,
      "current month's ring",
    );
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();

    // The scrim over a failed read.
    await pickMode(tester, "Week");
    await failNextRead(tester, api, "Next week");
    final scrim = tester
        .widget<ColoredBox>(
          find
              .ancestor(
                of: textIn(
                  find.byType(TimedGrid<ItemPayload>),
                  "Reading failed.",
                ),
                matching: find.byType(ColoredBox),
              )
              .first,
        )
        .color;
    expect(rgbOf(scrim), rgbOf(theme.background));
    expect(scrim.a, moreOrLessEquals(0.85, epsilon: 0.01));
  });

  testWidgets("C10 under A every view draws A's values alone, and together "
      "every field but the motion", (tester) async {
    var api = await pumpThemed(tester, sentinelA);
    final fields = <String>{};
    Future<void> visit(String where, {bool labels = false}) async {
      final drawn = drawnUnder(tester, viewRoots());
      expectOnly(drawn, sentinelA, forbidden: const [], reason: where);
      fields.addAll(fieldsOf(drawn, sentinelA));
      if (labels) {
        fields.addAll(await labelsOf(tester, sentinelA));
      }
    }

    Future<void> togglePicker() async {
      await tester.tap(
        find.byTooltip(
          find.byType(MonthPicker).evaluate().isEmpty
              ? "Pick a month"
              : "Close the months",
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> flipWeekendsShown() async {
      await openBar(tester);
      flipWeekends(tester);
      await tester.pumpAndSettle();
      await closeBar(tester);
    }

    await pickHours(tester, 8, 18);
    await visit("Agenda");
    for (final day in <DateTime>[april(22), april(23), april(26)]) {
      await revealDay(tester, day);
      await visit("Agenda, ${isoDate(day)}");
    }
    await revealDay(tester, april(21));
    await togglePicker();
    await visit("the picker in Agenda");
    await togglePicker();
    await pickMode(tester, "Day");
    await visit("Day", labels: true);
    await pickMode(tester, "Week");
    await visit("Week", labels: true);
    await selectBlock(tester, "item-1");
    await visit("a selected block");
    final gesture = await liftBlock(tester, "item-6", slots: 8.0);
    await visit("a lift");
    await gesture.cancel();
    await tester.pumpAndSettle();
    await togglePicker();
    await visit("the picker in Week");
    await togglePicker();
    await flipWeekendsShown();
    await visit("Week without weekends", labels: true);
    await flipWeekendsShown();
    await pickMode(tester, "Month");
    await visit("Month");

    // A failed read in each view.
    await failNextRead(tester, api, "Next month");
    expect(
      textIn(find.byType(MonthBoard<ItemPayload>), "Reading failed."),
      findsOneWidget,
    );
    await visit("Month, a failed read");
    for (final mode in <String>["Week", "Day", "Agenda"]) {
      await pickMode(tester, mode);
      expect(find.text("Reading failed."), findsWidgets, reason: mode);
      await visit("$mode, a failed read");
    }

    // Month's cards, at a size whose days hold them.
    api = await pumpThemed(tester, sentinelA, size: const Size(1100.0, 900.0));
    await pickMode(tester, "Month");
    await visit("Month's cards");

    final every = <String>{
      ...colourNames,
      "todayRingWidth",
      "draggedBlockOpacity",
      ...iconNames,
      ...styleNames,
    };
    expect(every, hasLength(52));
    expect(every.difference(fields), isEmpty);
  });

  testWidgets("C11 under A each animation runs 900 ms on a linear curve", (
    tester,
  ) async {
    final api = await pumpThemed(tester, sentinelA);
    expectListMotion(tester, const Duration(milliseconds: 900), Curves.linear);

    // An Agenda row growing in.
    await openBar(tester);
    setHours(tester, 7, 23);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      sizeFactorOf(tester, dayListGapKey(april(21), 7 * 60)),
      moreOrLessEquals(0.5),
    );
    await tester.pumpAndSettle();
    await closeBar(tester);

    // A reveal.
    final from = listOffset(tester);
    await tester.tap(cellOf(april(23)));
    await tester.pump();
    await tester.pump();
    final at = <double>[listOffset(tester)];
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 225));
      at.add(listOffset(tester));
    }
    await tester.pumpAndSettle();
    final distance = listOffset(tester) - from;
    for (final step in <double>[at[2] - at[1], at[3] - at[2]]) {
      expect(step / distance, inInclusiveRange(0.2, 0.3));
    }
    expect(at[4], moreOrLessEquals(listOffset(tester), epsilon: 0.5));

    // A strip slide.
    await pickMode(tester, "Day");
    final week = tester.getSize(find.byType(WeekStrip<ItemPayload>)).width;
    await tester.tap(find.byKey(weekStripDayKey(april(26))));
    await tester.pumpAndSettle();
    final strip = stripOffset(tester);
    await tester.tap(find.byTooltip("Next day"));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(
      stripOffset(tester) - strip,
      moreOrLessEquals(week / 2, epsilon: 1.0),
    );
    await tester.pumpAndSettle();

    // The grid's style and a lift, in today's week.
    await tapToday(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);
    await pickMode(tester, "Week");
    expectBoardMotion(
      gridBoard(tester).controller,
      const Duration(milliseconds: 900),
      Curves.linear,
    );
    final gesture = await liftBlock(tester, "item-7");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    final shadow = tester.widget<DecoratedBox>(find.byKey(liftedBlockKey));
    expect(
      (shadow.decoration as BoxDecoration).boxShadow!.first.color.a,
      moreOrLessEquals(liftedBlockShadows.first.color.a * 0.5, epsilon: 0.01),
    );
    await gesture.cancel();
    await tester.pumpAndSettle();

    // The month board's style and a picker slide.
    await pickMode(tester, "Month");
    expectBoardMotion(
      monthController(tester),
      const Duration(milliseconds: 900),
      Curves.linear,
    );
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next year"));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(pickerPosition(tester, 2026), moreOrLessEquals(2026.5));
    await tester.pumpAndSettle();
    expect(api.requests, isNotEmpty);
  });

  testWidgets("C12 every view draws B from the frame that installs it, and "
      "what starts after runs on B's motion", (tester) async {
    final b = sentinelB;
    for (final mode in <String>["Agenda", "Day", "Week", "Month"]) {
      final api = await pumpThemed(tester, sentinelA);
      if (mode != "Agenda") {
        await pickMode(tester, mode);
      }
      final grid = mode == "Day" || mode == "Week";
      var before = 0.0;
      if (grid) {
        before = gridViewport(tester).verticalPosition!.pixels;
        expect(before, greaterThan(6.5));
      }
      await installTheme(tester, api, b);
      if (grid) {
        final background = paintGridBackground(tester);
        expect(background.fillsOf(b.surface), isNotEmpty, reason: mode);
        expect(background.lines, isNotEmpty);
        for (final line in background.lines) {
          expect(line.isIn(b.outline), isTrue, reason: mode);
        }
        expectBlockTitles(tester, b);
        await labelsOf(tester, b);
        expect(
          gridViewport(tester).verticalPosition!.pixels,
          moreOrLessEquals(before + 0.5),
          reason: mode,
        );
      }
      if (mode == "Month") {
        final background = paintGridBackground(tester);
        expect(background.fillsOf(b.background), isNotEmpty);
        for (final line in background.lines) {
          expect(line.isIn(b.outline), isTrue);
        }
        final chip = find.byKey(
          monthChipKey(monthSegmentKey("item-1", april(20))),
        );
        expectText(
          tester,
          textIn(chip, "Planning"),
          b,
          "chipTitleStyle",
          b.text,
        );
      }
      if (mode == "Agenda" || mode == "Day") {
        final today = mode == "Agenda"
            ? cellOf(april(21))
            : stripCellOf(april(21));
        final other = mode == "Agenda"
            ? cellOf(april(22))
            : stripCellOf(april(22));
        expect(boxFillOf(tester, today), b.primary, reason: mode);
        expect(numberStyleOf(tester, today, april(21)).color, b.onPrimary);
        expect(boxFillOf(tester, other), b.background, reason: mode);
        expect(numberStyleOf(tester, other, april(22)).color, b.text);
      }
      if (mode == "Agenda") {
        expectText(
          tester,
          textIn(find.byKey(itemCardKey("item-1")), "Planning"),
          b,
          "entryCardTitleStyle",
          b.text,
        );
      }
      expectOnly(
        drawnUnder(tester, viewRoots()),
        b,
        forbidden: <CalendarThemeData>[sentinelA],
        reason: mode,
      );
      await tester.pumpAndSettle();

      switch (mode) {
        case "Agenda":
          // A gap row coming in on new hours, on B's motion.
          await openBar(tester);
          setHours(tester, 7, 23);
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            sizeFactorOf(tester, dayListGapKey(april(21), 7 * 60)),
            moreOrLessEquals(Curves.easeIn.transform(0.5)),
          );
          await tester.pumpAndSettle();
          await closeBar(tester);
        case "Day":
          // A strip slide on B's motion.
          final week = tester
              .getSize(find.byType(WeekStrip<ItemPayload>))
              .width;
          await tester.tap(find.byKey(weekStripDayKey(april(26))));
          await tester.pumpAndSettle();
          final from = stripOffset(tester);
          await tester.tap(find.byTooltip("Next day"));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            stripOffset(tester) - from,
            moreOrLessEquals(week * Curves.easeIn.transform(0.5), epsilon: 1.0),
          );
          await tester.pumpAndSettle();
        case "Week":
          // The board's style, and a lift fading its block at B's alpha.
          expectBoardMotion(
            gridBoard(tester).controller,
            const Duration(milliseconds: 600),
            Curves.easeIn,
          );
          final gesture = await liftBlock(tester, "item-7");
          await tester.pump();
          expect(gridBoard(tester).drag!.draggedItemOpacity, 0.3);
          expect(
            drawnUnder(tester, <Finder>[
              find.byType(TimedGrid<ItemPayload>),
            ]).alphas,
            contains(Color.getAlphaFromOpacity(0.3)),
          );
          await gesture.cancel();
          await tester.pumpAndSettle();
        case "Month":
          expectBoardMotion(
            monthController(tester),
            const Duration(milliseconds: 600),
            Curves.easeIn,
          );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets("C12 B installed while the pull tab folds the month lays the "
      "card out again, and the folded strip is as tall as B's weekday line "
      "makes it", (tester) async {
    final api = await pumpThemed(tester, sentinelA);
    final row = tester.getSize(find.byType(DayCell).first).height;
    final fold = 4 * row + weekdayHeaderHeight;
    final gesture = await foldBy(tester, fold * 2.0 / 3.0);
    final t = tester.widget<DayCell>(cellOf(april(22))).collapse.value;
    expect(t, inExclusiveRange(0.5, 1.0));
    await installTheme(tester, api, sentinelB);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await gesture.up();
    await tester.pumpAndSettle();
    final strip = tester.element(find.byType(WeekStrip<ItemPayload>));
    expect(
      tester.getSize(find.byType(WeekStrip<ItemPayload>)).height,
      moreOrLessEquals(
        lineHeightAt(strip, sentinelB.stripWeekdayStyle) +
            stripLabelGap +
            dayCircleSize,
      ),
    );
    // Setup sanity: B's weekday line is not A's.
    expect(
      lineHeightAt(strip, sentinelB.stripWeekdayStyle),
      isNot(lineHeightAt(strip, sentinelA.stripWeekdayStyle)),
    );
  });

  testWidgets("C12 animations running when a theme is installed run on to "
      "their end, and one the new theme turns off stops", (tester) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    Future<double> midExit(String id) async {
      storeOf(tester).requestDelete(id);
      await tester.pump();
      await tester.pump(api.latency);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 300));
      return tester.getSize(blockFinder(id)).width;
    }

    // A block shrinking away under A runs on under B, on B's curve from
    // the next tick, to its end.
    var width = await midExit("item-6");
    expect(width, greaterThan(0.0));
    await installTheme(tester, api, sentinelB);
    await tester.pump(const Duration(milliseconds: 16));
    expect(blockFinder("item-6"), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(blockFinder("item-6"), findsOneWidget);
    await tester.pumpAndSettle();
    expect(blockFinder("item-6"), findsNothing);

    // One shrinking under B stops at once under a theme whose motion is
    // off.
    width = await midExit("item-7");
    expect(width, greaterThan(0.0));
    await installTheme(
      tester,
      api,
      sentinelB.copyWith(motionDuration: Duration.zero),
    );
    await tester.pump();
    expect(blockFinder("item-7"), findsNothing);
    await installTheme(tester, api, sentinelA);
    await tester.pumpAndSettle();

    // An Agenda row growing in under A runs on under B to its end.
    await pickMode(tester, "Agenda");
    await openBar(tester);
    setHours(tester, 7, 23);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final gap = dayListGapKey(april(21), 7 * 60);
    final grown = sizeFactorOf(tester, gap);
    expect(grown, inExclusiveRange(0.0, 1.0));
    await installTheme(tester, api, sentinelB);
    await tester.pump(const Duration(milliseconds: 16));
    expect(sizeFactorOf(tester, gap), greaterThan(grown));
    await tester.pumpAndSettle();
    expect(sizeFactorOf(tester, gap), 1.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets("C12 a theme moving from A to B over several frames keeps a "
      "lift's session and a running exit, and lands on B's values", (
    tester,
  ) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickMode(tester, "Week");
    final slot = tester.getRect(blockFinder("item-6"));
    final gesture = await liftBlock(tester, "item-6", slots: 2.0);
    for (var i = 1; i <= 5; i++) {
      await installTheme(
        tester,
        api,
        CalendarThemeData.lerp(sentinelA, sentinelB, i / 5.0),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(liftedBlockKey), findsOneWidget, reason: "frame $i");
    }
    expect(gridBoard(tester).drag!.draggedItemOpacity, 0.3);
    expectOnly(
      drawnUnder(tester, <Finder>[find.byType(TimedGrid<ItemPayload>)]),
      sentinelB,
      forbidden: <CalendarThemeData>[sentinelA],
      reason: "the lerp's end",
    );
    await gesture.moveBy(Offset(0.0, slot.height * 6.0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(gridAnimationStyle(tester).effectiveDropSettle.duration);
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
    final stored = (await listAll(
      tester,
      api,
      april(24),
      april(24),
    )).firstWhere((item) => item["title"] == "Slot 1");
    expect(stored["startMinute"], 12 * 60);

    // An exit runs on through the frames of a theme moving back to A.
    storeOf(tester).requestDelete("item-7");
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pump(const Duration(milliseconds: 16));
    expect(blockFinder("item-7"), findsOneWidget);
    for (var i = 1; i <= 5; i++) {
      await installTheme(
        tester,
        api,
        CalendarThemeData.lerp(sentinelB, sentinelA, i / 5.0),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(blockFinder("item-7"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("C13 with no motion each animation stands at its end one "
      "frame after the change that starts it, and the strip reports a drag "
      "after a jump", (tester) async {
    final still = sentinelA.copyWith(motionDuration: Duration.zero);
    final api = await pumpThemed(tester, still);

    // An Agenda row coming in.
    await openBar(tester);
    setHours(tester, 7, 23);
    await tester.pump();
    expect(sizeFactorOf(tester, dayListGapKey(april(21), 7 * 60)), 1.0);
    await tester.pumpAndSettle();
    await closeBar(tester);

    // A reveal, which the frame of the tap starts after it.
    await tester.tap(cellOf(april(23)));
    await tester.pump();
    await tester.pump();
    expect(
      tester.getRect(find.byKey(dayListHeaderKey(april(23)))).top,
      moreOrLessEquals(
        tester.getRect(find.byType(DayList<ItemPayload>)).top,
        epsilon: 0.5,
      ),
    );
    await tester.pumpAndSettle();

    // A strip slide, then a drag of the strip into the next month, which
    // the header names.
    await pickMode(tester, "Day");
    final week = tester.getSize(find.byType(WeekStrip<ItemPayload>)).width;
    await tester.tap(find.byKey(weekStripDayKey(april(26))));
    await tester.pumpAndSettle();
    final from = stripOffset(tester);
    await tester.tap(find.byTooltip("Next day"));
    await tester.pump();
    expect(stripOffset(tester) - from, moreOrLessEquals(week));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(WeekStrip<ItemPayload>)),
    );
    await drag.moveBy(const Offset(-(kTouchSlop + 1.0), 0.0));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await drag.moveBy(Offset(-week / 4.0, 0.0));
      await tester.pump();
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text("May 2026"), findsOneWidget);

    // A lift.
    await tapToday(tester);
    await tester.pumpAndSettle();
    await closeBar(tester);
    await pickMode(tester, "Week");
    final gesture = await liftBlock(tester, "item-7");
    await tester.pump();
    final shadow = tester.widget<DecoratedBox>(find.byKey(liftedBlockKey));
    expect(
      (shadow.decoration as BoxDecoration).boxShadow!.first.color.a,
      moreOrLessEquals(liftedBlockShadows.first.color.a),
    );
    await gesture.cancel();
    await tester.pumpAndSettle();

    // A picker slide.
    await pickMode(tester, "Month");
    await tester.tap(find.byTooltip("Pick a month"));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip("Next year"));
    await tester.pump();
    expect(pickerPosition(tester, 2027), 2027.0);
    await tester.tap(find.byTooltip("Close the months"));
    await tester.pumpAndSettle();

    // A create confirmed in Month, whose chip the board's sync grows in.
    final cell = tester.getRect(find.byKey(monthDayKey(april(27))));
    await tester.longPressAt(Offset(cell.center.dx, cell.bottom - 4.0));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Task").last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, "Title"), "New");
    await tester.tap(find.byType(FilledButton));
    await tester.pump(api.latency);
    await tester.pump(const Duration(milliseconds: 16));
    final chip = find.byKey(
      monthChipKey(monthSegmentKey("item-14", april(27))),
    );
    expect(tester.getSize(chip).height, monthLaneExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets("C14 under larger Agenda text a reveal past rows the list has "
      "not laid out lands its day's header at the list's top", (tester) async {
    TextStyle larger(TextStyle style) {
      return style.copyWith(fontSize: style.fontSize! + 6.0);
    }

    await pumpThemed(
      tester,
      sentinelA.copyWith(
        agendaHeaderTitleStyle: larger(sentinelA.agendaHeaderTitleStyle),
        agendaHeaderCountStyle: larger(sentinelA.agendaHeaderCountStyle),
        entryCardTitleStyle: larger(sentinelA.entryCardTitleStyle),
        entryCardSummaryStyle: larger(sentinelA.entryCardSummaryStyle),
      ),
    );
    final target = april(29);
    // Setup sanity: the list has not laid out the day eight days ahead.
    expect(find.byKey(dayListHeaderKey(target)), findsNothing);
    await tester.tap(cellOf(target));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(dayListHeaderKey(target))).top,
      moreOrLessEquals(
        tester.getRect(find.byType(DayList<ItemPayload>)).top,
        epsilon: 0.5,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
