import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_lifecycle/juice_lifecycle.dart';

/// Pure-Dart fake — drives the bloc without a real WidgetsBinding.
class FakeLifecycleProvider implements LifecycleProvider {
  late final _ctrl = StreamController<AppLifecycle>.broadcast(
      onListen: () => log.add('listen'), onCancel: () => log.add('cancel'));
  AppLifecycle _current;
  bool disposed = false;
  Object? disposeError;

  /// Listen / cancel / dispose, in the order they happened.
  final log = <String>[];

  FakeLifecycleProvider([this._current = AppLifecycle.resumed]);

  @override
  Stream<AppLifecycle> get changes => _ctrl.stream;

  @override
  AppLifecycle get current => _current;

  @override
  Future<void> dispose() async {
    log.add('dispose');
    disposed = true;
    if (disposeError != null) throw disposeError!;
    await _ctrl.close();
  }

  void emit(AppLifecycle p) {
    _current = p;
    _ctrl.add(p);
  }

  /// Break the change stream.
  void fail(Object error) => _ctrl.addError(error);
}

class _CaptureLogger implements JuiceLogger {
  final errors = <String>[];
  @override
  void record(JuiceTelemetry e) {
    if (e.isError) errors.add('${e.message}: ${e.error}');
  }

  @override
  void log(String m,
      {Level level = Level.info, Map<String, dynamic>? context}) {}
  @override
  void logError(String m, Object e, StackTrace s,
          {Map<String, dynamic>? context}) =>
      errors.add('$m: $e');
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('LifecycleState model', () {
    test('foreground / background getters', () {
      expect(const LifecycleState(lifecycle: AppLifecycle.resumed).isForeground,
          isTrue);
      expect(const LifecycleState(lifecycle: AppLifecycle.paused).isBackground,
          isTrue);
      expect(const LifecycleState(lifecycle: AppLifecycle.hidden).isBackground,
          isTrue);
      expect(
          const LifecycleState(lifecycle: AppLifecycle.inactive).isForeground,
          isFalse);
    });

    test('resumedFromBackground only when coming back from non-foreground', () {
      expect(
        const LifecycleState(
                lifecycle: AppLifecycle.resumed, previous: AppLifecycle.paused)
            .resumedFromBackground,
        isTrue,
      );
      expect(
        const LifecycleState(
                lifecycle: AppLifecycle.paused, previous: AppLifecycle.resumed)
            .resumedFromBackground,
        isFalse,
      );
    });
  });

  group('LifecycleBloc', () {
    test('drops overlapping initialization', () async {
      final firstProvider = FakeLifecycleProvider(AppLifecycle.inactive);
      final secondProvider = FakeLifecycleProvider(AppLifecycle.paused);
      final bloc = LifecycleBloc();

      final first = bloc.send(InitializeLifecycleEvent(
        config: LifecycleConfig(provider: firstProvider),
      ));
      final second = bloc.send(InitializeLifecycleEvent(
        config: LifecycleConfig(provider: secondProvider),
      ));
      await Future.wait([first, second]);

      expect(bloc.provider, same(firstProvider));
      expect(bloc.state.lifecycle, AppLifecycle.inactive);
      await bloc.close();
      expect(firstProvider.disposed, isTrue);
      expect(secondProvider.disposed, isFalse);
    });

    test('emits the current phase on init', () async {
      final p = FakeLifecycleProvider(AppLifecycle.inactive);
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      expect(bloc.state.lifecycle, AppLifecycle.inactive);
      await bloc.close();
    });

    test('tracks transitions and the previous phase', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();
      expect(bloc.state.isForeground, isTrue);

      p.emit(AppLifecycle.paused);
      await settle();
      expect(bloc.state.isBackground, isTrue);
      expect(bloc.state.previous, AppLifecycle.resumed);

      p.emit(AppLifecycle.resumed);
      await settle();
      expect(bloc.state.isForeground, isTrue);
      expect(bloc.state.previous, AppLifecycle.paused);
      expect(bloc.state.resumedFromBackground, isTrue);
      await bloc.close();
    });

    test('processes rapid transitions in stream order', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      final inactive = bloc.send(LifecycleChangedEvent(AppLifecycle.inactive));
      final paused = bloc.send(LifecycleChangedEvent(AppLifecycle.paused));
      final resumed = bloc.send(LifecycleChangedEvent(AppLifecycle.resumed));
      await Future.wait([inactive, paused, resumed]);

      expect(bloc.state.lifecycle, AppLifecycle.resumed);
      expect(bloc.state.previous, AppLifecycle.paused);
      expect(bloc.state.resumedFromBackground, isTrue);
      await bloc.close();
    });

