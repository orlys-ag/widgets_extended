/// The calendar views draw what [CalendarTheme] holds: two sentinel themes,
/// whose every value differs from Harbor's, from the built-in ones and from
/// each other, and a probe that reads what each view paints.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_api.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_data.dart';
import 'package:workspace_calendar/workspace_calendar/calendar_schema.dart';
import 'package:workspace_calendar/workspace_calendar/harbor_theme.dart';
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
/// chevron [taps] times, the last one onto days no read has prefetched.
Future<void> failNextRead(
  WidgetTester tester,
  MockCalendarApi api,
  String tooltip, {
  int taps = 1,
}) async {
  api.failurePolicy = (request) {
    return request.method == CalendarMethod.list ? "Reading failed." : null;
  };
  for (var i = 0; i < taps; i++) {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
    await tester.pump(api.latency);
    await tester.pumpAndSettle();
  }
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

    await failNextRead(tester, api, "Next week", taps: 2);
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
}
