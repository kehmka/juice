import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// ResultEvent + sendAndWaitResult / sendForResult / OperationResult in core
/// (1.9.0, promoted from juice_storage).

class _S extends BlocState {
  const _S([this.n = 0]);
  final int n;
}

class _Double extends ResultEvent<int> {
  _Double(this.x, {this.delay = Duration.zero});
  final int x;
  final Duration delay;
}

class _Fail extends ResultEvent<int> {}

class _Cancel extends ResultEvent<int> {}

class _Silent extends ResultEvent<int> {}

/// Refused by its use case: failed, with nothing emitted for it.
class _Refused extends ResultEvent<int> {}

/// Emits progress at once, and its value only when [gate] opens.
class _Progress extends ResultEvent<int> {
  _Progress(this.gate);
  final Future<void> gate;
}

/// Succeeded by its use case, with nothing emitted for it.
class _SilentSuccess extends ResultEvent<int> {}

class _Slow extends ResultEvent<int> {
  _Slow(this.gate);
  final Future<void> gate;
}

class _DoubleUC extends BlocUseCase<_B, _Double> {
  @override
  Future<void> execute(_Double e) async {
    emitWaiting();
    await Future<void>.delayed(e.delay);
    emitUpdate(newState: _S(e.x * 2));
    e.succeed(e.x * 2);
  }
}

class _FailUC extends BlocUseCase<_B, _Fail> {
  @override
  Future<void> execute(_Fail e) async =>
      emitFailure(error: ArgumentError('nope'));
}

class _CancelUC extends BlocUseCase<_B, _Cancel> {
  @override
  Future<void> execute(_Cancel e) async => emitCancel();
}

class _SilentUC extends BlocUseCase<_B, _Silent> {
  @override
  Future<void> execute(_Silent e) async {}
}

class _RefusedUC extends BlocUseCase<_B, _Refused> {
  @override
  Future<void> execute(_Refused e) async =>
      e.fail(ArgumentError('not now'), StackTrace.current);
}

class _SilentSuccessUC extends BlocUseCase<_B, _SilentSuccess> {
  @override
  Future<void> execute(_SilentSuccess e) async => e.succeed(5);
}

class _ProgressUC extends BlocUseCase<_B, _Progress> {
  @override
  Future<void> execute(_Progress e) async {
    emitUpdate(newState: const _S(1));
    await e.gate;
    emitUpdate(newState: const _S(2));
    e.succeed(2);
  }
}

