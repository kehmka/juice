import 'package:juice/juice.dart';
import '../chat.dart';
import '../../../services/websocket_service.dart';

/// Handles WebSocket connection initialization, message listening, and automatic reconnection.
///
/// This use case manages the full lifecycle of a WebSocket connection including:
/// - Initial connection
/// - Message handling
/// - Automatic reconnection
/// - Resource cleanup
class InitializeWebSocketUseCase
    extends BlocUseCase<ChatBloc, ConnectWebSocketEvent> {
  final WebSocketService _service;
  StreamSubscription<String>? _messageSubscription;
  Timer? _reconnectionTimer;
  bool _isDisposed = false;

  InitializeWebSocketUseCase(this._service);

  /// Initializes the WebSocket connection.
  Future<void> initialize() async {
    if (_isDisposed) return;

    try {
      await _connect();
    } catch (e, stackTrace) {
      logError(e, stackTrace);
      _handleDisconnection();
    }
  }

  /// Establishes WebSocket connection and sets up message handling.
  Future<void> _connect() async {
    if (_isDisposed) return;

    try {
      emitWaiting(groupsToRebuild: {"messages"});

      // Connect with timeout
      await _service.connect('wss://echo.websocket.events').timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Connection timeout'),
          );

      // Update connection state
      emitUpdate(
        groupsToRebuild: {"connection", "messages"},
        newState: bloc.state.copyWith(
          isConnected: true,
          lastError: null,
        ),
      );

      _startListeningToMessages();

      JuiceLoggerConfig.logger.log('WebSocket connected successfully');
    } catch (e, stackTrace) {
      logError(e, stackTrace);

      emitUpdate(
        groupsToRebuild: {"connection", "messages"},
        newState: bloc.state.copyWith(
          isConnected: false,
          lastError: e.toString(),
        ),
      );

      rethrow;
    }
  }

  /// Sets up message listener with error handling.
  void _startListeningToMessages() {
    if (_isDisposed) return;

    // Cancel existing subscription
    _messageSubscription?.cancel();

    _messageSubscription = _service.messages.listen(
      (message) {
        if (!_isDisposed) {
          bloc.send(ReceiveMessageEvent(message: message));
        }
      },
      onError: (error, stackTrace) {
        logError(error, stackTrace);
        _handleDisconnection(error: error.toString());
      },
      onDone: () => _handleDisconnection(error: 'Connection closed by server'),
    );
  }

  /// Handles connection loss and initiates reconnection.
  void _handleDisconnection({String? error}) {
    if (_isDisposed) return;

    emitUpdate(
      groupsToRebuild: {"connection"},
      newState: bloc.state.copyWith(
        isConnected: false,
        lastError: error,
      ),
    );

    _attemptReconnection();
  }

  /// Implements exponential backoff reconnection strategy.
  void _attemptReconnection() {
    if (_isDisposed) return;

    _reconnectionTimer?.cancel();

    int attempts = 0;
    const maxAttempts = 5;
    const baseDelay = Duration(seconds: 2);

    _reconnectionTimer = Timer.periodic(baseDelay, (timer) async {
      if (_isDisposed || attempts >= maxAttempts) {
        timer.cancel();

        if (attempts >= maxAttempts) {
          emitFailure(
            groupsToRebuild: {"connection"},
            newState: bloc.state.copyWith(
              isConnected: false,
              lastError: 'Max reconnection attempts reached',
            ),
          );
        }
        return;
      }

      try {
        await _connect();
        timer.cancel();
        JuiceLoggerConfig.logger.log('Reconnection successful');
      } catch (e, stackTrace) {
        attempts++;
        logError(e, stackTrace);

        // Exponential backoff
        final nextDelay =
            Duration(seconds: baseDelay.inSeconds * (1 << attempts));
        timer.cancel();

        if (attempts < maxAttempts) {
          _reconnectionTimer = Timer(nextDelay, () => _attemptReconnection());
        }
      }
    });
  }

  /// Cleans up resources when the use case is disposed.
  /// Performs asynchronous cleanup of resources
  Future<void> dispose() async {
    _isDisposed = true;
    await _messageSubscription?.cancel();
    _reconnectionTimer?.cancel();
    await _service.disconnect();
  }

  @override
  void close() {
    // Start async cleanup but don't await it
    dispose().catchError((error, stackTrace) {
      logError(error, stackTrace);
    });
  }

  @override
  Future<void> execute(ConnectWebSocketEvent event) async {
    await initialize();
  }
}
