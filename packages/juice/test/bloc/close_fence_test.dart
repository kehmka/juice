import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// THE CLOSE FENCE (1.9.0): a use case still running when its bloc closes —
/// the user left mid-fetch — must not crash on its next emit, and nothing
/// new may be dispatched into a bloc that is tearing down. Before 1.9.0 the
/// late emit threw `StateError`, surfaced as a bloc error, and under
/// `RetryableUseCaseBuilder` was retried against the closed bloc.

class _RecordingLogger implements JuiceLogger {
  final types = <String>[];
  final errors = <Object>[];
  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    final t = context?['type'];
    if (t is String) types.add(t);
  }

  @override
  void logError(String m, Object e, StackTrace s,
      {Map<String, dynamic>? context}) {
    errors.add(e);
    final t = context?['type'];
    if (t is String) types.add(t);
  }
}

class _S extends BlocState {
  const _S(this.v);
  final int v;
}

class _Slow extends EventBase {
  _Slow(this.gate);
  final Future<void> gate;
}

class _Quick extends EventBase {}

class _Flaky extends EventBase {}

class _SlowUC extends BlocUseCase<_B, _Slow> {
  @override
  Future<void> execute(_Slow e) async {
    emitWaiting(groupsToRebuild: {'g'});
    await e.gate;
    emitUpdate(newState: const _S(99), groupsToRebuild: {'g'});
    emitFailure(error: StateError('late'), groupsToRebuild: {'g'});
    emitCancel(groupsToRebuild: {'g'});
  }
}

class _QuickUC extends BlocUseCase<_B, _Quick> {
  static int runs = 0;
  @override
  Future<void> execute(_Quick e) async {
    runs++;
    emitUpdate(newState: _S(bloc.state.v + 1), groupsToRebuild: {'g'});
  }
}

class _AlwaysFails extends BlocUseCase<_B, _Flaky> {
  static int attempts = 0;
  @override
  Future<void> execute(_Flaky e) async {
    attempts++;
    emitFailure(error: Exception('network'), groupsToRebuild: {'g'});
  }
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(0), [
          () => UseCaseBuilder(
              typeOfEvent: _Slow, useCaseGenerator: () => _SlowUC()),
          () => UseCaseBuilder(
              typeOfEvent: _Quick, useCaseGenerator: () => _QuickUC()),
          () => RetryableUseCaseBuilder<_B, _S, _Flaky>(
                typeOfEvent: _Flaky,
                useCaseGenerator: () => _AlwaysFails(),
                maxRetries: 5,
                backoff: const FixedBackoff(Duration(milliseconds: 40)),
              ),
        ]);
}

void main() {
  late _RecordingLogger logger;

  setUp(() {
    logger = _RecordingLogger();
    JuiceLoggerConfig.configureLogger(logger);
    _QuickUC.runs = 0;
    _AlwaysFails.attempts = 0;
  });
  tearDown(() => JuiceLoggerConfig.configureLogger(DefaultJuiceLogger()));

  test(
      'a use case emitting after close is dropped and logged — not a '
      'StateError, not a bloc error', () async {
    final b = _B();
    final gate = Completer<void>();
    final run = b.send(_Slow(gate.future));
    await Future<void>.delayed(Duration.zero);
    await b.close();

    gate.complete();
    await run; // would have thrown / routed StateError to onError

    expect(b.state.v, 0, reason: 'the late update never landed');
    expect(logger.types.where((t) => t == 'emission_after_close'), hasLength(3),
        reason: 'update, failure and cancel each dropped and logged');
    expect(logger.types, isNot(contains('bloc_error')));
    expect(logger.errors.whereType<StateError>(), isEmpty);
  });

  test('events sent while close() is in progress are refused', () async {
    final b = _B();
    final closing = b.close();
    expect(b.isClosing, isTrue);
    await b.send(_Quick());
    await closing;
    expect(_QuickUC.runs, 0);
    expect(b.isClosing, isFalse);
    expect(b.isClosed, isTrue);
  });

  test('a second close() awaits the same teardown', () async {
    final b = _B();
    final first = b.close();
    final second = b.close();
    await second;
    expect(b.isClosed, isTrue,
        reason: 'the second caller returned before the bloc was closed');
    await first;
  });

  test('sendAndWait on a closed bloc fails loud instead of timing out',
      () async {
    final b = _B();
    await b.close();
    await expectLater(
        b.sendAndWait(_Quick(), timeout: const Duration(seconds: 5)),
        throwsStateError);
  });

  test('a retry loop stops when the bloc closes during backoff', () async {
    final b = _B();
    final run = b.send(_Flaky());
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final before = _AlwaysFails.attempts;
    expect(before, inInclusiveRange(1, 2));
    await b.close();
    await run;
    expect(_AlwaysFails.attempts, before,
        reason: 'no attempt runs against the closed bloc');
    expect(logger.types, contains('retry_abandoned'));
    expect(logger.types, isNot(contains('bloc_error')));
  });
}
