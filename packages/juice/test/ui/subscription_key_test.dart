import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// `SubscriptionKey` (2.0.0): what a Juice widget's subscription depends on
/// — the bloc instances, by identity and in order. The hash agrees with
/// `==`.
void main() {
  final a = Object();
  final b = Object();

  test('equal: the same blocs by identity, in order', () {
    final k1 = SubscriptionKey([a, b]);
    final k2 = SubscriptionKey([a, b]);
    expect(k1, equals(k2));
    expect(k1.hashCode, k2.hashCode);
    expect(k1, equals(k1), reason: 'identical');
  });

  test('not equal: a different bloc instance, order or length', () {
    final base = SubscriptionKey([a, b]);
    expect(base, isNot(equals(SubscriptionKey([a, Object()]))));
    expect(base, isNot(equals(SubscriptionKey([b, a]))));
    expect(base, isNot(equals(SubscriptionKey([a]))));
    expect(base, isNot(equals(Object())));
  });
}
