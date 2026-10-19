/// The calendar views draw what [CalendarTheme] holds: two sentinel themes,
/// whose every value differs from Harbor's, from the built-in ones and from
/// each other, and a probe that reads what each view paints.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/widgets_extended.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_bar.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/day_cell.dart';
import 'package:workspace_calendar/workspace_calendar/day_list.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
import 'package:workspace_calendar/workspace_calendar/item_card.dart';
import 'package:workspace_calendar/workspace_calendar/mock_calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/month_board.dart';
import 'package:workspace_calendar/workspace_calendar/month_picker.dart';
import 'package:workspace_calendar/workspace_calendar/timed_grid.dart';
import 'package:workspace_calendar/workspace_calendar/week_strip.dart';
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

/// The thirty-one text style fields, numbered from 1 in this order.
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
      for (final element in find
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
  final bannedIcons = <IconData>{
    for (final other in banned) ...iconsOf(other),
  };
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
Future<int> pixelAt(WidgetTester tester, RenderObject over, Offset point) async {
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
  final context = tester.element(find.byType(TimedGrid));
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
      .widget<Text>(find.descendant(of: cell, matching: find.text("${day.day}")))
      .style!;
}

/// How far the week strip has scrolled.
double stripOffset(WidgetTester tester) {
  return tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(WeekStrip),
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
          of: find.byType(DayList),
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
            .ancestor(of: find.byKey(key), matching: find.byType(SizeTransition))
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
BoardController<String, MonthChip> monthController(WidgetTester tester) {
  return tester
      .widget<Board<String, MonthChip>>(find.byType(Board<String, MonthChip>))
      .controller;
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
      tagsOf(sentinelA).keys.toSet().intersection(tagsOf(sentinelB).keys.toSet()),
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
      expect(harborArgb.contains(colour.toARGB32()), isFalse, reason: "$colour");
    }
  });

  testWidgets("C2 under Harbor the probe finds the timed grid's colours and "
      "the ambient letter spacing, and skips a failed read's Retry", (
    tester,
  ) async {
    final api = await pumpThemed(tester, harborCalendarTheme);
    await pickMode(tester, "Week");
    final drawn = drawnUnder(tester, <Finder>[find.byType(TimedGrid)]);
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
    final tags = <double>{
      ...tagsOf(sentinelA).keys,
      ...tagsOf(sentinelB).keys,
    };
    expect(drawn.spacings.intersection(tags), isEmpty);

    await failNextRead(tester, api, "Next week");
    final message = find.descendant(
      of: find.byType(TimedGrid),
      matching: find.text("Reading failed."),
    );
    final retry = find.descendant(
      of: find.byType(TimedGrid),
      matching: find.text("Retry"),
    );
    expect(message, findsOneWidget);
    expect(retry, findsOneWidget);
    final failed = drawnUnder(tester, <Finder>[find.byType(TimedGrid)]);
    final retryLabel = tester.renderObject<RenderParagraph>(retry);
    expect(
      failed.paragraphs.contains(tester.renderObject(message)),
      isTrue,
    );
    expect(failed.paragraphs.contains(retryLabel), isFalse);
    expect(failed.styles.contains(retryLabel.text.style), isFalse);
  });

  testWidgets("C3 day cells, weekday headers, the strip and the picker draw "
      "and run on A, and on B from the frame that installs it", (
    tester,
  ) async {
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
    final week = tester.getSize(find.byType(WeekStrip)).width;
    await tester.tap(find.byKey(weekStripDayKey(april(26))));
    await tester.pumpAndSettle();
    var from = stripOffset(tester);
    await tester.tap(find.byTooltip("Next day"));
    // The frame that rebuilds the strip starts the slide after it; the
    // slide's first tick is the next frame.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(stripOffset(tester) - from, moreOrLessEquals(week / 2, epsilon: 1.0));
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
    final strip = tester.element(find.byType(WeekStrip));
    expect(
      tester.getSize(find.byType(WeekStrip)).height,
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
    final scaler = tester.widget<MonthCell>(find.byType(MonthCell).first)
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
      numberStyleOf(tester, cellOf(may(1)), may(1)),
      TextStyle.lerp(a.fromMuted, a.to, t),
    );
    final selected = numberStyleOf(tester, cellOf(april(24)), april(24));
    final todays = numberStyleOf(tester, cellOf(april(21)), april(21));
    await gesture.moveBy(const Offset(0.0, -10.0));
    await tester.pump();
    expect(
      tester.widget<DayCell>(cellOf(april(22))).collapse.value,
      isNot(t),
    );
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
      numberStyleOf(tester, cellOf(may(1)), may(1)),
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
    final roots = <Finder>[find.byType(DayList)];
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

    await failNextRead(tester, api, "Next month");
    expect(
      find.descendant(
        of: find.byType(DayList),
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
      isNot(lineHeightAt(header, const CalendarThemeData().agendaHeaderTitleStyle)),
    );
  });

  testWidgets("C4 a pinned day header whose row the list no longer builds, "
      "and a row growing in, draw B from the frame that installs it", (
    tester,
  ) async {
    final api = await pumpThemed(tester, sentinelA);
    await pickHours(tester, 8, 18);
    await revealDay(tester, april(24));
    final list = find.byType(DayList);
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
    expect(
      tester.widget<ColoredBox>(header).color,
      sentinelB.background,
    );
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
    final roots = <Finder>[find.byType(MonthBoard)];
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
            of: find.byType(MonthBoard),
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
          of: find.byType(MonthBoard),
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
          .widget<Text>(find.descendant(of: chip, matching: find.text("Planning")))
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
      moreOrLessEquals(tester.getRect(find.byType(DayList)).top, epsilon: 0.5),
    );
    expect(tester.takeException(), isNull);
  });
}
