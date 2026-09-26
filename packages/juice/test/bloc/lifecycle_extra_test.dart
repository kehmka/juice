import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

class _S extends BlocState {
  const _S();
}

class _PermBloc extends JuiceBloc<_S> {
  _PermBloc() : super(const _S(), []);
}

class _LeasedBloc extends JuiceBloc<_S> {
  _LeasedBloc() : super(const _S(), []);
}

/// A bloc whose close() takes a while, to observe the "closing" window.
class _SlowCloseBloc extends JuiceBloc<_S> {
  _SlowCloseBloc() : super(const _S(), []);

  static int closes = 0;

  @override
  Future<void> close() async {
    closes++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await super.close();
  }
}

class _IntResultEvent extends ResultEvent<int> {}

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
  tearDown(BlocScope.reset);

  group('BlocScope resolution edge cases', () {
    test('get() on a leased bloc throws in debug mode', () {
      BlocScope.register<_LeasedBloc>(() => _LeasedBloc(),
          lifecycle: BlocLifecycle.leased);
      expect(
        () => BlocScope.get<_LeasedBloc>(),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('use BlocScope.lease'))),
      );
    });

    test('leaseAsync on an unregistered bloc throws', () async {
      await expectLater(
          BlocScope.leaseAsync<_PermBloc>(), throwsA(isA<StateError>()));
    });

    test('leaseAsync on an idle bloc leases immediately', () async {
      BlocScope.register<_LeasedBloc>(() => _LeasedBloc(),
          lifecycle: BlocLifecycle.leased);
      final lease = await BlocScope.leaseAsync<_LeasedBloc>();
      expect(BlocScope.diagnostics<_LeasedBloc>()!.leaseCount, 1);
      lease.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(BlocScope.diagnostics<_LeasedBloc>()!.isActive, isFalse);
    });

    test('peekExisting throws when unregistered or not yet created', () {
      expect(() => BlocScope.peekExisting<_PermBloc>(), throwsStateError);
      BlocScope.register<_PermBloc>(() => _PermBloc());
      expect(
        () => BlocScope.peekExisting<_PermBloc>(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('no active'))),
      );
      final bloc = BlocScope.get<_PermBloc>();
      expect(BlocScope.peekExisting<_PermBloc>(), same(bloc));
    });

    test('maybePeekExisting returns null until an instance exists', () {
      expect(BlocScope.maybePeekExisting<_PermBloc>(), isNull);
      BlocScope.register<_PermBloc>(() => _PermBloc());
      expect(BlocScope.maybePeekExisting<_PermBloc>(), isNull);
      final bloc = BlocScope.get<_PermBloc>();
      expect(BlocScope.maybePeekExisting<_PermBloc>(), same(bloc));
      // Scope keys are distinct ids.
      expect(BlocScope.maybePeekExisting<_PermBloc>(scope: 'other'), isNull);
    });

    test('peeking does not change lease count', () {
      BlocScope.register<_LeasedBloc>(() => _LeasedBloc(),
          lifecycle: BlocLifecycle.leased);
      final lease = BlocScope.lease<_LeasedBloc>();
      BlocScope.peekExisting<_LeasedBloc>();
      BlocScope.maybePeekExisting<_LeasedBloc>();
      expect(BlocScope.diagnostics<_LeasedBloc>()!.leaseCount, 1);
      lease.dispose();
    });
  });

  group('BlocScope closing window', () {
    setUp(() => _SlowCloseBloc.closes = 0);

    test('sync get/lease during close throws, concurrent end shares close',
        () async {
      BlocScope.register<_SlowCloseBloc>(() => _SlowCloseBloc());
      final first = BlocScope.get<_SlowCloseBloc>();

      final end1 = BlocScope.end<_SlowCloseBloc>();
      final diag = BlocScope.diagnostics<_SlowCloseBloc>()!;
      expect(diag.isClosing, isTrue);

      expect(
        () => BlocScope.get<_SlowCloseBloc>(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('is closing'))),
      );
      expect(() => BlocScope.lease<_SlowCloseBloc>(), throwsStateError);

      // A second end while closing waits for the same close.
      final end2 = BlocScope.end<_SlowCloseBloc>();
      // leaseAsync waits for the close, then creates a fresh instance.
      final leaseFuture = BlocScope.leaseAsync<_SlowCloseBloc>();

      await Future.wait([end1, end2]);
      expect(_SlowCloseBloc.closes, 1);
      expect(first.isClosed, isTrue);

      final lease = await leaseFuture;
      expect(identical(lease.bloc, first), isFalse);
      expect(lease.bloc.isClosed, isFalse);
      lease.dispose();
    });

    test('ending an unregistered or never-created bloc is a no-op', () async {
      await BlocScope.end<_PermBloc>();
      BlocScope.register<_PermBloc>(() => _PermBloc());
      await BlocScope.end<_PermBloc>();
      expect(BlocScope.diagnostics<_PermBloc>()!.isActive, isFalse);
    });
  });

  group('BlocScope.validateRegistration', () {
    test('throws for unregistered bloc', () {
      expect(
        () => BlocScope.validateRegistration<_PermBloc>(
            expectedLifecycle: BlocLifecycle.permanent),
        throwsStateError,
      );
    });

    test('matching lifecycle is silent', () async {
      BlocScope.register<_PermBloc>(() => _PermBloc());
      final prints = await _capturePrints(() async {
        BlocScope.validateRegistration<_PermBloc>(
            expectedLifecycle: BlocLifecycle.permanent);
      });
      expect(prints, isEmpty);
    });

    test('mismatched lifecycle warns but does not throw', () async {
      BlocScope.register<_PermBloc>(() => _PermBloc());
      final prints = await _capturePrints(() async {
        BlocScope.validateRegistration<_PermBloc>(
            expectedLifecycle: BlocLifecycle.leased);
      });
      expect(prints.single, contains('expects _PermBloc with'));
      expect(prints.single, contains('BlocLifecycle.leased'));
      expect(prints.single, contains('BlocLifecycle.permanent'));
    });
  });

  group('BlocScope diagnostics', () {
    test('debugDump prints each registration', () async {
      BlocScope.register<_PermBloc>(() => _PermBloc());
      BlocScope.register<_LeasedBloc>(() => _LeasedBloc(),
          lifecycle: BlocLifecycle.leased, scope: 'k1');
      BlocScope.get<_PermBloc>();
      final prints = await _capturePrints(() async => BlocScope.debugDump());
      final out = prints.join('\n');
      expect(prints.first, '=== BlocScope Debug Dump ===');
      expect(prints.last, '=== End Dump ===');
      expect(out, contains('_PermBloc (scope: GlobalScope)'));
      expect(out, contains('instance: active'));
      expect(out, contains('_LeasedBloc (scope: k1)'));
      expect(out, contains('instance: null'));
      expect(out, contains('lifecycle: BlocLifecycle.leased'));
    });

    test('diagnostics for a scoped bloc and toString', () {
      BlocScope.register<_PermBloc>(() => _PermBloc(), scope: 'tenant');
      BlocScope.get<_PermBloc>(scope: 'tenant');
      final d = BlocScope.diagnostics<_PermBloc>(scope: 'tenant')!;
      expect(d.scope, 'tenant');
      expect(d.isActive, isTrue);
      expect(d.createdAt, isNotNull);
      expect(BlocScope.diagnostics<_PermBloc>(), isNull);
      final s = d.toString();
      expect(s, startsWith('BlocDiagnostics('));
      expect(s, contains('type: _PermBloc'));
      expect(s, contains('scope: tenant'));
      expect(s, contains('lifecycle: BlocLifecycle.permanent'));
      expect(s, contains('isActive: true'));
      expect(s, contains('leaseCount: 0'));
      expect(s, contains('isClosing: false'));
    });

    test('endAll warns about feature scopes that were never ended', () async {
      FeatureScope('checkout');
      final prints = await _capturePrints(BlocScope.endAll);
      expect(prints, contains('LEAK: FeatureScope "checkout" was never ended'));
    });
  });

  group('BlocId / BlocEntry', () {
    test('BlocId equality is by type and scope key', () {
      const a = BlocId(_PermBloc);
      const b = BlocId(_PermBloc, BlocId.globalScope);
      const c = BlocId(_PermBloc, 'x');
      const d = BlocId(_LeasedBloc);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a == d, isFalse);
      expect(a.toString(), 'BlocId(_PermBloc, GlobalScope)');
      expect(c.toString(), 'BlocId(_PermBloc, x)');
    });

    test('BlocEntry derived flags follow instance/closing state', () {
      final entry = BlocEntry<_PermBloc>(
          factory: () => _PermBloc(), lifecycle: BlocLifecycle.permanent);
      expect(entry.isActive, isFalse);
      expect(entry.isClosing, isFalse);
      expect(entry.canCreate, isTrue);

      final bloc = entry.factory();
      entry.instance = bloc;
      expect(entry.isActive, isTrue);
      expect(entry.canCreate, isFalse);

      entry.closingFuture = bloc.close();
      expect(entry.isActive, isFalse);
      expect(entry.isClosing, isTrue);
      expect(entry.canCreate, isFalse);

      entry.instance = null;
      expect(entry.canCreate, isFalse, reason: 'still closing');
      entry.closingFuture = null;
      expect(entry.canCreate, isTrue);
    });
  });

  group('ResultEvent', () {
    test('succeed completes once; later calls are ignored', () async {
      final e = _IntResultEvent();
      expect(e.isCompleted, isFalse);
      e.succeed(1);
      e.succeed(2);
      e.fail(StateError('late'));
      expect(e.isCompleted, isTrue);
      expect(await e.result, 1);
    });

    test('fail surfaces the error and stack trace to awaiters', () async {
      final e = _IntResultEvent();
      final trace = StackTrace.fromString('custom-trace');
      e.fail(ArgumentError('bad'), trace);
      e.succeed(3);
      expect(e.isCompleted, isTrue);
      try {
        await e.result;
        fail('expected error');
      } catch (err, st) {
        expect(err, isA<ArgumentError>());
        expect(st.toString(), contains('custom-trace'));
      }
    });

    test('fail without awaiting does not produce an unhandled error', () async {
      _IntResultEvent().fail(StateError('ignored'));
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('Scope value types', () {
    test('EndScopeResult.success requires found, completed and no failures',
        () {
      const ok = EndScopeResult(
        found: true,
        cleanupCompleted: true,
        cleanupFailedCount: 0,
        duration: Duration(seconds: 1),
        cleanupTaskCount: 2,
      );
      expect(ok.success, isTrue);
      expect(EndScopeResult.notFound.success, isFalse);
      expect(
        const EndScopeResult(
          found: true,
          cleanupCompleted: false,
          cleanupFailedCount: 0,
          duration: Duration.zero,
          cleanupTaskCount: 1,
        ).success,
        isFalse,
      );
      expect(
        const EndScopeResult(
          found: true,
          cleanupCompleted: true,
          cleanupFailedCount: 1,
          duration: Duration.zero,
          cleanupTaskCount: 1,
        ).success,
        isFalse,
      );
      expect(
        ok.toString(),
        'EndScopeResult(found: true, cleanupCompleted: true, '
        'cleanupFailedCount: 0, duration: 0:00:01.000000, '
        'cleanupTaskCount: 2)',
      );
    });

    test('notifications expose ids and describe themselves', () {
      final started = ScopeStartedNotification(
        scopeId: '7',
        scopeName: 'cart',
        startedAt: DateTime.utc(2024, 1, 2),
      );
      final ending = ScopeEndingNotification(
        scopeId: '7',
        scopeName: 'cart',
        barrier: CleanupBarrier(),
      );
      const ended = ScopeEndedNotification(
        scopeId: '7',
        scopeName: 'cart',
        duration: Duration(milliseconds: 5),
        cleanupCompleted: true,
      );
      for (final ScopeNotification n in [started, ending, ended]) {
        expect(n.scopeId, '7');
        expect(n.scopeName, 'cart');
      }
      expect(started.toString(),
          'ScopeStartedNotification(scopeId: 7, scopeName: cart, startedAt: 2024-01-02 00:00:00.000Z)');
      expect(ending.toString(),
          'ScopeEndingNotification(scopeId: 7, scopeName: cart)');
      expect(
          ended.toString(),
          'ScopeEndedNotification(scopeId: 7, scopeName: cart, '
          'duration: 0:00:00.005000, cleanupCompleted: true)');
    });

    test('ScopeInfo identity is its id; copyWith changes phase only', () {
      final scope = FeatureScope('cart');
      final at = DateTime.utc(2024);
      final info = ScopeInfo(
          id: '1',
          name: 'cart',
          phase: ScopePhase.active,
          startedAt: at,
          scope: scope);
      final ending = info.copyWith(phase: ScopePhase.ending);
      expect(ending.phase, ScopePhase.ending);
      expect(ending.id, '1');
      expect(ending.name, 'cart');
      expect(ending.startedAt, at);
      expect(ending.scope, same(scope));
      expect(info.copyWith().phase, ScopePhase.active);

      expect(info, equals(ending), reason: 'equality is by id');
      expect(info.hashCode, ending.hashCode);
      expect(
          info ==
              ScopeInfo(
                  id: '2',
                  name: 'cart',
                  phase: ScopePhase.active,
                  startedAt: at,
                  scope: scope),
          isFalse);
      expect(info.toString(),
          'ScopeInfo(id: 1, name: cart, phase: ScopePhase.active, startedAt: 2024-01-01 00:00:00.000Z)');
    });

    test('ScopeState queries by name and phase', () {
      final scope = FeatureScope('x');
      ScopeInfo mk(String id, String name, ScopePhase phase) => ScopeInfo(
          id: id,
          name: name,
          phase: phase,
          startedAt: DateTime.utc(2024),
          scope: scope);
      final state = ScopeState(scopes: {
        '1': mk('1', 'cart', ScopePhase.active),
        '2': mk('2', 'cart', ScopePhase.ending),
        '3': mk('3', 'profile', ScopePhase.ending),
      });

      expect(
          state.byName('cart').map((s) => s.id), unorderedEquals(['1', '2']));
      expect(state.byName('none'), isEmpty);
      expect(state.isActive('cart'), isTrue);
      expect(state.isActive('profile'), isFalse,
          reason: 'only ending instances');
      expect(state.inPhase(ScopePhase.ending).map((s) => s.id),
          unorderedEquals(['2', '3']));
      expect(state.toString(), 'ScopeState(scopes: 3)');

      final copy = state.copyWith();
      expect(identical(copy.scopes, state.scopes), isTrue);
      final cleared = state.copyWith(scopes: {});
      expect(cleared.scopes, isEmpty);
      expect(const ScopeState().scopes, isEmpty);

      expect(ScopeGroups.byName('cart'), 'scope:name:cart');
      expect(ScopeGroups.byId('1'), 'scope:id:1');
      expect(ScopeGroups.active, 'scope:active');
    });
  });
}
