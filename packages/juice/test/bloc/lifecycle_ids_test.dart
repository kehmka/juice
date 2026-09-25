import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// 1.8.1: FeatureScope ids and LeakDetector lease keys came from
/// `DateTime.now().microsecondsSinceEpoch`, so two created in the same clock
/// tick collided. Both are monotonic counters now.
void main() {
  test('FeatureScopes created back-to-back are never equal', () {
    final scopes = List.generate(1000, (i) => FeatureScope('s$i'));
    expect(scopes.toSet().length, scopes.length);
    expect(scopes.map((s) => BlocId(FeatureScope, s)).toSet().length,
        scopes.length,
        reason: 'equal scopes made BlocIds collide and blocs shared');
  });

  test('two leases acquired in the same tick are both tracked', () {
    LeakDetector.enable();
    addTearDown(LeakDetector.disable);
    const id = BlocId(FeatureScope);
    LeakDetector.trackLeaseAcquire(id);
    LeakDetector.trackLeaseAcquire(id);
    expect(LeakDetector.unreleasedLeaseCount, 2);
    LeakDetector.trackLeaseRelease(id);
    expect(LeakDetector.unreleasedLeaseCount, 1,
        reason: 'the second lease is still out — a real leak');
    LeakDetector.trackLeaseRelease(id);
    expect(LeakDetector.unreleasedLeaseCount, 0);
  });
}
