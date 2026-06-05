import 'package:web_socket_channel/web_socket_channel.dart';

import '../realtime_connection.dart';

/// Default [RealtimeConnector] backed by `web_socket_channel` — works across
/// mobile, desktop, and web.
class WebSocketRealtimeConnector implements RealtimeConnector {
  final Uri uri;
  final Iterable<String>? protocols;

  WebSocketRealtimeConnector(String url, {this.protocols})
      : uri = Uri.parse(url);

  @override
  Future<RealtimeConnection> connect() async {
    final channel = WebSocketChannel.connect(uri, protocols: protocols);
    // Throws if the handshake fails — the bloc treats that as a lost connection.
    await channel.ready;
    return _WebSocketConnection(channel);
  }

  @override
  Future<void> dispose() async {}
}

class _WebSocketConnection implements RealtimeConnection {
  final WebSocketChannel _channel;
  _WebSocketConnection(this._channel);

  @override
  Stream<RealtimeMessage> get messages =>
      _channel.stream.map((data) => RealtimeMessage(data as Object));

  @override
  Future<void> send(Object data) async => _channel.sink.add(data);

  @override
  Future<void> close() async => _channel.sink.close();
}
