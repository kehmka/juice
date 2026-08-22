import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

import '../test_helpers.dart';

/// The use-case telemetry pair (2026-08-21, BlocSignal tee-up item 1):
/// every execution logs a `use_case_execution` start and — sharing its
/// `executionId` — exactly one end entry: `use_case_completed` with
/// `elapsedMicros`, or `use_case_error` carrying the same fields. This is
/// what lets a DevTools consumer draw honest duration spans, including when
/// two events of the same type overlap under `concurrent`.
class _RecordingLogger implements JuiceLogger {
  final entries = <Map<String, dynamic>>[];

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    if (context != null) entries.add(Map.of(context));
  }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {
    if (context != null) entries.add(Map.of(context));
  }

  List<Map<String, dynamic>> ofType(String type) =>
      entries.where((e) => e['type'] == type).toList();
}

/// A use case is typed to its HOSTING bloc (setBloc casts) — the throwing
/// case needs its own bloc rather than borrowing the helpers'.
class _ThrowingBloc extends JuiceBloc<TestState> {
  _ThrowingBloc()
      : super(TestState(value: 0), [
          () => UseCaseBuilder(
              typeOfEvent: DecrementEvent,
              useCaseGenerator: () => _ThrowingUseCase()),
        ], []);
}

class _ThrowingUseCase extends BlocUseCase<_ThrowingBloc, DecrementEvent> {
  @override
  Future<void> execute(DecrementEvent event) async {
    throw StateError('deliberate');
  }
}

void main() {
  late _RecordingLogger logger;

  setUp(() {
    logger = _RecordingLogger();
    JuiceLoggerConfig.configureLogger(logger);
  });

  tearDown(() {
    // The logger config is process-global — never leak the recorder.
    JuiceLoggerConfig.configureLogger(DefaultJuiceLogger());
  });

  test('success logs a completed entry paired by executionId', () async {
    final bloc = TestBloc(initialState: TestState(value: 0));
    bloc.send(IncrementEvent());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final starts = logger.ofType('use_case_execution');
    final ends = logger.ofType('use_case_completed');
    expect(starts, hasLength(1));
    expect(ends, hasLength(1));
    expect(ends.single['executionId'], starts.single['executionId'],
        reason: 'the pair is a span');
    expect(ends.single['elapsedMicros'], isA<int>());
    expect(ends.single['useCase'], 'IncrementUseCase');
    expect(logger.ofType('use_case_error'), isEmpty);
    await bloc.close();
  });

  test(
      'failure logs use_case_error with the same span fields — and no '
      'completed entry', () async {
    final bloc = _ThrowingBloc();
    bloc.send(DecrementEvent());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final starts = logger.ofType('use_case_execution');
    // TWO sources share the use_case_error type: the executor's span-closing
    // entry (has executionId/elapsedMicros) and BlocErrorHandler's summary
    // (bloc/state, no span fields). A span consumer keys on executionId.
    final errors = logger
        .ofType('use_case_error')
        .where((e) => e.containsKey('executionId'))
        .toList();
    expect(starts, hasLength(1));
    expect(errors, hasLength(1));
    expect(errors.single['executionId'], starts.single['executionId']);
    expect(errors.single['elapsedMicros'], isA<int>());
    expect(logger.ofType('use_case_completed'), isEmpty,
        reason: 'exactly one end entry per execution');
    await bloc.close();
  });

  test('overlapping same-type executions keep distinct executionIds',
      () async {
    final bloc = TestBloc(initialState: TestState(value: 0));
    bloc.send(IncrementEvent());
    bloc.send(IncrementEvent());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final ids = logger
        .ofType('use_case_execution')
        .map((e) => e['executionId'])
        .toSet();
    expect(ids, hasLength(2), reason: 'ids are unique across overlap');
    final endIds = logger
        .ofType('use_case_completed')
        .map((e) => e['executionId'])
        .toSet();
    expect(endIds, ids, reason: 'every start closes');
    await bloc.close();
  });
}
