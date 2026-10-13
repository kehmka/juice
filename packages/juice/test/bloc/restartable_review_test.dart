import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import '../support/capture_logger.dart';

/// Pins for the independent review of `restartable` (2026-10-13). Each test
/// is one finding; the number is the finding's.
///
/// R1 a re-sent CancellableEvent instance is not pre-cancelled for its new run
/// R2 sendAndWait twice with the same instance resolves both, no timeout
/// R3 sendAndWait holds NO stream listener (tap-based) and times out cleanly
/// R5 a retried restartable run stops retrying once superseded
/// R6 a run that RETURNED is not superseded by a same-type send in the next
///    microtasks — its binding survives either way
/// R7 a throwing cancel() cannot stop the new run; the error is logged
/// R8 an emission that landed before the supersede wins over Canceling
/// R9 a nested restartable of another type keeps its own run
/// R10 close() while sendAndWait is pending fails it loudly
/// R11 a binding whose cancel throws is logged at supersede and at close

class _S extends BlocState {
  const _S(this.log);
  final List<String> log;
}

class _Scrub extends CancellableEvent {
  _Scrub(this.gate);
  final Future<void> gate;
  int ran = 0;
}

class _ScrubUC extends BlocUseCase<_B, _Scrub> {
  @override
  Future<void> execute(_Scrub e) async {
    e.ran++;
    if (e.isCancelled) {
      bloc.preCancelled.add(true);
      return;
    }
    bloc.preCancelled.add(false);
    await e.gate;
    if (isSuperseded) return;
    emitUpdate(
        newState: _S([...bloc.state.log, 'scrub']), groupsToRebuild: {'g'});
  }
}

class _Search extends EventBase {
  _Search(this.gate, {this.emitFirst = false});
  final Future<void> gate;
  final bool emitFirst;
}

class _SearchUC extends BlocUseCase<_B, _Search> {
  @override
  Future<void> execute(_Search e) async {
    if (e.emitFirst) {
      emitUpdate(
          newState: _S([...bloc.state.log, 'early']), groupsToRebuild: {'g'});
    }
    await e.gate;
    if (isSuperseded) return;
    emitUpdate(
        newState: _S([...bloc.state.log, 'search']), groupsToRebuild: {'g'});
  }
}

class _Quick extends EventBase {}

/// Binds and RETURNS at once; its binding then belongs to the bloc.
class _QuickUC extends BlocUseCase<_B, _Quick> {
  @override
  Future<void> execute(_Quick e) async {
    bloc.bindStream<int>(bloc.src.stream, (_) {});
  }
}

class _Inner extends EventBase {
  _Inner(this.gate);
  final Future<void> gate;
}

class _InnerUC extends BlocUseCase<_B, _Inner> {
  @override
  Future<void> execute(_Inner e) async {
    await e.gate;
    bloc.innerSaw.add(isSuperseded);
  }
}

class _Outer extends EventBase {
  _Outer(this.gate, [this.inner]);
  final Future<void> gate;
  final _Inner? inner;
}

class _OuterUC extends BlocUseCase<_B, _Outer> {
  @override
  Future<void> execute(_Outer e) async {
    if (e.inner != null) bloc.send(e.inner!); // nested restartable, other type
    await e.gate;
  }
}

class _BadCancel extends CancellableEvent {
  _BadCancel(this.gate);
  final Future<void> gate;
  @override
  void cancel() => throw StateError('cancel exploded');
}

class _BadCancelUC extends BlocUseCase<_B, _BadCancel> {
  @override
  Future<void> execute(_BadCancel e) async {
    await e.gate;
    if (isSuperseded) return;
    emitUpdate(
        newState: _S([...bloc.state.log, 'bad']), groupsToRebuild: {'g'});
  }
}

class _BadBind extends EventBase {
  _BadBind(this.gate);
  final Future<void> gate;
}

/// Binds a stream whose cancel THROWS, then waits.
class _BadBindUC extends BlocUseCase<_B, _BadBind> {
  @override
  Future<void> execute(_BadBind e) async {
    bloc.bindStream<int>(bloc.badSrc, (_) {});
    await e.gate;
  }
}

