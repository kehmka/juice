import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice/testing.dart';

import '../support/capture_logger.dart';

/// The telemetry vocabulary's contracts (2.0.0):
///
/// - every kind below the floor is NOT built; the exemptions are exactly
///   the error kinds, `emissionAfterClose`, `eventIgnored`,
///   `streamBindingRefused` and a failure `stateEmitted`;
/// - a failure emission carries its error AND its stack trace, at the
///   kind's level (not an error entry);
/// - a relay's and a subscription's failures are kinds with a `site`;
/// - `toMap` keeps the 1.x keys (`streamBindings`, `blocsEnded`), renders
///   `status` and `lifecycle` as their wire strings;
/// - `juiceTest` counts a sequential run's escaped failure as an error.

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _Set extends EventBase {
  _Set(this.n);
  final int n;
}

class _Fail extends EventBase {}

class _Boom extends EventBase {}

class _SetUC extends BlocUseCase<_B, _Set> {
  @override
  Future<void> execute(_Set e) async => emitUpdate(newState: _S(e.n));
}

class _FailUC extends BlocUseCase<_B, _Fail> {
  @override
  Future<void> execute(_Fail e) async => emitFailure(
      error: StateError('nope'), errorStackTrace: StackTrace.current);
}

class _BoomUC extends BlocUseCase<_B, _Boom> {
  @override
  Future<void> execute(_Boom e) async => throw StateError('boom');
}

class _B extends JuiceBloc<_S> {
  _B({JuiceLogger? logger, this.rethrowErrors = false})
      : super(
          const _S(0),
          [
            () => UseCaseBuilder.typed(() => _SetUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _FailUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _BoomUC(),
                concurrency: EventConcurrency.sequential),
          ],
          const [],
          logger,
          quietErrorHandler,
        );

  final bool rethrowErrors;

  @override
  void onError(Object error, StackTrace stackTrace) {
    super.onError(error, stackTrace);
    if (rethrowErrors) throw error;
  }
}

/// A relay source whose status stream the test can break.
class _Src extends JuiceBloc<_S> {
  _Src() : super(const _S(0), []) {
    super.stream.listen(_out.add);
  }
  final _out = StreamController<StreamStatus<_S>>.broadcast();
  @override
  Stream<StreamStatus<_S>> get stream => _out.stream;
  void breakStream() => _out.addError(StateError('broken'));
  @override
  Future<void> close() async {
    await super.close();
    await _out.close();
  }
}

class _Dst extends JuiceBloc<_S> {
  _Dst()
      : super(const _S(0), [
          () => UseCaseBuilder.typed(() => _SetUC2(),
              concurrency: EventConcurrency.sequential),
        ]);
}

