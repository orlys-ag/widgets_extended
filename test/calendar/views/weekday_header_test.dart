/// Tests of [WeekdayHeader] on its own, over a scrolled row of days.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/calendar/views/day_cell.dart';
import 'package:widgets_extended/scheduling/dates/calendar_dates.dart';

void main() {
  testWidgets("WH1 a header of fixed columns lays its letters out the way "
      "its columns run and follows the grid's scroll that way, while the "
      "letters keep the ambient direction as text", (tester) async {
    const width = 100.0;
    final columns = CalendarWeekdaySet.all.columns.toList();
    final letters = find.descendant(
      of: find.byType(WeekdayHeader),
      matching: find.byType(RichText),
    );
    for (final ambient in TextDirection.values) {
      for (final run in TextDirection.values) {
        final reason = "ambient $ambient, columns $run";
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await tester.pumpWidget(
          Directionality(
            // A new tree per case, so no list takes the last one's offset.
            key: ValueKey<String>(reason),
            textDirection: ambient,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 350.0,
                child: Column(
                  children: <Widget>[
                    WeekdayHeader(
                      weekdays: CalendarWeekdaySet.all,
                      columnWidth: width,
                      horizontal: scroll,
                      columnDirection: run,
                    ),
                    SizedBox(
                      height: 40.0,
                      // A grid whose columns run [run] whatever the ambient
                      // direction, as the board's do: a left-to-right
                      // list, reversed for right to left.
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          reverse: run == TextDirection.rtl,
                          controller: scroll,
                          children: <Widget>[
                            for (final column in columns)
                              SizedBox(
                                key: ValueKey<int>(column),
                                width: width,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        void expectLettersOverDays(String reason) {
          expect(letters, findsNWidgets(columns.length), reason: reason);
          for (var i = 0; i < columns.length; i++) {
            final day = find.byKey(ValueKey<int>(columns[i]));
            if (day.evaluate().isEmpty) {
              continue;
            }
            expect(
              tester.getCenter(letters.at(i)).dx,
              moreOrLessEquals(tester.getCenter(day).dx, epsilon: 0.5),
              reason: "$reason: column ${columns[i]}",
            );
          }
        }

        expectLettersOverDays(reason);
        scroll.jumpTo(150.0);
        await tester.pump();
        expectLettersOverDays("$reason, scrolled");
        expect(
          tester.renderObject<RenderParagraph>(letters.first).textDirection,
          ambient,
          reason: reason,
        );
      }
    }
  });
}
