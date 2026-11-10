import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../support/capture_logger.dart';

/// `JuiceBloc.waitFor`: wait until a predicate holds for a bloc's state.
/// The predicate sees state only; the timeout is required; every exit
/// other than a match fails loud; a wait made inside a `restartable` run
/// ends with that run. Pinned here, every exit — and on every exit the tap
/// and the timer are gone.

class _S extends BlocState {
  const _S(this.n);
  final int n;
}

class _Set extends EventBase {
  _Set(this.n);
  final int n;
}

/// Two emissions in one tick: 99 holds for a single emission.
class _Blip extends EventBase {}

class _FailWith extends EventBase {
  _FailWith(this.n);
  final int n;
}

class _WaitWith extends EventBase {
  _WaitWith(this.n);
  final int n;
}

class _Src extends JuiceBloc<_S> {
  _Src({JuiceLogger? logger})
      : super(
          const _S(0),
          [
            () => InlineUseCaseBuilder<_Src, _S, _Set>(
                  typeOfEvent: _Set,
                  concurrency: EventConcurrency.sequential,
                  handler: (ctx, e) async => ctx.emit.update(newState: _S(e.n)),
                ),
            () => InlineUseCaseBuilder<_Src, _S, _Blip>(
                  typeOfEvent: _Blip,
                  concurrency: EventConcurrency.sequential,
                  handler: (ctx, e) async {
                    ctx.emit.update(newState: const _S(99));
                    ctx.emit.update(newState: const _S(0));
                  },
                ),
            () => InlineUseCaseBuilder<_Src, _S, _FailWith>(
                  typeOfEvent: _FailWith,
                  concurrency: EventConcurrency.sequential,
                  handler: (ctx, e) async =>
                      ctx.emit.failure(newState: _S(e.n)),
                ),
            () => InlineUseCaseBuilder<_Src, _S, _WaitWith>(
                  typeOfEvent: _WaitWith,
                  concurrency: EventConcurrency.sequential,
                  handler: (ctx, e) async =>
                      ctx.emit.waiting(newState: _S(e.n)),
                ),
          ],
          const [],
          logger ?? CaptureLogger(),
          quietErrorHandler,
        );
}

/// Parks in `src.waitFor(n == target)` and records what the wait did.
class _Await extends EventBase {
  _Await(this.target, {this.gate});
  final int target;

  /// Awaited BEFORE the wait is made, when given.
  final Future<void>? gate;
}

class _AwaitSeq extends EventBase {
  _AwaitSeq(this.target);
  final int target;
}

/// Throws a CancelledException of its own once [gate] opens.
class _ThrowCancel extends EventBase {
  _ThrowCancel(this.gate);
  final Future<void> gate;
}

class _ThrowCancelSeq extends EventBase {}

class _AwaitUC extends BlocUseCase<_Caller, _Await> {
  @override
  Future<void> execute(_Await e) async {
    if (e.gate != null) await e.gate;
    final _S s;
    try {
      s = await bloc.src.waitFor((s) {
        bloc.predicateCalls++;
        return s.n == e.target;
      }, timeout: const Duration(minutes: 1));
    } catch (error) {
      bloc.thrown.add(error);
      rethrow; // the executor must see exactly what the wait threw
    }
    emitUpdate(newState: _S(s.n));
  }
}

class _AwaitSeqUC extends BlocUseCase<_Caller, _AwaitSeq> {
  @override
  Future<void> execute(_AwaitSeq e) async {
    final s = await bloc.src
        .waitFor((s) => s.n == e.target, timeout: const Duration(minutes: 1));
    emitUpdate(newState: _S(s.n));
  }
}

class _ThrowCancelUC extends BlocUseCase<_Caller, _ThrowCancel> {
  @override
  Future<void> execute(_ThrowCancel e) async {
    await e.gate;
    throw const CancelledException('my own cancel');
  }
}

class _ThrowCancelSeqUC extends BlocUseCase<_Caller, _ThrowCancelSeq> {
  @override
  Future<void> execute(_ThrowCancelSeq e) async {
    throw const CancelledException('my own cancel');
  }
}

class _Caller extends JuiceBloc<_S> {
  _Caller(_Src src, {JuiceLogger? logger}) : this._(src, logger, <Object>[]);

