import 'providers/web_socket_realtime_connector.dart';
import 'realtime_connection.dart';

/// Configures a `RealtimeBloc`.
class RealtimeConfig {
  /// How connections are opened. Defaults to a `WebSocketRealtimeConnector`
  /// built from [url].
  final RealtimeConnector connector;

  /// Connect as soon as the bloc initializes.
  final bool autoConnect;

  /// Backoff before the first reconnect attempt; doubles each attempt.
  final Duration initialBackoff;

  /// Upper bound on the backoff delay.
  final Duration maxBackoff;

  /// Max consecutive reconnect attempts before giving up (→ `disconnected`).
  /// Null means retry forever.
  final int? maxReconnectAttempts;

  RealtimeConfig({
    RealtimeConnector? connector,
    String? url,
    this.autoConnect = true,
    this.initialBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 30),
    this.maxReconnectAttempts,
  }) : connector = connector ??
            WebSocketRealtimeConnector(url ??
                (throw ArgumentError(
                    'RealtimeConfig requires either a connector or a url')));
}
