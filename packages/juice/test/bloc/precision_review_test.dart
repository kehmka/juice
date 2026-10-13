import 'package:flutter_test/flutter_test.dart' hide EventDispatcher;
import 'package:juice/juice.dart';
import 'package:juice/src/bloc/src/core/event_dispatcher.dart';
import 'package:juice/testing.dart';

/// Pins for the pre-2.0 precision review, one group per finding:
///
/// P1  a relay built inside its own bloc's factory fails loudly at the
///     scope — never a stack overflow
/// P2  StatefulUseCaseBuilder + restartable is refused at registration
/// P3  an inline use case's navigation is fenced like its emissions
/// P4  sendAndWait fails loud — dropped by droppable, emitted nothing, no
///     use case registered — and sendAndWaitResult inherits it, answering
///     a superseded run as canceled and a close as a failed result
/// P5  a relay or EventSubscription that fails to initialise holds no
///     lease and throws the real error from the constructor
/// P6  a throwing use-case generator is a use-case error; a sequential
///     run whose failure escapes the executor is logged and the queue goes
///     on; an unhandled-event fallback that throws fails the send
/// P7  bindStream: a throwing onError/onDone is the bloc's error; a listen
///     that throws leaves no binding; repeated cancel returns one future;
///     unbind's failing cancel is logged; a closing bloc refuses with its
///     reason
/// P8  emitEvent after close is dropped through the close fence
/// P9  juiceTest reports a build() that throws as that error, and counts
///     stream-binding errors
/// P10 sendCancellable on a closed bloc is refused like send, at warning
/// P11 a retry superseded before its backoff calls no onRetry
/// P12 a thrown use-case error is one use_case_error span and one
///     bloc_error — not three lines

class _S extends BlocState {
  const _S(this.log);
  final List<String> log;
}

class _Tick extends EventBase {}

class _Unknown extends EventBase {}

class _Cancellable extends CancellableEvent {}

class _Gated extends EventBase {
  _Gated(this.gate);
  final Future<void> gate;
}

class _Drop extends _Gated {
  _Drop(super.gate);
}

class _Silent extends EventBase {}

class _Boom extends EventBase {}

class _NoGen extends EventBase {}

class _Go extends _Gated {
  _Go(super.gate);
}

class _LateEvent extends _Gated {
  _LateEvent(super.gate);
}

class _SlowR extends ResultEvent<int> {
  _SlowR(this.gate);
  final Future<void> gate;
}

class _Fetch extends _Gated {
  _Fetch(super.gate);
}

class _Log implements JuiceLogger {
  final entries = <Map<String, dynamic>>[];
  @override
  void log(String m,
          {Level level = Level.info, Map<String, dynamic>? context}) =>
      entries.add({'message': m, 'level': level, ...?context});
  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      entries
          .add({'message': m, 'error': e, 'level': Level.error, ...?context});
  Iterable<Map<String, dynamic>> typed(String type) =>
      entries.where((e) => e['type'] == type);
}

final _quiet = BlocErrorHandler(onError: (m, {error, stackTrace}) {});