class _Flaky extends EventBase {}

class _FlakyUC extends BlocUseCase<_B, _Flaky> {
  @override
  Future<void> execute(_Flaky e) async {
    bloc.attempts++;
    await bloc.flakyGate.future;
    throw StateError('flaky');
  }
}

class _B extends JuiceBloc<_S> {
  _B(JuiceLogger log)
      : super(
          const _S([]),
          [
            () => UseCaseBuilder.typed(() => _ScrubUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _SearchUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _QuickUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _OuterUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _InnerUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _BadCancelUC(),
                concurrency: EventConcurrency.restartable),
            () => UseCaseBuilder.typed(() => _BadBindUC(),
                concurrency: EventConcurrency.restartable),
            () => RetryableUseCaseBuilder<_B, _S, _Flaky>(
                  typeOfEvent: _Flaky,
                  useCaseGenerator: () => _FlakyUC(),
                  maxRetries: 5,
                  backoff: FixedBackoff(const Duration(milliseconds: 1)),
                  concurrency: EventConcurrency.restartable,
                ),
          ],
          const [],
          log,
        );
  final src = StreamController<int>.broadcast();
  final _badCtl = StreamController<int>.broadcast();

  /// A stream whose subscriptions FAIL to cancel (the cancel future errors).
  late final Stream<int> badSrc = _FailingCancelStream(_badCtl.stream);
  final preCancelled = <bool>[];
  final innerSaw = <bool>[];
  int attempts = 0;
  Completer<void> flakyGate = Completer<void>();
  int listens = 0;
  @override
  Stream<StreamStatus<_S>> get stream {
    listens++;
    return super.stream;
  }

  @override
  Future<void> close() async {
    await src.close();
    await super.close();
  }
}

/// Wraps a stream so every subscription's cancel() completes with an error.
class _FailingCancelStream extends StreamView<int> {
  _FailingCancelStream(super.inner);
  @override
  StreamSubscription<int> listen(void Function(int)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _FailingSub(super.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError));
}

class _FailingSub implements StreamSubscription<int> {
  _FailingSub(this._inner);
  final StreamSubscription<int> _inner;
  @override
  Future<void> cancel() {
    _inner.cancel();
    return Future<void>.error(StateError('cancel failed'));
  }

  @override
  void onData(void Function(int data)? handleData) => _inner.onData(handleData);
  @override
  void onError(Function? handleError) => _inner.onError(handleError);
  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);
  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);
  @override
  void resume() => _inner.resume();
  @override
  bool get isPaused => _inner.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}