  _Caller._(this.src, JuiceLogger? logger, this.handled)
      : super(
          const _S(-1),
          [
            () => UseCaseBuilder.typed(() => _AwaitUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _AwaitSeqUC(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder.typed(() => _ThrowCancelUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _ThrowCancelSeqUC(),
                concurrency: EventConcurrency.sequential),
          ],
          const [],
          logger ?? (_useGlobalLogger ? null : CaptureLogger()),
          BlocErrorHandler(
              onError: (m, {error, stackTrace}) => handled.add(error!)),
        );

  final _Src src;
  final thrown = <Object>[];

  /// Every error that reached this bloc's error handler.
  final List<Object> handled;
  int predicateCalls = 0;
}

/// Set by the one test that needs a caller on the GLOBAL logger (to test
/// the telemetry floor); every other bloc here logs into a CaptureLogger of
/// its own so the default logger prints nothing.
bool _useGlobalLogger = false;

/// A timer the tracking zone handed out; in [_live] until it fires or is
/// cancelled.
class _Tracked implements Timer {
  _Tracked(this._live);
  final Set<Timer> _live;
  late final Timer inner;

  @override
  void cancel() {
    _live.remove(this);
    inner.cancel();
  }

  @override
  bool get isActive => inner.isActive;

  @override
  int get tick => inner.tick;
}

/// Runs [body] in a zone that tracks every one-shot timer created under it
/// (a use case run inherits the zone of its `send`). Returns the timers
/// still live when [body] is done: a wait that left its timeout running
/// shows up here.
Future<Set<Timer>> liveTimersAfter(Future<void> Function() body) async {
  final live = <Timer>{};
  await runZoned(body, zoneSpecification: ZoneSpecification(
    createTimer: (self, parent, zone, duration, f) {
      final tracked = _Tracked(live);
      tracked.inner = parent.createTimer(zone, duration, () {
        live.remove(tracked);
        f();
      });
      live.add(tracked);
      return tracked;
    },
  ));
  return live;
}

void main() {
  late JuiceLogger savedLogger;
  late Level savedLevel;
  setUp(() {
    savedLogger = JuiceLoggerConfig.logger;
    savedLevel = JuiceLoggerConfig.minLevel;
    JuiceLoggerConfig.minLevel = Level.all;
    _useGlobalLogger = false;
  });
  tearDown(() {
    JuiceLoggerConfig.configureLogger(savedLogger);
    JuiceLoggerConfig.minLevel = savedLevel;
  });

  const minute = Duration(minutes: 1);

  group('waitFor — the match', () {
    test('a predicate already true returns the current state; no timer',
        () async {
      final src = _Src();
      await src.send(_Set(5));
      var calls = 0;
      final live = await liveTimersAfter(() async {
        final s = await src.waitFor((s) {
          calls++;
          return s.n == 5;
        }, timeout: minute);
        expect(s.n, 5);
      });
      expect(live, isEmpty, reason: 'no timeout was ever armed');
      await src.send(_Set(6));
      expect(calls, 1, reason: 'nothing was left tapping the bloc');
      await src.close();
    });

    test('matches on a later emission and returns THAT state', () async {
      final src = _Src();
      var calls = 0;
      late _S got;
      final live = await liveTimersAfter(() async {
        final wait = src.waitFor((s) {
          calls++;
          return s.n == 2;
        }, timeout: minute);
        await src.send(_Set(1));
        await src.send(_Set(2));
        got = await wait;
      });
      expect(got.n, 2);
      expect(live, isEmpty, reason: 'the timeout was cancelled on the match');
      final callsAtMatch = calls;
      await src.send(_Set(2));
      await src.send(_Set(3));
      expect(calls, callsAtMatch, reason: 'the tap was removed on the match');
      await src.close();
    });

    test('a state that holds for one emission is seen (synchronous tap)',
        () async {
      final src = _Src();
      final wait = src.waitFor((s) => s.n == 99, timeout: minute);
      await src.send(_Blip());
      final s = await wait;
      expect(s.n, 99, reason: 'the state the predicate held for');
      expect(src.state.n, 0, reason: 'the bloc has already moved on');
      await src.close();
    });

    test('every status kind is observed: a failure and a waiting emission',
        () async {
      final src = _Src();
      final onFailure = src.waitFor((s) => s.n == 7, timeout: minute);
      await src.send(_FailWith(7));
      expect((await onFailure).n, 7);
      final onWaiting = src.waitFor((s) => s.n == 8, timeout: minute);
      await src.send(_WaitWith(8));
      expect((await onWaiting).n, 8);
      await src.close();
    });

    test('two waits on one bloc are independent', () async {
      final src = _Src();
      final a = src.waitFor((s) => s.n == 1, timeout: minute);
      final b = src.waitFor((s) => s.n == 2, timeout: minute);
      var aDone = false, bDone = false;
      a.then((_) => aDone = true);
      b.then((_) => bDone = true);
      await src.send(_Set(1));
      await pump();
      expect([aDone, bDone], [true, false]);
      await src.send(_Set(2));
      expect((await b).n, 2);
      expect(bDone, isTrue);
      await src.close();
    });
  });

  group('waitFor — every other exit fails loud', () {
    test('timeout: a TimeoutException naming the bloc; nothing left behind',
        () async {
      final src = _Src();
      var calls = 0;
      Object? error;
      final live = await liveTimersAfter(() async {
        try {
          await src.waitFor((s) {
            calls++;
            return false;
          }, timeout: const Duration(milliseconds: 20));
        } catch (e) {
          error = e;
        }
      });
      expect(error, isA<TimeoutException>());
      final timeout = error as TimeoutException;
      expect(timeout.message, contains('_Src'));
      expect(timeout.duration, const Duration(milliseconds: 20));
      expect(live, isEmpty);
      final callsAtTimeout = calls;
      await src.send(_Set(1));
      expect(calls, callsAtTimeout, reason: 'the tap was removed');
      await src.close();
    });

    test('a closed bloc: StateError, the predicate is never asked', () async {
      final src = _Src();
      await src.close();
      var calls = 0;
      await expectLater(
          src.waitFor((s) {
            calls++;
            return true;
          }, timeout: minute),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('closed or closing'))));
      expect(calls, 0);
    });

    test('a closing bloc: StateError', () async {
      final src = _Src();
      final closing = src.close();
      await expectLater(src.waitFor((s) => true, timeout: minute),
          throwsA(isA<StateError>()));
      await closing;
    });

    test('the bloc closes while the wait is pending: StateError, no timer',
        () async {
      final src = _Src();
      Object? error;
      final live = await liveTimersAfter(() async {
        final wait = src.waitFor((s) => false, timeout: minute);
        final failed = wait.then<void>((_) {}, onError: (Object e) {
          error = e;
        });
        await src.close();
        await failed;
      });
      expect(
          error,
          isA<StateError>()
              .having((e) => e.message, 'message', contains('_Src closed')));
      expect(live, isEmpty, reason: 'the close cancelled the timeout');
    });

    test('a predicate that throws at the call fails the wait with that error',
        () async {
      final src = _Src();
      final live = await liveTimersAfter(() async {
        await expectLater(
            src.waitFor((s) => throw ArgumentError('bad predicate'),
                timeout: minute),
            throwsA(isA<ArgumentError>()));
      });
      expect(live, isEmpty);
      await src.close();
    });

    test(
        'a predicate that throws on an emission fails the wait, and the use '
        'case that emitted is untouched', () async {
      final log = CaptureLogger();
      final src = _Src(logger: log);
      var calls = 0;
      Object? error;
      final live = await liveTimersAfter(() async {
        final wait = src.waitFor((s) {
          calls++;
          if (s.n == 3) throw ArgumentError('bad predicate');
          return false;
        }, timeout: minute);
        final failed = wait.then<void>((_) {}, onError: (Object e) {
          error = e;
        });
        await src.send(_Set(3));
        await failed;
      });
      expect(error, isA<ArgumentError>());
      expect(src.state.n, 3, reason: 'the emit went through');
      expect(log.typed('use_case_error'), isEmpty,
          reason: 'the throw did not unwind into the emitting use case');
      expect(live, isEmpty);
      final callsAtThrow = calls;
      await src.send(_Set(4));
      expect(calls, callsAtThrow, reason: 'the wait is over: tap removed');
      await src.close();
    });
  });

