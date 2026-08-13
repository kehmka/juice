import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_connectivity/juice_connectivity.dart';

/// Pure-Dart fake provider — drives the bloc without any platform plugin.
class FakeConnectivityProvider implements ConnectivityProvider {
  final _ctrl = StreamController<ConnectivitySnapshot>.broadcast();
  ConnectivitySnapshot _current;
  bool disposed = false;
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
    disposed = true;
    await _ctrl.close();
  }

  /// Push a new reading through the change stream.
  void emit(ConnectivitySnapshot s) {
    _current = s;
    _ctrl.add(s);
  }
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
}