Future<void> pump([int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// --- P1: a bloc that builds a relay on ITSELF in its constructor.

class _TickUC<B extends JuiceBloc<_S>> extends BlocUseCase<B, _Tick> {
  @override
  Future<void> execute(_Tick e) async =>
      emitUpdate(newState: _S([...bloc.state.log, 'tick']));
}

class _Plain extends JuiceBloc<_S> {
  _Plain()
      : super(const _S([]), [
          () => UseCaseBuilder.typed(() => _TickUC<_Plain>(),
              concurrency: EventConcurrency.sequential),
        ]);
}

class _SelfRelay extends JuiceBloc<_S> {
  _SelfRelay() : super(const _S([]), []) {
    StateRelay<_SelfRelay, _Plain, _S>(toEvent: (_) => _Tick());
  }
}

// --- P2

class _StatefulRestartable extends JuiceBloc<_S> {
  _StatefulRestartable()
      : super(const _S([]), [
          () => StatefulUseCaseBuilder(
                typeOfEvent: _Tick,
                useCaseGenerator: () => NoOpUseCase(),
                concurrency: EventConcurrency.restartable,
              ),
        ]);
}

// --- P3

int _navigated = 0;

class _Nav extends JuiceBloc<_S> {
  _Nav()
      : super(
          const _S([]),
          [
            () => InlineUseCaseBuilder<_Nav, _S, _Go>(
                  typeOfEvent: _Go,
                  concurrency: EventConcurrency.restartable,
                  handler: (ctx, e) async {
                    await e.gate;
                    ctx.emit.update(
                        newState: _S([...ctx.state.log, 'went']),
                        aviatorName: 'go');
                  },
                ),
          ],
          [() => Aviator(name: 'go', navigateWhere: (_) => _navigated++)],
          null,
          _quiet,
        );
}

// --- P4, P6, P7, P8, P9, P10, P12: one bloc, every mode

class _DropUC extends BlocUseCase<_W, _Drop> {
  @override
  Future<void> execute(_Drop e) async {
    await e.gate;
    emitUpdate(newState: _S([...bloc.state.log, 'drop']));
  }
}

class _SilentUC extends BlocUseCase<_W, _Silent> {
  @override
  Future<void> execute(_Silent e) async {}
}

class _BoomUC extends BlocUseCase<_W, _Boom> {
  @override
  Future<void> execute(_Boom e) async => throw StateError('boom');
}

class _SlowRUC extends BlocUseCase<_W, _SlowR> {
  @override
  Future<void> execute(_SlowR e) async {
    await e.gate;
    emitUpdate(newState: _S([...bloc.state.log, 'slow']));
    e.succeed(1);
  }
}

class _LateUC extends BlocUseCase<_W, _LateEvent> {
  @override
  Future<void> execute(_LateEvent e) async {
    await e.gate;
    emitEvent(event: _Tick());
  }
}

class _W extends JuiceBloc<_S> {
  _W({JuiceLogger? logger, this.rethrowErrors = false})
      : super(
          const _S([]),
          [
            () => UseCaseBuilder.typed(() => _DropUC(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder.typed(() => _SilentUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _BoomUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _SlowRUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _LateUC(),
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                  typeOfEvent: _NoGen,
                  useCaseGenerator: () => throw StateError('no DI'),
                  concurrency: EventConcurrency.concurrent,
                ),
          ],
          const [],
          logger,
          _quiet,
        );

  /// P6: an `onError` override that throws is the one way a failure
  /// escapes the executor.
  final bool rethrowErrors;
  final errors = <Object>[];

  @override
  void onError(Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(error, stackTrace);
    if (rethrowErrors) throw error;
  }
}

// --- P5

class _Sub extends JuiceBloc<_S> {
  _Sub()
      : super(const _S([]), [
          () => EventSubscription<_Plain, _Tick, _Tick>(
                toEvent: (e) => _Tick(),
                useCaseGenerator: () => _TickUC<_Sub>(),
              ),
        ]);
}

// --- P11

int _retries = 0;

class _FetchUC extends BlocUseCase<_R, _Fetch> {
  @override
  Future<void> execute(_Fetch e) async {
    await e.gate;
    emitFailure(error: StateError('flaky'));
  }
}

class _R extends JuiceBloc<_S> {
  _R()
      : super(
          const _S([]),
          [
            () => RetryableUseCaseBuilder<_R, _S, _Fetch>(
                  typeOfEvent: _Fetch,
                  useCaseGenerator: () => _FetchUC(),
                  maxRetries: 3,
                  backoff: const FixedBackoff(Duration(milliseconds: 1)),
                  onRetry: (a, e, d) => _retries++,
                  concurrency: EventConcurrency.restartable,
                ),
          ],
          const [],
          null,
          _quiet,
        );
}

void main() {
  late JuiceLogger savedLogger;
  late Level savedLevel;
  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    savedLevel = JuiceLoggerConfig.minLevel;
    JuiceLoggerConfig.minLevel = Level.all;
    _navigated = 0;
    _retries = 0;
  });
  tearDown(() async {
    JuiceLoggerConfig.configureLogger(savedLogger);
    JuiceLoggerConfig.minLevel = savedLevel;
    await BlocScope.reset();
  });

  group('P1 scope construction re-entrancy', () {
    test('a relay on its own bloc inside the constructor throws, not overflows',
        () {
      BlocScope.register<_Plain>(() => _Plain());
      BlocScope.register<_SelfRelay>(() => _SelfRelay());
      expect(
          () => BlocScope.get<_SelfRelay>(),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('own factory'))));
      expect(BlocScope.diagnostics<_SelfRelay>()!.isActive, isFalse,
          reason: 'nothing half-built is kept');
    });
  });

  group('P2 stateful + restartable', () {
    test('is refused at registration with ArgumentError', () {
      expect(
          () => _StatefulRestartable(),
          throwsA(isA<ArgumentError>()
              .having((e) => e.message, 'message', contains('restartable'))));
    });
  });

  group('P3 inline navigation', () {
    test('a superseded inline run navigates nowhere; the fresh run does',
        () async {
      final b = _Nav();
      final g1 = Completer<void>();
      final g2 = Completer<void>();
      final old = b.send(_Go(g1.future));
      final fresh = b.send(_Go(g2.future));
      g1.complete();
      await old;
      expect(b.state.log, isEmpty);
      expect(_navigated, 0, reason: 'fenced with the emission');
      g2.complete();
      await fresh;
      expect(b.state.log, ['went']);
      expect(_navigated, 1);
      await b.close();
    });
  });

  group('P4 sendAndWait fails loud', () {
    test('an event dropped by its droppable builder', () async {
      final b = _W();
      final gate = Completer<void>();
      b.send(_Drop(gate.future));
      await pump();
      final sw = Stopwatch()..start();
      await expectLater(
          b.sendAndWait(_Drop(gate.future)),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('dropped'))));
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      gate.complete();
      await b.close();
    });

    test('a use case that emits nothing', () async {
      final b = _W();
      await expectLater(
          b.sendAndWait(_Silent()),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('emitted nothing'))));
      await b.close();
    });

    test('an event no use case handles', () async {
      final b = _W();
      await expectLater(
          b.sendAndWait(_Unknown()),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('no use case'))));
      await b.close();
    });

    test('sendAndWaitResult: a superseded run is canceled and its result fails',
        () async {
      final b = _W();
      final g1 = Completer<void>();
      final g2 = Completer<void>();
      final e1 = _SlowR(g1.future);
      final w1 = b.sendAndWaitResult(e1);
      final w2 = b.sendAndWaitResult(_SlowR(g2.future));
      final op = await w1;
      expect(op.isCanceled, isTrue);
      await expectLater(e1.result, throwsStateError);
      g1.complete();
      g2.complete();
      expect((await w2).value, 1);
      await b.close();
    });

    test('sendAndWaitResult: a close mid-wait fails the wait and the result',
        () async {
      final b = _W();
      final e = _SlowR(Completer<void>().future);
      final wait = expectLater(b.sendAndWaitResult(e), throwsStateError);
      final result = expectLater(e.result, throwsStateError);
      await b.close();
      await wait;
      await result;
    });
  });

  group('P5 failed initialisation holds nothing', () {
    test('a relay whose destination is unregistered: real error, no lease', () {
      BlocScope.register<_Plain>(() => _Plain());
      expect(
          () => StateRelay<_Plain, _Nav, _S>(toEvent: (_) => _Tick()),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('not registered'))));
      expect(BlocScope.diagnostics<_Plain>()!.leaseCount, 0);
    });

    test(
        'an EventSubscription on a closed source: thrown from the ctor, no '
        'lease', () async {
      final src = _Plain();
      await src.close();
      BlocScope.register<_Plain>(() => src);
      expect(
          () => _Sub(),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', contains('closed'))));
      expect(BlocScope.diagnostics<_Plain>()!.leaseCount, 0);
    });
  });

  group('P6 failures outside the use case body', () {
    test('a throwing generator is a use-case error with a span-closer',
        () async {
      final log = _Log();
      final b = _W(logger: log);
      await b.send(_NoGen());
      expect(b.errors.single, isA<StateError>());
      final err = log.typed('use_case_error').single;
      expect(err['executionId'], isNotNull);
      expect(log.typed('use_case_execution'), isEmpty,
          reason: 'no span was opened for a use case that never existed');
      await b.close();
    });

    test(
        'a sequential failure that escapes the executor is logged; the '
        'queue goes on', () async {
      final log = _Log();
      final b = _W(logger: log, rethrowErrors: true);
      await b.send(_Boom());
      final escaped = log.entries.where(
          (e) => e['message'] == 'Sequential run failed outside the executor');
      expect(escaped.single['type'], 'use_case_error');
      await b.send(_Silent()); // the queue is not wedged
      await b.close();
    });

    test('an unhandled-event fallback that throws fails the dispatch',
        () async {
      final d = EventDispatcher<EventBase>(
          onUnhandledEvent: (_) => throw StateError('fallback broke'));
      await expectLater(
          d.dispatch(_Unknown()),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', 'fallback broke')));
    });
  });

  group('P7 bindStream hardening', () {
    test('a throwing onError is the bloc\'s error; the binding is cancelled',
        () async {
      final log = _Log();
      final b = _W(logger: log);
      final c = StreamController<int>();
      final binding = b.bindStream<int>(c.stream, (_) {},
          onError: (e, st) => throw ArgumentError('handler broke'));
      c.addError(StateError('stream broke'));
      await pump();
      expect(b.errors.single, isA<ArgumentError>());
      final threw = log
          .typed('stream_binding')
          .where((e) => e['action'] == 'callback_error')
          .single;
      expect(threw['callback'], 'onError');
      expect(binding.isActive, isFalse);
      await c.close();
      await b.close();
    });

    test('a throwing onDone is the bloc\'s error', () async {
      final log = _Log();
      final b = _W(logger: log);
      final c = StreamController<int>();
      b.bindStream<int>(c.stream, (_) {},
          onDone: () => throw ArgumentError('done broke'));
      await c.close();
      await pump();
      expect(b.errors.single, isA<ArgumentError>());
      expect(
          log
              .typed('stream_binding')
              .where((e) => e['action'] == 'callback_error')
              .single['callback'],
          'onDone');
      await b.close();
    });

    test('a stream whose listen throws leaves no binding behind', () async {
      final b = _W();
      final c = StreamController<int>();
      c.stream.listen((_) {}); // single-subscription: a second listen throws
      expect(() => b.bindStream<int>(c.stream, (_) {}), throwsStateError);
      expect(b.activeBindingCount, 0);
      await c.close();
      await b.close();
    });

    test('cancel is memoized: every caller awaits the one teardown', () async {
      final b = _W();
      final teardown = Completer<void>();
      final c = StreamController<int>(onCancel: () => teardown.future);
      final binding = b.bindStream<int>(c.stream, (_) {});
      final f1 = binding.cancel();
      final f2 = binding.cancel();
      expect(identical(f1, f2), isTrue);
      teardown.complete();
      await f1;
      await b.close();
    });

    test('unbind: a cancel that fails is logged as cancel_error', () async {
      final log = _Log();
      final b = _W(logger: log);
      final c = StreamController<int>(
          onCancel: () => throw StateError('cancel broke'));
      b.bindStream<int>(c.stream, (_) {}, key: 'k');
      expect(b.unbind('k'), isTrue);
      await pump();
      final failed = log
          .typed('stream_binding')
          .where((e) => e['action'] == 'cancel_error')
          .single;
      expect(failed['key'], 'k');
      expect(failed['message'], contains('at unbind'));
      await b.close();
    });

    test('a bloc that has started closing refuses with its reason', () async {
      final log = _Log();
      final b = _W(logger: log);
      final closing = b.close();
      final c = StreamController<int>();
      final binding = b.bindStream<int>(c.stream, (_) {});
      expect(binding.isActive, isFalse);
      final refused = log
          .typed('stream_binding')
          .where((e) => e['action'] == 'refused')
          .single;
      expect(refused['reason'], 'bloc is closing');
      expect(refused['level'], Level.warning);
      await closing;
      // No listener ever attached, so close() would never complete.
      unawaited(c.close());
    });
  });

  group('P8 emitEvent after close', () {
    test('is dropped through the close fence, logged with status event',
        () async {
      final log = _Log();
      final b = _W(logger: log);
      final gate = Completer<void>();
      final run = b.send(_LateEvent(gate.future));
      await b.close();
      gate.complete();
      await run;
      expect(log.typed('emission_after_close').single['status'], 'event');
    });
  });

  group('P9 juiceTest', () {
    test('a build() that throws reports that error', () async {
      await expectLater(
          runJuiceTest<_W, _S>(build: () => throw StateError('build boom')),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', 'build boom')));
    });

    juiceTest<_W, _S>(
      'a stream-binding error counts as an error',
      build: () => _W(),
      act: (b) async {
        final c = StreamController<int>();
        b.bindStream<int>(c.stream, (_) {});
        c.addError(StateError('stream broke'));
        await pump();
        await c.close();
      },
      errors: () => [isStateError],
    );
  });

  group('P10 sendCancellable', () {
    test('on a closed bloc is refused like send, at warning', () async {
      final log = _Log();
      final b = _W(logger: log);
      await b.close();
      final e = b.sendCancellable(_Cancellable());
      expect(e.isCancelled, isFalse);
      final ignored = log
          .typed('bloc_lifecycle')
          .where((x) => x['action'] == 'event_ignored')
          .single;
      expect(ignored['level'], Level.warning);
      expect(ignored['event'], '_Cancellable');
    });
  });

  group('P11 retry under restartable', () {
    test('a run superseded before its backoff calls no onRetry', () async {
      final b = _R();
      final g1 = Completer<void>();
      final old = b.send(_Fetch(g1.future));
      b.send(_Fetch(Completer<void>().future));
      g1.complete();
      await old;
      expect(_retries, 0);
      await b.close();
    });
  });

  group('P12 one error, two lines', () {
    test('a thrown use-case error logs one span-closer and one bloc_error',
        () async {
      final log = _Log();
      final b = _W(logger: log);
      await b.send(_Boom());
      expect(log.typed('use_case_error').length, 1);
      expect(log.typed('use_case_error').single['executionId'], isNotNull);
      expect(log.typed('bloc_error').length, 1);
      await b.close();
    });
  });
}
