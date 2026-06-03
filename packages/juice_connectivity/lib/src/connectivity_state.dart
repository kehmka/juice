import 'package:juice/juice.dart';

import 'connectivity_provider.dart';

/// Whether the device currently has a usable network.
enum ConnectivityStatus {
  /// Not yet determined (before initialization).
  unknown,

  /// A usable network is available.
  online,

  /// No usable network.
  offline,
}

/// Rebuild groups emitted by [ConnectivityBloc].
abstract final class ConnectivityGroups {
  /// Online/offline status changed.
  static const status = 'connectivity:status';

  /// Connection type changed (e.g. wifi → cellular).
  static const type = 'connectivity:type';

  static const all = {status, type};
}

/// Immutable connectivity state.
class ConnectivityState extends BlocState {
  /// Online/offline/unknown.
  final ConnectivityStatus status;

  /// The active interface kind.
  final ConnectionType connectionType;

  /// When the status or type last changed.
  final DateTime? lastChangedAt;

  const ConnectivityState({
    this.status = ConnectivityStatus.unknown,
    this.connectionType = ConnectionType.none,
    this.lastChangedAt,
  });

  /// Initial state before the first reading.
  static const initial = ConnectivityState();

  /// Whether a usable network is available.
  bool get isOnline => status == ConnectivityStatus.online;

  /// Whether there is no usable network.
  bool get isOffline => status == ConnectivityStatus.offline;

  ConnectivityState copyWith({
    ConnectivityStatus? status,
    ConnectionType? connectionType,
    DateTime? lastChangedAt,
  }) {
    return ConnectivityState(
      status: status ?? this.status,
      connectionType: connectionType ?? this.connectionType,
      lastChangedAt: lastChangedAt ?? this.lastChangedAt,
    );
  }

  @override
  String toString() => 'ConnectivityState($status, $connectionType)';
}
