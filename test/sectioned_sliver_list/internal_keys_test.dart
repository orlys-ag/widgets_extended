import 'package:flutter_test/flutter_test.dart';
import 'package:widgets_extended/sectioned_sliver_list/_internal_keys.dart';

void main() {
  group("SectionKey / ItemKey equality", () {
    test("same SKey value with same wrapper compare equal", () {
      const a = SectionKey<String, String>("x");
      const b = SectionKey<String, String>("x");
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test("same IKey value with same wrapper compare equal", () {
      const a = ItemKey<String, String>("x");
      const b = ItemKey<String, String>("x");
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test("section and item with the same string value are NOT equal", () {
      const section = SectionKey<String, String>("x");
      const item = ItemKey<String, String>("x");
      expect(section, isNot(equals(item)));
      expect(section.hashCode, isNot(equals(item.hashCode)));
    });

    test("section and item live in disjoint Map domains", () {
      final map = <SecKey<String, String>, int>{
        const SectionKey("x"): 1,
        const ItemKey("x"): 2,
      };
      expect(map.length, equals(2));
      expect(map[const SectionKey<String, String>("x")], equals(1));
      expect(map[const ItemKey<String, String>("x")], equals(2));
    });

    test("different SKey values are not equal", () {
      const a = SectionKey<String, String>("x");
      const b = SectionKey<String, String>("y");
      expect(a, isNot(equals(b)));
    });

    test("with int SKey, section and item with same int value are NOT equal", () {
      const a = SectionKey<int, int>(1);
      const b = ItemKey<int, int>(1);
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
