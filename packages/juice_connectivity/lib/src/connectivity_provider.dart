import 'package:flutter/foundation.dart';

/// The active network interface kind.
enum ConnectionType { none, wifi, cellular, ethernet, other }

/// A point-in-time snapshot of connectivity reported by a [ConnectivityProvider].
@immutable
class ConnectivitySnapshot {
  /// The active interface kind.
  final ConnectionType type;

  /// Whether the internet is actually reachable, when the provider measures it.
  ///
  /// `null` means reachability was not probed (interface-state only). A provider
  /// that performs an active reachability check sets this to `true`/`false`.
  final bool? reachable;

  const ConnectivitySnapshot({required this.type, this.reachable});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectivitySnapshot &&
          other.type == type &&
          other.reachable == reachable;

  @override
  int get hashCode => Object.hash(type, reachable);

  @override
  String toString() => 'ConnectivitySnapshot($type, reachable: $reachable)';
}

/// Vendor seam for connectivity.
///
/// `ConnectivityBloc` depends on this interface, never on a platform plugin —
/// which is what makes it testable without a device: inject a fake provider
/// whose [changes] stream and [check] result you control.
///
/// The default implementation is `ConnectivityPlusProvider`.
abstract class ConnectivityProvider {
  /// Stream of connectivity changes from the underlying source.
  Stream<ConnectivitySnapshot> get changes;

  /// One-shot current connectivity.
  Future<ConnectivitySnapshot> check();

  /// Release any resources held by the provider.
  Future<void> dispose();
}