  group('waitFor — inside a restartable run', () {
    test(
        'superseded while parked: the wait throws CancelledException at '
        'once, the span closes superseded, nothing is a failure', () async {
      final log = CaptureLogger();
      final src = _Src();
      final caller = _Caller(src, logger: log);
      late Future<void> fresh;
      final live = await liveTimersAfter(() async {
        final old = caller.send(_Await(1)); // parks: one-minute timeout
        await pump();
        fresh = caller.send(_Await(2)); // supersedes it
        await old.timeout(const Duration(seconds: 2),
            onTimeout: () => fail('the superseded run was left parked'));
        expect(caller.thrown.single, isA<CancelledException>());
        expect(log.typed('use_case_error'), isEmpty);
        expect(caller.handled, isEmpty,
            reason: 'the error handler is not called');
        final ended = log
            .typed('use_case_completed')
            .where((e) => e['event'] == '_Await')
            .toList();
        expect(ended, hasLength(1));
        expect(ended.single['superseded'], isTrue);

        // The winner's wait is its own: it is still pending, then matches.
        await src.send(_Set(2));
        await fresh;
      });
      expect(caller.state.n, 2);
      expect(caller.thrown, hasLength(1));
      expect(live, isEmpty, reason: 'both timeouts are gone');
      await caller.close();
      await src.close();
    });

    test(
        'a run already superseded when it calls waitFor: CancelledException '
        'at once, the predicate is never asked, no timer', () async {
      final log = CaptureLogger();
      final src = _Src();
      final caller = _Caller(src, logger: log);
      final gate = Completer<void>();
      final live = await liveTimersAfter(() async {
        final old = caller.send(_Await(1, gate: gate.future));
        caller.send(_ThrowCancel(Completer<void>().future)); // other type
        final winner = Completer<void>();
        caller.send(_Await(5, gate: winner.future)); // supersedes, parked
        gate.complete(); // the superseded run reaches its waitFor now
        await old;
      });
      expect(caller.thrown.single, isA<CancelledException>());
      expect(caller.predicateCalls, 0);
      expect(log.typed('use_case_error'), isEmpty);
      expect(caller.handled, isEmpty);
      expect(live, isEmpty);
      await caller.close();
      await src.close();
    });

    test(
        'a CancelledException the superseded run throws itself ends it the '
        'same way', () async {
      final log = CaptureLogger();
      final caller = _Caller(_Src(), logger: log);
      final gate = Completer<void>();
      final old = caller.send(_ThrowCancel(gate.future));
      caller.send(_ThrowCancel(Completer<void>().future)); // supersedes
      gate.complete();
      await old;
      expect(log.typed('use_case_error'), isEmpty);
      expect(caller.handled, isEmpty);
      final ended = log.typed('use_case_completed').toList();
      expect(ended.single['superseded'], isTrue);
      expect(ended.single['event'], '_ThrowCancel');
      expect(ended.single.containsKey('executionId'), isTrue);
      await caller.close();
      await caller.src.close();
    });

    test(
        'below the telemetry floor a superseded cancel records nothing and '
        'still is not an error', () async {
      final log = CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      JuiceLoggerConfig.minLevel = Level.warning;
      _useGlobalLogger = true;
      final caller = _Caller(_Src());
      final gate = Completer<void>();
      final old = caller.send(_ThrowCancel(gate.future));
      caller.send(_ThrowCancel(Completer<void>().future));
      gate.complete();
      await old;
      expect(log.typed('use_case_error'), isEmpty);
      expect(log.typed('use_case_completed'), isEmpty);
      expect(caller.handled, isEmpty);
      await caller.close();
      await caller.src.close();
    });
  });

