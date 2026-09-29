import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// `JuiceLoggerConfig.minLevel` (1.10.0): below it, the framework's per-event
/// chatter — the span pair and the emission entry — is not BUILT, so the
/// logger is never called for it. Errors, `emission_after_close`, ignored
/// events and failure emissions stay loud whatever the level.

class _S extends BlocState {
  final int v;
  const _S(this.v);
}

class _Set extends EventBase {
  final int v;
  _Set(this.v);
}

class _Fail extends EventBase {}

class _SetUC extends BlocUseCase<_B, _Set> {
  @override
  Future<void> execute(_Set e) async =>
      emitUpdate(newState: _S(e.v), groupsToRebuild: {'g'});
}

class _FailUC extends BlocUseCase<_B, _Fail> {
  @override
  Future<void> execute(_Fail e) async =>
      emitFailure(error: StateError('nope'), groupsToRebuild: {'g'});
}

class _B extends JuiceBloc<_S> {
  _B()
      : super(const _S(0), [
          () => UseCaseBuilder(
              typeOfEvent: _Set,
              useCaseGenerator: () => _SetUC(),
              concurrency: EventConcurrency.sequential),
          () => UseCaseBuilder(
              typeOfEvent: _Fail,
              useCaseGenerator: () => _FailUC(),
              concurrency: EventConcurrency.sequential),
        ]);
}

class _Counting implements JuiceLogger {
  final types = <String>[];
  int errors = 0;
  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    types.add(context?['type'] as String? ?? '(untyped)');
  }

  @override
  void logError(String m, Object e, StackTrace s,
      {Map<String, dynamic>? context}) {
    errors++;
    types.add('ERR:${context?['type']}');
  }
}

void main() {
  late Level saved;
  setUp(() {
    saved = JuiceLoggerConfig.minLevel;
    JuiceLoggerConfig.minLevel = Level.all;
  });
  tearDown(() => JuiceLoggerConfig.minLevel = saved);

  test('default (Level.all): the span pair and the emission are logged',
      () async {
    final log = _Counting();
    JuiceLoggerConfig.configureLogger(log);
    final b = _B();
    await b.send(_Set(1));
    expect(
        log.types,
        containsAll(
            ['use_case_execution', 'state_emission', 'use_case_completed']));
    await b.close();
  });

  test(
      'minLevel = warning: NO chatter is built for a plain emission — the '
      'logger is not called', () async {
    JuiceLoggerConfig.minLevel = Level.warning;
    final log = _Counting();
    JuiceLoggerConfig.configureLogger(log);
    final b = _B();
    await b.send(_Set(1));
    await b.send(_Set(2));
    final chatter = log.types.where((t) =>
        t == 'use_case_execution' ||
        t == 'use_case_completed' ||
        t == 'state_emission');
    expect(chatter, isEmpty, reason: 'built nothing: ${log.types}');
    expect(b.state.v, 2, reason: 'behavior unchanged');
    await b.close();
  });

  test(
      'minLevel = warning: a failure emission is still logged, and errors '
      'still reach logError', () async {
    JuiceLoggerConfig.minLevel = Level.warning;
    final log = _Counting();
    JuiceLoggerConfig.configureLogger(log);
    final b = _B();
    await b.send(_Fail());
    expect(log.types, contains('state_emission'),
        reason: 'the failure entry is not chatter');
    await b.close();
  });

  test('minLevel = warning: an event sent after close is still reported',
      () async {
    JuiceLoggerConfig.minLevel = Level.warning;
    final log = _Counting();
    JuiceLoggerConfig.configureLogger(log);
    final b = _B();
    await b.close();
    await b.send(_Set(9));
    expect(log.types, contains('bloc_lifecycle'));
  });
}
