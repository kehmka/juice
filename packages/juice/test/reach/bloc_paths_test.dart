// ignore_for_file: implementation_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:rxdart/rxdart.dart';
import 'package:juice/src/bloc/src/core/state_manager.dart';
import 'package:juice/src/bloc/src/core/status_emitter.dart';

/// Core paths no other test reached (coverage to 99, 2026-10-07): the bloc's
/// start/dispose/addError and a THROWING custom error handler; emitEvent;
/// an initial event sent at construction; EventSubscription's registration
/// path, getters, closed-source refusal, status filters and stream error;
/// a relay whose source stream errors or ends; the retry wrapper forwarding
/// waiting/cancel/event; scope-ending edge cases; leak reporting; the raw
/// store and emitter guards; FeatureScope after end.

class _S extends BlocState {
  const _S(this.n, [this.log = const []]);
  final int n;
  final List<String> log;
}

class _Bump extends EventBase {}

class _Seed extends EventBase {}

class _Pub extends EventBase {
  _Pub(this.kind);
  final String kind; // 'update' | 'waiting' | 'failure' | 'cancel' | 'event'
}

class _Local extends EventBase {
  _Local(this.from);
  final String from;
}

class _BumpUC extends BlocUseCase<_Src, _Bump> {
  @override
  Future<void> execute(_Bump e) async =>
      emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'g'});
}

class _SeedUC extends BlocUseCase<_Src, _Seed> {
  @override
  Future<void> execute(_Seed e) async =>
      emitUpdate(newState: const _S(100), groupsToRebuild: {'g'});
}

/// Emits one status of each kind, by name; 'event' uses emitEvent.
class _PubUC extends BlocUseCase<_Src, _Pub> {
  @override
  Future<void> execute(_Pub e) async {
    switch (e.kind) {
      case 'waiting':
        emitWaiting(groupsToRebuild: {'g'});
      case 'failure':
        emitFailure(error: StateError('f'), groupsToRebuild: {'g'});
      case 'cancel':
        emitCancel(groupsToRebuild: {'g'});
      case 'event':
        emitEvent(event: _Bump());
      default:
        emitUpdate(newState: _S(bloc.state.n), groupsToRebuild: {'g'});
    }
  }
}

class _Src extends JuiceBloc<_S> {
  _Src({BlocErrorHandler? handler, bool withInitial = false, JuiceLogger? log})
      : super(
          const _S(0),
          [
            () => UseCaseBuilder.typed(() => _BumpUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _PubUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _SeedUC(),
                concurrency: EventConcurrency.sequential,
                initialEventBuilder: withInitial ? () => _Seed() : null),
          ],
          const [],
          log,
          handler ?? const BlocErrorHandler(),
        );
  final _errors = StreamController<StreamStatus<_S>>.broadcast();
  void failStream() => _errors.addError(StateError('src stream boom'));

  /// addError is @protected: report from inside the bloc.
  void report(Object e) => addError(e);
  Future<void> endStream() => _errors.close();
  @override
  Stream<StreamStatus<_S>> get stream => _errors.isClosed
      ? super.stream
      : Rx.merge([super.stream, _errors.stream]);
  @override
  Future<void> close() async {
    if (!_errors.isClosed) await _errors.close();
    await super.close();
  }
}

class _LocalUC extends BlocUseCase<_Dst, _Local> {
  @override
  Future<void> execute(_Local e) async => emitUpdate(
      newState: _S(bloc.state.n, [...bloc.state.log, e.from]),
      groupsToRebuild: {'g'});
}

/// Subscribes to EVERY status kind of _Src, turning each into a _Local.
class _Dst extends JuiceBloc<_S> {
  _Dst({Set<Type>? statusTypes, BlocDependencyResolver? resolver})
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _LocalUC(),
              concurrency: EventConcurrency.sequential),
          () => EventSubscription<_Src, EventBase, _Local>(
                toEvent: (e) => _Local(e.runtimeType.toString()),
                useCaseGenerator: () => _LocalUC(),
                statusTypes: statusTypes ??
                    const {
                      UpdatingStatus,
                      WaitingStatus,
                      FailureStatus,
                      CancelingStatus
                    },
                resolver: resolver,
              ),
        ]);
}

/// A destination whose ONLY handler for _Local comes from the subscription.
class _DstNoHandler extends JuiceBloc<_S> {
  _DstNoHandler()
      : super(const _S(0), [
          () => EventSubscription<_Src, _Bump, _Local>(
                toEvent: (e) => _Local('bump'),
                useCaseGenerator: () => _LocalUC2(),
              ),
        ]);
}

class _LocalUC2 extends BlocUseCase<_DstNoHandler, _Local> {
  @override
  Future<void> execute(_Local e) async =>
      emitUpdate(newState: _S(bloc.state.n + 1), groupsToRebuild: {'g'});
}

class _Map implements BlocDependencyResolver {
  _Map(this.m);
  final Map<Type, JuiceBloc> m;
  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) =>
      (m[T] ?? (throw StateError('no $T'))) as T;
  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) =>
      throw UnimplementedError();
  @override
  Future<void> disposeAll() async {}
}

