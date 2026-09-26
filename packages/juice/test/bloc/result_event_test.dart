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
