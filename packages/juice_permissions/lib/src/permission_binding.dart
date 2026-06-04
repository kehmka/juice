import 'package:juice/juice.dart';

import 'permission_provider.dart';
import 'permissions_bloc.dart';
import 'permissions_state.dart';

/// A generic, callback-based binding from [PermissionsBloc] to anything that
/// cares about one permission's status.
///
/// This is how capability blocs (notifications, location, media) react to
/// permission changes — *without* a per-capability glue package. The capability
/// bloc exposes its own neutral status setter; the user maps in the callback:
///
/// ```dart
/// final binding = PermissionBinding(
///   permissionsBloc,
///   JuicePermission.notification,
///   onStatus: (status) =>
///       notificationsBloc.setPermissionStatus(status == PermissionStatus.granted),
/// )..start();
/// // ... on teardown
/// binding.dispose();
/// ```
///
/// Because it communicates through a callback, this binding depends only on
/// `juice_permissions` — it never references the capability bloc.
class PermissionBinding {
  /// The permissions bloc to watch.
  final PermissionsBloc permissionsBloc;

  /// The permission whose status changes are forwarded.
  final JuicePermission permission;

  /// Called with the permission's status — immediately on [start] (when
  /// [emitInitial]) and on every change thereafter.
  final void Function(PermissionStatus status) onStatus;

  /// Fire [onStatus] with the current status when [start] is called.
  final bool emitInitial;

  StreamSubscription<StreamStatus<PermissionsState>>? _subscription;
  PermissionStatus? _last;

  PermissionBinding(
    this.permissionsBloc,
    this.permission, {
    required this.onStatus,
    this.emitInitial = true,
  });

  /// Begin forwarding status changes.
  void start() {
    if (emitInitial) {
      _last = permissionsBloc.state.statusOf(permission);
      onStatus(_last!);
    }
    _subscription = permissionsBloc.stream.listen((status) {
      final current = status.state.statusOf(permission);
      if (current != _last) {
        _last = current;
        onStatus(current);
      }
    });
  }

  /// Stop forwarding.
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
