/// The builder details and states as plain values, and what each of the
/// module's default builders draws from them and the theme alone, with no
/// Material above it.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/calendar.dart';
import 'package:widgets_extended/calendar/presentation/calendar_defaults.dart';

const Color colour = Color(0xFF8A2B4C);

/// A theme whose every field the defaults read differs from its built-in
/// value, each text style the defaults read at a font size and a letter
/// spacing no other of them has.
const CalendarThemeData distinct = CalendarThemeData(
  primary: Color(0xFF0B5A3A),
  primaryTint: Color(0xFFD9F2E6),
  surface: Color(0xFFF7F1E3),
  text: Color(0xFF221133),
  textSecondary: Color(0xFF334455),
  error: Color(0xFF991100),
  notice: Color(0xFFFFE0A0),
  onNotice: Color(0xFF443300),
  entryTintOpacity: 0.3,
  pendingEntryOpacity: 0.4,
  motionDuration: Duration(milliseconds: 450),
  beforeHoursIcon: IconData(0xe100, fontFamily: "MaterialIcons"),
  afterHoursIcon: IconData(0xe101, fontFamily: "MaterialIcons"),
  addEntryIcon: IconData(0xe102, fontFamily: "MaterialIcons"),
  blockTitleStyle: TextStyle(fontSize: 9.5, letterSpacing: 0.15),
  detailedBlockTitleStyle: TextStyle(fontSize: 13.5, letterSpacing: 0.25),
  detailedBlockDetailStyle: TextStyle(fontSize: 12.5, letterSpacing: 0.35),
  chipTitleStyle: TextStyle(fontSize: 10.5, letterSpacing: 0.45),
  monthCardTitleStyle: TextStyle(fontSize: 11.5, letterSpacing: 0.55),
  monthCardTimeStyle: TextStyle(fontSize: 8.5, letterSpacing: 0.65),
  entryCardTitleStyle: TextStyle(
    fontSize: 15.5,
    height: 1.4,
    letterSpacing: 0.75,
  ),
  noticeStyle: TextStyle(fontSize: 7.5, letterSpacing: 0.85),
  messageStyle: TextStyle(fontSize: 16.5, letterSpacing: 0.95),
  actionLabelStyle: TextStyle(fontSize: 17.5, letterSpacing: 1.05),
);

/// The tint every entry default draws [colour] in under [distinct].
final Color tint = Color.alphaBlend(
  colour.withValues(alpha: distinct.entryTintOpacity),
  distinct.surface,
);

/// An entry from 09:00 to 10:00 on April 21 2026, in [colour].
CalendarShownEntry<String> shown({
  bool pending = false,
  String title = "Standup",
}) {
  return CalendarShownEntry<String>(
    CalendarEntry<String>(
      id: "entry-1",
      start: DateTime(2026, 4, 21, 9),
      end: DateTime(2026, 4, 21, 10),
      title: title,
      color: colour,
      payload: "note",
    ),
    pending: pending,
  );
}

const Key rootKey = ValueKey<String>("default");

/// What a default builds, under the box [host] gives it.
final Finder root = find.byKey(rootKey);

/// [build] called through a [Builder] in a box [width] wide and [height]
/// tall, or of its own height where [height] is null, at the top left of
/// the view, under [distinct] and with no Material, MaterialApp or
/// WidgetsApp above it.
Widget host(
  WidgetBuilder build, {
  double width = 120.0,
  double? height = 60.0,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: CalendarTheme(
      data: distinct,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: height,
          child: KeyedSubtree(
            key: rootKey,
            child: Builder(builder: build),
          ),
        ),
      ),
    ),
  );
}

/// The widgets of type [W] under [of], or under [root].
List<W> widgetsUnder<W extends Widget>(WidgetTester tester, {Finder? of}) {
  return tester
      .widgetList<W>(find.descendant(of: of ?? root, matching: find.byType(W)))
      .toList();
}

