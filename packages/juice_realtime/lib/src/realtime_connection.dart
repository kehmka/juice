/// A message received over (or to send across) a realtime connection.
///
/// [data] is the raw payload — a `String` or bytes for WebSocket, or an
/// event's data for SSE. [event] is an optional channel/event name (SSE event
/// type, or a topic you've multiplexed).
class RealtimeMessage {
  final Object data;
  final String? event;

  const RealtimeMessage(this.data, {this.event});

  @override
  String toString() =>
      'RealtimeMessage(${event == null ? '' : '$event: '}$data)';
}

/// One live realtime connection — the seam's unit of a single connect attempt.
///
/// Its [messages] stream **closes when the connection drops**; the bloc detects
/// that and drives reconnection. The bloc never reuses a closed connection.
abstract class RealtimeConnection {
  /// Inbound messages. Closes (or errors) when the connection is lost.
  Stream<RealtimeMessage> get messages;

  /// Send a payload (WebSocket). Read-only transports (SSE) should throw
  /// [UnsupportedError].
  Future<void> send(Object data);

  /// Close the connection.
  Future<void> close();
}

/// Vendor seam for opening realtime connections.
///
/// The bloc depends on this, not on a socket library — testable with a fake,
/// and SSE / a vendor SDK can implement it too. Default:
/// `WebSocketRealtimeConnector`.
abstract class RealtimeConnector {
  /// Open one connection. Throws if the attempt fails (the bloc then backs off
  /// and retries).
  Future<RealtimeConnection> connect();

  /// Release resources.
  Future<void> dispose();
}
