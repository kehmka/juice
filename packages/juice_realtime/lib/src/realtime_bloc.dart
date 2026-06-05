import 'dart:math' as math;

import 'package:juice/juice.dart';

import 'realtime_config.dart';
import 'realtime_connection.dart';
import 'realtime_events.dart';
import 'realtime_state.dart';
import 'use_cases/connect_use_case.dart';
import 'use_cases/connection_established_use_case.dart';
import 'use_cases/connection_lost_use_case.dart';
import 'use_cases/disconnect_use_case.dart';
import 'use_cases/initialize_realtime_use_case.dart';
import 'use_cases/message_received_use_case.dart';
import 'use_cases/reconnect_use_case.dart';
import 'use_cases/send_use_case.dart';

/// A realtime-connection bloc — a persistent WebSocket/SSE stream with
/// **automatic reconnection (exponential backoff)**, behind a swappable
/// [RealtimeConnector] seam.
///
/// Connection *status* is state ([RealtimeState]); message *delivery* is the
/// [messages] broadcast stream (so high-frequency consumers like chat never
/// drop a message). `state.lastMessage` + the `realtime:message` group cover the
/// simple "show the latest" case.
///
/// ```dart
/// final rt = RealtimeBloc.withConfig(RealtimeConfig(url: 'wss://example/ws'));
/// rt.messages.listen(handle);
/// rt.send('{"type":"ping"}');
/// ```
class RealtimeBloc extends JuiceBloc<RealtimeState> {
  late RealtimeConfig _config;

  RealtimeConnection? _connection;
  StreamSubscription<RealtimeMessage>? _messageSub;
  Timer? _reconnectTimer;
  bool _manualClose = false;

  final StreamController<RealtimeMessage> _messages =
      StreamController<RealtimeMessage>.broadcast();

  RealtimeBloc()
      : super(
          RealtimeState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeRealtimeEvent,
                useCaseGenerator: () => InitializeRealtimeUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ConnectEvent,
                useCaseGenerator: () => ConnectUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ReconnectEvent,
                useCaseGenerator: () => ReconnectUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: DisconnectEvent,
                useCaseGenerator: () => DisconnectUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SendEvent,
                useCaseGenerator: () => SendUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ConnectionEstablishedEvent,
                useCaseGenerator: () => ConnectionEstablishedUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ConnectionLostEvent,
                useCaseGenerator: () => ConnectionLostUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: MessageReceivedEvent,
                useCaseGenerator: () => MessageReceivedUseCase()),
          ],
        );

  /// Create and initialize in one step.
  factory RealtimeBloc.withConfig(RealtimeConfig config) {
    final bloc = RealtimeBloc();
    bloc.send(InitializeRealtimeEvent(config: config));
    return bloc;
  }

  // === Config (used by use cases) ===

  void configure(RealtimeConfig config) => _config = config;
  RealtimeConfig get config => _config;

  /// Inbound messages — listen here to receive *every* message in order.
  Stream<RealtimeMessage> get messages => _messages.stream;

  /// Whether the live connection can send.
  bool get hasConnection => _connection != null;

  // === Connection lifecycle (resources live here) ===

  /// Open a connection and wire its message stream to internal events.
  /// Sends [ConnectionEstablishedEvent] on success, [ConnectionLostEvent] on
  /// failure or drop.
  Future<void> openConnection() async {
    _manualClose = false;
    try {
      final conn = await _config.connector.connect();
      _connection = conn;
      _messageSub = conn.messages.listen(
        (m) {
          if (!isClosed) send(MessageReceivedEvent(m));
        },
        onError: (Object e) {
          if (!isClosed) send(ConnectionLostEvent(e));
        },
        onDone: () {
          if (!isClosed) send(ConnectionLostEvent(null));
        },
      );
      if (!isClosed) send(ConnectionEstablishedEvent());
    } catch (e) {
      if (!isClosed) send(ConnectionLostEvent(e));
    }
  }

  /// Push a received message to the broadcast stream.
  void pushMessage(RealtimeMessage m) {
    if (!_messages.isClosed) _messages.add(m);
  }

  /// Send over the live connection (caller ensures it exists).
  Future<void> sendData(Object data) => _connection!.send(data);

  /// Whether the last close was user-initiated (suppresses reconnect).
  bool get manualClose => _manualClose;

  /// Mark a user-initiated disconnect and cancel any pending reconnect.
  void markManualClose() {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Tear down the current connection + subscription (not the broadcast stream).
  Future<void> teardownConnection() async {
    await _messageSub?.cancel();
    _messageSub = null;
    final conn = _connection;
    _connection = null;
    await conn?.close();
  }

  /// Whether another reconnect is allowed given [attempt] (1-based).
  bool canReconnect(int attempt) {
    final max = _config.maxReconnectAttempts;
    return max == null || attempt <= max;
  }

  /// Schedule a reconnect with exponential backoff for [attempt] (1-based).
  void scheduleReconnect(int attempt) {
    _reconnectTimer?.cancel();
    final base = _config.initialBackoff * math.pow(2, attempt - 1).toDouble();
    final delay = base > _config.maxBackoff ? _config.maxBackoff : base;
    _reconnectTimer = Timer(delay, () {
      if (!isClosed) send(ReconnectEvent());
    });
  }

  // === Convenience API ===

  void connect() => send(ConnectEvent());
  void disconnect() => send(DisconnectEvent());
  void sendMessage(Object data) => send(SendEvent(data));

  @override
  Future<void> close() async {
    _reconnectTimer?.cancel();
    await _messageSub?.cancel();
    await _connection?.close();
    await _messages.close();
    try {
      await _config.connector.dispose();
    } catch (_) {
      // Config may never have been applied; ignore.
    }
    await super.close();
  }
}
