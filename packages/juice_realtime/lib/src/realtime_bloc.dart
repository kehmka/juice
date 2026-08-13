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
  bool _connecting = false;
  int _connectionEpoch = 0;

  final StreamController<RealtimeMessage> _messages =
      StreamController<RealtimeMessage>.broadcast();

  RealtimeBloc()
      : super(
          RealtimeState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeRealtimeEvent,
                useCaseGenerator: () => InitializeRealtimeUseCase(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder(
                typeOfEvent: ConnectEvent,
                useCaseGenerator: () => ConnectUseCase(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder(
                typeOfEvent: ReconnectEvent,
                useCaseGenerator: () => ReconnectUseCase(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder(
                typeOfEvent: DisconnectEvent,
                useCaseGenerator: () => DisconnectUseCase(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder(
                typeOfEvent: SendEvent,
                useCaseGenerator: () => SendUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: ConnectionEstablishedEvent,
                useCaseGenerator: () => ConnectionEstablishedUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: ConnectionLostEvent,
                useCaseGenerator: () => ConnectionLostUseCase(),
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder(
                typeOfEvent: MessageReceivedEvent,
                useCaseGenerator: () => MessageReceivedUseCase(),
                concurrency: EventConcurrency.sequential),
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

  /// A connection lifecycle transition is in flight.
  bool get isConnecting => _connecting;

  /// Begin a connect attempt and return its epoch.
  ///
  /// A user-initiated connect supersedes manual-close state and any scheduled
  /// reconnect. Reconnect attempts leave that policy untouched.
  int beginConnecting({bool userInitiated = false}) {
    if (userInitiated) {
      _manualClose = false;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
    _connecting = true;
    return ++_connectionEpoch;
  }

  void endConnecting() => _connecting = false;

  /// Whether [epoch] still owns the connection lifecycle.
  bool isConnectionEpoch(int epoch) => !isClosed && epoch == _connectionEpoch;

  /// Whether a live attempt/callback is current and not manually closed.
  ///
  /// A null epoch keeps manually dispatched internal events source-compatible.
  bool isCurrentConnectionEpoch(int? epoch) =>
      !_manualClose &&
      !isClosed &&
      (epoch == null || epoch == _connectionEpoch);

  /// Claim connection-loss handling and invalidate callbacks from the old link.
  /// Returns the transition epoch, or null when the loss event is stale.
  int? beginConnectionLoss(int? connectionEpoch) {
    if (!isCurrentConnectionEpoch(connectionEpoch)) return null;
    _connecting = true;
    return ++_connectionEpoch;
  }

  // === Connection lifecycle (resources live here) ===

  /// Open a connection and wire its message stream to internal events.
  /// Sends [ConnectionEstablishedEvent] on success, [ConnectionLostEvent] on
  /// failure or drop.
  Future<void> openConnection(int connectionEpoch) async {
    try {
      final conn = await _config.connector.connect();
      if (!isCurrentConnectionEpoch(connectionEpoch)) {
        await conn.close();
        return;
      }

      _connection = conn;
      _messageSub = conn.messages.listen(
        (m) {
          if (isCurrentConnectionEpoch(connectionEpoch)) {
            send(MessageReceivedEvent(
              m,
              connectionEpoch: connectionEpoch,
            ));
          }
        },
        onError: (Object e) {
          if (isCurrentConnectionEpoch(connectionEpoch)) {
            send(ConnectionLostEvent(
              e,
              connectionEpoch: connectionEpoch,
            ));
          }
        },
        onDone: () {
          if (isCurrentConnectionEpoch(connectionEpoch)) {
            send(ConnectionLostEvent(
              null,
              connectionEpoch: connectionEpoch,
            ));
          }
        },
      );
      if (isCurrentConnectionEpoch(connectionEpoch)) {
        await send(ConnectionEstablishedEvent(
          connectionEpoch: connectionEpoch,
        ));
      }
    } catch (e) {
      if (isCurrentConnectionEpoch(connectionEpoch)) {
        await send(ConnectionLostEvent(
          e,
          connectionEpoch: connectionEpoch,
        ));
      }
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
  int markManualClose() {
    _manualClose = true;
    _connecting = false;
    final epoch = ++_connectionEpoch;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    return epoch;
  }

  /// Tear down the current connection + subscription (not the broadcast stream).
  Future<void> teardownConnection() async {
    final messageSub = _messageSub;
    final connection = _connection;
    _messageSub = null;
    _connection = null;
    await messageSub?.cancel();
    await connection?.close();
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
    markManualClose();
    await teardownConnection();
    await _messages.close();
    try {
      await _config.connector.dispose();
    } catch (_) {
      // Config may never have been applied; ignore.
    }
    await super.close();
  }
}
