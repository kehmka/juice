import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

class _S extends BlocState {
  const _S();
}

class _LeakyBloc extends JuiceBloc<_S> {
  _LeakyBloc() : super(const _S(), []);
}

class _OtherBloc extends JuiceBloc<_S> {
  _OtherBloc() : super(const _S(), []);
}

/// Captures everything sent through [debugPrint] while [body] runs.
Future<List<String>> _capturePrints(Future<void> Function() body) async {
  final lines = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return lines;
}

void main() {
  setUp(BlocScope.reset);
  tearDown(() async {
    LeakDetector.disable();
    await BlocScope.reset();
  });

  group('LeakDetector (disabled)', () {
    test('is disabled by default and tracking calls are no-ops', () {
      expect(LeakDetector.isEnabled, isFalse);
      const id = BlocId(_LeakyBloc);
      LeakDetector.trackBlocCreation(id);
      LeakDetector.trackLeaseAcquire(id);
      LeakDetector.trackLeaseRelease(id);
      LeakDetector.trackBlocClose(id);
      expect(LeakDetector.unreleasedLeaseCount, 0);
      expect(LeakDetector.unclosedBlocCount, 0);
      expect(LeakDetector.hasLeaks, isFalse);
      expect(LeakDetector.checkForLeaks(), isFalse);
      expect(LeakDetector.getLeakReport(), 'Leak detection not enabled');
    });

    test('disable() clears tracked data', () {
      LeakDetector.enable();
      LeakDetector.trackBlocCreation(const BlocId(_LeakyBloc));
      LeakDetector.trackLeaseAcquire(const BlocId(_LeakyBloc));
      expect(LeakDetector.hasLeaks, isTrue);
      LeakDetector.disable();
      expect(LeakDetector.isEnabled, isFalse);
      expect(LeakDetector.unclosedBlocCount, 0);
      expect(LeakDetector.unreleasedLeaseCount, 0);
    });
  });

  group('LeakDetector (enabled)', () {
    setUp(LeakDetector.enable);

    test('enable() turns detection on in debug mode', () {
      expect(LeakDetector.isEnabled, isTrue);
      expect(LeakDetector.hasLeaks, isFalse);
    });

    test('clean state reports no leaks', () async {
      expect(LeakDetector.getLeakReport(), contains('No leaks detected.'));
      final prints = await _capturePrints(() async {
        expect(LeakDetector.checkForLeaks(), isFalse);
      });
      expect(prints, isEmpty);
    });

    test('bloc creation/close is tracked per BlocId', () {
      const a = BlocId(_LeakyBloc);
      const b = BlocId(_LeakyBloc, 'scoped');
      LeakDetector.trackBlocCreation(a);
      LeakDetector.trackBlocCreation(b);
      expect(LeakDetector.unclosedBlocCount, 2);
      LeakDetector.trackBlocClose(a);
      expect(LeakDetector.unclosedBlocCount, 1);
      LeakDetector.trackBlocClose(b);
      expect(LeakDetector.hasLeaks, isFalse);
    });

    test('lease release only removes a lease for the same bloc', () {
      LeakDetector.trackLeaseAcquire(const BlocId(_LeakyBloc));
      LeakDetector.trackLeaseRelease(const BlocId(_OtherBloc));
      expect(LeakDetector.unreleasedLeaseCount, 1);
      LeakDetector.trackLeaseRelease(const BlocId(_LeakyBloc));
      expect(LeakDetector.unreleasedLeaseCount, 0);
      // Releasing with nothing tracked is harmless.
      LeakDetector.trackLeaseRelease(const BlocId(_LeakyBloc));
      expect(LeakDetector.unreleasedLeaseCount, 0);
    });

    test('report lists unreleased leases grouped by bloc with context', () {
      LeakDetector.trackLeaseAcquire(const BlocId(_LeakyBloc),
          context: 'ProfilePage');
      LeakDetector.trackLeaseAcquire(const BlocId(_LeakyBloc));
      LeakDetector.trackLeaseAcquire(const BlocId(_OtherBloc));

      final report = LeakDetector.getLeakReport();
      expect(report, contains('=== Juice Leak Detection Report ==='));
      expect(report, contains('UNRELEASED LEASES (3):'));
      expect(report, contains('_LeakyBloc (2 unreleased):'));
      expect(report, contains('_OtherBloc (1 unreleased):'));
      expect(report, contains('Context: ProfilePage'));
      expect(report, contains('Acquired at:'));
      expect(report, contains('Stack trace:'));
      expect(report, isNot(contains('UNCLOSED BLOCS')));
      expect(report, contains('=== End Report ==='));
    });

    test('report lists unclosed blocs', () {
      LeakDetector.trackBlocCreation(const BlocId(_OtherBloc));
      final report = LeakDetector.getLeakReport();
      expect(report, contains('UNCLOSED BLOCS (1):'));
      expect(report, contains('_OtherBloc:'));
      expect(report, contains('Created at:'));
      expect(report, isNot(contains('UNRELEASED LEASES')));
    });

    test('checkForLeaks returns true and prints the report', () async {
      LeakDetector.trackBlocCreation(const BlocId(_LeakyBloc));
      late bool found;
      final prints = await _capturePrints(() async {
        found = LeakDetector.checkForLeaks();
      });
      expect(found, isTrue);
      expect(prints.join('\n'), contains('UNCLOSED BLOCS (1):'));
    });

    test('reset() clears data but keeps detection enabled', () {
      LeakDetector.trackBlocCreation(const BlocId(_LeakyBloc));
      LeakDetector.trackLeaseAcquire(const BlocId(_LeakyBloc));
      // ignore: invalid_use_of_visible_for_testing_member
      LeakDetector.reset();
      expect(LeakDetector.isEnabled, isTrue);
      expect(LeakDetector.hasLeaks, isFalse);
    });
  });

  group('LeakDetector integration with BlocScope', () {
    test('enableLeakDetection + leased bloc: leak until lease disposed',
        () async {
      BlocScope.enableLeakDetection();
      expect(LeakDetector.isEnabled, isTrue);

      BlocScope.register<_LeakyBloc>(() => _LeakyBloc(),
          lifecycle: BlocLifecycle.leased);
      final lease = BlocScope.lease<_LeakyBloc>();

      expect(LeakDetector.unreleasedLeaseCount, 1);
      expect(LeakDetector.unclosedBlocCount, 1);
      late bool found;
      final prints = await _capturePrints(() async {
        found = BlocScope.checkForLeaks();
      });
      expect(found, isTrue);
      expect(prints.join('\n'), contains('_LeakyBloc (1 unreleased)'));

      lease.dispose();
      // Last lease on a leased bloc closes it asynchronously.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(LeakDetector.unreleasedLeaseCount, 0);
      expect(LeakDetector.unclosedBlocCount, 0);
      expect(BlocScope.checkForLeaks(), isFalse);
    });

    test('permanent bloc is an unclosed bloc until ended', () async {
      LeakDetector.enable();
      BlocScope.register<_OtherBloc>(() => _OtherBloc());
      BlocScope.get<_OtherBloc>();
      expect(LeakDetector.unclosedBlocCount, 1);
      await BlocScope.end<_OtherBloc>();
      expect(LeakDetector.hasLeaks, isFalse);
    });
  });
}
