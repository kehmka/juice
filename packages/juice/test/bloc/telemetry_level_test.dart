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

/// A logger that DECLARES what it keeps ([LevelAwareJuiceLogger]).
class _Declaring extends _Counting implements LevelAwareJuiceLogger {
  _Declaring(this.minLevel);
  @override
  Level minLevel;
}

/// A wrapper that does NOT declare: only `implements JuiceLogger`.
class _Wrapper implements JuiceLogger {
  _Wrapper(this.inner);
  final JuiceLogger inner;
  final types = <String>[];
  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {
    types.add(context?['type'] as String? ?? '(untyped)');
    inner.log(m, level: level, context: context);
  }

  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      inner.logError(m, e, s, context: context);
}

const _chatter = {
  'use_case_execution',
  'use_case_completed',
  'state_emission',
};

void main() {
  late Level saved;
  late JuiceLogger savedLogger;
  late Level savedPackageLevel;
  setUp(() {
    saved = JuiceLoggerConfig.minLevel;
    savedLogger = JuiceLoggerConfig.logger;
    savedPackageLevel = Logger.level;
    JuiceLoggerConfig.minLevel = Level.all;
  });
  tearDown(() {
    JuiceLoggerConfig.minLevel = saved;
    JuiceLoggerConfig.configureLogger(savedLogger);
    Logger.level = savedPackageLevel;
  });

  group('the logger declares what it keeps (LevelAwareJuiceLogger)', () {
    test('declares warning: NO chatter is built, global floor untouched',
        () async {
      final log = _Declaring(Level.warning);
      JuiceLoggerConfig.configureLogger(log);
      expect(JuiceLoggerConfig.minLevel, Level.all);
      expect(JuiceLoggerConfig.logs(Level.info), isFalse);
      final b = _B();
      await b.send(_Set(1));
      expect(log.types.where(_chatter.contains), isEmpty,
          reason: 'built nothing: ${log.types}');
      expect(b.state.v, 1, reason: 'behavior unchanged');
      await b.close();
    });

    test('declares off: a failure emission and an ignored event are STILL '
        'delivered — never gated', () async {
      final log = _Declaring(Level.off);
      JuiceLoggerConfig.configureLogger(log);
      final b = _B();
      await b.send(_Fail());
      expect(log.types, contains('state_emission'),
          reason: 'the failure entry is not chatter');
      await b.close();
      await b.send(_Set(9));
      expect(log.types, contains('bloc_lifecycle'));
    });

    test('declares all: everything is built', () async {
      final log = _Declaring(Level.all);
      JuiceLoggerConfig.configureLogger(log);
      final b = _B();
      await b.send(_Set(1));
      expect(log.types, containsAll(_chatter));
      await b.close();
    });

    test('the global floor is the HIGHER of the two: it silences a logger '
        'that declares all, and cannot lower one that declares warning',
        () async {
      final all = _Declaring(Level.all);
      JuiceLoggerConfig.configureLogger(all);
      JuiceLoggerConfig.minLevel = Level.warning;
      expect(JuiceLoggerConfig.logs(Level.info), isFalse);
      expect(JuiceLoggerConfig.logs(Level.warning), isTrue);

      final warning = _Declaring(Level.warning);
      JuiceLoggerConfig.configureLogger(warning);
      JuiceLoggerConfig.minLevel = Level.all;
      expect(JuiceLoggerConfig.logs(Level.info), isFalse,
          reason: 'the floor cannot force entries into the logger');
    });

    test('the declaration is read live: raising and lowering it at run time '
        'turns the chatter off and on', () async {
      final log = _Declaring(Level.warning);
      JuiceLoggerConfig.configureLogger(log);
      final b = _B();
      await b.send(_Set(1));
      expect(log.types.where(_chatter.contains), isEmpty);
      log.minLevel = Level.all; // e.g. a DevTools panel attached
      await b.send(_Set(2));
      expect(log.types, containsAll(_chatter));
      await b.close();
    });

    test('a logger that does not declare keeps everything, as before',
        () async {
      final log = _Counting();
      JuiceLoggerConfig.configureLogger(log);
      expect(JuiceLoggerConfig.logs(Level.trace), isTrue);
    });
  });

  group('DefaultJuiceLogger declares what its filter keeps', () {
    test('asserts enabled (tests, debug): Logger.level — everything by '
        'default, and it follows the package level', () {
      final logger = DefaultJuiceLogger();
      expect(logger.minLevel, Logger.level);
      JuiceLoggerConfig.configureLogger(logger);
      expect(JuiceLoggerConfig.logs(Level.info), isTrue);
      Logger.level = Level.warning;
      expect(logger.minLevel, Level.warning);
      expect(JuiceLoggerConfig.logs(Level.info), isFalse);
    });

    test('a caller-supplied Logger has an unknown filter: declared all', () {
      Logger.level = Level.warning;
      final logger = DefaultJuiceLogger(
          logger: Logger(printer: SimplePrinter(), output: _NoOutput()));
      expect(logger.minLevel, Level.all);
    });

    test('only the CONFIGURED logger\'s declaration counts: a wrapper that '
        'does not declare receives everything', () async {
      Logger.level = Level.off; // the inner default logger keeps nothing
      final wrapper = _Wrapper(DefaultJuiceLogger());
      JuiceLoggerConfig.configureLogger(wrapper);
      final b = _B();
      await b.send(_Set(1));
      expect(wrapper.types, containsAll(_chatter));
      await b.close();
    });
  });

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

class _NoOutput extends LogOutput {
  @override
  void output(OutputEvent event) {}
}
