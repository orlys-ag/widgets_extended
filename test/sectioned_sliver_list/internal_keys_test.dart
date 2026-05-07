import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sectioned_sliver_list/_internal_keys.dart';

void main() {
  group("SectionKey / ItemKey equality", () {
    test("same value with same wrapper compare equal", () {
      const a = SectionKey<String>("x");
      const b = SectionKey<String>("x");
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test("same item value with same wrapper compare equal", () {
      const a = ItemKey<String>("x");
      const b = ItemKey<String>("x");
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test("section and item with the same string value are NOT equal", () {
      const section = SectionKey<String>("x");
      const item = ItemKey<String>("x");
      expect(section, isNot(equals(item)));
      expect(section.hashCode, isNot(equals(item.hashCode)));
    });

    test("section and item live in disjoint Map domains", () {
      final map = <SecKey<String>, int>{
        const SectionKey("x"): 1,
        const ItemKey("x"): 2,
      };
      expect(map.length, equals(2));
      expect(map[const SectionKey<String>("x")], equals(1));
      expect(map[const ItemKey<String>("x")], equals(2));
    });

    test("different values are not equal", () {
      const a = SectionKey<String>("x");
      const b = SectionKey<String>("y");
      expect(a, isNot(equals(b)));
    });

    test("with int K, section and item with same int value are NOT equal", () {
      const a = SectionKey<int>(1);
      const b = ItemKey<int>(1);
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });

  group("SectionPayload / ItemPayload", () {
    test("hold their values without coercion", () {
      const sp = SectionPayload<String, int>("hello");
      const ip = ItemPayload<String, int>(42);
      expect(sp.value, equals("hello"));
      expect(ip.value, equals(42));
    });

    test("sealed switch is exhaustive over the two variants", () {
      String describe(SecPayload<String, int> payload) {
        return switch (payload) {
          SectionPayload(value: final v) => "section:$v",
          ItemPayload(value: final v) => "item:$v",
        };
      }

      expect(describe(const SectionPayload("hello")), equals("section:hello"));
      expect(describe(const ItemPayload(42)), equals("item:42"));
    });
  });
}
