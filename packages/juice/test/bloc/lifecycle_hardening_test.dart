import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// LIFECYCLE THAT CAN'T WEDGE (1.9.0): a stale lease must not close a
/// replacement bloc; a bloc whose close() throws must not strand its entry
/// or hang FeatureScope.end(); a use case registered on the wrong bloc must
/// close its telemetry span and say what is wrong.

class _S extends BlocState {
  const _S();
}

class _Leased extends JuiceBloc<_S> {
  _Leased() : super(const _S(), const []);
}

class _ThrowsOnClose extends JuiceBloc<_S> {
  _ThrowsOnClose() : super(const _S(), const []);

  /// Only the first instance's close fails, so teardown can close the
  /// replacement cleanly.
  static bool failNextClose = true;

  @override
  Future<void> close() async {
    await super.close();
    if (failNextClose) {
      failNextClose = false;
      throw StateError('seam dispose failed');
    }
  }
}

class _Ping extends EventBase {}

class _Other extends JuiceBloc<_S> {
  _Other() : super(const _S(), const []);
}

/// Declares `_Other` as its bloc…
class _PingUC extends BlocUseCase<_Other, _Ping> {
  @override
  Future<void> execute(_Ping e) async => emitUpdate(newState: const _S());
}

/// …but is registered on `_Host` — the copy-paste mistake.
class _Host extends JuiceBloc<_S> {
  _Host(EventConcurrency mode)
      : super(const _S(), [
          () => UseCaseBuilder(
                typeOfEvent: _Ping,
                useCaseGenerator: () => _PingUC(),
                concurrency: mode,
              ),
        ]);
}

class _SpanLogger implements JuiceLogger {
  final starts = <int>[];
  final ends = <int>[];
  final errors = <Object>[];
  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    if (context?['type'] == 'use_case_execution') {
      starts.add(context!['executionId'] as int);
    }
    if (context?['type'] == 'use_case_completed') {
      ends.add(context!['executionId'] as int);
    }
  }

  @override
  void logError(String m, Object e, StackTrace s,
      {Map<String, dynamic>? context}) {
    // Span closers carry executionId; BlocErrorHandler's summary shares the
    // type but not the id (AGENTS §4b).
    if (context?['type'] == 'use_case_error' &&
        context!.containsKey('executionId')) {
      ends.add(context['executionId'] as int);
      errors.add(e);
    }
  }
}

void main() {
  setUp(() {
    BlocScope.reset();
    _ThrowsOnClose.failNextClose = true;
  });
  tearDown(BlocScope.reset);

  group('stale leases', () {
    test('a lease from an ended instance cannot close its replacement',
        () async {
      BlocScope.register<_Leased>(() => _Leased(),
          lifecycle: BlocLifecycle.leased);
      final old = BlocScope.lease<_Leased>();
      await BlocScope.end<_Leased>();
      expect(old.bloc.isClosed, isTrue);

      final fresh = BlocScope.lease<_Leased>();
      expect(identical(fresh.bloc, old.bloc), isFalse);

      old.dispose(); // the stale release
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fresh.bloc.isClosed, isFalse,
          reason: 'the stale release zeroed the new count and auto-closed it');

      fresh.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(fresh.bloc.isClosed, isTrue,
          reason: 'the real last release still auto-closes');
    });
  });

  group('a close() that throws', () {
    test('leaves the entry reusable, and the error reaches the caller',
        () async {
      BlocScope.register<_ThrowsOnClose>(() => _ThrowsOnClose());
      final first = BlocScope.get<_ThrowsOnClose>();
      await expectLater(BlocScope.end<_ThrowsOnClose>(), throwsStateError);

      final second = BlocScope.get<_ThrowsOnClose>();
      expect(identical(first, second), isFalse,
          reason: 'was: closingFuture stuck, get() threw "is closing" forever');
    });

    test('FeatureScope.end() completes (with the error) instead of hanging',
        () async {
      BlocScope.register<ScopeLifecycleBloc>(() => ScopeLifecycleBloc());
      final scope = FeatureScope('checkout');
      await scope.start();
      BlocScope.register<_ThrowsOnClose>(() => _ThrowsOnClose(),
          lifecycle: BlocLifecycle.feature, scope: scope);
      BlocScope.get<_ThrowsOnClose>(scope: scope);

      await expectLater(
          scope.end().timeout(const Duration(seconds: 2)), throwsStateError);

      final lifecycle = BlocScope.get<ScopeLifecycleBloc>();
      expect(lifecycle.state.scopes, isEmpty,
          reason: 'the scope must not be stranded in the ending phase');
    });

    test('FeatureScope.end() does not hang when the lifecycle bloc is closed',
        () async {
      BlocScope.register<ScopeLifecycleBloc>(() => ScopeLifecycleBloc());
      final scope = FeatureScope('late');
      await scope.start();
      await BlocScope.get<ScopeLifecycleBloc>().close();

      final result = await scope.end().timeout(const Duration(seconds: 2));
      expect(result.found, isTrue);
    });
  });

  group('a use case registered on the wrong bloc', () {
    late _SpanLogger logger;
    setUp(() {
      logger = _SpanLogger();
      JuiceLoggerConfig.configureLogger(logger);
    });
    tearDown(() => JuiceLoggerConfig.configureLogger(DefaultJuiceLogger()));

    for (final mode in EventConcurrency.values) {
      test('closes its span and names the mistake ($mode)', () async {
        final host = _Host(mode);
        await host.send(_Ping());

        expect(logger.starts, hasLength(1));
        expect(logger.ends, logger.starts,
            reason: 'every START needs exactly one END');
        final error = logger.errors.single;
        expect(error, isA<StateError>());
        expect('$error',
            allOf(contains('_PingUC'), contains('_Other'), contains('_Host')));
        await host.close();
      });
    }
  });
}
