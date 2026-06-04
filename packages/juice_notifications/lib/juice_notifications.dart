/// Local notification delivery and tap routing as a Juice bloc.
///
/// `NotificationsBloc` owns local notification scheduling/display and the
/// last-tapped payload, through a swappable [NotificationService] seam (default
/// `LocalNotificationService`). Permission status is set externally via
/// [NotificationsBloc.setPermissionStatus] — wire it from `juice_permissions`
/// with a `PermissionBinding`.
///
/// ```dart
/// final notifications = NotificationsBloc.withConfig(NotificationsConfig());
/// notifications.show(JuiceNotification(id: 1, title: 'Hi', body: 'There'));
///
/// // Wire permission status from juice_permissions:
/// PermissionBinding(permissions, JuicePermission.notification,
///   onStatus: (s) => notifications.setPermissionStatus(s == PermissionStatus.granted),
/// )..start();
/// ```
///
/// Push notifications (FCM/APNs) are out of scope for now — a separate
/// `PushNotificationSource` seam is planned.
library juice_notifications;

export 'src/notification_service.dart';
export 'src/notifications_bloc.dart';
export 'src/notifications_config.dart';
export 'src/notifications_events.dart';
export 'src/notifications_state.dart';
export 'src/providers/local_notification_service.dart';