void main() {
  late JuiceLogger saved;
  setUp(() => saved = JuiceLoggerConfig.logger);
  tearDown(() => JuiceLoggerConfig.configureLogger(saved));

  test(
      'R1 the same CancellableEvent instance re-sent: the NEW run is not '
      'pre-cancelled; only the old run is fenced', () async {
    final b = _B(CaptureLogger());
    final gate = Completer<void>();
    final e = _Scrub(gate.future);
    final first = b.send(e);
    final second = b.send(e);
    gate.complete();
    await Future.wait([first, second]);
    expect(b.preCancelled, [false, false], reason: 'neither run saw cancel');
    expect(e.isCancelled, isFalse);
    expect(b.state.log, ['scrub']);
    await b.close();
  });

  test('R2 sendAndWait twice with the same instance resolves both', () async {
    final b = _B(CaptureLogger());
    final gate = Completer<void>();
    final e = _Search(gate.future);
    final w1 = b.sendAndWait(e, timeout: const Duration(seconds: 2));
    final w2 = b.sendAndWait(e, timeout: const Duration(seconds: 2));
    gate.complete();
    final r = await Future.wait([w1, w2]);
    expect(r.every((s) => s is! WaitingStatus), isTrue);
    await b.close();
  });

  test('R3 sendAndWait holds no stream listener; a timeout is clean', () async {
    final b = _B(CaptureLogger());
    final before = b.listens;
    final pending = b.sendAndWait(_Search(Completer<void>().future));
    b.send(_Search(Completer<void>().future)); // supersedes the first
    expect(await pending, isA<CancelingStatus<_S>>());
    expect(b.listens, before, reason: 'tap-based: no stream subscription');
    await expectLater(
        b.sendAndWait(_Search(Completer<void>().future),
            timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()));
    expect(b.listens, before);
    await b.close();
  });

  test('R5 a retried restartable run stops retrying once superseded', () async {
    final b = _B(CaptureLogger());
    final first = b.send(_Flaky());
    await pump();
    expect(b.attempts, 1);
    b.flakyGate.complete(); // attempt 1 fails → backoff 1 ms
    b.flakyGate = Completer<void>();
    final second = b.send(_Flaky()); // supersedes during the backoff
    await pump();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(b.attempts, 2,
        reason: 'the superseded run did not retry; the new run ran once');
    b.flakyGate.complete();
    await Future.wait([first, second]); // the new run retries to exhaustion
    await b.close();
  });

  test(
      'R6 a run that RETURNED is not superseded by a send in the next '
      'microtask: its binding survives, same as with a pump between', () async {
    for (final withPump in [false, true]) {
      final b = _B(CaptureLogger());
      final first = b.send(_Quick());
      await first; // returned; _current is cleared a few microtasks later
      if (withPump) await pump();
      final second = b.send(_Quick());
      await second;
      expect(b.activeBindingCount, 2,
          reason: 'withPump=$withPump: neither binding was cancelled');
      await b.close();
    }
  });

  test('R7 a throwing cancel() cannot stop the new run; the error is logged',
      () async {
    final log = CaptureLogger();
    final b = _B(log);
    final g1 = Completer<void>();
    final g2 = Completer<void>();
    final first = b.send(_BadCancel(g1.future));
    late Future<void> second;
    expect(() => second = b.send(_BadCancel(g2.future)), returnsNormally);
    g1.complete();
    g2.complete();
    await Future.wait([first, second]);
    expect(b.state.log, ['bad'], reason: 'the new run ran and emitted');
    expect(log.where('use_case_superseded', 'error'), hasLength(1));
    await b.close();
  });

  test(
      'R8 an emission that landed before the supersede wins over Canceling, '
      'even in the same synchronous block', () async {
    final b = _B(CaptureLogger());
    final w = b.sendAndWait(_Search(Completer<void>().future, emitFirst: true));
    b.send(_Search(Completer<void>().future)); // same tick: supersedes
    final status = await w;
    expect(status, isA<UpdatingStatus<_S>>());
    expect(status.state.log, ['early']);
    await b.close();
  });

  test('R9 a nested restartable of another type keeps its own run', () async {
    final b = _B(CaptureLogger());
    final innerGate = Completer<void>();
    final outerGate = Completer<void>();
    final outer1 = b.send(_Outer(outerGate.future, _Inner(innerGate.future)));
    await pump();
    final outer2Gate = Completer<void>();
    final outer2 = b.send(_Outer(outer2Gate.future)); // supersedes outer1
    await pump();
    innerGate.complete();
    await pump();
    expect(b.innerSaw, [false], reason: 'the inner run was never superseded');
    outerGate.complete();
    await outer1;
    await b.close();
    outer2Gate.complete();
    await outer2;
  });

  test('R10 close() while sendAndWait is pending fails it loudly', () async {
    final b = _B(CaptureLogger());
    final w = b.sendAndWait(_Search(Completer<void>().future));
    final failsLoudly = expectLater(w, throwsA(isA<StateError>()));
    await b.close();
    await failsLoudly;
  });

  test(
      'R11 a binding whose cancel throws is logged at supersede and at '
      'close; neither path breaks', () async {
    final log = CaptureLogger();
    final b = _B(log);
    final g1 = Completer<void>();
    final first = b.send(_BadBind(g1.future));
    await pump();
    final g2 = Completer<void>();
    final second = b.send(_BadBind(g2.future)); // cancels the bad binding
    await pump();
    expect(log.where('stream_binding', 'cancel_error'), hasLength(1));
    g1.complete();
    await first;
    await b.close(); // the second run's bad binding cancels at close
    expect(log.where('stream_binding', 'cancel_error'), hasLength(2));
    g2.complete();
    await second;
  });
}
