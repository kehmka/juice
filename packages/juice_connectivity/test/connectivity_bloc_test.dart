import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_connectivity/juice_connectivity.dart';

/// Pure-Dart fake provider — drives the bloc without any platform plugin.
class FakeConnectivityProvider implements ConnectivityProvider {
  late final _ctrl = StreamController<ConnectivitySnapshot>.broadcast(
      onListen: () => log.add('listen'), onCancel: () => log.add('cancel'));
  ConnectivitySnapshot _current;
  bool disposed = false;
  Object? disposeError;

  /// Listen / cancel / dispose, in the order they happened.
  final log = <String>[];
  int checks = 0;
  Completer<ConnectivitySnapshot>? checkGate;

  FakeConnectivityProvider(
      [this._current = const ConnectivitySnapshot(type: ConnectionType.wifi)]);

  @override
  Stream<ConnectivitySnapshot> get changes => _ctrl.stream;

  @override
  Future<ConnectivitySnapshot> check() {
    checks++;
    return checkGate?.future ?? Future.value(_current);
  }

  @override
  Future<void> dispose() async {
    log.add('dispose');
    disposed = true;
    if (disposeError != null) throw disposeError!;
    await _ctrl.close();
  }

  /// Push a new reading through the change stream.
  void emit(ConnectivitySnapshot s) {
    _current = s;
    _ctrl.add(s);
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
  // Debounce is 0 here so stream changes apply on the next microtask/timer
  // without slowing the suite; the debounce behavior itself is tested
  // explicitly below with a non-zero window.
  ConnectivityConfig cfg(
    FakeConnectivityProvider p, {
    Duration debounce = Duration.zero,
  }) =>
      ConnectivityConfig(provider: p, debounce: debounce);

  Future<void> settle([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('ConnectivityState model', () {
    test('defaults to unknown / none', () {
      const s = ConnectivityState();
      expect(s.status, ConnectivityStatus.unknown);
      expect(s.connectionType, ConnectionType.none);
      expect(s.isOnline, isFalse);
      expect(s.isOffline, isFalse);
    });

    test('isOnline / isOffline track status', () {
      expect(
        const ConnectivityState(status: ConnectivityStatus.online).isOnline,
        isTrue,
      );
      expect(
        const ConnectivityState(status: ConnectivityStatus.offline).isOffline,
        isTrue,
      );
    });
  });

  group('ConnectivityBloc', () {
    test('initial check sets online + connection type', () async {
      final p = FakeConnectivityProvider(
          const ConnectivitySnapshot(type: ConnectionType.cellular));
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();

      expect(bloc.state.status, ConnectivityStatus.online);
      expect(bloc.state.connectionType, ConnectionType.cellular);
      expect(bloc.state.isOnline, isTrue);
      await bloc.close();
    });

    test('transitions to offline when interface drops to none', () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();
      expect(bloc.state.isOnline, isTrue);

      p.emit(const ConnectivitySnapshot(type: ConnectionType.none));
      await settle();

      expect(bloc.state.status, ConnectivityStatus.offline);
      expect(bloc.state.connectionType, ConnectionType.none);
      await bloc.close();
    });

    test('reachable:false forces offline even with an interface up', () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();
      expect(bloc.state.isOnline, isTrue);

      p.emit(const ConnectivitySnapshot(
          type: ConnectionType.wifi, reachable: false));
      await settle();

      expect(bloc.state.status, ConnectivityStatus.offline);
      await bloc.close();
    });

    test('records lastChangedAt on a change', () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();

      expect(bloc.state.lastChangedAt, isNotNull);
      await bloc.close();
    });

    test('manual check() re-reads current connectivity', () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();
      expect(bloc.state.isOnline, isTrue);

      // Change the underlying value without emitting on the stream.
      p._current = const ConnectivitySnapshot(type: ConnectionType.none);
      bloc.check();
      await settle();

      expect(bloc.state.isOffline, isTrue);
      await bloc.close();
    });

    test('overlapping manual checks are coalesced', () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();
      final checksAfterInitialization = p.checks;

      final gate = Completer<ConnectivitySnapshot>();
      p.checkGate = gate;
      bloc.check();
      await settle(1); // let the first check enter provider.check()
      bloc.check();
      await settle(1);

      expect(p.checks, checksAfterInitialization + 1,
          reason: 'the in-flight check makes a second read redundant');

      p.checkGate = null;
      gate.complete(const ConnectivitySnapshot(type: ConnectionType.none));
      await settle();
      expect(bloc.state.isOffline, isTrue);
      await bloc.close();
    });