/// Expects [text], one [Text] under [root], to lay out in [style]'s size
/// and letter spacing and in [color].
void expectText(
  WidgetTester tester,
  String text,
  TextStyle style,
  Color color,
) {
  final finder = find.descendant(of: root, matching: find.text(text));
  expect(finder, findsOneWidget, reason: text);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final painted = paragraph.text.style!;
  expect(painted.fontSize, style.fontSize, reason: text);
  expect(painted.letterSpacing, style.letterSpacing, reason: text);
  expect(painted.color, color, reason: text);
}

/// The data of each [Text] under [root].
List<String?> textsUnder(WidgetTester tester) {
  return widgetsUnder<Text>(tester).map((text) {
    return text.data;
  }).toList();
}

/// The start angle the one indicator under [root] paints its arc at.
double startAngleOf(WidgetTester tester) {
  final paint = tester.renderObject<RenderCustomPaint>(
    find.descendant(
      of: find.byType(CalendarActivityIndicator),
      matching: find.byType(CustomPaint),
    ),
  );
  final canvas = TestRecordingCanvas();
  paint.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  final arcs = canvas.invocations.where((call) {
    return call.invocation.memberName == #drawArc;
  }).toList();
  expect(arcs, hasLength(1));
  return arcs.single.invocation.positionalArguments[1] as double;
}

const DefaultCalendarLocalizations english = DefaultCalendarLocalizations();