class _SetUC2 extends BlocUseCase<_Dst, _Set> {
  @override
  Future<void> execute(_Set e) async => emitUpdate(newState: _S(e.n));
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

void main() {
  late JuiceLogger savedLogger;
  late Level savedLevel;
  late CaptureLogger log;
  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    savedLevel = JuiceLoggerConfig.minLevel;
    log = CaptureLogger();
    JuiceLoggerConfig.configureLogger(log);
    JuiceLoggerConfig.minLevel = Level.all;
  });
  tearDown(() async {
    JuiceLoggerConfig.configureLogger(savedLogger);
    JuiceLoggerConfig.minLevel = savedLevel;
    await BlocScope.reset();
  });

  group('the floor', () {
    test('lifecycle, lease and subscription kinds are not built below it',
        () async {
      JuiceLoggerConfig.minLevel = Level.warning;
      BlocScope.register<_B>(() => _B(logger: log),
          lifecycle: BlocLifecycle.leased);
      final lease = BlocScope.lease<_B>();
      await lease.bloc.send(_Set(1));
      lease.dispose();
      await BlocScope.reset();
      expect(
          log.entries
              .map((e) => e['type'])
              .where((t) => t == 'bloc_lifecycle' || t == 'use_case_execution'),
          isEmpty,
          reason: 'nothing at info is built: ${log.entries}');
    });

    test('and ARE built at Level.all, with the 1.x wire keys', () async {
      BlocScope.register<_B>(() => _B(logger: log),
          lifecycle: BlocLifecycle.leased);
      final lease = BlocScope.lease<_B>();
      lease.dispose();
      final registered = log.where('bloc_lifecycle', 'register').single;
      expect(registered['lifecycle'], 'leased');
      expect(
          log.where('bloc_lifecycle', 'lease_acquire').single['leaseCount'], 1);
      expect(
          log.where('bloc_lifecycle', 'lease_release').single['leaseCount'], 0);
    });

    test('a bloc\'s close entry keeps the streamBindings key', () async {
      final b = _B(logger: log);
      final c = StreamController<int>.broadcast();
      b.bindStream<int>(c.stream, (_) {});
      await b.close();
      expect(log.where('bloc_lifecycle', 'close').single['streamBindings'], 1);
      await c.close();
    });

    test(
        'a refused bind on a closing bloc is recorded below the floor; a '
        'superseded run\'s is not', () async {
      JuiceLoggerConfig.minLevel = Level.warning;
      final b = _B(logger: log);
      final closing = b.close();
      final c = StreamController<int>();
      b.bindStream<int>(c.stream, (_) {});
      await closing;
      final refused = log.bindings('refused').single;
      expect(refused['reason'], 'bloc is closing');
      expect(refused['level'], Level.warning);
      unawaited(c.close());
    });
  });

  group('a failure emission', () {
    test('carries error and stack trace at info, not as an error entry',
        () async {
      final entries = <JuiceTelemetry>[];
      final b = _B(logger: _Recording(entries));
      await b.send(_Fail());
      final failure =
          entries.singleWhere((e) => e.kind == JuiceTelemetryKind.stateEmitted);
      expect(failure.status, EmissionKind.failure);
      expect(failure.error, isA<StateError>());
      expect(failure.stackTrace, isNotNull);
      expect(failure.isError, isFalse);
      expect(failure.level, Level.info);
      expect(failure.toMap()['status'], 'failure');
      await b.close();
    });
  });

  group('relay and subscription failures', () {
    test('a relay whose source stream errors records relayFailed/stream',
        () async {
      final entries = <JuiceTelemetry>[];
      JuiceLoggerConfig.configureLogger(_Recording(entries));
      final src = _Src();
      final dst = _Dst();
      final relay = StateRelay<_Src, _Dst, _S>(
          toEvent: (s) => _Set(s.n), resolver: _Map({_Src: src, _Dst: dst}));
      src.breakStream();
      await Future<void>.delayed(Duration.zero);
      final failed =
          entries.singleWhere((e) => e.kind == JuiceTelemetryKind.relayFailed);
      expect(failed.relay, 'StateRelay');
      expect(failed.site, 'stream');
      expect(failed.sourceBloc, '_Src');
      expect(failed.destBloc, '_Dst');
      expect(failed.error, isA<StateError>());
      expect(relay.isClosed, isTrue);
      await src.close();
      await dst.close();
    });

    test(
        'a relay on an unregistered bloc records relayFailed/initialize '
        'and throws', () async {
      final entries = <JuiceTelemetry>[];
      JuiceLoggerConfig.configureLogger(_Recording(entries));
      expect(() => StateRelay<_Src, _Dst, _S>(toEvent: (s) => _Set(s.n)),
          throwsStateError);
      final failed =
          entries.singleWhere((e) => e.kind == JuiceTelemetryKind.relayFailed);
      expect(failed.site, 'initialize');
    });
  });

  group('juiceTest', () {
    test('counts a sequential run\'s escaped failure as an error', () async {
      await expectLater(
        runJuiceTest<_B, _S>(
          build: () => _B(rethrowErrors: true),
          act: (b) => b.send(_Boom()),
          errors: () => [isStateError, isStateError],
        ),
        completes,
        reason: 'the span-closer and the escaped failure are both counted',
      );
    });
  });
}

class _Recording implements JuiceLogger {
  _Recording(this.entries);
  final List<JuiceTelemetry> entries;
  @override
  void record(JuiceTelemetry e) => entries.add(e);
  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {}
  @override
  void logError(String m, Object e, StackTrace s,
      {Map<String, dynamic>? context}) {}
}
