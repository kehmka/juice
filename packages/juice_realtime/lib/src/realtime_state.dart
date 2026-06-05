import 'package:juice/juice.dart';

import 'realtime_connection.dart';

/// Connection lifecycle.
enum RealtimeStatus {
  /// Not connected (initial, or after giving up / manual disconnect).
  disconnected,

  /// A connect attempt is in flight.
  connecting,

  /// Connected and receiving.
  connected,

  /// Connection dropped; a reconnect is scheduled/in progress.
  reconnecting,
}

/// Rebuild groups emitted by `RealtimeBloc`.
abstract final class RealtimeGroups {
  /// Connection status (or reconnect attempts / error) changed.
  static const status = 'realtime:status';

  /// A new message arrived ([RealtimeState.lastMessage] updated).
  ///
  /// For *every* message (e.g. chat), listen to `bloc.messages` instead — this
  /// group only reflects the latest.
  static const message = 'realtime:message';

  static const all = {status, message};
}

/// Immutable realtime connection state.
class RealtimeState extends BlocState {
  final RealtimeStatus status;

  /// The most recently received message (latest only).
  final RealtimeMessage? lastMessage;

  /// Consecutive failed reconnect attempts (reset on a successful connect).
  final int reconnectAttempts;

  /// Total messages received this session.
  final int messageCount;

  /// Last connection error, if any.
  final String? lastError;

  const RealtimeState({
    this.status = RealtimeStatus.disconnected,
    this.lastMessage,
    this.reconnectAttempts = 0,
    this.messageCount = 0,
    this.lastError,
  });

  static const initial = RealtimeState();

  bool get isConnected => status == RealtimeStatus.connected;

  RealtimeState copyWith({
    RealtimeStatus? status,
    RealtimeMessage? lastMessage,
    int? reconnectAttempts,
    int? messageCount,
    Object? lastError = _unset,
  }) {
    return RealtimeState(
      status: status ?? this.status,
      lastMessage: lastMessage ?? this.lastMessage,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      messageCount: messageCount ?? this.messageCount,
      lastError: identical(lastError, _unset) ? this.lastError : lastError as String?,
    );
  }

  @override
  String toString() =>
      'RealtimeState($status, msgs: $messageCount, attempts: $reconnectAttempts)';
}

const Object _unset = Object();