class _SlowUC extends BlocUseCase<_B, _Slow> {
  @override
  Future<void> execute(_Slow e) async {
    await e.gate;
    emitUpdate();
    e.succeed(1);
  }
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(), [
          () => UseCaseBuilder.typed(() => _DoubleUC(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder.typed(() => _FailUC(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder.typed(() => _CancelUC(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder.typed(() => _SilentUC(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder.typed(() => _ProgressUC(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder.typed(() => _RefusedUC(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder.typed(() => _SilentSuccessUC(),
              concurrency: EventConcurrency.concurrent),
          () => UseCaseBuilder.typed(() => _SlowUC(),
              concurrency: EventConcurrency.droppable),
        ]);
}

void main() {
  late _B b;
  setUp(() => b = _B());
  tearDown(() => b.close());

  const fast = Duration(seconds: 2);

  test('success: the terminal status and the typed value', () async {
    final op = await b.sendAndWaitResult(_Double(21), timeout: fast);
    expect(op.isSuccess, isTrue);
    expect(op.value, 42);
    expect(op.status, isA<UpdatingStatus<_S>>());
    expect(await b.sendForResult(_Double(5), timeout: fast), 10);
  });

  test('failure: OperationResult carries the error; sendForResult throws it',
      () async {
    final e = _Fail();
    final op = await b.sendAndWaitResult(e, timeout: fast);
    expect(op.isFailure, isTrue);
    expect(op.error, isA<ArgumentError>());
    await expectLater(e.result, throwsArgumentError,
        reason: 'the event is failed for any other awaiter');
    await expectLater(
        b.sendForResult(_Fail(), timeout: fast), throwsArgumentError);
  });

  test('cancel: isCanceled; sendForResult throws StateError', () async {
    final op = await b.sendAndWaitResult(_Cancel(), timeout: fast);
    expect(op.isCanceled, isTrue);
    expect(op.value, isNull);
    await expectLater(
        b.sendForResult(_Cancel(), timeout: fast), throwsStateError);
  });

  test('concurrent events each get their own value', () async {
    final results = await Future.wait([
      b.sendForResult(_Double(1, delay: const Duration(milliseconds: 20))),
      b.sendForResult(_Double(2)),
      b.sendForResult(_Double(3, delay: const Duration(milliseconds: 5))),
    ]);
    expect(results, [2, 4, 6]);
  });

  test('a use case that emits nothing fails loud, not after the timeout',
      () async {
    final sw = Stopwatch()..start();
    await expectLater(
        b.sendAndWaitResult(_Silent(), timeout: const Duration(seconds: 30)),
        throwsStateError);
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test(
      'a use case that REFUSES the event — fails it and emits nothing — has '
      'said why: its error is the one thrown', () async {
    final notNow = throwsA(
        isA<ArgumentError>().having((e) => e.message, 'message', 'not now'));
    await expectLater(b.sendForResult(_Refused(), timeout: fast), notNow);
    await expectLater(b.sendAndWaitResult(_Refused(), timeout: fast), notNow);
    expect(b.state.n, 0, reason: 'nothing was emitted');
  });

  test(
      'a use case that succeeds the event but emits nothing still fails '
      'loud: a value is not a terminal status', () async {
    final event = _SilentSuccess();
    await expectLater(
        b.sendForResult(event, timeout: fast),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('finished without a terminal status'))));
    expect(await event.result, 5);
  });

  test(
      'a bloc that closes AFTER the first status and before the value '
      'fails the wait at the close, not after the timeout', () async {
    final gate = Completer<void>();
    final event = _Progress(gate.future);
    final sw = Stopwatch()..start();
    final waiting =
        b.sendForResult(event, timeout: const Duration(seconds: 30));
    final outcome = expectLater(
        waiting,
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            '_B closed while _Progress was waiting for its result')));
    await Future<void>.delayed(Duration.zero);
    expect(b.state.n, 1, reason: 'the first status is out');

    await b.close();
    await outcome;
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));

    // The run comes back to a closed bloc: nothing more happens.
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    await expectLater(event.result, throwsStateError);
  });

  test(
      'a close that begins in the same breath as the first status fails '
      'the wait too', () async {
    final gate = Completer<void>();
    // The use case runs to its first emit inside this call…
    final waiting = b.sendForResult(_Progress(gate.future),
        timeout: const Duration(seconds: 30));
    final outcome = expectLater(
        waiting,
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            '_B closed while _Progress was waiting for its result')));
    // …and the bloc starts closing before the waiter has resumed.
    final closing = b.close();
    await outcome;
    await closing;
    gate.complete();
  });

  test('a result that arrives in time is unaffected by a later close',
      () async {
    final gate = Completer<void>();
    final waiting = b.sendForResult(_Progress(gate.future), timeout: fast);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    expect(await waiting, 2);
    await b.close();
  });

  test('an event dropped by a droppable builder fails loud', () async {
    final gate = Completer<void>();
    final first = b.sendForResult(_Slow(gate.future), timeout: fast);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
        b.sendForResult(_Slow(gate.future), timeout: fast), throwsStateError);
    gate.complete();
    expect(await first, 1);
  });

  test('a closed bloc refuses at once', () async {
    await b.close();
    await expectLater(
        b.sendAndWaitResult(_Double(1), timeout: fast), throwsStateError);
  });
}