void main() {
  test("BD1 the details and states are plain values that read their "
      "arguments back, the block's and the chip's equal by their fields", () {
    const block = CalendarBlockDetails(
      detailed: true,
      tall: false,
      cutAtStart: true,
      cutAtEnd: false,
    );
    expect(block.detailed, isTrue);
    expect(block.tall, isFalse);
    expect(block.cutAtStart, isTrue);
    expect(block.cutAtEnd, isFalse);
    expect(block.hourLabelFormat, HourLabelFormat.twentyFourHour);
    CalendarBlockDetails blockOf({
      bool? detailed,
      bool? tall,
      bool? cutAtStart,
      bool? cutAtEnd,
      HourLabelFormat? hourLabelFormat,
    }) {
      return CalendarBlockDetails(
        detailed: detailed ?? block.detailed,
        tall: tall ?? block.tall,
        cutAtStart: cutAtStart ?? block.cutAtStart,
        cutAtEnd: cutAtEnd ?? block.cutAtEnd,
        hourLabelFormat: hourLabelFormat ?? block.hourLabelFormat,
      );
    }

    final sameBlock = blockOf();
    expect(identical(sameBlock, block), isFalse);
    expect(sameBlock, block);
    expect(sameBlock.hashCode, block.hashCode);
    for (final other in <String, CalendarBlockDetails>{
      "detailed": blockOf(detailed: false),
      "tall": blockOf(tall: true),
      "cutAtStart": blockOf(cutAtStart: false),
      "cutAtEnd": blockOf(cutAtEnd: true),
      "hourLabelFormat": blockOf(hourLabelFormat: HourLabelFormat.twelveHour),
    }.entries) {
      expect(other.value, isNot(block), reason: other.key);
      expect(other.value.hashCode, isNot(block.hashCode), reason: other.key);
    }

    const chip = CalendarChipDetails(
      card: true,
      continuesBefore: false,
      continuesAfter: true,
    );
    expect(chip.card, isTrue);
    expect(chip.continuesBefore, isFalse);
    expect(chip.continuesAfter, isTrue);
    expect(chip.hourLabelFormat, HourLabelFormat.twentyFourHour);
    CalendarChipDetails chipOf({
      bool? card,
      bool? continuesBefore,
      bool? continuesAfter,
      HourLabelFormat? hourLabelFormat,
    }) {
      return CalendarChipDetails(
        card: card ?? chip.card,
        continuesBefore: continuesBefore ?? chip.continuesBefore,
        continuesAfter: continuesAfter ?? chip.continuesAfter,
        hourLabelFormat: hourLabelFormat ?? chip.hourLabelFormat,
      );
    }

    final sameChip = chipOf();
    expect(identical(sameChip, chip), isFalse);
    expect(sameChip, chip);
    expect(sameChip.hashCode, chip.hashCode);
    for (final other in <String, CalendarChipDetails>{
      "card": chipOf(card: false),
      "continuesBefore": chipOf(continuesBefore: true),
      "continuesAfter": chipOf(continuesAfter: false),
      "hourLabelFormat": chipOf(hourLabelFormat: HourLabelFormat.twelveHour),
    }.entries) {
      expect(other.value, isNot(chip), reason: other.key);
      expect(other.value.hashCode, isNot(chip.hashCode), reason: other.key);
    }

    const card = CalendarCardDetails(startsAt: "07:30", endsAt: "19:30");
    expect(card.startsAt, "07:30");
    expect(card.endsAt, "19:30");
    expect(card.onEdit, isNull);
    expect(card.onDelete, isNull);
    void edit() {}
    void delete() {}
    final callbacks = CalendarCardDetails(onEdit: edit, onDelete: delete);
    expect(callbacks.startsAt, isNull);
    expect(callbacks.endsAt, isNull);
    expect(callbacks.onEdit, edit);
    expect(callbacks.onDelete, delete);

    final day = DateTime(2026, 4, 21);
    final last = DateTime(2026, 4, 27);
    void press() {}
    final add = CalendarAddButtonDetails(
      day: day,
      startMinute: 570,
      onPressed: press,
    );
    expect(add.day, day);
    expect(add.startMinute, 570);
    expect(add.onPressed, press);

    final loading = CalendarLoadingState(
      site: CalendarStateSite.cover,
      first: day,
      last: last,
    );
    expect(loading.site, CalendarStateSite.cover);
    expect(loading.first, day);
    expect(loading.last, last);

    final error = StateError("offline");
    void retry() {}
    final failure = CalendarFailureState(
      site: CalendarStateSite.dayRow,
      first: day,
      last: day,
      error: error,
      retry: retry,
    );
    expect(failure.site, CalendarStateSite.dayRow);
    expect(failure.first, day);
    expect(failure.last, day);
    expect(failure.error, same(error));
    expect(failure.retry, retry);
    final unread = CalendarFailureState(
      site: CalendarStateSite.dayRow,
      first: day,
      last: day,
      error: null,
      retry: retry,
    );
    expect(unread.error, isNull);
  });

  testWidgets("BD2 each default has its builder's signature, and the block "
      "default draws the tint, the edge and the title in the block style", (
    tester,
  ) async {
    // Each default as a value of its signature, which takes the context,
    // the shown entry and its details, or the context and one value.
    const CalendarBlockBuilder<String> block = defaultCalendarBlockBuilder;
    const CalendarChipBuilder<String> chip = defaultCalendarChipBuilder;
    const CalendarCardBuilder<String> card = defaultCalendarCardBuilder;
    const CalendarAddButtonBuilder add = defaultCalendarAddButtonBuilder;
    const CalendarLoadingBuilder loading = defaultCalendarLoadingBuilder;
    const CalendarFailureBuilder failure = defaultCalendarFailureBuilder;
    expect(<Object>[chip, card, add, loading, failure], hasLength(5));
    final entry = shown();
    await tester.pumpWidget(
      host((context) {
        return block(
          context,
          entry,
          const CalendarBlockDetails(
            detailed: false,
            tall: false,
            cutAtStart: false,
            cutAtEnd: false,
          ),
        );
      }),
    );
    final box = widgetsUnder<DecoratedBox>(tester).first;
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.color, tint);
    expect(
      decoration.border,
      const Border(left: BorderSide(color: colour, width: 4.0)),
    );
    expect(textsUnder(tester), <String>["Standup"]);
    expectText(tester, "Standup", distinct.blockTitleStyle, distinct.text);
    expect(widgetsUnder<Icon>(tester), isEmpty);
    expect(widgetsUnder<Opacity>(tester), isEmpty);
    expect(widgetsUnder<CalendarActivityIndicator>(tester), isEmpty);
  });

  testWidgets("BD3 the detailed block default draws the title and the times "
      "in the detailed styles", (tester) async {
    final entry = shown();
    await tester.pumpWidget(
      host((context) {
        return defaultCalendarBlockBuilder(
          context,
          entry,
          const CalendarBlockDetails(
            detailed: true,
            tall: true,
            cutAtStart: false,
            cutAtEnd: false,
          ),
        );
      }),
    );
    expect(
      textsUnder(tester),
      unorderedEquals(<String>[
        "Standup",
        english.formatTimeRange(540, 600, HourLabelFormat.twentyFourHour),
      ]),
    );
    expectText(
      tester,
      "Standup",
      distinct.detailedBlockTitleStyle,
      distinct.text,
    );
    expectText(
      tester,
      english.formatTimeRange(540, 600, HourLabelFormat.twentyFourHour),
      distinct.detailedBlockDetailStyle,
      distinct.textSecondary,
    );
  });

  testWidgets("BD4 the block default marks each end the hours cut with its "
      "arrow at that end", (tester) async {
    Future<List<Icon>> pumpCut({required bool start, required bool end}) async {
      final entry = shown();
      await tester.pumpWidget(
        host((context) {
          return defaultCalendarBlockBuilder(
            context,
            entry,
            CalendarBlockDetails(
              detailed: false,
              tall: false,
              cutAtStart: start,
              cutAtEnd: end,
            ),
          );
        }),
      );
      return widgetsUnder<Icon>(tester);
    }

    void expectArrow(Icon icon) {
      expect(icon.size, 14.0);
      expect(icon.color, distinct.textSecondary);
      final rect = tester.getRect(find.byWidget(icon));
      final box = tester.getRect(root);
      if (icon.icon == distinct.beforeHoursIcon) {
        expect(rect.topRight, box.topRight);
      } else {
        expect(icon.icon, distinct.afterHoursIcon);
        expect(rect.bottomRight, box.bottomRight);
      }
    }

    final both = await pumpCut(start: true, end: true);
    expect(
      both.map((icon) {
        return icon.icon;
      }),
      unorderedEquals(<IconData>[
        distinct.beforeHoursIcon,
        distinct.afterHoursIcon,
      ]),
    );
    both.forEach(expectArrow);

    final start = await pumpCut(start: true, end: false);
    expect(start, hasLength(1));
    expect(start.single.icon, distinct.beforeHoursIcon);
    expectArrow(start.single);

    final end = await pumpCut(start: false, end: true);
    expect(end, hasLength(1));
    expect(end.single.icon, distinct.afterHoursIcon);
    expectArrow(end.single);
  });

  testWidgets("BD5 the pending block default dims the block and its arrows, "
      "and spins an indicator at its top right", (tester) async {
    final entry = shown(pending: true);
    await tester.pumpWidget(
      host((context) {
        return defaultCalendarBlockBuilder(
          context,
          entry,
          const CalendarBlockDetails(
            detailed: false,
            tall: false,
            cutAtStart: true,
            cutAtEnd: true,
          ),
        );
      }),
    );
    final opacity = find.descendant(of: root, matching: find.byType(Opacity));
    expect(opacity, findsOneWidget);
    expect(
      tester.widget<Opacity>(opacity).opacity,
      distinct.pendingEntryOpacity,
    );
    final tinted = widgetsUnder<DecoratedBox>(tester, of: opacity).first;
    expect((tinted.decoration as BoxDecoration).color, tint);
    expect(widgetsUnder<Icon>(tester, of: opacity), hasLength(2));
    expect(widgetsUnder<CalendarActivityIndicator>(tester), hasLength(1));
    expect(
      widgetsUnder<CalendarActivityIndicator>(tester, of: opacity),
      isEmpty,
    );
    final indicator = find.byType(CalendarActivityIndicator);
    final box = tester.getRect(root);
    expect(
      tester.getRect(indicator),
      Rect.fromLTWH(box.right - 2.0 - 12.0, box.top + 2.0, 12.0, 12.0),
    );
    expect(
      tester.renderObject(
        find.descendant(of: indicator, matching: find.byType(CustomPaint)),
      ),
      paints..arc(color: distinct.primary),
    );
  });

  testWidgets("BD6 the chip default rounds the ends the entry does not "
      "continue past, and draws the chip and card forms", (tester) async {
    Future<void> pumpChip(
      CalendarChipDetails details, {
      bool pending = false,
    }) async {
      final entry = shown(pending: pending);
      await tester.pumpWidget(
        host((context) {
          return defaultCalendarChipBuilder(context, entry, details);
        }),
      );
    }

    BorderRadiusGeometry radiusOf() {
      return widgetsUnder<ClipRRect>(tester).single.borderRadius;
    }

    const radius = Radius.circular(4.0);
    await pumpChip(
      const CalendarChipDetails(
        card: false,
        continuesBefore: false,
        continuesAfter: false,
      ),
    );
    expect(radiusOf(), const BorderRadius.all(radius));
    final boxes = widgetsUnder<ColoredBox>(tester);
    expect(
      boxes.where((box) {
        return box.color == tint;
      }),
      hasLength(1),
    );
    final edges = boxes.where((box) {
      return box.color == colour;
    }).toList();
    expect(edges, hasLength(1));
    expect(tester.getSize(find.byWidget(edges.single)).width, 4.0);
    expect(textsUnder(tester), <String>["Standup"]);
    expectText(tester, "Standup", distinct.chipTitleStyle, distinct.text);
    expect(widgetsUnder<Icon>(tester), isEmpty);
    expect(widgetsUnder<Opacity>(tester), isEmpty);

    await pumpChip(
      const CalendarChipDetails(
        card: false,
        continuesBefore: true,
        continuesAfter: false,
      ),
    );
    expect(
      radiusOf(),
      const BorderRadius.horizontal(left: Radius.zero, right: radius),
    );
    await pumpChip(
      const CalendarChipDetails(
        card: false,
        continuesBefore: false,
        continuesAfter: true,
      ),
    );
    expect(
      radiusOf(),
      const BorderRadius.horizontal(left: radius, right: Radius.zero),
    );

    await pumpChip(
      const CalendarChipDetails(
        card: true,
        continuesBefore: false,
        continuesAfter: false,
      ),
    );
    expect(
      textsUnder(tester),
      unorderedEquals(<String>[
        "Standup",
        english.formatTimeRange(540, 600, HourLabelFormat.twentyFourHour),
      ]),
    );
    expectText(tester, "Standup", distinct.monthCardTitleStyle, distinct.text);
    expectText(
      tester,
      english.formatTimeRange(540, 600, HourLabelFormat.twentyFourHour),
      distinct.monthCardTimeStyle,
      distinct.textSecondary,
    );
    expect(widgetsUnder<Icon>(tester), isEmpty);

    await pumpChip(
      const CalendarChipDetails(
        card: false,
        continuesBefore: false,
        continuesAfter: false,
      ),
      pending: true,
    );
    final opacity = widgetsUnder<Opacity>(tester);
    expect(opacity, hasLength(1));
    expect(opacity.single.opacity, distinct.pendingEntryOpacity);
    expect(widgetsUnder<CalendarActivityIndicator>(tester), isEmpty);
  });

  testWidgets("BD7 the card default draws the tint, the edge, the title on "
      "one line and the strips, at the height Agenda predicts, and takes "
      "no gesture", (tester) async {
    Future<void> pumpCard(
      CalendarCardDetails details, {
      bool pending = false,
      String title = "Standup",
    }) async {
      final entry = shown(pending: pending, title: title);
      await tester.pumpWidget(
        host(
          (context) {
            return defaultCalendarCardBuilder(context, entry, details);
          },
          width: 240.0,
          height: null,
        ),
      );
    }

    final extent = defaultCalendarCardExtent(distinct);
    final style = distinct.entryCardTitleStyle;
    expect(extent, 16.0 + style.fontSize! * style.height!);
    expect(
      defaultCalendarCardExtent(
        const CalendarThemeData(entryCardTitleStyle: TextStyle()),
      ),
      16.0 + kDefaultFontSize * 1.25,
    );

    await pumpCard(const CalendarCardDetails());
    expect(
      (widgetsUnder<ClipRRect>(tester).single.borderRadius),
      BorderRadius.circular(16.0),
    );
    final decoration =
        widgetsUnder<DecoratedBox>(tester).first.decoration as BoxDecoration;
    expect(decoration.color, tint);
    expect(
      decoration.border,
      const Border(left: BorderSide(color: colour, width: 4.0)),
    );
    expect(textsUnder(tester), <String>["Standup"]);
    expectText(tester, "Standup", style, distinct.text);
    expect(widgetsUnder<Icon>(tester), isEmpty);
    expect(tester.getSize(root).height, moreOrLessEquals(extent));

    await pumpCard(
      const CalendarCardDetails(),
      title: "A title far too long to fit on the one line a card gives it",
    );
    expect(tester.getSize(root).height, moreOrLessEquals(extent));

    List<Rect> stripsOf() {
      return widgetsUnder<ColoredBox>(tester)
          .where((box) {
            return box.color == distinct.notice;
          })
          .map((box) {
            return tester.getRect(find.byWidget(box));
          })
          .toList();
    }

    await pumpCard(
      const CalendarCardDetails(startsAt: "07:30", endsAt: "19:30"),
    );
    final card = tester.getRect(root);
    expect(card.height, moreOrLessEquals(extent + 2 * calendarCardStripExtent));
    final both = stripsOf();
    expect(both, hasLength(2));
    expect(both.first.top, card.top);
    expect(both.first.height, calendarCardStripExtent);
    expect(both.last.bottom, moreOrLessEquals(card.bottom));
    expect(both.last.height, calendarCardStripExtent);
    expectText(
      tester,
      english.startsAt("07:30"),
      distinct.noticeStyle,
      distinct.onNotice,
    );
    expectText(
      tester,
      english.endsAt("19:30"),
      distinct.noticeStyle,
      distinct.onNotice,
    );
    expect(
      tester.getCenter(find.text(english.startsAt("07:30"))).dy,
      moreOrLessEquals(both.first.center.dy),
    );

    await pumpCard(const CalendarCardDetails(startsAt: "07:30"));
    final top = stripsOf();
    expect(top, hasLength(1));
    expect(top.single.top, tester.getRect(root).top);
    expect(find.text(english.startsAt("07:30")), findsOneWidget);

    await pumpCard(const CalendarCardDetails(endsAt: "19:30"));
    final bottom = stripsOf();
    expect(bottom, hasLength(1));
    expect(bottom.single.bottom, moreOrLessEquals(tester.getRect(root).bottom));
    expect(find.text(english.endsAt("19:30")), findsOneWidget);

    await pumpCard(const CalendarCardDetails(startsAt: "07:30"), pending: true);
    final opacity = widgetsUnder<Opacity>(tester);
    expect(opacity, hasLength(1));
    expect(opacity.single.opacity, distinct.pendingEntryOpacity);
    final pendingCard = tester.getRect(root);
    expect(
      tester.getRect(find.byType(CalendarActivityIndicator)),
      Rect.fromLTWH(
        pendingCard.right - 8.0 - 12.0,
        pendingCard.top + calendarCardStripExtent + 8.0,
        12.0,
        12.0,
      ),
    );

    var edits = 0;
    var deletes = 0;
    final entry = shown();
    await tester.pumpWidget(
      host(
        (context) {
          return defaultCalendarCardBuilder(
            context,
            entry,
            CalendarCardDetails(
              onEdit: () {
                edits++;
              },
              onDelete: () {
                deletes++;
              },
            ),
          );
        },
        width: 240.0,
        height: null,
      ),
    );
    expect(find.text("Edit"), findsNothing);
    expect(find.text("Delete"), findsNothing);
    final rect = tester.getRect(root);
    for (final point in <Offset>[
      rect.center,
      rect.topLeft + const Offset(1.0, 1.0),
      rect.topRight + const Offset(-1.0, 1.0),
      rect.bottomLeft + const Offset(1.0, -1.0),
      rect.bottomRight + const Offset(-1.0, -1.0),
    ]) {
      await tester.tapAt(point);
      await tester.pump();
    }
    expect(edits, 0);
    expect(deletes, 0);
    expect(find.semantics.byAction(SemanticsAction.tap), findsNothing);
  });

  testWidgets("BD8 the add button default is a circle of the tint holding "
      "the add icon, which only the circle takes a press for", (tester) async {
    var presses = 0;
    final details = CalendarAddButtonDetails(
      day: DateTime(2026, 4, 21),
      startMinute: 570,
      onPressed: () {
        presses++;
      },
    );
    await tester.pumpWidget(
      host(
        (context) {
          return defaultCalendarAddButtonBuilder(context, details);
        },
        width: 24.0,
        height: 24.0,
      ),
    );
    expect(tester.takeException(), isNull);
    final circle = widgetsUnder<DecoratedBox>(tester).single;
    final decoration = circle.decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, distinct.primaryTint);
    expect(tester.getSize(find.byWidget(circle)), const Size(24.0, 24.0));
    final icons = widgetsUnder<Icon>(tester, of: find.byWidget(circle));
    expect(icons, hasLength(1));
    expect(icons.single.icon, distinct.addEntryIcon);
    expect(icons.single.color, distinct.primary);

    await tester.tapAt(tester.getCenter(root));
    expect(presses, 1);
    await tester.tapAt(tester.getTopLeft(root) + const Offset(1.0, 1.0));
    expect(presses, 1);
  });

  testWidgets("BD9 the loading default spins an indicator in the theme's "
      "primary, centred on the cover and at the start of a row", (
    tester,
  ) async {
    final day = DateTime(2026, 4, 21);
    await tester.pumpWidget(
      host(
        (context) {
          return Center(
            child: defaultCalendarLoadingBuilder(
              context,
              CalendarLoadingState(
                site: CalendarStateSite.cover,
                first: day,
                last: day,
              ),
            ),
          );
        },
        width: 300.0,
        height: 200.0,
      ),
    );
    final indicator = find.byType(CalendarActivityIndicator);
    expect(indicator, findsOneWidget);
    expect(tester.getSize(indicator), const Size(36.0, 36.0));
    expect(
      tester.renderObject(
        find.descendant(of: indicator, matching: find.byType(CustomPaint)),
      ),
      paints..arc(color: distinct.primary),
    );
    await tester.pump();
    final before = startAngleOf(tester);
    await tester.pump(const Duration(milliseconds: 250));
    expect(startAngleOf(tester), isNot(moreOrLessEquals(before)));

    await tester.pumpWidget(
      host(
        (context) {
          return defaultCalendarLoadingBuilder(
            context,
            CalendarLoadingState(
              site: CalendarStateSite.dayRow,
              first: day,
              last: day,
            ),
          );
        },
        width: 300.0,
        height: 24.0,
      ),
    );
    final row = tester.getRect(root);
    expect(
      tester.getRect(find.byType(CalendarActivityIndicator)),
      Rect.fromLTWH(row.left, row.top + 4.0, 16.0, 16.0),
    );
  });

  testWidgets("BD10 the failure default says the read failed, never the "
      "error, beside a Retry of its own semantics node", (tester) async {
    for (final site in CalendarStateSite.values) {
      var retries = 0;
      final day = DateTime(2026, 4, 21);
      final state = CalendarFailureState(
        site: site,
        first: day,
        last: day,
        error: StateError("A sentence the error carries."),
        retry: () {
          retries++;
        },
      );
      await tester.pumpWidget(
        host(
          (context) {
            final failure = defaultCalendarFailureBuilder(context, state);
            return site == CalendarStateSite.cover
                ? Center(child: failure)
                : failure;
          },
          width: 800.0,
          height: site == CalendarStateSite.cover ? 200.0 : 48.0,
        ),
      );
      expect(tester.takeException(), isNull, reason: "$site");
      expectText(
        tester,
        english.readFailed,
        distinct.messageStyle,
        distinct.error,
      );
      expect(
        find.textContaining("A sentence the error carries."),
        findsNothing,
        reason: "$site",
      );
      expectText(
        tester,
        english.retry,
        distinct.actionLabelStyle,
        distinct.primary,
      );
      await tester.tap(find.text(english.retry));
      expect(retries, 1, reason: "$site");
      final retryNode = tester.getSemantics(find.text(english.retry));
      expect(
        retryNode,
        isSemantics(label: english.retry, isButton: true, hasTapAction: true),
        reason: "$site",
      );
      expect(
        identical(
          retryNode,
          tester.getSemantics(find.text(english.readFailed)),
        ),
        isFalse,
        reason: "$site",
      );
    }
  });

  testWidgets("BD11 the add button, loading and failure defaults show only "
      "the labels' strings", (tester) async {
    final day = DateTime(2026, 4, 21);
    final shownTexts = <String?>[];
    final builders = <WidgetBuilder>[
      (context) {
        return defaultCalendarAddButtonBuilder(
          context,
          CalendarAddButtonDetails(
            day: day,
            startMinute: 570,
            onPressed: () {},
          ),
        );
      },
      for (final site in CalendarStateSite.values) ...<WidgetBuilder>[
        (context) {
          return defaultCalendarLoadingBuilder(
            context,
            CalendarLoadingState(site: site, first: day, last: day),
          );
        },
        (context) {
          return defaultCalendarFailureBuilder(
            context,
            CalendarFailureState(
              site: site,
              first: day,
              last: day,
              error: StateError("offline"),
              retry: () {},
            ),
          );
        },
      ],
    ];
    for (final build in builders) {
      await tester.pumpWidget(host(build, width: 800.0, height: 200.0));
      shownTexts.addAll(textsUnder(tester));
    }
    expect(shownTexts, isNotEmpty);
    for (final text in shownTexts) {
      expect(<String>[english.readFailed, english.retry], contains(text));
    }
  });

  testWidgets("BD12 the block default laid out at a new height each frame "
      "neither rebuilds nor overflows", (tester) async {
    for (final detailed in <bool>[false, true]) {
      final height = ValueNotifier<double>(60.0);
      addTearDown(height.dispose);
      final entry = shown(pending: true);
      final details = CalendarBlockDetails(
        detailed: detailed,
        tall: true,
        cutAtStart: true,
        cutAtEnd: true,
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CalendarTheme(
            data: distinct,
            child: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<double>(
                valueListenable: height,
                child: KeyedSubtree(
                  key: rootKey,
                  child: Builder(
                    builder: (context) {
                      return defaultCalendarBlockBuilder(
                        context,
                        entry,
                        details,
                      );
                    },
                  ),
                ),
                builder: (context, value, child) {
                  return SizedBox(width: 120.0, height: value, child: child);
                },
              ),
            ),
          ),
        ),
      );
      final top = tester.element(root);
      final rebuilt = <Element>[];
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        var under = identical(element, top);
        element.visitAncestorElements((ancestor) {
          under = under || identical(ancestor, top);
          return !under;
        });
        if (under) {
          rebuilt.add(element);
        }
      };
      try {
        for (var frame = 1; frame <= 10; frame++) {
          height.value = 60.0 - frame * 5.8;
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull, reason: "frame $frame");
        }
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(tester.getSize(root).height, moreOrLessEquals(2.0));
      expect(rebuilt, isEmpty, reason: "detailed: $detailed");
    }
  });

  testWidgets("HF5 the detailed block default and the chip default's card "
      "form write the times in their details' hour format", (tester) async {
    final entry = shown();
    await tester.pumpWidget(
      host((context) {
        return defaultCalendarBlockBuilder(
          context,
          entry,
          const CalendarBlockDetails(
            detailed: true,
            tall: true,
            cutAtStart: false,
            cutAtEnd: false,
            hourLabelFormat: HourLabelFormat.twelveHour,
          ),
        );
      }),
    );
    expect(
      textsUnder(tester),
      unorderedEquals(<String>["Standup", "9 AM-10 AM"]),
    );

    await tester.pumpWidget(
      host((context) {
        return defaultCalendarChipBuilder(
          context,
          entry,
          const CalendarChipDetails(
            card: true,
            continuesBefore: false,
            continuesAfter: false,
            hourLabelFormat: HourLabelFormat.twelveHour,
          ),
        );
      }),
    );
    expect(
      textsUnder(tester),
      unorderedEquals(<String>["Standup", "9 AM-10 AM"]),
    );
  });
}
