import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// `SubscriptionKey` (2.0.0): what a Juice widget's subscription depends on.
/// Equal when the same bloc instances (by identity, in order), set-equal
/// groups and an equal key; the hash agrees with `==`.
void main() {
  final a = Object();
  final b = Object();

  test('equal: same blocs by identity, set-equal groups, equal key', () {
    final k1 = SubscriptionKey([a, b], {'x', 'y'}, const ValueKey('k'));
    final k2 = SubscriptionKey([a, b], {'y', 'x'}, const ValueKey('k'));
    expect(k1, equals(k2));
    expect(k1.hashCode, k2.hashCode);
    expect(k1, equals(k1), reason: 'identical');
  });

  test('not equal: a different bloc instance, order, length, groups or key',
      () {
    final base = SubscriptionKey([a, b], {'x'}, null);
    expect(base, isNot(equals(SubscriptionKey([a, Object()], {'x'}, null))));
    expect(base, isNot(equals(SubscriptionKey([b, a], {'x'}, null))));
    expect(base, isNot(equals(SubscriptionKey([a], {'x'}, null))));
    expect(base, isNot(equals(SubscriptionKey([a, b], {'x', 'z'}, null))));
    expect(base, isNot(equals(SubscriptionKey([a, b], null, null))));
    expect(base,
        isNot(equals(SubscriptionKey([a, b], {'x'}, const ValueKey('k')))));
    expect(base, isNot(equals(Object())));
  });

  test('null groups hash and compare', () {
    final k1 = SubscriptionKey([a], null, null);
    final k2 = SubscriptionKey([a], null, null);
    expect(k1, equals(k2));
    expect(k1.hashCode, k2.hashCode);
    expect(k1.hashCode, isNot(SubscriptionKey([a], {'g'}, null).hashCode));
  });
}