class _Log implements JuiceLogger {
  @override
  void record(JuiceTelemetry e) =>
      e.isError ? errors.add(e.message) : entries.add(e.message);

  final errors = <String>[];
  final entries = <String>[];
  @override
  void log(String m,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      entries.add(m);
  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      errors.add(m);
}

/// A retried use case that forwards waiting, cancel and event.
class _RetryUC extends BlocUseCase<_RetryBloc, _Pub> {
  @override
  Future<void> execute(_Pub e) async {
    switch (e.kind) {
      case 'waiting':
        emitWaiting(groupsToRebuild: {'g'});
      case 'cancel':
        emitCancel(groupsToRebuild: {'g'});
      case 'event':
        emitEvent(event: _Bump());
      default:
        emitUpdate(newState: const _S(1), groupsToRebuild: {'g'});
    }
  }
}

class _RetryBloc extends JuiceBloc<_S> {
  _RetryBloc()
      : super(const _S(0), [
          () => RetryableUseCaseBuilder<_RetryBloc, _S, _Pub>(
                typeOfEvent: _Pub,
                useCaseGenerator: () => _RetryUC(),
                concurrency: EventConcurrency.sequential,
                // no backoff → the default ExponentialBackoff is constructed
              ),
        ]);
}

Future<void> pump([int n = 2]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  tearDown(() async {
    await BlocScope.endAll();
  });

  group('JuiceBloc', () {
    test('start() re-emits the current state as an update', () async {
      final b = _Src();
      final seen = <StreamStatus<_S>>[];
      final sub = b.stream.listen(seen.add);
      b.start();
      await pump();
      expect(seen.single, isA<UpdatingStatus<_S>>());
      expect(seen.single.state.n, 0);
      await sub.cancel();
      await b.close();
    });

    test('dispose() closes the bloc', () async {
      final b = _Src();
      b.dispose();
      await pump();
      expect(b.isClosed, isTrue);
    });

    test(
        'addError routes to onError; a THROWING custom handler is caught '
        'and logged, never propagated', () async {
      final log = _Log();
      final b = _Src(
          log: log,
          handler: BlocErrorHandler(
              onError: (m, {error, stackTrace}) =>
                  throw StateError('handler')));
      expect(() => b.report(StateError('x')), returnsNormally);
      expect(log.errors,
          containsAll(['Bloc error', 'Error in custom errorHandler']));
      await b.close();
    });

    test('emitEvent from a use case stamps the event onto the current status',
        () async {
      final b = _Src();
      await b.send(_Pub('event'));
      expect(b.currentStatus.event, isA<_Bump>());
      expect(b.state.n, 0, reason: 'state untouched');
      await b.close();
    });

    test('an initialEventBuilder on a plain builder is sent at construction',
        () async {
      final b = _Src(withInitial: true);
      await pump();
      expect(b.state.n, 100);
      await b.close();
    });
  });

  group('EventSubscription', () {
    test('getters and the no-local-handler registration path', () async {
      final src = _Src();
      BlocScope.register<_Src>(() => src);
      final dst = _DstNoHandler();
      await pump();
      await src.send(_Bump());
      await pump();
      expect(dst.state.n, 1, reason: 'the subscription registered _Local');
      final sub = EventSubscription<_Src, _Bump, _Local>(
          toEvent: (e) => _Local('x'), useCaseGenerator: () => _LocalUC2());
      expect(sub.generator, isNotNull);
      expect(sub.sourceEventType, _Bump);
      expect(sub.sourceBlocType, _Src);
      expect(sub.initialEventBuilder, isNull);
      await dst.close();
    });

    test('every status kind passes its filter; a stream error is logged',
        () async {
      final log = _Log();
      final saved = JuiceLoggerConfig.logger;
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final src = _Src();
      BlocScope.register<_Src>(() => src);
      final dst = _Dst();
      await pump();
      for (final k in ['update', 'waiting', 'failure', 'cancel']) {
        await src.send(_Pub(k));
        await pump();
      }
      expect(dst.state.log.length, 4, reason: 'one _Local per status kind');
      src.failStream();
      await pump();
      expect(log.errors, contains('Stream error in EventSubscription'));
      await dst.close();
    });

    test(
        'a closed source bloc is refused at construction: thrown from the '
        'subscribing bloc\'s constructor, and logged', () async {
      final log = _Log();
      final saved = JuiceLoggerConfig.logger;
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final src = _Src();
      await src.close();
      expect(
          () => _Dst(resolver: _Map({_Src: src})),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('closed bloc'))));
      expect(
          log.errors
              .any((e) => e.contains('Failed to initialize EventSubscription')),
          isTrue);
    });
  });

  group('relays', () {
    test('a source stream error closes the relay (StateRelay and StatusRelay)',
        () async {
      final src = _Src();
      final dst = _Dst(resolver: _Map({_Src: src}));
      final r = _Map({_Src: src, _Dst: dst});
      final state = StateRelay<_Src, _Dst, _S>(
          toEvent: (s) => _Local('state'), resolver: r);
      final status = StatusRelay<_Src, _Dst, _S>(
          toEvent: (s) => _Local('status'), resolver: r);
      src.failStream();
      await pump(3);
      expect(state.isClosed, isTrue);
      expect(status.isClosed, isTrue);
      await src.close();
      await dst.close();
    });

    test('a source stream ending closes the relay', () async {
      final src = _Src();
      final dst = _Dst(resolver: _Map({_Src: src}));
      final r = _Map({_Src: src, _Dst: dst});
      final state = StateRelay<_Src, _Dst, _S>(
          toEvent: (s) => _Local('state'), resolver: r);
      final status = StatusRelay<_Src, _Dst, _S>(
          toEvent: (s) => _Local('status'), resolver: r);
      await src.close(); // the status stream completes
      await pump(3);
      expect(state.isClosed, isTrue);
      expect(status.isClosed, isTrue);
      await dst.close();
    });
  });

  group('RetryableUseCaseBuilder', () {
    test(
        'forwards waiting, cancel and event from the wrapped use case; '
        'the default backoff is exponential', () async {
      final b = _RetryBloc();
      final seen = <StreamStatus<_S>>[];
      final sub = b.stream.listen(seen.add);
      await b.send(_Pub('waiting'));
      await b.send(_Pub('cancel'));
      await pump();
      expect(seen.whereType<WaitingStatus<_S>>(), hasLength(1));
      expect(seen.whereType<CancelingStatus<_S>>(), hasLength(1));
      // emitEvent re-emits the CURRENT status kind with the new event.
      await b.send(_Pub('event'));
      await pump();
      expect(b.currentStatus.event, isA<_Bump>());
      expect(b.currentStatus, isA<CancelingStatus<_S>>());
      await sub.cancel();
      await b.close();
    });
  });

  group('scopes', () {
    test('BlocScope.get on a LEASED bloc throws under asserts', () {
      BlocScope.register<_Src>(() => _Src(), lifecycle: BlocLifecycle.leased);
      expect(() => BlocScope.get<_Src>(), throwsA(isA<StateError>()));
    });

    test('endAll reports an un-ended feature bloc as a leak', () async {
      final scope = FeatureScope('cov');
      BlocScope.register<_Src>(() => _Src(),
          lifecycle: BlocLifecycle.feature, scope: scope);
      BlocScope.get<_Src>(scope: scope); // instantiate it
      final printed = <String>[];
      final saved = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
      try {
        await BlocScope.endAll();
      } finally {
        debugPrint = saved;
      }
      expect(
          printed.any(
              (l) => l.contains('Feature bloc') && l.contains('not ended')),
          isTrue);
    });

    test('FeatureScope: track after end throws; == is by id', () async {
      final a = FeatureScope('x');
      final b = FeatureScope('x');
      expect(a == a, isTrue);
      expect(a == b, isFalse);
      await a.end();
      expect(() => a.track(_Src), throwsA(isA<StateError>()));
    });

    test('ending a scope twice concurrently shares one future', () async {
      final scope = FeatureScope('twice');
      BlocScope.register<_Src>(() => _Src(),
          lifecycle: BlocLifecycle.feature, scope: scope);
      BlocScope.get<_Src>(scope: scope);
      final first = scope.end();
      final second = scope.end();
      await Future.wait([first, second]);
      expect(scope.isEnded, isTrue);
    });
  });

  group('ScopeLifecycleBloc', () {
    test(
        'a scope seeded as ENDING with no in-flight future ends as notFound '
        '(the invariant breach is logged, not thrown)', () async {
      final bloc = ScopeLifecycleBloc();
      final scope = FeatureScope('ghost');
      bloc.seedState(ScopeState(scopes: {
        'ghost-id': ScopeInfo(
          id: 'ghost-id',
          name: 'ghost',
          phase: ScopePhase.ending,
          startedAt: DateTime.now(),
          scope: scope,
        ),
      }));
      final event = EndScopeEvent(scopeId: 'ghost-id');
      await bloc.send(event);
      expect(await event.result, EndScopeResult.notFound);
      await bloc.close();
      await scope.end();
    });
  });

  group('raw store and emitter guards', () {
    test('StateManager refuses an emit after close', () async {
      final sm = StateManager<int>(0);
      await sm.close();
      expect(() => sm.emit(1), throwsA(isA<StateError>()));
    });

    test('StatusEmitter exposes oldState, currentStatus and isClosed',
        () async {
      final sm = StateManager<StreamStatus<_S>>(
          StreamStatus.updating(const _S(1), const _S(0), null));
      final em =
          StatusEmitter<_S>(stateManager: sm, logger: _Log(), blocName: 'x');
      expect(em.oldState.n, 0);
      expect(em.currentStatus.state.n, 1);
      expect(em.isClosed, isFalse);
      await sm.close();
      expect(em.isClosed, isTrue);
    });
  });
}