  group('waitFor — what did not change', () {
    test(
        'a CancelledException from a run that was NOT superseded is still a '
        'failure (restartable, current run)', () async {
      final log = CaptureLogger();
      final caller = _Caller(_Src(), logger: log);
      await caller.send(_ThrowCancel(Future<void>.value()));
      final err = log.typed('use_case_error').single;
      expect(err['event'], '_ThrowCancel');
      expect(err.containsKey('superseded'), isFalse,
          reason: 'the flag is written only when true');
      expect(caller.handled.single, isA<CancelledException>());
      await caller.close();
      await caller.src.close();
    });

    test('a CancelledException from a sequential run is still a failure',
        () async {
      final log = CaptureLogger();
      final caller = _Caller(_Src(), logger: log);
      await caller.send(_ThrowCancelSeq());
      expect(log.typed('use_case_error').single['event'], '_ThrowCancelSeq');
      expect(caller.handled.single, isA<CancelledException>());
      await caller.close();
      await caller.src.close();
    });

    test('a wait made inside a sequential run matches like any other',
        () async {
      final src = _Src();
      final caller = _Caller(src);
      final run = caller.send(_AwaitSeq(4));
      await pump();
      await src.send(_Set(4));
      await run;
      expect(caller.state.n, 4);
      expect(caller.handled, isEmpty);
      await caller.close();
      await src.close();
    });
  });
}
