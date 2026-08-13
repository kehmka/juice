import 'package:juice/juice.dart';

import 'realtime_config.dart';
import 'realtime_connection.dart';

/// Base class for realtime events.
abstract class RealtimeEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

/// Apply config; auto-connect if configured.
class InitializeRealtimeEvent extends RealtimeEvent {
  final RealtimeConfig config;
  InitializeRealtimeEvent({required this.config});
}

/// Open a connection (resets reconnect attempts; clears manual-disconnect).
class ConnectEvent extends RealtimeEvent {}

/// Close and stop reconnecting.
class DisconnectEvent extends RealtimeEvent {}

/// Send a payload over the connection.
class SendEvent extends RealtimeEvent {
  final Object data;
  SendEvent(this.data);
}

/// Internal: a scheduled reconnect fired (preserves the attempt count).
class ReconnectEvent extends RealtimeEvent {}

/// Internal: the connection opened successfully.
class ConnectionEstablishedEvent extends RealtimeEvent {
  final int? connectionEpoch;
  ConnectionEstablishedEvent({this.connectionEpoch});
}

/// Internal: the connection dropped or failed to open.
class ConnectionLostEvent extends RealtimeEvent {
  final Object? error;
  final int? connectionEpoch;
  ConnectionLostEvent(this.error, {this.connectionEpoch});
}

/// Internal: a message arrived.
class MessageReceivedEvent extends RealtimeEvent {
  final RealtimeMessage message;
  final int? connectionEpoch;
  MessageReceivedEvent(this.message, {this.connectionEpoch});
}
