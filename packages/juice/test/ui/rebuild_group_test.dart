import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

// Example type-safe group definitions
abstract class CounterGroups {
  static const counter = RebuildGroup('counter');
  static const display = RebuildGroup('counter:display');
  static const buttons = RebuildGroup('counter:buttons');
}

void main() {
  group('RebuildGroup', () {
    test('creates group with name', () {
      const group = RebuildGroup('test');
      expect(group.name, 'test');
    });

    test('equality works correctly', () {
      const group1 = RebuildGroup('test');
      const group2 = RebuildGroup('test');
      const group3 = RebuildGroup('other');

      expect(group1, equals(group2));
      expect(group1, isNot(equals(group3)));
    });

    test('hashCode is consistent', () {
      const group1 = RebuildGroup('test');
      const group2 = RebuildGroup('test');

      expect(group1.hashCode, equals(group2.hashCode));
    });

    test('built-in all group has correct name', () {
      expect(RebuildGroup.all.name, '*');
    });

    test('built-in optOut group has correct name', () {
      expect(RebuildGroup.optOut.name, '-');
    });

    test('toStringSet converts set of groups to string set', () {
      final groups = {CounterGroups.counter, CounterGroups.display};
      final stringSet = groups.toStringSet();

      expect(stringSet, {'counter', 'counter:display'});
    });

    test('toSet converts single group to string set', () {
      final stringSet = CounterGroups.counter.toSet();

      expect(stringSet, {'counter'});
    });

    test('works with rebuildAlways comparison', () {
      final stringSet = {RebuildGroup.all}.toStringSet();

      expect(stringSet, rebuildAlways);
    });

    test('works with optOutOfRebuilds comparison', () {
      final stringSet = {RebuildGroup.optOut}.toStringSet();

      expect(stringSet, optOutOfRebuilds);
    });

    test('type-safe groups prevent typos at compile time', () {
      // This demonstrates the pattern - using CounterGroups.counter
      // instead of 'counter' string provides compile-time safety
      final groups = {
        CounterGroups.counter,
        CounterGroups.display,
      }.toStringSet();

      expect(groups.contains('counter'), isTrue);
      expect(groups.contains('counter:display'), isTrue);
      expect(groups.contains('typo'), isFalse);
    });
  });
}