    test('overlapping initialization does not replace the active provider',
        () async {
      final first = FakeConnectivityProvider();
      final second = FakeConnectivityProvider(
          const ConnectivitySnapshot(type: ConnectionType.none));
      final gate = Completer<ConnectivitySnapshot>();
      first.checkGate = gate;

      final bloc = ConnectivityBloc();
      bloc.send(InitializeConnectivityEvent(config: cfg(first)));
      await settle(1); // first initialization is now waiting on its check
      bloc.send(InitializeConnectivityEvent(config: cfg(second)));
      await settle(1);

      expect(first.checks, 1);
      expect(second.checks, 0,
          reason: 'a second init would also create an untracked subscription');

      first.checkGate = null;
      gate.complete(const ConnectivitySnapshot(type: ConnectionType.cellular));
      await settle();
      expect(bloc.provider, same(first));
      expect(bloc.state.connectionType, ConnectionType.cellular);

      await bloc.close();
      expect(first.disposed, isTrue);
      expect(second.disposed, isFalse,
          reason: 'the dropped config was never owned by the bloc');
      await second.dispose();
    });

    test('close disposes the provider and stops listening', () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();

      await bloc.close();
      expect(p.disposed, isTrue);
    });
  });

  group('debounce', () {
    test('only the final reading in a flapping burst is applied', () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(
        cfg(p, debounce: const Duration(milliseconds: 80)),
      );
      await settle(); // initial: online/wifi

      // Rapid flaps within the debounce window.
      p.emit(const ConnectivitySnapshot(type: ConnectionType.none));
      await settle(10);
      p.emit(const ConnectivitySnapshot(type: ConnectionType.cellular));
      await settle(10);
      p.emit(const ConnectivitySnapshot(type: ConnectionType.none));

      // Before the window elapses, nothing has been applied yet.
      expect(bloc.state.connectionType, ConnectionType.wifi);

      // After the window settles, only the last reading lands.
      await settle(120);
      expect(bloc.state.connectionType, ConnectionType.none);
      expect(bloc.state.isOffline, isTrue);
      await bloc.close();
    });
  });

  group('ConnectivityBloc review pins (2.0.0)', () {
    test('close cancels the changes binding before disposing the provider',
        () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();
      await bloc.close();
      expect(p.log, ['listen', 'cancel', 'dispose']);
    });

    test('a second start replaces the binding instead of adding one', () async {
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();
      bloc.startListening();
      await settle();
      expect(p.log, ['listen', 'cancel', 'listen']);
      await bloc.close();
    });

    test(
        'a changes stream error is logged as a bloc error and ends the binding',
        () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final p = FakeConnectivityProvider();
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();
      p.fail(StateError('radio off'));
      await settle();
      // Two entries by design: the binding's own `stream_binding/error`
      // (it names the key) and the `bloc_error` from the bloc's onError.
      expect(log.errors, hasLength(2));
      expect(log.errors, everyElement(contains('radio off')));
      expect(p.log, ['listen', 'cancel']);
      await bloc.close();
    });

    test('an uninitialized bloc closes cleanly and names its missing config',
        () async {
      final bloc = ConnectivityBloc();
      expect(() => bloc.provider, throwsStateError);
      await bloc.close();
    });

    test('a provider whose dispose throws is logged, not swallowed', () async {
      final saved = JuiceLoggerConfig.logger;
      final log = _CaptureLogger();
      JuiceLoggerConfig.configureLogger(log);
      addTearDown(() => JuiceLoggerConfig.configureLogger(saved));
      final p = FakeConnectivityProvider()
        ..disposeError = StateError('radio busy');
      final bloc = ConnectivityBloc.withConfig(cfg(p));
      await settle();
      await bloc.close();
      expect(log.errors.single, contains('radio busy'));
    });
  });
}