    test('ignores a repeat of the same phase (no-op)', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      p.emit(AppLifecycle.resumed); // same as current
      await settle();
      expect(bloc.state.previous, isNull); // never transitioned
      await bloc.close();
    });

    test('records lastChangedAt on a transition', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      p.emit(AppLifecycle.paused);
      await settle();
      expect(bloc.state.lastChangedAt, isNotNull);
      await bloc.close();
    });

    test('close disposes the provider', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();

      await bloc.close();
      expect(p.disposed, isTrue);
    });
  });

  group('LifecycleBloc review pins (2.0.0)', () {
    test('close cancels the changes binding before disposing the provider',
        () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();
      await bloc.close();
      expect(p.log, ['listen', 'cancel', 'dispose']);
    });

    test('a second start replaces the binding instead of adding one', () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();
      bloc.startListening();
      await settle();
      expect(p.log, ['listen', 'cancel', 'listen']);
      await bloc.close();
    });

    test(
        'a changes stream error is logged as a bloc error; the binding keeps '
        'listening', () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();
      p.fail(StateError('binding gone'));
      await settle();
      // Two entries by design: the binding's own `stream_binding/error`
      // (it names the key) and the `bloc_error` from the bloc's onError.
      expect(log.errors, hasLength(2));
      expect(log.errors, everyElement(contains('binding gone')));
      expect(p.log, ['listen'], reason: 'not cancelled on error');
      p.emit(AppLifecycle.paused);
      await settle();
      expect(bloc.state.isBackground, isTrue, reason: 'still listening');
      await bloc.close();
    });

    test('an uninitialized bloc closes cleanly and names its missing config',
        () async {
      final bloc = LifecycleBloc();
      expect(() => bloc.provider, throwsStateError);
      await bloc.close();
    });

    test('a provider whose dispose throws is logged, not swallowed', () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final p = FakeLifecycleProvider()
        ..disposeError = StateError('binding busy');
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();
      await bloc.close();
      expect(log.errors.single, contains('binding busy'));
    });

    test('a second close() awaits the first: the provider is disposed once',
        () async {
      final p = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: p));
      await settle();
      await Future.wait([bloc.close(), bloc.close()]);
      await bloc.close();
      expect(bloc.activeBindingCount, 0);
      expect(p.log.where((e) => e == 'dispose').length, 1);
    });

    test(
        'a second initialization after the first is refused; the first '
        'provider stays', () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final first = FakeLifecycleProvider();
      final second = FakeLifecycleProvider();
      final bloc = LifecycleBloc.withConfig(LifecycleConfig(provider: first));
      await settle();
      await bloc.send(
          InitializeLifecycleEvent(config: LifecycleConfig(provider: second)));
      await settle();
      // Two entries by the 2.0 contract: the span's `use_case_error` and the
      // `bloc_error`.
      expect(log.errors, hasLength(2));
      expect(log.errors, everyElement(contains('already initialized')));
      expect(bloc.provider, same(first));
      await bloc.close();
      expect(first.disposed, isTrue);
      expect(second.disposed, isFalse, reason: 'never owned');
    });
  });
}
