import 'package:juice/juice.dart';

import 'notification_service.dart';

/// Rebuild groups emitted by [NotificationsBloc].
abstract final class NotificationsGroups {
  /// The scheduled/active set changed.
  static const scheduled = 'notifications:scheduled';

  /// A notification was tapped.
  static const tap = 'notifications:tap';

  /// The (externally-set) permission status changed.
  static const permission = 'notifications:permission';

  static const all = {scheduled, tap, permission};
}

/// Immutable notifications state.
class NotificationsState extends BlocState {
  /// Notifications this bloc has shown/scheduled and not cancelled.
  ///
  /// (Best-effort local tracking; the OS owns final delivery.)
  final List<JuiceNotification> scheduled;

  /// The most recent tap, for the app to route on.
  final NotificationTap? lastTap;

  /// Whether the app may post notifications. Set via
  /// [NotificationsBloc.setPermissionStatus] — typically wired from
  /// `juice_permissions` with a `PermissionBinding`. Informational: the OS is
  /// the final authority.
  final bool permissionGranted;

  const NotificationsState({
    this.scheduled = const [],
    this.lastTap,
    this.permissionGranted = false,
  });

  static const initial = NotificationsState();

  NotificationsState copyWith({
    List<JuiceNotification>? scheduled,
    Object? lastTap = _unset,
    bool? permissionGranted,
  }) {
    return NotificationsState(
      scheduled: scheduled ?? this.scheduled,
      lastTap: identical(lastTap, _unset) ? this.lastTap : lastTap as NotificationTap?,
      permissionGranted: permissionGranted ?? this.permissionGranted,
    );
  }

  @override
  String toString() =>
      'NotificationsState(${scheduled.length} scheduled, granted: $permissionGranted)';
}

const Object _unset = Object();
