import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_realtime/juice_realtime.dart';

/// A fake live connection — drive messages, drops, and inspect sends.
class FakeRealtimeConnection implements RealtimeConnection {
  final _controller = StreamController<RealtimeMessage>();
  final List<Object> sent = [];
  Completer<void>? sendGate;
  bool closed = false;
  int closeCalls = 0;

  void emit(RealtimeMessage m) => _controller.add(m);

  /// Simulate the server closing the socket → bloc sees `onDone`.
  void drop() {
    if (!_controller.isClosed) _controller.close();
  }

  @override
  Stream<RealtimeMessage> get messages => _controller.stream;

  @override
  Future<void> send(Object data) async {
    sent.add(data);
    final gate = sendGate;
    sendGate = null;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
    if (!_controller.isClosed) await _controller.close();
  }
}

/// A fake connector — hands out connections, or fails to connect.
class FakeRealtimeConnector implements RealtimeConnector {
  bool failConnect = false;
  final List<FakeRealtimeConnection> connections = [];
  Completer<void>? connectGate;
  int connectCalls = 0;
  bool disposed = false;

  FakeRealtimeConnection get latest => connections.last;

  @override
  Future<RealtimeConnection> connect() async {
    connectCalls++;
    final gate = connectGate;
    connectGate = null;
    if (gate != null) await gate.future;
    if (failConnect) throw StateError('connect failed');
    final c = FakeRealtimeConnection();
    connections.add(c);
    return c;
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  RealtimeConfig cfg(FakeRealtimeConnector c,
          {bool autoConnect = false, int? maxAttempts}) =>
      RealtimeConfig(
        connector: c,
        autoConnect: autoConnect,
        initialBackoff: const Duration(milliseconds: 10),
        maxBackoff: const Duration(milliseconds: 40),
        maxReconnectAttempts: maxAttempts,
      );

  group('RealtimeState model', () {
    test('defaults', () {
      const s = RealtimeState();
      expect(s.status, RealtimeStatus.disconnected);
      expect(s.messageCount, 0);
      expect(s.isConnected, isFalse);
    });
  });

  group('Connect / messages', () {
    test('connect reaches connected', () async {
      final conn = FakeRealtimeConnector();
      final bloc = RealtimeBloc.withConfig(cfg(conn));
      await settle();
      expect(bloc.state.status, RealtimeStatus.disconnected);

      bloc.connect();
      await settle();
      expect(bloc.state.status, RealtimeStatus.connected);
      await bloc.close();
    });

    test('messages reach lastMessage, count, and the broadcast stream',
        () async {
      final conn = FakeRealtimeConnector();
      final bloc = RealtimeBloc.withConfig(cfg(conn));
      await settle();
      bloc.connect();
      await settle();

      final got = <RealtimeMessage>[];
      final sub = bloc.messages.listen(got.add);

      conn.latest.emit(const RealtimeMessage('one'));
      conn.latest.emit(const RealtimeMessage('two'));
      conn.latest.emit(const RealtimeMessage('three'));
      await settle();

      expect(bloc.state.lastMessage?.data, 'three');
      expect(bloc.state.messageCount, 3);
      expect(got.map((m) => m.data), ['one', 'two', 'three']);

      await sub.cancel();
      await bloc.close();
    });
  });

  group('Send (fail-loud)', () {
    test('send forwards to the connection', () async {
      final conn = FakeRealtimeConnector();
      final bloc = RealtimeBloc.withConfig(cfg(conn));
      await settle();
      bloc.connect();
      await settle();

      bloc.sendMessage('ping');
      await settle();
      expect(conn.latest.sent, ['ping']);
      await bloc.close();
    });

    test('overlapping sends preserve FIFO order', () async {
      final conn = FakeRealtimeConnector();
      final bloc = RealtimeBloc.withConfig(cfg(conn));
      await settle();
      bloc.connect();
      await settle();

      final gate = Completer<void>();
      conn.latest.sendGate = gate;
      bloc.sendMessage('first');
      bloc.sendMessage('second');
      await settle();
      expect(conn.latest.sent, ['first']);

      gate.complete();
      await settle();
      expect(conn.latest.sent, ['first', 'second']);
      await bloc.close();
    });

    test('send while not connected fails loudly', () async {
      final conn = FakeRealtimeConnector();
      final bloc = RealtimeBloc.withConfig(cfg(conn)); // not connected
      await settle();

      bloc.sendMessage('x');
      await settle();
      expect(bloc.state.lastError, contains('not connected'));
      await bloc.close();
    });
  });

  group('Reconnection', () {
    test('a dropped connection reconnects with backoff', () async {
      final conn = FakeRealtimeConnector();
      // Longer backoff so the transient `reconnecting` state is observable.
      final bloc = RealtimeBloc.withConfig(RealtimeConfig(
        connector: conn,
        autoConnect: false,
        initialBackoff: const Duration(milliseconds: 80),
        maxBackoff: const Duration(milliseconds: 80),
      ));
      await settle();
      bloc.connect();
      await settle();
      expect(conn.connections.length, 1);

      conn.latest.drop(); // server closes
      await settle(); // < 80ms backoff: still waiting to reconnect
      expect(bloc.state.status, RealtimeStatus.reconnecting);

      await settle(120); // let the backoff timer fire
      expect(bloc.state.status, RealtimeStatus.connected);
      expect(conn.connections.length, 2); // reconnected on a fresh connection
      expect(bloc.state.reconnectAttempts, 0); // reset on success
      await bloc.close();
    });

    test('gives up loudly after maxReconnectAttempts', () async {
      final conn = FakeRealtimeConnector()..failConnect = true;
      final bloc =
          RealtimeBloc.withConfig(cfg(conn, autoConnect: true, maxAttempts: 2));
      await settle(120); // initial attempt + 2 backoff retries

      expect(bloc.state.status, RealtimeStatus.disconnected);
      expect(bloc.state.lastError, isNotNull);
      await bloc.close();
    });

    test('connect/reconnect overlap opens only one connection', () async {
      final gate = Completer<void>();
      final conn = FakeRealtimeConnector()..connectGate = gate;
      final bloc = RealtimeBloc.withConfig(cfg(conn));
      await settle();

      bloc.connect();
      bloc.send(ReconnectEvent());
      bloc.connect();
      await settle();

      expect(conn.connectCalls, 1);
      expect(bloc.state.status, RealtimeStatus.connecting);

      gate.complete();
      await settle();
      expect(conn.connections.length, 1);
      expect(bloc.state.status, RealtimeStatus.connected);
      await bloc.close();
    });

    test('disconnect wins against a pending connect completion', () async {
      final gate = Completer<void>();
      final conn = FakeRealtimeConnector()..connectGate = gate;
      final bloc = RealtimeBloc.withConfig(cfg(conn));
      await settle();

      bloc.connect();
      await settle();
      expect(bloc.state.status, RealtimeStatus.connecting);

      bloc.disconnect();
      await settle();
      expect(bloc.state.status, RealtimeStatus.disconnected);

      gate.complete();
      await settle();
      expect(conn.connections.single.closed, isTrue);
      expect(bloc.state.status, RealtimeStatus.disconnected);
      expect(bloc.hasConnection, isFalse);
      await bloc.close();
    });

    test('user connect supersedes a scheduled reconnect', () async {
      final conn = FakeRealtimeConnector();
      final bloc = RealtimeBloc.withConfig(RealtimeConfig(
        connector: conn,
        autoConnect: false,
        initialBackoff: const Duration(milliseconds: 80),
        maxBackoff: const Duration(milliseconds: 80),
      ));
      await settle();
      bloc.connect();
      await settle();

      conn.latest.drop();
      await settle();
      expect(bloc.state.status, RealtimeStatus.reconnecting);

      bloc.connect();
      await settle();
      expect(conn.connections.length, 2);
      expect(bloc.state.status, RealtimeStatus.connected);

      await settle(120);
      expect(conn.connections.length, 2);
      expect(bloc.state.status, RealtimeStatus.connected);
      await bloc.close();
    });

    test('manual disconnect stops reconnection', () async {
      final conn = FakeRealtimeConnector();
      final bloc = RealtimeBloc.withConfig(cfg(conn));
      await settle();
      bloc.connect();
      await settle();

      bloc.disconnect();
      await settle();
      expect(bloc.state.status, RealtimeStatus.disconnected);

      // A late drop on the old connection must not trigger a reconnect.
      await settle(40);
      expect(bloc.state.status, RealtimeStatus.disconnected);
      expect(conn.connections.length, 1);
      await bloc.close();
    });
  });

  group('Lifecycle', () {
    test('close disposes the connector', () async {
      final conn = FakeRealtimeConnector();
      final bloc = RealtimeBloc.withConfig(cfg(conn));
      await settle();
      await bloc.close();
      expect(conn.disposed, isTrue);
    });
  });
}
